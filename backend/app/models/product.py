"""
NIRIKSHAK AI - Product SQLAlchemy Model (Digital Twin).
"""

from datetime import datetime, timezone
import uuid

from sqlalchemy import DateTime, String, JSON
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Product(Base):
    """Product model acting as Digital Twin storing persistent compliance history."""

    __tablename__ = "products"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    barcode: Mapped[str | None] = mapped_column(String(100), index=True, nullable=True)
    product_name: Mapped[str] = mapped_column(String(255), index=True, nullable=False)
    generic_name: Mapped[str | None] = mapped_column(String(255), index=True, nullable=True)
    brand: Mapped[str | None] = mapped_column(String(255), nullable=True)
    manufacturer: Mapped[str | None] = mapped_column(String(255), index=True, nullable=True)
    category: Mapped[str | None] = mapped_column(String(100), nullable=True)
    hero_image_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    extra_metadata: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )

    # Relationships
    scans = relationship("Scan", back_populates="product", cascade="all, delete-orphan")
    trust_score = relationship("TrustScore", back_populates="product", uselist=False, cascade="all, delete-orphan")
    complaints = relationship("Complaint", back_populates="product")
