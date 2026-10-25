"""
NIRIKSHAK AI - Database Connection Management.

Provides async SQLAlchemy engine, session factory, and base model.
"""

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.core.config import get_settings

settings = get_settings()

# Async engine
engine = create_async_engine(
    settings.database_url_resolved,
    echo=settings.debug,
    pool_size=20,
    max_overflow=10,
    pool_pre_ping=True,
)

# Async session factory
async_session_factory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


class Base(DeclarativeBase):
    """Base class for all SQLAlchemy ORM models."""
    pass


async def get_db() -> AsyncSession:
    """
    Dependency that yields an async database session.

    Usage in FastAPI routes:
        db: AsyncSession = Depends(get_db)
    """
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def init_db() -> None:
    """Create all database tables and ensure new columns exist during startup."""
    from sqlalchemy import text
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        try:
            await conn.execute(text("ALTER TABLE products ADD COLUMN IF NOT EXISTS generic_name VARCHAR(255);"))
            await conn.execute(text("ALTER TABLE products ADD COLUMN IF NOT EXISTS hero_image_url VARCHAR(512);"))
        except Exception:
            pass


async def close_db() -> None:
    """Dispose of the database engine. Used during shutdown."""
    await engine.dispose()
