
from app.services.product_rating import rate_product


def test_missing_nutrition_is_inconclusive():
    result = rate_product([], None)

    assert result["status"] == "inconclusive"
    assert result["rating_out_of_5"] is None
    assert result["components"]["ingredients"] is None


def test_available_nutrition_returns_transparent_breakdown():
    rows = [
        {"nutrient": "Sugars", "per_100g": 4},
        {"nutrient": "Saturated Fat", "per_100g": 1},
        {"nutrient": "Sodium", "per_100g": 100},
        {"nutrient": "Protein", "per_100g": 6},
        {"nutrient": "Dietary Fibre", "per_100g": 7},
    ]

    result = rate_product(rows, None)

    assert result["status"] == "provisional"
    assert result["components"]["nutrition"] == 100
    assert result["components"]["ingredients"] is None
    assert result["rating_out_of_5"] == 5.0
    assert result["rubric_version"] == "provisional-1.1"


def test_ingredient_text_is_not_assigned_a_quality_score():
    result = rate_product(
        [{"nutrient": "Sugars", "per_100g": 20}],
        "Ingredients: flour, sugar, vegetable oil",
    )

    assert result["status"] == "inconclusive"
    assert result["components"]["ingredients"] is None
    assert result["components"]["nutrition"] is None
    assert any(
        "not been scored" in item
        for item in result["limitations"]
    )


def test_two_nutrients_are_not_enough_for_a_rating():
    rows = [
        {"nutrient": "Sugars", "per_100g": 4},
        {"nutrient": "Sodium", "per_100g": 100},
    ]

    result = rate_product(rows)

    assert result["status"] == "inconclusive"
    assert result["rating_out_of_5"] is None
    assert result["components"]["evidence_completeness"] == 40.0


def test_rating_with_parenthetical_units_and_fssai_terms():
    rows = [
        {"nutrient": "Total Sugars (g)", "per_100g": "4.0"},
        {"nutrient": "Saturated Fatty Acids (g)", "per_100g": "1.0"},
        {"nutrient": "Sodium (mg)", "per_100g": "100.0"},
        {"nutrient": "Protein (g)", "per_100g": "6.0"},
        {"nutrient": "Dietary Fibre (g)", "per_100g": "7.0"},
    ]

    result = rate_product(rows)
    assert result["status"] == "provisional"
    assert result["reason_code"] == "OK"
    assert result["rating_out_of_5"] == 5.0
    assert len(result["available_nutrients"]) == 5


def test_rating_with_salt_instead_of_sodium():
    rows = [
        {"nutrient": "Sugars (g)", "per_100g": "3.0"},
        {"nutrient": "Saturated Fat", "per_100g": "1.2"},
        {"nutrient": "Salt", "per_100g": "0.25 g"},  # 0.25g salt ≈ 100mg sodium
        {"nutrient": "Protein", "per_100g": "5.5"},
    ]

    result = rate_product(rows)
    assert result["status"] == "provisional"
    assert result["reason_code"] == "OK"
    assert result["available_nutrients"]["sodium"] == 100.0

