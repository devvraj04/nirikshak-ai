import asyncio
from sqlalchemy import text
from app.core.database import async_session_factory

async def dump_ocr():
    async with async_session_factory() as session:
        query = text("""
            SELECT image_side, raw_text, processed_text, confidence, image_url 
            FROM ocr_results 
            ORDER BY created_at DESC 
            LIMIT 5
        """)
        result = await session.execute(query)
        rows = result.fetchall()
        print("--- LATEST MULTI-ANGLE OCR RESULTS ---")
        for i, row in enumerate(rows):
            print(f"\n[FACE: {row.image_side}] Confidence: {row.confidence} | Image: {row.image_url}")
            print(f"CLEAN OCR TRANSCRIPTION:\n{row.processed_text or row.raw_text}\n" + "-"*50)

if __name__ == "__main__":
    asyncio.run(dump_ocr())
