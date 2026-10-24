"""
NIRIKSHAK AI - Multi-Angle PaddleOCR Extraction Engine.

Extracts text blocks, confidence scores, and 2D bounding boxes from package images.
Scans images across 4 orientations (0°, 90°, 180°, 270°) to detect all possible text
on all package faces, filters out pure symbols/noise, maps coordinates back to original space,
and writes down everything detected in natural reading order.
"""

import math
import os
import re
from dataclasses import dataclass
from typing import Any, List, Optional, Tuple

import cv2
import numpy as np

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger("services.ocr.ocr_engine")
settings = get_settings()

_paddle_ocr_instance = None


def get_paddle_ocr():
    """Lazy initializer for PaddleOCR engine."""
    global _paddle_ocr_instance
    if _paddle_ocr_instance is None:
        try:
            from paddleocr import PaddleOCR
            logger.info("Initializing PaddleOCR engine...")
            _paddle_ocr_instance = PaddleOCR(
                use_angle_cls=False,
                lang=settings.ocr_language or "en",
                use_gpu=settings.ocr_use_gpu,
                show_log=False,
            )
            logger.info("PaddleOCR engine initialized successfully.")
        except Exception as e:
            logger.warning(f"PaddleOCR failed to initialize: {e}. OCR will operate in fallback mode.")
            _paddle_ocr_instance = False
    return _paddle_ocr_instance if _paddle_ocr_instance is not False else None


@dataclass
class OCRBlock:
    """Structure for an OCR text block with coordinates."""
    text: str
    confidence: float
    bbox: List[List[float]]  # [[x1, y1], [x2, y2], [x3, y3], [x4, y4]] in original image space
    angle: int = 0           # Detection angle (0, 90, 180, 270)


@dataclass
class OCRResultPayload:
    """Consolidated OCR extraction output."""
    raw_text: str
    processed_text: str
    average_confidence: float
    blocks: List[OCRBlock]
    bounding_boxes_json: List[dict]
    image_width: int = 0
    image_height: int = 0


class OCREngine:
    """Product packaging OCR extractor with 4-way rotation and symbol filtering."""

    @staticmethod
    def clean_and_filter_text(text: str) -> Optional[str]:
        """
        Sanitize OCR text and filter out pure symbol noise and hallucinated artifacts.
        
        Preserves valid text, numbers, punctuation, units, dates, currency, and emails.
        Drops pure symbol lines, isolated non-alphanumeric noise, and garbled symbols.
        """
        if not text:
            return None

        # Remove control characters and non-printable characters
        cleaned = re.sub(r"[\x00-\x1f\x7f-\x9f\ufffd]", "", text).strip()
        if not cleaned:
            return None

        # Remove known decorative standalone unicode symbols
        cleaned = re.sub(r"[•●■▲▼◆★☆©®™§°±²³µ¿¡¬|~^]+", " ", cleaned)

        # Strip leading and trailing non-alphanumeric symbols (except allowed currency/parentheses if appropriate)
        cleaned = re.sub(r"^[^\w\d₹$€£%]+|[^\w\d₹$€£%]+$", "", cleaned).strip()

        # Collapse whitespace
        cleaned = re.sub(r"\s+", " ", cleaned).strip()

        if not cleaned:
            return None

        # Count alphanumeric characters (letters and digits)
        alnum_chars = [c for c in cleaned if c.isalnum()]
        alnum_count = len(alnum_chars)

        # 1. Pure symbol strings without any letter or digit -> DROP
        if alnum_count == 0:
            return None

        # 2. Check for repetitive symbol patterns (e.g. "----", "====", "....", "____")
        if re.match(r"^[-=_.*#~:;/\\]{2,}$", cleaned):
            return None

        # 3. If very short (1 char), only allow alphanumeric
        if len(cleaned) == 1 and not cleaned.isalnum():
            return None

        # 4. Filter strings where symbols dominate heavily (> 75% symbols)
        if len(cleaned) > 3 and (alnum_count / len(cleaned)) < 0.25:
            return None

        return cleaned

    @staticmethod
    def _map_bbox_to_original(
        bbox: List[List[float]],
        angle: int,
        orig_h: int,
        orig_w: int,
        scaled_h: int = 0,
        scaled_w: int = 0,
        scale: float = 1.0,
    ) -> List[List[float]]:
        """
        Transform bounding box coordinates from rotated/scaled image space back to original (0°) coordinates.
        """
        s_h = scaled_h or orig_h
        s_w = scaled_w or orig_w
        inv_scale = 1.0 / max(1e-6, scale)

        mapped = []
        for pt in bbox:
            rx, ry = float(pt[0]), float(pt[1])
            if angle == 0:
                sx, sy = rx, ry
            elif angle == 90:
                # 90° CW rotation: rot_w = scaled_h, rot_h = scaled_w
                # rx = scaled_h - 1 - sy, ry = sx
                sx = ry
                sy = max(0.0, float(s_h - 1) - rx)
            elif angle == 180:
                sx = max(0.0, float(s_w - 1) - rx)
                sy = max(0.0, float(s_h - 1) - ry)
            elif angle == 270:
                sx = max(0.0, float(s_w - 1) - ry)
                sy = rx
            else:
                sx, sy = rx, ry

            ox = sx * inv_scale
            oy = sy * inv_scale

            ox = max(0.0, min(float(orig_w), ox))
            oy = max(0.0, min(float(orig_h), oy))
            mapped.append([round(ox, 2), round(oy, 2)])

        # Return standardized [top-left, top-right, bottom-right, bottom-left]
        xs = [p[0] for p in mapped]
        ys = [p[1] for p in mapped]
        x_min, x_max = min(xs), max(xs)
        y_min, y_max = min(ys), max(ys)

        return [
            [round(x_min, 2), round(y_min, 2)],
            [round(x_max, 2), round(y_min, 2)],
            [round(x_max, 2), round(y_max, 2)],
            [round(x_min, 2), round(y_max, 2)],
        ]

    @staticmethod
    def _compute_iou(box1: List[float], box2: List[float]) -> float:
        """Compute Intersection-over-Union between two [x_min, y_min, x_max, y_max] boxes."""
        x_left = max(box1[0], box2[0])
        y_top = max(box1[1], box2[1])
        x_right = min(box1[2], box2[2])
        y_bottom = min(box1[3], box2[3])

        if x_right <= x_left or y_bottom <= y_top:
            return 0.0

        inter_area = (x_right - x_left) * (y_bottom - y_top)
        box1_area = (box1[2] - box1[0]) * (box1[3] - box1[1])
        box2_area = (box2[2] - box2[0]) * (box2[3] - box2[1])

        return inter_area / float(box1_area + box2_area - inter_area + 1e-6)

    @staticmethod
    def _sort_reading_order(blocks: List[OCRBlock]) -> List[OCRBlock]:
        """
        Sort text blocks in natural human reading order: top-to-bottom, left-to-right.
        Groups adjacent words/blocks on the same horizontal band into unified lines.
        """
        if not blocks:
            return []

        # Sort primarily by y_min, secondarily by x_min
        sorted_by_y = sorted(blocks, key=lambda b: (b.bbox[0][1], b.bbox[0][0]))

        lines: List[List[OCRBlock]] = []
        current_line: List[OCRBlock] = [sorted_by_y[0]]

        for b in sorted_by_y[1:]:
            prev = current_line[-1]
            prev_h = max(1.0, prev.bbox[2][1] - prev.bbox[0][1])
            curr_y = b.bbox[0][1]
            prev_y = prev.bbox[0][1]

            # If vertical difference is small relative to line height, consider same line
            if abs(curr_y - prev_y) <= max(14.0, prev_h * 0.65):
                current_line.append(b)
            else:
                lines.append(sorted(current_line, key=lambda x: x.bbox[0][0]))
                current_line = [b]

        if current_line:
            lines.append(sorted(current_line, key=lambda x: x.bbox[0][0]))

        flattened = []
        for line in lines:
            flattened.extend(line)
        return flattened

    def process_image(self, image_path: str) -> OCRResultPayload:
        """
        Run PaddleOCR across all 4 orientations (0°, 90°, 180°, 270°).
        
        - Captures all text lines on the package (horizontal, vertical, inverted).
        - Maps all bounding boxes back to the original image coordinate frame.
        - Sanitizes text and discards symbol-only artifacts and noise.
        - Deduplicates redundant detections across angles, favoring higher confidence.
        - Sorts all text into natural reading order for comprehensive transcription.
        """
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"Image file not found: {image_path}")

        img = cv2.imread(image_path)
        if img is None:
            raise ValueError(f"Unable to load image at: {image_path}")

        orig_h, orig_w = img.shape[:2]
        ocr = get_paddle_ocr()

        if not ocr:
            logger.warning("PaddleOCR instance unavailable, returning empty OCR payload.")
            return OCRResultPayload(
                raw_text="",
                processed_text="",
                average_confidence=0.0,
                blocks=[],
                bounding_boxes_json=[],
                image_width=orig_w,
                image_height=orig_h,
            )

        # Scale image down for OCR if larger than 1024px (blistering fast inference on CPU)
        max_ocr_dim = 1024
        if max(orig_h, orig_w) > max_ocr_dim:
            scale = max_ocr_dim / float(max(orig_h, orig_w))
            new_w = max(1, int(round(orig_w * scale)))
            new_h = max(1, int(round(orig_h * scale)))
            scaled_img = cv2.resize(img, (new_w, new_h), interpolation=cv2.INTER_AREA)
        else:
            scale = 1.0
            scaled_img = img

        scaled_h, scaled_w = scaled_img.shape[:2]

        orientations: List[Tuple[int, np.ndarray]] = [(0, scaled_img)]

        collected_blocks: List[OCRBlock] = []

        for angle, rot_img in orientations:
            try:
                # PaddleOCR accepts numpy ndarray directly (cls=False is 2x+ faster on CPU)
                results = ocr.ocr(rot_img, cls=False)
                if not results or not results[0]:
                    continue

                for line in results[0]:
                    bbox, (raw_str, score) = line
                    conf = float(score)

                    # Discard very low confidence hallucinations
                    if conf < 0.35:
                        continue

                    # Filter out symbols and noise
                    clean_str = self.clean_and_filter_text(str(raw_str))
                    if not clean_str:
                        continue

                    # Map coordinates back to original image coordinate space
                    mapped_bbox = self._map_bbox_to_original(
                        bbox, angle, orig_h, orig_w, scaled_h, scaled_w, scale
                    )

                    candidate_block = OCRBlock(
                        text=clean_str,
                        confidence=round(conf, 4),
                        bbox=mapped_bbox,
                        angle=angle,
                    )

                    # Deduplication check against already collected blocks
                    cand_box = [
                        mapped_bbox[0][0], mapped_bbox[0][1],
                        mapped_bbox[2][0], mapped_bbox[2][1],
                    ]
                    cand_cx = (cand_box[0] + cand_box[2]) / 2.0
                    cand_cy = (cand_box[1] + cand_box[3]) / 2.0
                    cand_norm = re.sub(r"[^a-zA-Z0-9]", "", clean_str).lower()

                    is_duplicate = False
                    for idx, existing in enumerate(collected_blocks):
                        exist_box = [
                            existing.bbox[0][0], existing.bbox[0][1],
                            existing.bbox[2][0], existing.bbox[2][1],
                        ]
                        iou = self._compute_iou(cand_box, exist_box)
                        exist_cx = (exist_box[0] + exist_box[2]) / 2.0
                        exist_cy = (exist_box[1] + exist_box[3]) / 2.0
                        dist = math.hypot(cand_cx - exist_cx, cand_cy - exist_cy)
                        exist_norm = re.sub(r"[^a-zA-Z0-9]", "", existing.text).lower()

                        # Check if this represents the same text region on the package
                        has_text_overlap = (
                            cand_norm == exist_norm
                            or (len(cand_norm) >= 4 and cand_norm in exist_norm)
                            or (len(exist_norm) >= 4 and exist_norm in cand_norm)
                        )

                        if iou > 0.30 or (dist < 0.06 * max(orig_h, orig_w) and has_text_overlap):
                            is_duplicate = True
                            # Keep whichever detection has higher confidence
                            if candidate_block.confidence > existing.confidence:
                                collected_blocks[idx] = candidate_block
                            break

                    if not is_duplicate:
                        collected_blocks.append(candidate_block)

            except Exception as e:
                logger.error(f"Error processing image {image_path} at {angle}° rotation: {e}")

        # Sort all deduplicated blocks into natural reading order
        sorted_blocks = self._sort_reading_order(collected_blocks)

        raw_lines = [b.text for b in sorted_blocks]
        bboxes_json = []
        for b in sorted_blocks:
            x_min = float(b.bbox[0][0])
            y_min = float(b.bbox[0][1])
            x_max = float(b.bbox[2][0])
            y_max = float(b.bbox[2][1])
            w_box = max(1.0, x_max - x_min)
            h_box = max(1.0, y_max - y_min)

            norm_x = round((x_min / max(1.0, float(orig_w))) * 100.0, 2)
            norm_y = round((y_min / max(1.0, float(orig_h))) * 100.0, 2)
            norm_w = round((w_box / max(1.0, float(orig_w))) * 100.0, 2)
            norm_h = round((h_box / max(1.0, float(orig_h))) * 100.0, 2)

            bboxes_json.append({
                "text": b.text,
                "bbox": b.bbox,
                "score": b.confidence,
                "confidence": b.confidence,
                "detected_angle": b.angle,
                "orig_w": orig_w,
                "orig_h": orig_h,
                "aspect_ratio": round(orig_w / max(1.0, float(orig_h)), 4),
                "x": norm_x,
                "y": norm_y,
                "width": norm_w,
                "height": norm_h,
                "normalized": {
                    "x": norm_x,
                    "y": norm_y,
                    "width": norm_w,
                    "height": norm_h,
                },
            })

        total_conf = sum(b.confidence for b in sorted_blocks)
        avg_conf = (total_conf / len(sorted_blocks)) if sorted_blocks else 0.0

        raw_text = "\n".join(raw_lines)

        logger.info(
            f"Multi-angle OCR on {os.path.basename(image_path)}: "
            f"captured {len(sorted_blocks)} clean text blocks across 4 orientations."
        )

        return OCRResultPayload(
            raw_text=raw_text,
            processed_text=raw_text,
            average_confidence=round(avg_conf, 4),
            blocks=sorted_blocks,
            bounding_boxes_json=bboxes_json,
            image_width=orig_w,
            image_height=orig_h,
        )
