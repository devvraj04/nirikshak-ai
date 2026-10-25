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
from app.services.pipeline import CompliancePipeline
from app.services.storage import StorageService
from app.services.rag.violation_analyzer import LegalViolationAnalyzer
from app.services.ingredients.ingredient_engine import ingredient_engine
from app.services.surrogate.surrogate_engine import surrogate_engine
from app.services.extraction.panel_cropper import packaging_cropper

router = APIRouter(prefix="/scans", tags=["Product Scans"])

storage_service = StorageService()
pipeline_service = CompliancePipeline()
violation_analyzer = LegalViolationAnalyzer()

class IngredientAnalyzeRequest(BaseModel):
    ingredients_text: str

class SurrogateAnalyzeRequest(BaseModel):
    brand_name: str
    product_name: str
    ingredients_text: Optional[str] = ""
    brand_claims: Optional[List[Dict[str, Any]]] = None
    detected_text: Optional[str] = ""


@router.post("/analyze-surrogate")
async def analyze_surrogate_endpoint(req: SurrogateAnalyzeRequest) -> Dict[str, Any]:
    """
    On-demand analysis for surrogate advertising, brand extension camouflage, and packaging dark patterns.
    """
    return surrogate_engine.analyze_product(
        brand_name=req.brand_name,
        product_name=req.product_name,
        ingredients_list=req.ingredients_text or "",
        brand_claims=req.brand_claims or [],
        detected_text=req.detected_text or "",
    )


@router.post("/quick-ocr")
async def quick_ocr_endpoint(
    file: UploadFile = File(...),
) -> Dict[str, Any]:
    """
    Rapid OCR preview endpoint for Circle to Search & Mobile Overlay extension.
    Saves temporary image, executes rapid OCR, extracts instant entities (Brand, MRP, Net Qty, Mfg),
    and returns immediate feedback before user decides to submit for formal audit.
    """
    import re
    temp_path = await storage_service.save_upload_file(file, subfolder="scans")
    abs_path = _resolve_image_path(temp_path)
    if not abs_path or not os.path.exists(abs_path):
        raise HTTPException(status_code=400, detail="Could not cache snip image for OCR.")

    try:
        ocr_res = pipeline_service.ocr_engine.process_image(abs_path)
    except Exception as e:
        return {
            "success": False,
            "detected_text": "",
            "entities": {},
            "confidence": 0.0,
            "error": str(e),
        }

    raw_text = ocr_res.processed_text or ocr_res.raw_text or ""
    lines = [l.strip() for l in raw_text.split("\n") if l.strip()]

    # Extract Quick Entities
    mrp_match = re.search(r"(?:MRP|M\.R\.P\.?|Rs\.?|₹|INR)\s*[:.]?\s*(\d+(?:\.\d{1,2})?)", raw_text, re.IGNORECASE)
    qty_match = re.search(r"(?:Net\s*(?:Qty|Quantity|Weight|Wt\.?|Vol\.?|Volume)|Net)\s*[:.]?\s*(\d+(?:\.\d+)?)\s*(kg|g|gm|ml|l|ltr|litre|pieces|pcs|tabs|pills)?", raw_text, re.IGNORECASE)
    mfg_match = re.search(r"(?:Mfg\.?\s*by|Manufactured\s*by|Marketed\s*by|Packed\s*by|M/s\.?)\s*[:.]?\s*([A-Za-z0-9\s.,&'-]{3,60})", raw_text, re.IGNORECASE)

    extracted_mrp = float(mrp_match.group(1)) if mrp_match else None
    extracted_qty = float(qty_match.group(1)) if qty_match else None
    extracted_unit = qty_match.group(2).lower() if (qty_match and qty_match.group(2)) else None
    extracted_mfg = mfg_match.group(1).strip() if mfg_match else None

    # Guess product name from top non-noisy line
    guessed_title = lines[0] if lines else "Packaged Commodity"
    for l in lines[:4]:
        if len(l) > 3 and not re.search(r"^(mrp|net|batch|mfd|exp|best|weight)", l, re.IGNORECASE):
            guessed_title = l
            break

    return {
        "success": True,
        "image_url": temp_path,
        "detected_text": raw_text[:800],
        "line_count": len(lines),
        "confidence": round(ocr_res.average_confidence, 3),
        "entities": {
            "product_name": guessed_title,
            "mrp": extracted_mrp,
            "net_quantity": extracted_qty,
            "unit": extracted_unit,
            "manufacturer": extracted_mfg,
        },
    }


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
    """Convert a stored relative path or Supabase URL to an absolute local file path."""
    if not rel_path:
        return None

    # If it's a relative path starting with /uploads
    if rel_path.startswith("/uploads/"):
        sub = rel_path.replace("/uploads/", "")
        candidate = os.path.join("./data/uploads", sub)
        if os.path.exists(candidate):
            return candidate

    abs_path = os.path.join("./data", rel_path.lstrip("/"))
    if os.path.exists(abs_path):
        return abs_path

    # Extract base filename from URL or path
    filename = os.path.basename(rel_path.split("?")[0])
    for sub in ["scans", "crops", "crops/nutrition", "crops/ingredients", "evidence", "products"]:
        cand = os.path.join("./data/uploads", sub, filename)
        if os.path.exists(cand):
            return cand

    cand_direct = os.path.join("./data/uploads", filename)
    if os.path.exists(cand_direct):
        return cand_direct

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

    return {
        "scan_id": str(scan.id),
        "status": scan.status.value,
        "overall_compliance": scan.overall_compliance.value if scan.overall_compliance else None,
        "image_urls": scan.image_urls,
        "nutrition_table_image": scan.nutrition_table_image_url,
        "ingredients_image": scan.ingredients_image_url,
        "crop_metadata": scan.crop_metadata,
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
        "surrogate_analysis": raw_decl.get("surrogate_analysis") or surrogate_engine.analyze_product(
            brand_name=decl_row.manufacturer_name or decl_row.packer_name or (raw_decl.get("brand_claims", [{}])[0].get("context", "") if raw_decl.get("brand_claims") else "") or "",
            product_name=decl_row.generic_product_name or "",
            ingredients_list=raw_decl.get("ingredients_list") or "",
            brand_claims=raw_decl.get("brand_claims") or [],
            detected_text=all_detected_text or "",
        ),
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
        "surrogate_analysis": raw_decl.get("surrogate_analysis") or surrogate_engine.analyze_product(
            brand_name=decl_row.manufacturer_name or decl_row.packer_name or (raw_decl.get("brand_claims", [{}])[0].get("context", "") if raw_decl.get("brand_claims") else "") or "",
            product_name=decl_row.generic_product_name or "",
            ingredients_list=raw_decl.get("ingredients_list") or "",
            brand_claims=raw_decl.get("brand_claims") or [],
            detected_text=all_detected_text or "",
        ),
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


@router.post("/{scan_id}/recrop-panels")
async def recrop_scan_panels_endpoint(
    scan_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
) -> Dict[str, Any]:
    """
    Re-trigger visual region cropping for an existing scan session.
    Detects and isolates the nutrition table and ingredient list into separate images.
    """
    scan = await db.get(Scan, scan_id)
    if not scan:
        raise HTTPException(status_code=404, detail="Scan record not found.")

    image_urls = scan.image_urls or {}
    if not image_urls:
        raise HTTPException(status_code=400, detail="Scan record has no attached image URLs.")

    image_paths = []
    for side in ["back", "left", "right", "front", "top", "bottom", "main"]:
        rel_path = image_urls.get(side)
        if rel_path:
            abs_path = _resolve_image_path(rel_path)
            if abs_path:
                image_paths.append((side, abs_path))

    if not image_paths:
        raise HTTPException(status_code=400, detail="Uploaded images could not be located on disk.")

    # Retrieve existing OCR bounding boxes for fallback
    ocr_stmt = select(OCRResult).where(OCRResult.scan_id == scan_id)
    ocr_res = await db.execute(ocr_stmt)
    ocr_rows = ocr_res.scalars().all()
    all_bboxes = []
    for r in ocr_rows:
        if isinstance(r.bounding_boxes, list):
            for b in r.bounding_boxes:
                b["_source_image"] = r.image_url
                all_bboxes.append(b)

    crop_outcome = packaging_cropper.process_packaging_images(
        panel_images=image_paths,
        scan_id=scan.id,
        all_ocr_bboxes=all_bboxes,
    )

    scan.nutrition_table_image_url = crop_outcome.get("nutrition_table_image")
    scan.ingredients_image_url = crop_outcome.get("ingredients_image")
    scan.crop_metadata = crop_outcome.get("crop_metadata")
    db.add(scan)
    await db.commit()
    await db.refresh(scan)

    return {
        "scan_id": str(scan.id),
        "nutrition_table_image": scan.nutrition_table_image_url,
        "ingredients_image": scan.ingredients_image_url,
        "crop_metadata": scan.crop_metadata,
        "message": "Visual panel cropping completed successfully."
    }

