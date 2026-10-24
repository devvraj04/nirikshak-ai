"""
NIRIKSHAK AI - Application Configuration.

Centralized configuration management using pydantic-settings.
All config is loaded from environment variables / .env file.
"""

import os
from functools import lru_cache
from typing import Literal

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- Application ---
    app_name: str = "NIRIKSHAK AI"
    app_version: str = "0.1.0"
    debug: bool = True
    backend_host: str = "0.0.0.0"
    backend_port: int = 8080

    # --- Security ---
    secret_key: str = "change-this-to-a-random-secret-key-in-production"
    jwt_algorithm: str = "HS256"
    jwt_expiration_minutes: int = 1440  # 24 hours

    # --- PostgreSQL ---
    postgres_user: str = "nirikshak"
    postgres_password: str = "nirikshak_dev_password"
    postgres_db: str = "nirikshak_db"
    postgres_host: str = "postgres"
    postgres_port: int = 5432
    database_url: str = "postgresql+asyncpg://nirikshak:nirikshak_dev_password@postgres:5432/nirikshak_db"

    @field_validator("database_url")
    @classmethod
    def assemble_db_connection(cls, v: str) -> str:
        if v.startswith("postgres://"):
            return v.replace("postgres://", "postgresql+asyncpg://", 1)
        if v.startswith("postgresql://"):
            return v.replace("postgresql://", "postgresql+asyncpg://", 1)
        return v

    # --- ChromaDB ---
    chroma_host: str = "chromadb"
    chroma_port: int = 8000

    # --- Redis ---
    redis_host: str = "redis"
    redis_port: int = 6379
    redis_url: str = "redis://redis:6379/0"

    # --- MinIO ---
    minio_root_user: str = "minioadmin"
    minio_root_password: str = "minioadmin123"
    minio_host: str = "minio"
    minio_port: int = 9000
    minio_console_port: int = 9001
    minio_bucket: str = "nirikshak-storage"

    # --- LLM ---
    groq_api_key: str = ""
    gemini_api_key: str = ""
    llm_provider: Literal["groq", "openai", "gemini"] = "groq"
    llm_model: str = "groq/compound-mini"

    # --- Embeddings ---
    embedding_provider: Literal["local", "gemini"] = "local"
    embedding_model: str = "all-MiniLM-L6-v2"

    # --- OCR ---
    ocr_language: str = "en"
    ocr_use_gpu: bool = False

    # --- File Storage ---
    storage_backend: Literal["local", "minio", "s3"] = "minio"
    local_storage_path: str = "./data/uploads"
    max_upload_size_mb: int = 50

    # --- Celery ---
    celery_broker_url: str = "redis://redis:6379/0"
    celery_result_backend: str = "redis://redis:6379/1"

    @property
    def database_url_resolved(self) -> str:
        """Get database URL, resolving 'postgres' to 'localhost' when running outside Docker container."""
        url = self.database_url
        if os.environ.get("POSTGRES_HOST") is None and "postgres:5432" in url:
            # Check if running outside docker container
            if not os.path.exists("/.dockerenv"):
                url = url.replace("postgres:5432", "localhost:5432")
        return url

    @property
    def sync_database_url(self) -> str:
        """Get synchronous database URL (for Alembic migrations)."""
        return self.database_url_resolved.replace("postgresql+asyncpg", "postgresql+psycopg2")


@lru_cache()
def get_settings() -> Settings:
    """Get cached application settings singleton."""
    return Settings()
