"""
NIRIKSHAK AI - Scan SQLAlchemy Model.
"""

from datetime import datetime, timezone
import uuid

from sqlalchemy import DateTime, Enum, ForeignKey, String, JSON
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base
from app.models.enums import ComplianceStatus, ScanStatus


class Scan(Base):
    """Scan session model holding captured image assets and workflow state."""

    __tablename__ = "scans"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    product_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("products.id", ondelete="SET NULL"), nullable=True
    )

    status: Mapped[ScanStatus] = mapped_column(
        Enum(ScanStatus), default=ScanStatus.PENDING, nullable=False
    )
    overall_compliance: Mapped[ComplianceStatus | None] = mapped_column(
        Enum(ComplianceStatus), nullable=True
    )

    image_urls: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # {"front": "...", "back": "..."}
    nutrition_table_image_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    ingredients_image_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    crop_metadata: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    geo_location: Mapped[dict | None] = mapped_column(JSON, nullable=True)  # {"lat": ..., "lng": ...}
    notes: Mapped[str | None] = mapped_column(String(500), nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    # Relationships
    user = relationship("User", back_populates="scans")
    product = relationship("Product", back_populates="scans")
    ocr_results = relationship("OCRResult", back_populates="scan", cascade="all, delete-orphan")
    declarations = relationship("Declaration", back_populates="scan", cascade="all, delete-orphan")
    violations = relationship("Violation", back_populates="scan", cascade="all, delete-orphan")
    evidence_items = relationship("Evidence", back_populates="scan", cascade="all, delete-orphan")
    reviews = relationship("Review", back_populates="scan", cascade="all, delete-orphan")
