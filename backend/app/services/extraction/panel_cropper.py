"""
NIRIKSHAK AI - Packaging Region Cropping Engine.

Detects, isolates, and crops the Nutrition Table and Ingredients Section
into separate high-resolution images using free-tier Vision LLMs (Google Gemini Flash / Groq Vision)
with deterministic PaddleOCR anchor clustering fallback.
"""

import base64
import json
import os
import re
import uuid
from typing import Any, Dict, List, Optional, Tuple
import cv2
import numpy as np

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger("services.extraction.panel_cropper")
settings = get_settings()


class PackagingRegionCropper:
    """
    Automated visual region detector and cropper for:
    1. Nutrition Facts / Information Tables
    2. Ingredients and Allergen Declarations
    """

    def __init__(self):
        self.gemini_api_key = getattr(settings, "gemini_api_key", "") or os.getenv("GEMINI_API_KEY", "")
        self.groq_api_key = getattr(settings, "groq_api_key", "") or os.getenv("GROQ_API_KEY", "")
        self._gemini_client = None
        self._groq_client = None

        if self.gemini_api_key:
            try:
                from google import genai
                self._gemini_client = genai.Client(api_key=self.gemini_api_key)
                # Primary modern model is gemini-2.5-flash / gemini-3.8-flash
                self._gemini_models = ["gemini-2.5-flash", "gemini-3.8-flash", "gemini-flash-latest"]
                logger.info("Configured Google GenAI SDK (google-genai) for packaging region cropping.")
            except Exception as e:
                logger.warning(f"Could not initialize Google GenAI client: {e}")

        if self.groq_api_key and not self._gemini_client:
            try:
                from groq import Groq
                self._groq_client = Groq(api_key=self.groq_api_key)
                logger.info("Configured Groq Vision for packaging region cropping.")
            except Exception as e:
                logger.warning(f"Could not initialize Groq client: {e}")

    def _encode_image_to_base64(self, image_path: str) -> str:
        """Encode an image file to a base64 data URI string."""
        with open(image_path, "rb") as img_file:
            encoded = base64.b64encode(img_file.read()).decode("utf-8")
        return f"data:image/jpeg;base64,{encoded}"

    def _detect_regions_gemini(self, image_path: str) -> Optional[Dict[str, Any]]:
        """Call Google Gemini Flash via new google-genai SDK to detect bounding boxes (0-1000 scale)."""
        if not self._gemini_client:
            return None

        prompt = """
        You are an expert document layout and food packaging inspection engine.
        Examine this product packaging image.
        Locate the exact bounding boxes for:
        1. "nutrition_table": The complete nutritional information panel, nutrition facts table, or electrolyte concentrations table (header, nutrients, values, per serve / per 100g, or osmolarity).
        2. "ingredients_section": The full ingredients declaration section or composition statement (starting with 'Ingredients:', 'Composition:', or 'Contains:' up to allergen warnings or excipients).

        Return ONLY a JSON object:
        {
          "has_nutrition_table": bool,
          "nutrition_table": {
            "box_2d": [ymin, xmin, ymax, xmax],
            "confidence": float
          },
          "has_ingredients": bool,
          "ingredients_section": {
            "box_2d": [ymin, xmin, ymax, xmax],
            "confidence": float
          }
        }
        Note: Bounding box coordinates must be normalized integers from 0 to 1000 relative to image height and width.
        If a section is not present on this packaging image, set its flag to false and box_2d to null.
        """
        try:
            from PIL import Image
            from google.genai import types

            pil_img = Image.open(image_path)
            candidate_models = getattr(self, "_gemini_models", ["gemini-2.5-flash", "gemini-3.8-flash"])
            response = None
            used_model = None

            for model_name in candidate_models:
                try:
                    response = self._gemini_client.models.generate_content(
                        model=model_name,
                        contents=[prompt, pil_img],
                        config=types.GenerateContentConfig(response_mime_type="application/json")
                    )
                    used_model = model_name
                    break
                except Exception as model_err:
                    logger.info(f"Model {model_name} attempt error: {model_err}, trying next fallback model...")

            if not response or not response.text:
                return None

            text_resp = response.text.strip()
            # Clean possible markdown block wrappers
            text_resp = re.sub(r"^```(?:json)?\s*", "", text_resp, flags=re.MULTILINE)
            text_resp = re.sub(r"\s*```$", "", text_resp, flags=re.MULTILINE)
            data = json.loads(text_resp)
            data["_provider"] = f"google-genai:{used_model}"
            return data
        except Exception as e:
            logger.warning(f"Gemini region detection failed for {image_path}: {e}")
            return None

    def _detect_regions_groq(self, image_path: str) -> Optional[Dict[str, Any]]:
        """Call Groq Llama 3.2 Vision to detect bounding boxes."""
        if not self._groq_client:
            return None

        base64_url = self._encode_image_to_base64(image_path)
        prompt = """
        Examine this product packaging image. Locate two bounding regions if present:
        1. "nutrition_table": Nutritional information table, nutrition facts, or electrolyte table.
        2. "ingredients_section": The full ingredients list or composition declaration block.

        Output ONLY valid JSON:
        {
          "has_nutrition_table": bool,
          "nutrition_table": {"box_2d": [ymin, xmin, ymax, xmax], "confidence": float},
          "has_ingredients": bool,
          "ingredients_section": {"box_2d": [ymin, xmin, ymax, xmax], "confidence": float}
        }
        Coordinates must be normalized integers from 0 to 1000. If missing, set flag to false and box_2d to null.
        """
        try:
            completion = self._groq_client.chat.completions.create(
                model="llama-3.2-11b-vision-preview",
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {"type": "image_url", "image_url": {"url": base64_url}},
                        ],
                    }
                ],
                temperature=0.1,
                max_tokens=600,
                response_format={"type": "json_object"},
            )
            data = json.loads(completion.choices[0].message.content)
            data["_provider"] = "groq-llama-3.2-vision"
            return data
        except Exception as e:
            logger.warning(f"Groq Vision region detection failed for {image_path}: {e}")
            return None

    def _detect_regions_paddleocr_fallback(
        self,
        image_path: str,
        ocr_bboxes: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """
        Deterministic fallback: clusters PaddleOCR word/line boxes around anchor keywords
        ('Nutrition', 'Ingredients', 'Composition', 'Electrolytes') to compute enclosing bounding rectangles.
        """
        result = {
            "has_nutrition_table": False,
            "nutrition_table": None,
            "has_ingredients": False,
            "ingredients_section": None,
            "_provider": "paddleocr-anchor-clustering"
        }

        if not ocr_bboxes:
            return result

        img = cv2.imread(image_path)
        if img is None:
            return result
        h, w = img.shape[:2]

        nutrition_boxes = []
        ingredient_boxes = []

        nutrition_anchors = ["nutrition", "nutritional", "facts", "per 100g", "energy", "carbohydrate", "protein", "fat", "electrolytes", "osmolarity", "approximate value"]
        ingredient_anchors = ["ingredients", "ingredient", "ingrédients", "contains", "allergen", "composition", "active ingredients", "samagri"]


        for item in ocr_bboxes:
            text = (item.get("text") or "").lower().strip()
            bbox = item.get("bbox") or []
            if not bbox or len(bbox) != 4:
                continue

            pts = np.array(bbox, dtype=np.float32)
            bx_min, by_min = pts[:, 0].min(), pts[:, 1].min()
            bx_max, by_max = pts[:, 0].max(), pts[:, 1].max()

            # Check if this box or adjacent boxes belong to nutrition facts
            if any(anchor in text for anchor in nutrition_anchors):
                nutrition_boxes.append((by_min, bx_min, by_max, bx_max))

            # Check if this box or adjacent boxes belong to ingredients
            if any(anchor in text for anchor in ingredient_anchors):
                ingredient_boxes.append((by_min, bx_min, by_max, bx_max))

        # Build Nutrition Bounding Box
        if nutrition_boxes:
            all_pts = np.array(nutrition_boxes)
            y_min = int(max(0, all_pts[:, 0].min()))
            x_min = int(max(0, all_pts[:, 1].min()))
            # Expand downward to catch typical nutrition table grid height
            y_max = int(min(h, all_pts[:, 2].max() + (h * 0.25)))
            x_max = int(min(w, all_pts[:, 3].max() + (w * 0.20)))

            # Normalize to 0-1000
            norm_box = [
                int((y_min / h) * 1000),
                int((x_min / w) * 1000),
                int((y_max / h) * 1000),
                int((x_max / w) * 1000),
            ]
            result["has_nutrition_table"] = True
            result["nutrition_table"] = {"box_2d": norm_box, "confidence": 0.85}

        # Build Ingredients Bounding Box
        if ingredient_boxes:
            all_pts = np.array(ingredient_boxes)
            y_min = int(max(0, all_pts[:, 0].min()))
            x_min = int(max(0, all_pts[:, 1].min()))
            # Expand downward to capture ingredient paragraph
            y_max = int(min(h, all_pts[:, 2].max() + (h * 0.15)))
            x_max = int(min(w, all_pts[:, 3].max() + (w * 0.25)))

            norm_box = [
                int((y_min / h) * 1000),
                int((x_min / w) * 1000),
                int((y_max / h) * 1000),
                int((x_max / w) * 1000),
            ]
            result["has_ingredients"] = True
            result["ingredients_section"] = {"box_2d": norm_box, "confidence": 0.80}

        return result

    def detect_regions(
        self,
        image_path: str,
        ocr_bboxes: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """
        Unified detection entry point:
        1. Attempts Gemini Flash (Free tier)
        2. Attempts Groq Vision (Free tier)
        3. Falls back to PaddleOCR anchor clustering
        """
        # 1. Try Gemini
        if self._gemini_client:
            res = self._detect_regions_gemini(image_path)
            if res and (res.get("has_nutrition_table") or res.get("has_ingredients")):
                return res

        # 2. Try Groq
        if self._groq_client:
            res = self._detect_regions_groq(image_path)
            if res and (res.get("has_nutrition_table") or res.get("has_ingredients")):
                return res

        # 3. Fallback to PaddleOCR keyword clustering
        return self._detect_regions_paddleocr_fallback(image_path, ocr_bboxes)

    def crop_normalized_box(
        self,
        image_path: str,
        box_2d: List[float],
        output_abs_path: str,
        padding_pct: float = 0.04
    ) -> bool:
        """
        Scales normalized coordinates [ymin, xmin, ymax, xmax] (0-1000 scale)
        to real image pixel coordinates with context padding, then writes the crop.
        """
        try:
            img = cv2.imread(image_path)
            if img is None:
                logger.error(f"Cannot read image at {image_path}")
                return False

            height, width = img.shape[:2]
            ymin, xmin, ymax, xmax = box_2d

            # Handle 0.0-1.0 float scale or 0-1000 integer scale
            if max(ymin, xmin, ymax, xmax) <= 1.0:
                y1 = int(ymin * height)
                x1 = int(xmin * width)
                y2 = int(ymax * height)
                x2 = int(xmax * width)
            else:
                y1 = int((ymin / 1000.0) * height)
                x1 = int((xmin / 1000.0) * width)
                y2 = int((ymax / 1000.0) * height)
                x2 = int((xmax / 1000.0) * width)

            # Ensure y1 < y2 and x1 < x2
            y1, y2 = min(y1, y2), max(y1, y2)
            x1, x2 = min(x1, x2), max(x1, x2)

            box_h = y2 - y1
            box_w = x2 - x1

            if box_h <= 5 or box_w <= 5:
                return False

            # Dynamic context padding
            pad_h = int(box_h * padding_pct)
            pad_w = int(box_w * padding_pct)

            y1 = max(0, y1 - pad_h)
            x1 = max(0, x1 - pad_w)
            y2 = min(height, y2 + pad_h)
            x2 = min(width, x2 + pad_w)

            cropped = img[y1:y2, x1:x2]
            if cropped.size == 0:
                return False

            os.makedirs(os.path.dirname(output_abs_path), exist_ok=True)
            cv2.imwrite(output_abs_path, cropped, [cv2.IMWRITE_JPEG_QUALITY, 95])
            logger.info(f"Successfully saved crop to {output_abs_path} (size: {cropped.shape[1]}x{cropped.shape[0]})")
            return True

        except Exception as e:
            logger.error(f"Failed to crop region from {image_path}: {e}")
            return False

    def process_packaging_images(
        self,
        panel_images: List[Tuple[str, str]],
        scan_id: uuid.UUID,
        all_ocr_bboxes: Optional[List[Dict[str, Any]]] = None,
        base_uploads_dir: str = "./data/uploads"
    ) -> Dict[str, Any]:
        """
        Iterates over packaging panels (back -> left -> right -> front -> others)
        to isolate and crop both the nutrition table and ingredient list.

        Args:
            panel_images: List of tuples (panel_name, local_file_path)
            scan_id: UUID of the scan
            all_ocr_bboxes: OCR bounding boxes across images for fallback
            base_uploads_dir: Root directory for saving crops

        Returns:
            Dict containing:
            - nutrition_table_image: HTTP relative path (e.g. /uploads/crops/nutrition/...)
            - ingredients_image: HTTP relative path (e.g. /uploads/crops/ingredients/...)
            - crop_metadata: Metadata with detection providers, panel sources, and bboxes
        """
        results: Dict[str, Any] = {
            "nutrition_table_image": None,
            "ingredients_image": None,
            "crop_metadata": {
                "panels_inspected": [],
                "detections": {}
            }
        }

        # Priority order for inspecting packaging panels
        panel_priority = {"back": 1, "left": 2, "right": 3, "bottom": 4, "top": 5, "front": 6, "main": 7}
        sorted_panels = sorted(
            panel_images,
            key=lambda item: panel_priority.get(item[0].lower(), 99)
        )

        for side, img_path in sorted_panels:
            if not os.path.exists(img_path):
                continue

            results["crop_metadata"]["panels_inspected"].append(side)

            # Filter OCR boxes corresponding to this source image
            side_bboxes = [b for b in (all_ocr_bboxes or []) if b.get("_source_image") == img_path] if all_ocr_bboxes else None

            detection = self.detect_regions(img_path, side_bboxes)
            results["crop_metadata"]["detections"][side] = detection

            # Determine crop subfolder
            if base_uploads_dir.rstrip("/\\").endswith("uploads"):
                crops_root = os.path.join(base_uploads_dir, "crops")
            else:
                crops_root = os.path.join(base_uploads_dir, "uploads", "crops")

            # 1. Nutrition Table Crop (if not yet found)
            if not results["nutrition_table_image"] and detection.get("has_nutrition_table"):
                nut_data = detection.get("nutrition_table") or {}
                box = nut_data.get("box_2d")
                if box and len(box) == 4:
                    filename = f"{scan_id}_nutrition_{side}.jpg"
                    rel_crop_url = f"/uploads/crops/nutrition/{filename}"
                    abs_crop_path = os.path.join(crops_root, "nutrition", filename)

                    if self.crop_normalized_box(img_path, box, abs_crop_path):
                        supa_url = None
                        if settings.storage_backend == "supabase":
                            try:
                                from app.services.storage import StorageService
                                st = StorageService()
                                with open(abs_crop_path, "rb") as cf:
                                    supa_url = st._upload_to_supabase_sync(cf.read(), "crops/nutrition", filename)
                            except Exception as e:
                                logger.debug(f"Could not sync nutrition crop to Supabase: {e}")

                        results["nutrition_table_image"] = supa_url or rel_crop_url
                        results["crop_metadata"]["nutrition_panel"] = side
                        results["crop_metadata"]["nutrition_box"] = box

            # 2. Ingredients Section Crop (if not yet found)
            if not results["ingredients_image"] and detection.get("has_ingredients"):
                ing_data = detection.get("ingredients_section") or {}
                box = ing_data.get("box_2d")
                if box and len(box) == 4:
                    filename = f"{scan_id}_ingredients_{side}.jpg"
                    rel_crop_url = f"/uploads/crops/ingredients/{filename}"
                    abs_crop_path = os.path.join(crops_root, "ingredients", filename)

                    if self.crop_normalized_box(img_path, box, abs_crop_path):
                        supa_url = None
                        if settings.storage_backend == "supabase":
                            try:
                                from app.services.storage import StorageService
                                st = StorageService()
                                with open(abs_crop_path, "rb") as cf:
                                    supa_url = st._upload_to_supabase_sync(cf.read(), "crops/ingredients", filename)
                            except Exception as e:
                                logger.debug(f"Could not sync ingredients crop to Supabase: {e}")

                        results["ingredients_image"] = supa_url or rel_crop_url
                        results["crop_metadata"]["ingredients_panel"] = side
                        results["crop_metadata"]["ingredients_box"] = box

            # Early exit if both critical sections are cropped
            if results["nutrition_table_image"] and results["ingredients_image"]:
                logger.info(f"Both nutrition and ingredients cropped successfully for scan {scan_id}.")
                break


        return results


# Global singleton instance
packaging_cropper = PackagingRegionCropper()
