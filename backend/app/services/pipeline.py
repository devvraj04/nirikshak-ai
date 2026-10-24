"""
NIRIKSHAK AI - Central Compliance Orchestration Pipeline.

Executes end-to-end workflow:
Image -> PaddleOCR -> Declarations -> RAG -> Rule Engine -> Evidence -> Digital Twin -> Database Persistence.
"""

import os
import uuid
from typing import Any, Dict, List, Optional
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.models import Declaration, Evidence, OCRResult, Rule, Scan, Violation
from app.models.product import Product
from app.models.enums import ComplianceStatus, ScanStatus
from app.services.extraction.declaration_extractor import DeclarationExtractor
from app.services.ocr.ocr_engine import OCREngine
from app.services.rag.rag_pipeline import RAGPipeline
from app.services.rules.rule_engine import RuleEngine
from app.services.storage import StorageService
from app.services.ingredients.ingredient_engine import ingredient_engine
from app.services.surrogate.surrogate_engine import surrogate_engine
from app.services.extraction.panel_cropper import packaging_cropper

logger = get_logger("services.pipeline")


class CompliancePipeline:
    """Orchestrates full AI product inspection pipeline."""

    def __init__(self):
        self.ocr_engine = OCREngine()
        self.extractor = DeclarationExtractor()
        self.rag_pipeline = RAGPipeline()
        self.rule_engine = RuleEngine()
        self.storage = StorageService()
        self.panel_cropper = packaging_cropper

    def _crop_evidence_region(self, image_path: str, bbox: List[List[float]], scan_id: uuid.UUID, field_name: str) -> Optional[str]:
        """Crop bounding box region from image and save as evidence artifact."""
        try:
            import cv2
            import numpy as np
            img = cv2.imread(image_path)
            if img is None:
                return None
            
            pts = np.array(bbox, dtype=np.float32)
            x_min = int(max(0, pts[:, 0].min() - 25))
            y_min = int(max(0, pts[:, 1].min() - 15))
            x_max = int(min(img.shape[1], pts[:, 0].max() + 25))
            y_max = int(min(img.shape[0], pts[:, 1].max() + 15))
            
            cropped = img[y_min:y_max, x_min:x_max]
            if cropped.size == 0:
                return None
            
            crop_dir = os.path.join("uploads", "evidence_crops")
            os.makedirs(crop_dir, exist_ok=True)
            crop_filename = f"{scan_id}_{field_name}_crop.jpg"
            crop_path = os.path.join(crop_dir, crop_filename)
            cv2.imwrite(crop_path, cropped)
            
            return f"/uploads/evidence_crops/{crop_filename}"
        except Exception as e:
            logger.warning(f"Failed to crop evidence region for {field_name}: {e}")
            return None

    def _find_best_bbox_for_field(self, field_name: str, field_value: Any, ocr_bboxes: List[dict]) -> Optional[dict]:
        """Find the OCR bounding box that best matches a declaration field value."""
        if not field_value or not ocr_bboxes:
            return None
        
        search_val = str(field_value).lower().strip()
        best_match = None
        best_score = 0
        
        for box in ocr_bboxes:
            text = box.get("text", "").lower().strip()
            if search_val in text or text in search_val:
                score = len(search_val) / max(len(text), 1)
                if score > best_score:
                    best_score = score
                    best_match = box
        
        return best_match

    async def _find_or_create_product(
        self, declarations, db: AsyncSession
    ) -> Optional[Product]:
        """Find an existing product by manufacturer + product name, or create a new one."""
        mfr = declarations.manufacturer_name or declarations.packer_name or ""
        prod_name = declarations.generic_product_name or ""
        
        if not mfr and not prod_name:
            return None
        
        # Fuzzy match: case-insensitive search
        stmt = select(Product)
        if mfr:
            stmt = stmt.where(func.lower(Product.manufacturer) == mfr.lower())
        if prod_name:
            stmt = stmt.where(func.lower(Product.product_name) == prod_name.lower())
        
        result = await db.execute(stmt)
        existing = result.scalars().first()
        
        from app.api.routes.products import _generate_or_get_twice_daily_price_history

        if existing:
            # Update metadata with latest declarations
            existing.extra_metadata = existing.extra_metadata or {}
            existing.extra_metadata["latest_declarations"] = {
                "mrp": declarations.mrp,
                "net_quantity": declarations.net_quantity,
                "unit": declarations.unit,
                "manufacturer_name": declarations.manufacturer_name,
                "manufacture_month": declarations.manufacture_month,
                "manufacture_year": declarations.manufacture_year,
            }
            existing.extra_metadata["price_history"] = _generate_or_get_twice_daily_price_history(
                declarations.mrp, existing.extra_metadata
            )
            db.add(existing)
            return existing
        
        # Create new product record (Digital Twin)
        meta = {
            "latest_declarations": {
                "mrp": declarations.mrp,
                "net_quantity": declarations.net_quantity,
                "unit": declarations.unit,
                "manufacturer_name": declarations.manufacturer_name,
                "manufacture_month": declarations.manufacture_month,
                "manufacture_year": declarations.manufacture_year,
            }
        }
        meta["price_history"] = _generate_or_get_twice_daily_price_history(declarations.mrp, meta)

        product = Product(
            product_name=prod_name or "Unknown Product",
            brand=mfr,
            manufacturer=mfr,
            category=None,
            extra_metadata=meta,
        )
        db.add(product)
        await db.flush()
        return product

    def _compare_with_historical(self, product: Product, declarations) -> List[Dict[str, str]]:
        """Compare current declarations with historical product data to flag discrepancies."""
        discrepancies = []
        if not product or not product.extra_metadata:
            return discrepancies
        
        historical = product.extra_metadata.get("latest_declarations", {})
        if not historical:
            return discrepancies
        
        fields_to_compare = [
            ("mrp", "MRP"),
            ("net_quantity", "Net Quantity"),
            ("manufacturer_name", "Manufacturer Name"),
        ]
        
        for field_key, label in fields_to_compare:
            hist_val = historical.get(field_key)
            curr_val = getattr(declarations, field_key, None)
            
            if hist_val is not None and curr_val is not None:
                if str(hist_val).strip().lower() != str(curr_val).strip().lower():
                    discrepancies.append({
                        "field": label,
                        "historical_value": str(hist_val),
                        "current_value": str(curr_val),
                        "severity": "WARNING",
                    })
        
        return discrepancies

    async def process_scan(
        self,
        scan_id: uuid.UUID,
        image_paths: List[str],
        db: AsyncSession,
    ) -> Dict[str, Any]:
        """
        Process a product scan end-to-end asynchronously.

        Args:
            scan_id: ID of the scan record in database
            image_paths: List of local filesystem paths of product images (front, back, etc.)
            db: Async SQLAlchemy database session

        Returns:
            Structured compliance outcome payload.
        """
        logger.info(f"Processing scan {scan_id} with {len(image_paths)} image(s): {image_paths}")

        # 1. Fetch Scan Record
        scan = await db.get(Scan, scan_id)
        if not scan:
            raise ValueError(f"Scan with ID {scan_id} not found.")

        scan.status = ScanStatus.PROCESSING
        await db.commit()

        try:
            # 2. Run PaddleOCR on ALL product images and combine text
            all_raw_text_parts = []
            all_bboxes = []  # Collect all bboxes for evidence cropping
            ocr_records = []

            # Normalize image inputs into a structured list of (side, image_path)
            if isinstance(image_paths, dict):
                items = list(image_paths.items())
            elif isinstance(image_paths, list) and image_paths and isinstance(image_paths[0], (tuple, list)):
                items = [(side, str(p)) for side, p in image_paths]
            else:
                side_labels = ["front", "back", "left", "right", "top", "bottom"]
                items = [(side_labels[idx] if idx < len(side_labels) else f"side_{idx}", str(p)) for idx, p in enumerate(image_paths)]

            primary_image_path = items[0][1]

            for side, image_path in items:
                ocr_payload = self.ocr_engine.process_image(image_path)

                # Store each OCR Result in Database
                ocr_record = OCRResult(
                    scan_id=scan.id,
                    image_side=side,
                    image_url=image_path,
                    raw_text=ocr_payload.raw_text,
                    processed_text=ocr_payload.processed_text,
                    confidence=ocr_payload.average_confidence,
                    bounding_boxes=ocr_payload.bounding_boxes_json,
                    extraction_method="paddleocr",
                    detected_language="en",
                )
                db.add(ocr_record)
                ocr_records.append(ocr_record)
                await db.flush()

                # Collect bboxes with image path for evidence cropping
                for bbox_item in ocr_payload.bounding_boxes_json:
                    bbox_item["_source_image"] = image_path
                all_bboxes.extend(ocr_payload.bounding_boxes_json)

                if ocr_payload.raw_text.strip():
                    all_raw_text_parts.append(f"[{side.upper()} LABEL]\n{ocr_payload.raw_text}")
                    logger.info(f"OCR [{side}]: extracted {len(ocr_payload.blocks)} text blocks")

            combined_ocr_text = "\n\n".join(all_raw_text_parts)
            logger.info(f"Combined OCR text ({len(combined_ocr_text)} chars): {combined_ocr_text[:200]}...")

            # 3. Layered Declaration Extraction on combined text from ALL images
            declarations = self.extractor.extract_declarations(combined_ocr_text)

            # 3.1 Comprehensive Ingredient Safety & Chemical Breakdown Engine
            ingr_text = getattr(declarations, "ingredients_list", None) or getattr(declarations, "composition", None) or ""
            ingredient_analysis = ingredient_engine.analyze_full_product(ingr_text)
            if declarations.raw_extractions is None:
                declarations.raw_extractions = {}
            declarations.raw_extractions["ingredient_analysis"] = ingredient_analysis

            # 3.2 Flagship Surrogate Advertising & Dark Pattern Intelligence Engine
            mfr = declarations.manufacturer_name or getattr(declarations, "packer_name", None) or ""
            prod_name = declarations.generic_product_name or ""
            brand_claims = getattr(declarations, "brand_claims", []) or []
            surrogate_analysis = surrogate_engine.analyze_product(
                brand_name=mfr,
                product_name=prod_name,
                ingredients_list=ingr_text,
                brand_claims=brand_claims,
                detected_text=combined_ocr_text,
            )
            declarations.raw_extractions["surrogate_analysis"] = surrogate_analysis

            # Store Declarations in Database
            decl_record = Declaration(
                scan_id=scan.id,
                manufacturer_name=declarations.manufacturer_name,
                packer_name=declarations.packer_name,
                importer_name=declarations.importer_name,
                generic_product_name=declarations.generic_product_name,
                net_quantity=declarations.net_quantity,
                unit=declarations.unit,
                mrp=declarations.mrp,
                currency=declarations.currency,
                manufacture_month=declarations.manufacture_month,
                manufacture_year=declarations.manufacture_year,
                consumer_care_name=declarations.consumer_care_name,
                consumer_care_phone=declarations.consumer_care_phone,
                consumer_care_email=declarations.consumer_care_email,
                consumer_care_address=declarations.consumer_care_address,
                field_confidence=declarations.field_confidence,
                raw_declarations=declarations.raw_extractions,
            )
            db.add(decl_record)
            await db.flush()

            # 4. Digital Twin: Find or create Product record
            product = await self._find_or_create_product(declarations, db)
            if product:
                scan.product_id = product.id
                db.add(scan)
                await db.flush()

            # Compare with historical (Digital Twin discrepancy detection)
            discrepancies = self._compare_with_historical(product, declarations)
            if discrepancies:
                logger.info(f"Digital Twin discrepancies detected: {discrepancies}")

            # 5. RAG Legal Knowledge Retrieval
            rag_context = self.rag_pipeline.search_legal_context(
                query=f"MRP declaration requirements net quantity {declarations.generic_product_name or ''}",
                top_k=3,
            )

            # 6. Deterministic Rule Engine Evaluation with RAG LLM Violation Grounding
            report = self.rule_engine.evaluate_declarations(
                scan_id=str(scan.id),
                declarations=declarations,
                source_image_url=primary_image_path,
                rag_context=rag_context,
                ocr_text=combined_ocr_text,
            )

            # Update Scan Status
            scan.status = ScanStatus.COMPLETED
            scan.overall_compliance = report.overall_status

            # 7. Save Violations and Evidence to DB (with bounding box crops)
            for rule_res in report.rule_results:
                # Ensure Rule exists in DB or create default
                rule_obj = await db.get(Rule, uuid.uuid5(uuid.NAMESPACE_DNS, rule_res.rule_id))
                if not rule_obj:
                    rule_obj = Rule(
                        id=uuid.uuid5(uuid.NAMESPACE_DNS, rule_res.rule_id),
                        rule_id=rule_res.rule_id,
                        title=rule_res.rule_title,
                        conditions={"field": rule_res.field_name, "citation": rule_res.citation},
                        outcome={"status": rule_res.status.value},
                    )
                    db.add(rule_obj)
                    await db.flush()
                else:
                    rule_obj.conditions = {"field": rule_res.field_name, "citation": rule_res.citation}
                    db.add(rule_obj)
                    await db.flush()

                # Add Violation Record
                violation_record = Violation(
                    scan_id=scan.id,
                    rule_id=rule_obj.id,
                    field_name=rule_res.field_name,
                    status=rule_res.status,
                    reason=rule_res.reason,
                )
                db.add(violation_record)
                await db.flush()

                # Evidence: find matching bounding box and crop it
                cropped_image_url = None
                bbox_data = None
                if rule_res.detected_value:
                    best_bbox = self._find_best_bbox_for_field(
                        rule_res.field_name, rule_res.detected_value, all_bboxes
                    )
                    if best_bbox:
                        bbox_data = best_bbox.get("bbox")
                        source_img = best_bbox.get("_source_image", primary_image_path)
                        cropped_image_url = self._crop_evidence_region(
                            source_img, bbox_data, scan.id, rule_res.field_name
                        )

                # Add Evidence Record
                ev_data = rule_res.evidence_package
                evidence_record = Evidence(
                    scan_id=scan.id,
                    violation_id=violation_record.id,
                    rule_id=rule_obj.id,
                    field=ev_data["field"],
                    detected_value=str(ev_data.get("detected_value") or ""),
                    source_image=ev_data["source_image"],
                    cropped_image=cropped_image_url,
                    bounding_box={"coords": bbox_data} if bbox_data else None,
                    ocr_confidence=ev_data["ocr_confidence"],
                    rule_version=ev_data["rule_version"],
                    file_hash=ev_data["file_hash"],
                )
                db.add(evidence_record)

            # 5. Visual Region Cropping for Nutrition Table and Ingredients
            try:
                crop_outcome = self.panel_cropper.process_packaging_images(
                    panel_images=items,
                    scan_id=scan.id,
                    all_ocr_bboxes=all_bboxes
                )
                scan.nutrition_table_image_url = crop_outcome.get("nutrition_table_image")
                scan.ingredients_image_url = crop_outcome.get("ingredients_image")
                scan.crop_metadata = crop_outcome.get("crop_metadata")
                db.add(scan)
            except Exception as e:
                logger.warning(f"Packaging panel cropping encountered non-fatal error: {e}")

            await db.commit()

            logger.info(f"Scan {scan.id} processing finished. Overall Status: {report.overall_status}")

            return {
                "scan_id": str(scan.id),
                "status": scan.status.value,
                "overall_compliance": report.overall_status.value,
                "rule_definitions_version": report.rule_definitions_version,
                "product_id": str(product.id) if product else None,
                "image_urls": scan.image_urls,
                "nutrition_table_image": scan.nutrition_table_image_url,
                "ingredients_image": scan.ingredients_image_url,
                "crop_metadata": scan.crop_metadata,
                "digital_twin_discrepancies": discrepancies,
                "all_detected_text": combined_ocr_text,
                "ocr_transcriptions": [
                    {
                        "side": r.image_side,
                        "image_url": r.image_url,
                        "text": r.processed_text or r.raw_text,
                        "confidence": r.confidence,
                        "lines_detected": len((r.processed_text or r.raw_text or "").splitlines()),
                        "boxes_count": len(r.bounding_boxes) if isinstance(r.bounding_boxes, list) else 0,
                        "bounding_boxes": r.bounding_boxes or [],
                    }
                    for r in ocr_records
                ],
                "brand_claims": getattr(declarations, "brand_claims", []) or [],
                "summary_sentences": getattr(declarations, "summary_sentences", []) or [],
                "declarations_table": getattr(declarations, "declarations_table", []) or [],
                "front_panel_table": getattr(declarations, "front_panel_table", []) or [],
                "back_panel_table": getattr(declarations, "back_panel_table", []) or [],
                "left_panel_table": getattr(declarations, "left_panel_table", []) or [],
                "right_panel_table": getattr(declarations, "right_panel_table", []) or [],
                "all_key_value_pairs": getattr(declarations, "all_key_value_pairs", []) or [],
                "ingredients_list": getattr(declarations, "ingredients_list", None),
                "ingredient_analysis": ingredient_analysis,
                "nutrition_table": getattr(declarations, "nutrition_table", None),
                "allergen_info": getattr(declarations, "allergen_info", None),
                "storage_instructions": getattr(declarations, "storage_instructions", None),
                "usage_instructions": getattr(declarations, "usage_instructions", None),
                "composition": getattr(declarations, "composition", None),
                "certifications": getattr(declarations, "certifications", None),
                "legal_disclaimer": getattr(declarations, "legal_disclaimer", None),
                "other_text_blocks": getattr(declarations, "other_text_blocks", None),
                "extracted_declarations": {
                    "mrp": declarations.mrp,
                    "currency": getattr(declarations, "currency", "INR"),
                    "net_quantity": declarations.net_quantity,
                    "unit": declarations.unit,
                    "manufacturer_name": declarations.manufacturer_name,
                    "packer_name": getattr(declarations, "packer_name", None),
                    "importer_name": getattr(declarations, "importer_name", None),
                    "generic_product_name": declarations.generic_product_name,
                    "manufacture_month": declarations.manufacture_month,
                    "manufacture_year": declarations.manufacture_year,
                    "consumer_care_name": getattr(declarations, "consumer_care_name", None),
                    "consumer_care_email": declarations.consumer_care_email,
                    "consumer_care_phone": declarations.consumer_care_phone,
                    "consumer_care_address": getattr(declarations, "consumer_care_address", None),
                    "expiry_date": getattr(declarations, "expiry_date", None),
                    "batch_number": getattr(declarations, "batch_number", None),
                    "brand_claims": getattr(declarations, "brand_claims", []) or [],
                    "summary_sentences": getattr(declarations, "summary_sentences", []) or [],
                    "declarations_table": getattr(declarations, "declarations_table", []) or [],
                    "front_panel_table": getattr(declarations, "front_panel_table", []) or [],
                    "back_panel_table": getattr(declarations, "back_panel_table", []) or [],
                    "left_panel_table": getattr(declarations, "left_panel_table", []) or [],
                    "right_panel_table": getattr(declarations, "right_panel_table", []) or [],
                    "all_key_value_pairs": getattr(declarations, "all_key_value_pairs", []) or [],
                    **({k: v for k, v in (getattr(declarations, "dynamic_fields", None) or {}).items() if v is not None}),
                    **({k: v for k, v in (getattr(declarations, "raw_extractions", None) or {}).items() if v is not None}),
                },
                "compliance_summary": {
                    "passed_rules": report.passed_count,
                    "failed_rules": report.failed_count,
                    "review_rules": report.review_count,
                    "compliance_score": int((report.passed_count / max(1, (report.passed_count + report.failed_count + report.review_count))) * 100)
                },
                "surrogate_analysis": surrogate_analysis,
                "evaluations": [
                    {
                        "rule_id": r.rule_id,
                        "rule_code": getattr(r, "rule_code", None) or r.rule_id,
                        "rule_title": r.rule_title,
                        "status": r.status.value,
                        "reason": r.reason,
                        "evidence_hash": r.evidence_package.get("file_hash"),
                        "citation": r.citation,
                        "penalty": getattr(r, "penalty", None),
                    }
                    for r in report.rule_results
                ],
                "legal_context_citations": rag_context.get("retrieved_documents", []),
            }

        except Exception as e:
            logger.error(f"Error executing compliance pipeline for scan {scan_id}: {e}")
            scan.status = ScanStatus.FAILED
            await db.commit()
            raise
