
from app.services.extraction.declaration_extractor import DeclarationExtractor


def test_extracts_values_when_reporting_basis_is_explicit():
    text = """
    Nutrition Information per 100 g
    Energy 420 kcal
    Protein 8 g
    Carbohydrate 60 g
    Total Fat 12 g
    """

    rows = DeclarationExtractor._nutrition_table_regex_fallback(text)

    by_name = {row["nutrient"]: row for row in rows}

    assert by_name["energy"]["per_100g"] == "420 kcal"
    assert by_name["protein"]["per_100g"] == "8 g"
    assert by_name["carbohydrate"]["per_100g"] == "60 g"
    assert by_name["total fat"]["per_100g"] == "12 g"


def test_does_not_guess_reporting_basis():
    text = """
    Energy 420 kcal
    Protein 8 g
    """

    assert DeclarationExtractor._nutrition_table_regex_fallback(text) == []


def test_does_not_invent_values_when_nutrition_is_missing():
    text = """
    Sugar Free
    With Chromium
    Contains Milk Lactose
    """

    assert DeclarationExtractor._nutrition_table_regex_fallback(text) == []
