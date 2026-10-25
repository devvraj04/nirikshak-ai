"""
NIRIKSHAK AI - Object Storage Service.

Provides file upload abstraction supporting Supabase Storage, MinIO S3-compatible,
and local disk storage with automatic local caching.
"""

import os
import uuid
import mimetypes
from pathlib import Path
from typing import Optional
from fastapi import UploadFile
import httpx

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger("services.storage")
settings = get_settings()


class StorageService:
    """Manages file persistence for product label scans and evidence crops."""

    def __init__(self):
        self.backend = settings.storage_backend
        self.upload_dir = Path(settings.local_storage_path)
        self.upload_dir.mkdir(parents=True, exist_ok=True)
        self.supabase_url = settings.resolved_supabase_url
        self.supabase_key = settings.supabase_key
        self.bucket = settings.supabase_storage_bucket

    def _get_public_supabase_url(self, subfolder: str, filename: str) -> str:
        """Construct public HTTPS URL for an object stored in Supabase."""
        return f"{self.supabase_url}/storage/v1/object/public/{self.bucket}/{subfolder}/{filename}"

    async def _upload_to_supabase(self, data: bytes, subfolder: str, filename: str, content_type: str = "image/jpeg") -> Optional[str]:
        """Upload raw bytes to Supabase Storage via REST API."""
        if not self.supabase_key:
            logger.debug("SUPABASE_KEY not configured; skipping remote upload to Supabase.")
            return None

        upload_url = f"{self.supabase_url}/storage/v1/object/{self.bucket}/{subfolder}/{filename}"
        headers = {
            "Authorization": f"Bearer {self.supabase_key}",
            "apikey": self.supabase_key,
            "Content-Type": content_type or "image/jpeg",
            "x-upsert": "true",
        }

        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                resp = await client.post(upload_url, content=data, headers=headers)
                if resp.status_code in (200, 201):
                    public_url = self._get_public_supabase_url(subfolder, filename)
                    logger.info(f"Uploaded asset to Supabase Storage -> {public_url}")
                    return public_url
                else:
                    logger.warning(f"Supabase Storage upload returned {resp.status_code}: {resp.text}")
        except Exception as e:
            logger.error(f"Failed to upload to Supabase Storage: {e}")

        return None

    def _upload_to_supabase_sync(self, data: bytes, subfolder: str, filename: str, content_type: str = "image/jpeg") -> Optional[str]:
        """Synchronously upload bytes to Supabase Storage (for synchronous helper functions)."""
        if not self.supabase_key:
            return None

        upload_url = f"{self.supabase_url}/storage/v1/object/{self.bucket}/{subfolder}/{filename}"
        headers = {
            "Authorization": f"Bearer {self.supabase_key}",
            "apikey": self.supabase_key,
            "Content-Type": content_type or "image/jpeg",
            "x-upsert": "true",
        }

        try:
            with httpx.Client(timeout=15.0) as client:
                resp = client.post(upload_url, content=data, headers=headers)
                if resp.status_code in (200, 201):
                    public_url = self._get_public_supabase_url(subfolder, filename)
                    logger.info(f"Synchronously uploaded asset to Supabase -> {public_url}")
                    return public_url
        except Exception as e:
            logger.error(f"Failed synchronous Supabase upload: {e}")

        return None

    async def save_upload_file(self, file: UploadFile, subfolder: str = "scans") -> str:
        """
        Save uploaded file to local disk cache and upload to Supabase Storage.
        Returns public HTTPS Supabase URL if configured/available, otherwise relative local path.
        """
        dest_folder = self.upload_dir / subfolder
        dest_folder.mkdir(parents=True, exist_ok=True)

        ext = Path(file.filename or "image.jpg").suffix
        filename = f"{uuid.uuid4().hex}{ext}"
        filepath = dest_folder / filename

        content = await file.read()
        # Save local copy for fast pipeline / OCR processing
        with open(filepath, "wb") as f:
            f.write(content)

        relative_path = f"/uploads/{subfolder}/{filename}"
        logger.info(f"Cached local file {file.filename} -> {relative_path}")

        # Upload to Supabase Storage
        if self.backend == "supabase":
            content_type = file.content_type or mimetypes.guess_type(filename)[0] or "image/jpeg"
            supabase_url = await self._upload_to_supabase(content, subfolder, filename, content_type)
            if supabase_url:
                return supabase_url

        return relative_path

    def save_bytes(self, data: bytes, filename: str, subfolder: str = "evidence") -> str:
        """Save raw bytes (e.g. cropped evidence image) to local storage and sync to Supabase."""
        dest_folder = self.upload_dir / subfolder
        dest_folder.mkdir(parents=True, exist_ok=True)

        filepath = dest_folder / filename
        with open(filepath, "wb") as f:
            f.write(data)

        relative_path = f"/uploads/{subfolder}/{filename}"

        if self.backend == "supabase":
            content_type = mimetypes.guess_type(filename)[0] or "image/jpeg"
            supabase_url = self._upload_to_supabase_sync(data, subfolder, filename, content_type)
            if supabase_url:
                return supabase_url

        return relative_path

    async def upload_file_path(self, local_file_path: str, subfolder: str = "crops") -> str:
        """Upload an existing local file (e.g. cropped nutrition/ingredients panel) to Supabase Storage."""
        p = Path(local_file_path)
        if not p.exists():
            return f"/uploads/{subfolder}/{p.name}"

        filename = p.name
        with open(p, "rb") as f:
            data = f.read()

        if self.backend == "supabase":
            content_type = mimetypes.guess_type(filename)[0] or "image/jpeg"
            supabase_url = await self._upload_to_supabase(data, subfolder, filename, content_type)
            if supabase_url:
                return supabase_url

        return f"/uploads/{subfolder}/{filename}"
