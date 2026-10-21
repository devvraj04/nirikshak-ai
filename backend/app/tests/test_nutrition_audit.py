from app.services.nutrition_audit import audit_nutrition_table


def test_energy_within_screening_tolerance():
    rows = [
        {"nutrient": "Protein", "per_100g": "8 g"},
        {"nutrient": "Carbohydrate", "per_100g": "60 g"},
        {"nutrient": "Total Fat", "per_100g": "15 g"},
        {"nutrient": "Energy", "per_100g": "407 kcal"},
    ]

    result = audit_nutrition_table(rows)

    assert result["calculated_energy_kcal"] == 407.0
    assert result["status"] == "within_screening_tolerance"


def test_energy_discrepancy_requires_review():
    rows = [
        {"nutrient": "Protein", "per_100g": "8 g"},
        {"nutrient": "Carbohydrate", "per_100g": "60 g"},
        {"nutrient": "Total Fat", "per_100g": "15 g"},
        {"nutrient": "Energy", "per_100g": "350 kcal"},
    ]

    result = audit_nutrition_table(rows)

    assert result["status"] == "review_required"
    assert result["difference_kcal"] == 57.0


def test_missing_macronutrient_is_inconclusive():
    rows = [
        {"nutrient": "Protein", "per_100g": "8 g"},
        {"nutrient": "Energy", "per_100g": "100 kcal"},
    ]

    result = audit_nutrition_table(rows)

    assert result["status"] == "inconclusive"
    assert result["calculated_energy_kcal"] is None


def test_fat_with_parenthetical_unit_and_kj_kcal_energy():
    rows = [
        {"nutrient": "Protein (g)", "per_100g": "10.0"},
        {"nutrient": "Total Carbohydrate (g)", "per_100g": "50.0"},
        {"nutrient": "Fat (g)", "per_100g": "20.0"},
        {"nutrient": "Energy (kJ / kcal)", "per_100g": "1757 kJ / 420 kcal"},
    ]

    result = audit_nutrition_table(rows)

    assert result["status"] == "within_screening_tolerance"
    assert result["calculated_energy_kcal"] == 420.0
    assert result["declared_energy_kcal"] == 420.0
    assert result["difference_kcal"] == 0.0

    