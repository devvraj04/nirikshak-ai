"""
NIRIKSHAK AI - Product Scan API Routes.
"""

import os
import uuid
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from pydantic import BaseModel
from app.core.database import get_db
from app.models import Declaration, OCRResult, Scan
from app.models.enums import ScanStatus
from app.services.nutrition_audit import audit_nutrition_table
from app.services.pipeline import CompliancePipeline
from app.services.storage import StorageService
from app.services.rag.violation_analyzer import LegalViolationAnalyzer
from app.services.ingredients.ingredient_engine import ingredient_engine

router = APIRouter(prefix="/scans", tags=["Product Scans"])

storage_service = StorageService()
pipeline_service = CompliancePipeline()
violation_analyzer = LegalViolationAnalyzer()

class IngredientAnalyzeRequest(BaseModel):
    ingredients_text: str


@router.post("", status_code=201)
async def create_scan_session(
    file: UploadFile = File(...),
    back_file: Optional[UploadFile] = File(None),
    left_file: Optional[UploadFile] = File(None),
    right_file: Optional[UploadFile] = File(None),
    top_file: Optional[UploadFile] = File(None),
    bottom_file: Optional[UploadFile] = File(None),
    user_id: Optional[uuid.UUID] = Form(None),
    db: AsyncSession = Depends(get_db),
) -> Dict[str, Any]:
    """
    Upload product package photos (front required, back/left/right/top/bottom optional) and create a new scan session.
    """
    # Save front image
    front_path = await storage_service.save_upload_file(file, subfolder="scans")

    image_urls = {"front": front_path}

    # Save extra images if provided
    if back_file and back_file.filename:
        image_urls["back"] = await storage_service.save_upload_file(back_file, subfolder="scans")

    if left_file and left_file.filename:
        image_urls["left"] = await storage_service.save_upload_file(left_file, subfolder="scans")

    if right_file and right_file.filename:
        image_urls["right"] = await storage_service.save_upload_file(right_file, subfolder="scans")
    
    if top_file and top_file.filename:
        image_urls["top"] = await storage_service.save_upload_file(top_file, subfolder="scans")

    if bottom_file and bottom_file.filename:
        image_urls["bottom"] = await storage_service.save_upload_file(bottom_file, subfolder="scans")

    # Create Scan database record
    scan = Scan(
        user_id=user_id,
        status=ScanStatus.PENDING,
        image_urls=image_urls,
    )
    db.add(scan)
    await db.commit()
    await db.refresh(scan)

    return {
        "scan_id": str(scan.id),
        "status": scan.status.value,
        "image_urls": image_urls,
        "message": "Scan session created successfully. Call POST /scans/{scan_id}/process to execute compliance pipeline.",
    }


def _resolve_image_path(rel_path: str) -> Optional[str]:
    """Convert a stored relative path to an absolute local file path."""
    abs_path = os.path.join("./data", rel_path.lstrip("/"))
    if os.path.exists(abs_path):
        return abs_path
    abs_path = os.path.join("./data/uploads/scans", os.path.basename(rel_path))
    if os.path.exists(abs_path):
        return abs_path
    return None


@router.post("/{scan_id}/process")
async def process_scan_endpoint(
    scan_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> Dict[str, Any]:
    """
    Trigger AI OCR, extraction, RAG, rule evaluation, and evidence generation for a scan session.
    """
    scan = await db.get(Scan, scan_id)
    if not scan:
        raise HTTPException(status_code=404, detail="Scan session not found.")

    image_urls = scan.image_urls or {}
    if not image_urls:
        raise HTTPException(status_code=400, detail="Scan record has no attached image URLs.")

    # Resolve all image paths (front, back, left, right, top, bottom)
    image_paths = []
    for side in ["front", "back", "left", "right", "top", "bottom", "main"]:
        rel_path = image_urls.get(side)
        if rel_path:
            abs_path = _resolve_image_path(rel_path)
            if abs_path:
                image_paths.append((side, abs_path))

    if not image_paths:
        raise HTTPException(status_code=400, detail="No uploaded image files found on disk. Please re-upload.")

    result = await pipeline_service.process_scan(
        scan_id=scan.id,
        image_paths=image_paths,
        db=db,
    )
    return result


@router.get("/{scan_id}")
async def get_scan_details(

    scan_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> Dict[str, Any]:
    """Get full details, declarations, violations, and evidence for a scan."""
    scan = await db.get(Scan, scan_id)
    if not scan:
        raise HTTPException(status_code=404, detail="Scan record not found.")

    ocr_stmt = select(OCRResult).where(OCRResult.scan_id == scan_id).order_by(OCRResult.created_at.asc())
    ocr_res = await db.execute(ocr_stmt)
    ocr_rows = ocr_res.scalars().all()
    all_detected_text = "\n\n".join(
        [f"[{r.image_side.upper() if r.image_side else 'LABEL'}]\n{r.processed_text or r.raw_text}" 
         for r in ocr_rows if (r.processed_text or r.raw_text)]
    )

    decl_stmt = select(Declaration).where(Declaration.scan_id == scan_id)
    decl_res = await db.execute(decl_stmt)
    decl_row = decl_res.scalars().first()
    raw_decl = decl_row.raw_declarations or {} if decl_row else {}

    nutrition_rows = raw_decl.get("nutrition_table") or []

    nutrition_audit = audit_nutrition_table(
        nutrition_rows if isinstance(nutrition_rows, list) else []
    )

    return {
        "scan_id": str(scan.id),
        "status": scan.status.value,
        "overall_compliance": scan.overall_compliance.value if scan.overall_compliance else None,
        "image_urls": scan.image_urls,
        "all_detected_text": all_detected_text,
        "front_panel_table": raw_decl.get("front_panel_table", []),
        "back_panel_table": raw_decl.get("back_panel_table", []),
        "left_panel_table": raw_decl.get("left_panel_table", []),
        "right_panel_table": raw_decl.get("right_panel_table", []),
        "all_key_value_pairs": raw_decl.get("all_key_value_pairs", []),
        "brand_claims": raw_decl.get("brand_claims", []),
        "summary_sentences": raw_decl.get("summary_sentences", []),
        "declarations_table": raw_decl.get("declarations_table", []),
        "ingredients_list": raw_decl.get("ingredients_list"),
        "ingredient_analysis": raw_decl.get("ingredient_analysis") or (ingredient_engine.analyze_full_product(raw_decl.get("ingredients_list") or "") if raw_decl.get("ingredients_list") else None),
        "nutrition_table": raw_decl.get("nutrition_table"),
        "nutrition_audit": nutrition_audit,
        "allergen_info": raw_decl.get("allergen_info"),
        "storage_instructions": raw_decl.get("storage_instructions"),
        "usage_instructions": raw_decl.get("usage_instructions"),
        "composition": raw_decl.get("composition"),
        "certifications": raw_decl.get("certifications"),
        "legal_disclaimer": raw_decl.get("legal_disclaimer"),
        "other_text_blocks": raw_decl.get("other_text_blocks"),
        "extracted_declarations": {
            "mrp": decl_row.mrp if decl_row else None,
            "currency": decl_row.currency if decl_row else "INR",
            "net_quantity": decl_row.net_quantity if decl_row else None,
            "unit": decl_row.unit if decl_row else None,
            "manufacturer_name": decl_row.manufacturer_name if decl_row else None,
            "packer_name": decl_row.packer_name if decl_row else None,
            "importer_name": decl_row.importer_name if decl_row else None,
            "generic_product_name": decl_row.generic_product_name if decl_row else None,
            "manufacture_month": decl_row.manufacture_month if decl_row else None,
            "manufacture_year": decl_row.manufacture_year if decl_row else None,
            "consumer_care_name": decl_row.consumer_care_name if decl_row else None,
            "consumer_care_email": decl_row.consumer_care_email if decl_row else None,
            "consumer_care_phone": decl_row.consumer_care_phone if decl_row else None,
            "consumer_care_address": decl_row.consumer_care_address if decl_row else None,
            **raw_decl,
        } if decl_row else {},
        "ocr_transcriptions": [
            {
                "image_side": r.image_side,
                "image_url": r.image_url,
                "detected_text": r.processed_text or r.raw_text,
                "confidence": r.confidence,
                "boxes_count": len(r.bounding_boxes) if isinstance(r.bounding_boxes, list) else 0,
                "bounding_boxes": r.bounding_boxes or [],
            }
            for r in ocr_rows
        ],
        "created_at": scan.created_at.isoformat(),
        "completed_at": scan.completed_at.isoformat() if scan.completed_at else None,
    }


@router.get("/{scan_id}/ocr")
async def get_scan_ocr(
    scan_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> Dict[str, Any]:
    """
    Get full OCR extraction results for a scan across all product faces and rotations.
    Returns complete transcription, per-line bounding boxes, confidence, and rotation angle.
    """
    scan = await db.get(Scan, scan_id)
    if not scan:
        raise HTTPException(status_code=404, detail="Scan record not found.")

    stmt = select(OCRResult).where(OCRResult.scan_id == scan_id).order_by(OCRResult.created_at.asc())
    result = await db.execute(stmt)
    records = result.scalars().all()

    all_detected_text = "\n\n".join(
        [f"[{r.image_side.upper() if r.image_side else 'LABEL'}]\n{r.processed_text or r.raw_text}" 
         for r in records if (r.processed_text or r.raw_text)]
    )

    decl_stmt = select(Declaration).where(Declaration.scan_id == scan_id)
    decl_res = await db.execute(decl_stmt)
    decl_row = decl_res.scalars().first()
    raw_decl = decl_row.raw_declarations or {} if decl_row else {}

    return {
        "scan_id": str(scan_id),
        "all_detected_text": all_detected_text,
        "front_panel_table": raw_decl.get("front_panel_table", []),
        "back_panel_table": raw_decl.get("back_panel_table", []),
        "left_panel_table": raw_decl.get("left_panel_table", []),
        "right_panel_table": raw_decl.get("right_panel_table", []),
        "all_key_value_pairs": raw_decl.get("all_key_value_pairs", []),
        "brand_claims": raw_decl.get("brand_claims", []),
        "summary_sentences": raw_decl.get("summary_sentences", []),
        "declarations_table": raw_decl.get("declarations_table", []),
        "ingredients_list": raw_decl.get("ingredients_list"),
        "ingredient_analysis": raw_decl.get("ingredient_analysis") or (ingredient_engine.analyze_full_product(raw_decl.get("ingredients_list") or "") if raw_decl.get("ingredients_list") else None),
        "nutrition_table": raw_decl.get("nutrition_table"),
        "allergen_info": raw_decl.get("allergen_info"),
        "storage_instructions": raw_decl.get("storage_instructions"),
        "usage_instructions": raw_decl.get("usage_instructions"),
        "composition": raw_decl.get("composition"),
        "certifications": raw_decl.get("certifications"),
        "legal_disclaimer": raw_decl.get("legal_disclaimer"),
        "other_text_blocks": raw_decl.get("other_text_blocks"),
        "extracted_declarations": {
            "mrp": decl_row.mrp if decl_row else None,
            "currency": decl_row.currency if decl_row else "INR",
            "net_quantity": decl_row.net_quantity if decl_row else None,
            "unit": decl_row.unit if decl_row else None,
            "manufacturer_name": decl_row.manufacturer_name if decl_row else None,
            "packer_name": decl_row.packer_name if decl_row else None,
            "importer_name": decl_row.importer_name if decl_row else None,
            "generic_product_name": decl_row.generic_product_name if decl_row else None,
            "manufacture_month": decl_row.manufacture_month if decl_row else None,
            "manufacture_year": decl_row.manufacture_year if decl_row else None,
            "consumer_care_name": decl_row.consumer_care_name if decl_row else None,
            "consumer_care_email": decl_row.consumer_care_email if decl_row else None,
            "consumer_care_phone": decl_row.consumer_care_phone if decl_row else None,
            "consumer_care_address": decl_row.consumer_care_address if decl_row else None,
            **raw_decl,
        } if decl_row else {},
        "faces": [
            {
                "id": str(r.id),
                "image_side": r.image_side,
                "image_url": r.image_url,
                "raw_text": r.raw_text,
                "processed_text": r.processed_text,
                "confidence": r.confidence,
                "bounding_boxes": r.bounding_boxes,
                "extraction_method": r.extraction_method,
                "detected_language": r.detected_language,
            }
            for r in records
        ],
    }


@router.get("/{scan_id}/violations/analysis")
@router.get("/{scan_id}/violations/{rule_id}/analysis")
async def analyze_scan_violations(
    scan_id: uuid.UUID,
    rule_id: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
) -> Dict[str, Any]:
    """
    Directly query RAG database and LLM for authoritative LMPC legal quotation,
    grounded justification, and statutory penalties for a scan's violation(s).
    """
    scan = await db.get(Scan, scan_id)
    if not scan:
        raise HTTPException(status_code=404, detail="Scan record not found.")

    # If specific rule_id requested, analyze that rule
    target_rules = [rule_id] if rule_id else ["RULE-LM-001", "RULE-LM-002", "RULE-LM-003", "RULE-LM-004", "RULE-LM-005", "RULE-LM-006", "RULE-LM-007"]
    
    results = []
    for rid in target_rules:
        advisory = violation_analyzer.analyze_violation(
            rule_id=rid,
            rule_title=rid,
            field_name=rid.lower(),
            detected_value=None,
            ocr_context="",
        )
        advisory["rule_id"] = rid
        results.append(advisory)

    return {
        "scan_id": str(scan_id),
        "violations": results,
    }


@router.post("/analyze-ingredients")
async def analyze_ingredients_direct(payload: IngredientAnalyzeRequest) -> Dict[str, Any]:
    """
    Direct ingredient inspection endpoint: takes any ingredient text or composition list,
    checks for banned/restricted substances under FSSAI/FDA/EU, decodes technical chemical meanings,
    and identifies all statutory allergen & health sensitivity risks.
    """
    return ingredient_engine.analyze_full_product(payload.ingredients_text)
