"""Regression tests built from the real 'Sugar Free Gold+' scan (scan ea4cf11d).

Problems covered:
  1. the ingredient regex fallback treated the allergen line ("Contains Milk Lactose")
     as an ingredient list
  2. all_key_value_pairs duplicated every row and labelled back-panel rows as "front"
  3. nutrition audit / rating gave no machine-readable reason when no nutrition table exists
  4. the label points to a blister card / side of container that was never scanned
"""

from app.services.extraction.declaration_extractor import DeclarationExtractor
from app.services.label_coverage import label_coverage
from app.services.nutrition_audit import audit_nutrition_table
from app.services.product_rating import rate_product

FRONT = "Sugar\nFree\nTM\nGoldt\nwith Chromium\nSweetener for fitness conscious\nhaeds\n0\nAspar\nSweetener\nTable Top\nServing Suggestion only"
BACK = """in sweetness
Chromium Picolinate
AllergenContains Milk Lactose
Each 100 mg (1 pellet of Sugar Free Gold+ contains
1g of chromium (RDA as per ICMR 2020
Storage Condition:Keep in a cool& dry place
Do not refrigerate
Container not to be sold loose without the blister card
Refer Blister card for Regulatory/Statutory information
Net Quantity50 g (500 Pellets
from Zydus Wellness Limited
TM-Trademark under license
Wellness
Zydus
sugar in the diet
of Sucralose 5 mg/kg body weight/day
Date of Expiry-see on the side of container
For Batch No. Date of Packaging and
2075324"""
ALL_TEXT = f"[FRONT]\n{FRONT}\n\n[BACK]\n{BACK}"


# ---- 1. ingredient regex -------------------------------------------------------
def test_allergen_line_is_not_mistaken_for_ingredients():
    result = DeclarationExtractor.extract_layer1_regex(None, ALL_TEXT)
    assert "ingredients_list_regex" not in result


def test_real_ingredients_heading_is_still_captured():
    text = "[BACK]\nINGREDIENTS: Sugar, Salt, Spices (Chilli, Turmeric), Acidity Regulator (INS 330)\n\nStorage: keep cool"
    result = DeclarationExtractor.extract_layer1_regex(None, text)
    assert result["ingredients_list_regex"].startswith("Sugar, Salt, Spices")


def test_composition_heading_is_still_captured():
    text = "Composition: Wheat flour 70%, Palm oil, Sugar, Iodised salt\n\nMRP Rs 20"
    result = DeclarationExtractor.extract_layer1_regex(None, text)
    assert result["ingredients_list_regex"].startswith("Wheat flour")


# ---- 2. key/value pairs --------------------------------------------------------
FRONT_TABLE = [
    {"key": "Generic Product Name", "value": "Sugar Free Goldt", "category": "Statutory Declaration", "panel": "front", "is_brand_claim": False},
    {"key": "Net Quantity", "value": "50.0 g", "category": "Statutory Declaration", "panel": "front", "is_brand_claim": False},
]
BACK_TABLE = [
    {"key": "Allergen", "value": "Contains Milk Lactose", "category": "Allergen", "is_brand_claim": False},
    {"key": "Storage Condition", "value": "Keep in a cool& dry place", "category": "Storage", "is_brand_claim": False},
    {"key": "Do not refrigerate", "value": "", "category": "Storage", "is_brand_claim": False},
    {"key": "Net Quantity", "value": "50 g (500 Pellets", "category": "Product Identity", "is_brand_claim": False},
]


def test_key_value_pairs_have_no_duplicates_and_correct_panels():
    pairs = DeclarationExtractor._build_all_key_value_pairs({}, [], FRONT_TABLE, BACK_TABLE, [], [])
    assert len(pairs) == 6                                   # was 11 (every row duplicated)
    by_key = {(p["key"], p["panel"]) for p in pairs}
    assert ("Allergen", "back") in by_key                    # was mislabelled "front"
    assert ("Storage Condition", "back") in by_key
    assert ("Generic Product Name", "front") in by_key
    assert not any(p["key"] == "Allergen" and p["panel"] == "front" for p in pairs)


def test_key_value_pairs_keep_same_key_with_different_values():
    pairs = DeclarationExtractor._build_all_key_value_pairs({}, [], FRONT_TABLE, BACK_TABLE)
    net = [p["value"] for p in pairs if p["key"] == "Net Quantity"]
    assert sorted(net) == ["50 g (500 Pellets", "50.0 g"]


# ---- 3. machine-readable reasons -----------------------------------------------
def test_audit_with_no_table_says_so():
    result = audit_nutrition_table([])
    assert result["status"] == "inconclusive"
    assert result["reason"] == "Required macronutrient values are missing."   # unchanged text
    assert result["reason_code"] == "NO_NUTRITION_TABLE"
    assert "no nutrition table" in result["user_message"].lower()
    assert result["next_step"]


def test_audit_with_partial_table_names_what_is_missing():
    result = audit_nutrition_table([{"nutrient": "Energy", "per_100g": "380 kcal"}])
    assert result["reason_code"] == "MISSING_MACRONUTRIENTS"
    assert "protein" in result["user_message"]


def test_rating_with_no_table_explains_and_has_no_score():
    result = rate_product([], "Milk Lactose")
    assert result["status"] == "inconclusive"
    assert result["rating_out_of_5"] is None
    assert result["components"]["ingredients"] is None                       # still not invented
    assert result["reason_code"] == "NO_NUTRITION_TABLE"
    assert result["next_step"]


def test_rating_with_two_nutrients_says_how_many_were_read():
    rows = [{"nutrient": "Sugars", "per_100g": "4 g"}, {"nutrient": "Protein", "per_100g": "6 g"}]
    result = rate_product(rows)
    assert result["reason_code"] == "INSUFFICIENT_NUTRITION_DATA"
    assert "2 of 5" in result["user_message"]


def test_rating_with_enough_data_is_ok():
    rows = [{"nutrient": n, "per_100g": v} for n, v in
            (("Sugars", "4 g"), ("Saturated Fat", "1 g"), ("Sodium", "100 mg"), ("Protein", "6 g"), ("Dietary Fibre", "7 g"))]
    result = rate_product(rows)
    assert result["reason_code"] == "OK"
    assert result["rating_out_of_5"] == 5.0
    assert "user_message" not in result


# ---- 4. label coverage ---------------------------------------------------------
def test_label_points_to_blister_card_and_side_of_container():
    cov = label_coverage(ALL_TEXT, {"front": "/a.jpg", "back": "/b.jpg"})
    assert cov["scanned_faces"] == ["front", "back"]
    assert cov["unscanned_faces"] == ["left", "right", "top", "bottom"]
    assert cov["info_may_be_elsewhere"] is True
    assert "Refer Blister card for Regulatory/Statutory information" in cov["cues"]
    assert "Date of Expiry-see on the side of container" in cov["cues"]
    assert "Container not to be sold loose without the blister card" not in cov["cues"]   # not a pointer
    assert cov["message"]


def test_label_coverage_is_quiet_when_nothing_is_referenced():
    cov = label_coverage("[FRONT]\nCrunchy Chips\nNet Qty 50 g\nMRP Rs 20", {"front": "/a.jpg"})
    assert cov["cues"] == []
    assert cov["info_may_be_elsewhere"] is False
    assert cov["message"] == ""
