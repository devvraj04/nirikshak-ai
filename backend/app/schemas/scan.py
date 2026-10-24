"""
NIRIKSHAK AI - Scan Pydantic Schemas.
"""

from datetime import datetime
import uuid
from pydantic import BaseModel

from app.models.enums import ComplianceStatus, ScanStatus


class ScanBase(BaseModel):
    notes: str | None = None
    geo_location: dict | None = None
    image_urls: dict | None = None
    nutrition_table_image_url: str | None = None
    ingredients_image_url: str | None = None
    crop_metadata: dict | None = None


class ScanCreate(ScanBase):
    product_id: uuid.UUID | None = None


class ScanRead(ScanBase):
    id: uuid.UUID
    user_id: uuid.UUID | None = None
    product_id: uuid.UUID | None = None
    status: ScanStatus
    overall_compliance: ComplianceStatus | None = None
    nutrition_table_image_url: str | None = None
    ingredients_image_url: str | None = None
    crop_metadata: dict | None = None
    created_at: datetime
    completed_at: datetime | None = None

    class Config:
        from_attributes = True
