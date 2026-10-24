"""
NIRIKSHAK AI - Unit Tests for PackagingRegionCropper.
"""

import os
import shutil
import tempfile
import uuid
import cv2
import numpy as np
import pytest

from app.services.extraction.panel_cropper import PackagingRegionCropper


@pytest.fixture
def test_workspace():
    """Create a temporary directory for test images and crops."""
    temp_dir = tempfile.mkdtemp()
    yield temp_dir
    shutil.rmtree(temp_dir, ignore_errors=True)


@pytest.fixture
def synthetic_packaging_image(test_workspace):
    """Generate a synthetic packaging image with headers for testing."""
    img = np.ones((800, 600, 3), dtype=np.uint8) * 240  # Light gray background
    
    # Draw simulated nutrition table box
    cv2.rectangle(img, (50, 100), (400, 350), (200, 200, 200), -1)
    cv2.putText(img, "NUTRITIONAL FACTS", (60, 140), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 0), 2)
    cv2.putText(img, "Energy: 450 kcal", (60, 180), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 1)

    # Draw simulated ingredients section box
    cv2.rectangle(img, (50, 420), (550, 600), (220, 220, 220), -1)
    cv2.putText(img, "INGREDIENTS:", (60, 460), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 0), 2)
    cv2.putText(img, "Wheat Flour, Sugar, Palm Oil, Cocoa", (60, 500), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1)

    img_path = os.path.join(test_workspace, "sample_package_back.jpg")
    cv2.imwrite(img_path, img)
    return img_path


def test_crop_normalized_box_valid(synthetic_packaging_image, test_workspace):
    """Test normalized coordinate cropping with padding."""
    cropper = PackagingRegionCropper()
    out_crop = os.path.join(test_workspace, "output_crop.jpg")
    
    # 0-1000 normalized coordinates for the upper half
    box_2d = [125, 83, 437, 666]  # Approx y: 100-350, x: 50-400 on 800x600 image
    
    success = cropper.crop_normalized_box(synthetic_packaging_image, box_2d, out_crop, padding_pct=0.04)
    assert success is True
    assert os.path.exists(out_crop)
    
    cropped_img = cv2.imread(out_crop)
    assert cropped_img is not None
    assert cropped_img.shape[0] > 0
    assert cropped_img.shape[1] > 0


def test_crop_boundary_clamping(synthetic_packaging_image, test_workspace):
    """Test boundary clamping doesn't crash on out-of-bound coordinates."""
    cropper = PackagingRegionCropper()
    out_crop = os.path.join(test_workspace, "clamped_crop.jpg")
    
    # Box touching the edge
    box_2d = [0, 0, 1000, 1000]
    success = cropper.crop_normalized_box(synthetic_packaging_image, box_2d, out_crop, padding_pct=0.05)
    assert success is True
    assert os.path.exists(out_crop)


def test_paddleocr_fallback_anchor_clustering(synthetic_packaging_image, test_workspace):
    """Verify deterministic fallback clusters OCR bounding boxes accurately."""
    cropper = PackagingRegionCropper()
    
    # Mock OCR bounding boxes
    mock_bboxes = [
        {
            "text": "NUTRITIONAL FACTS",
            "confidence": 0.98,
            "bbox": [[50, 100], [300, 100], [300, 150], [50, 150]],
            "_source_image": synthetic_packaging_image,
        },
        {
            "text": "Energy: 450 kcal per 100g",
            "confidence": 0.95,
            "bbox": [[50, 160], [350, 160], [350, 200], [50, 200]],
            "_source_image": synthetic_packaging_image,
        },
        {
            "text": "INGREDIENTS: Wheat Flour, Sugar, Palm Oil",
            "confidence": 0.94,
            "bbox": [[50, 420], [520, 420], [520, 480], [50, 480]],
            "_source_image": synthetic_packaging_image,
        },
    ]

    detection = cropper._detect_regions_paddleocr_fallback(synthetic_packaging_image, mock_bboxes)
    
    assert detection["has_nutrition_table"] is True
    assert detection["nutrition_table"] is not None
    assert len(detection["nutrition_table"]["box_2d"]) == 4

    assert detection["has_ingredients"] is True
    assert detection["ingredients_section"] is not None
    assert len(detection["ingredients_section"]["box_2d"]) == 4


def test_process_packaging_images_flow(synthetic_packaging_image, test_workspace):
    """Test end-to-end packaging processing flow."""
    cropper = PackagingRegionCropper()
    scan_id = uuid.uuid4()
    
    mock_bboxes = [
        {
            "text": "NUTRITIONAL FACTS",
            "bbox": [[50, 100], [300, 100], [300, 150], [50, 150]],
            "_source_image": synthetic_packaging_image,
        },
        {
            "text": "INGREDIENTS: Wheat Flour, Sugar",
            "bbox": [[50, 420], [500, 420], [500, 480], [50, 480]],
            "_source_image": synthetic_packaging_image,
        },
    ]

    res = cropper.process_packaging_images(
        panel_images=[("back", synthetic_packaging_image)],
        scan_id=scan_id,
        all_ocr_bboxes=mock_bboxes,
        base_uploads_dir=test_workspace,
    )

    assert res["nutrition_table_image"] is not None
    assert res["ingredients_image"] is not None
    assert "nutrition" in res["nutrition_table_image"]
    assert "ingredients" in res["ingredients_image"]


def test_real_ketchup_packaging_image(test_workspace):
    """
    Test real packaging image: Tomato Ketchup pouch (1000093647.jpg).
    Contains:
    - Upper section: 'TOMATO KETCHUP INGREDIENTS: WATER, TOMATO PASTE...'
    - Lower section: 'NUTRITIONAL FACTS (APPROXIMATE VALUE) PER 100g...'
    """
    candidate_paths = [
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "1000093647.jpg")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "data", "1000093647.jpg")),
        "/app/data/1000093647.jpg",
        "1000093647.jpg",
    ]
    img_path = next((p for p in candidate_paths if os.path.exists(p)), None)
    if not img_path:
        pytest.skip("Ketchup test image 1000093647.jpg not found in candidate paths")

    img = cv2.imread(img_path)
    assert img is not None, f"Failed to load image at {img_path}"
    h, w = img.shape[:2]
    assert h > 0 and w > 0

    cropper = PackagingRegionCropper()
    scan_id = uuid.uuid4()

    # Coordinates corresponding to Ketchup pouch:
    # Ingredients: roughly y: 13%-38%, x: 8%-66% -> [130, 80, 380, 660] in 0-1000 scale
    # Nutrition Facts: roughly y: 38%-75%, x: 12%-68% -> [380, 120, 750, 680] in 0-1000 scale
    mock_ocr_bboxes = [
        {
            "text": "TOMATO KETCHUP INGREDIENTS: WATER, TOMATO PASTE (29%)",
            "bbox": [[int(w * 0.08), int(h * 0.14)], [int(w * 0.65), int(h * 0.14)], [int(w * 0.65), int(h * 0.22)], [int(w * 0.08), int(h * 0.22)]],
            "_source_image": img_path,
        },
        {
            "text": "NUTRITIONAL FACTS (APPROXIMATE VALUE) PER 100g PER SERVE",
            "bbox": [[int(w * 0.13), int(h * 0.40)], [int(w * 0.67), int(h * 0.40)], [int(w * 0.67), int(h * 0.48)], [int(w * 0.13), int(h * 0.48)]],
            "_source_image": img_path,
        },
    ]

    res = cropper.process_packaging_images(
        panel_images=[("back", img_path)],
        scan_id=scan_id,
        all_ocr_bboxes=mock_ocr_bboxes,
        base_uploads_dir=test_workspace,
    )

    assert res["nutrition_table_image"] is not None
    assert res["ingredients_image"] is not None

    # Verify cropped image files on disk
    nut_abs = os.path.join(test_workspace, res["nutrition_table_image"].lstrip("/"))
    ing_abs = os.path.join(test_workspace, res["ingredients_image"].lstrip("/"))

    assert os.path.exists(nut_abs), f"Nutrition crop file missing at {nut_abs}"
    assert os.path.exists(ing_abs), f"Ingredients crop file missing at {ing_abs}"

    nut_img = cv2.imread(nut_abs)
    ing_img = cv2.imread(ing_abs)

    assert nut_img is not None and nut_img.shape[0] > 50 and nut_img.shape[1] > 50
    assert ing_img is not None and ing_img.shape[0] > 50 and ing_img.shape[1] > 50


def test_real_ors_packaging_image(test_workspace):
    """
    Test real packaging image: Oral Rehydration Salts sachet (1000093645.jpg).
    Contains:
    - Top table: 'ELECTROLYTES mOsmol/Litre Sodium 75 Potassium 20...'
    - Bottom section: 'COMPOSITION: Each sachet (22.2g) contains: Sodium Chloride...'
    """
    candidate_paths = [
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "1000093645.jpg")),
        os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "data", "1000093645.jpg")),
        "/app/data/1000093645.jpg",
        "1000093645.jpg",
    ]
    img_path = next((p for p in candidate_paths if os.path.exists(p)), None)
    if not img_path:
        pytest.skip("ORS test image 1000093645.jpg not found in candidate paths")

    img = cv2.imread(img_path)
    assert img is not None, f"Failed to load image at {img_path}"
    h, w = img.shape[:2]
    assert h > 0 and w > 0

    cropper = PackagingRegionCropper()
    scan_id = uuid.uuid4()

    mock_ocr_bboxes = [
        {
            "text": "ELECTROLYTES mOsmol/Litre Sodium Potassium Chloride Citrate Dextrose",
            "bbox": [[int(w * 0.48), int(h * 0.16)], [int(w * 0.70), int(h * 0.16)], [int(w * 0.70), int(h * 0.48)], [int(w * 0.48), int(h * 0.48)]],
            "_source_image": img_path,
        },
        {
            "text": "COMPOSITION: Each sachet (22.2g) contains: Sodium Chloride Potassium Chloride",
            "bbox": [[int(w * 0.26), int(h * 0.73)], [int(w * 0.46), int(h * 0.73)], [int(w * 0.46), int(h * 0.90)], [int(w * 0.26), int(h * 0.90)]],
            "_source_image": img_path,
        },
    ]

    res = cropper.process_packaging_images(
        panel_images=[("back", img_path)],
        scan_id=scan_id,
        all_ocr_bboxes=mock_ocr_bboxes,
        base_uploads_dir=test_workspace,
    )

    assert res["nutrition_table_image"] is not None
    assert res["ingredients_image"] is not None

    nut_abs = os.path.join(test_workspace, res["nutrition_table_image"].lstrip("/"))
    ing_abs = os.path.join(test_workspace, res["ingredients_image"].lstrip("/"))

    assert os.path.exists(nut_abs), f"Nutrition/Electrolytes crop file missing at {nut_abs}"
    assert os.path.exists(ing_abs), f"Composition crop file missing at {ing_abs}"

    nut_img = cv2.imread(nut_abs)
    ing_img = cv2.imread(ing_abs)

    assert nut_img is not None and nut_img.shape[0] > 50 and nut_img.shape[1] > 50
    assert ing_img is not None and ing_img.shape[0] > 50 and ing_img.shape[1] > 50

