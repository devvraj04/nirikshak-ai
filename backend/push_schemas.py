"""
Script to create/push all SQLAlchemy schemas and tables to Supabase PostgreSQL.
"""

import asyncio
from sqlalchemy import inspect, text
from app.core.config import get_settings
from app.core.database import engine, Base
import app.models  # Ensures all models are registered in Base.metadata

settings = get_settings()

async def push_all_schemas():
    print("=" * 60)
    print("NIRIKSHAK AI - Pushing All Schemas to Supabase")
    print(f"Connecting to database...")
    print("=" * 60)

    async with engine.begin() as conn:
        print("\nCreating all tables from Base.metadata...")
        await conn.run_sync(Base.metadata.create_all)
        print("Base.metadata.create_all executed successfully!")

    # Verify tables in the database
    async with engine.connect() as conn:
        def get_tables(sync_conn):
            inspector = inspect(sync_conn)
            return inspector.get_table_names()

        table_names = await conn.run_sync(get_tables)
        print(f"\nExisting Tables in Supabase Database ({len(table_names)} found):")
        for idx, t in enumerate(sorted(table_names), 1):
            print(f"  {idx}. {t}")

    await engine.dispose()
    print("\nDatabase push completed successfully.")

if __name__ == "__main__":
    asyncio.run(push_all_schemas())
