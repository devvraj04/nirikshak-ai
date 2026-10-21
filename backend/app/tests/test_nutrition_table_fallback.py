
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


def test_extracts_table_with_parenthetical_units_and_fssai_terms():
    text = """
    NUTRITIONAL INFORMATION
    (Approximate Values per 100g)
    Energy (kcal) 420
    Protein (g) 8.0
    Total Carbohydrate (g) 65.0
    Total Sugars (g) 22.0
    Added Sugars (g) 18.0
    Total Fat (g) 15.0
    Saturated Fatty Acids (g) 7.0
    Trans Fatty Acids (g) 0.0
    Sodium (mg) 350.0
    Dietary Fibre (g) 4.5
    """

    rows = DeclarationExtractor._nutrition_table_regex_fallback(text)
    by_name = {row["nutrient"]: row for row in rows}

    assert "energy" in by_name
    assert by_name["energy"]["per_100g"] == "420 kcal"
    assert by_name["protein"]["per_100g"] == "8.0 g"
    assert by_name["carbohydrate"]["per_100g"] == "65.0 g"
    assert by_name["sugars"]["per_100g"] == "22.0 g"
    assert by_name["added sugars"]["per_100g"] == "18.0 g"
    assert by_name["total fat"]["per_100g"] == "15.0 g"
    assert by_name["saturated fat"]["per_100g"] == "7.0 g"
    assert by_name["sodium"]["per_100g"] == "350.0 mg"
    assert by_name["dietary fibre"]["per_100g"] == "4.5 g"


def test_extracted_table_yields_valid_product_rating():
    from app.services.product_rating import rate_product

    text = """
    NUTRITIONAL INFORMATION
    Per 100g of product
    Energy (kcal) 420
    Protein (g) 8.0
    Carbohydrates (g) 65.0
    Total Sugars (g) 12.0
    Total Fat (g) 14.0
    Saturated Fatty Acids (g) 4.0
    Sodium (mg) 280.0
    Dietary Fibre (g) 5.0
    """

    rows = DeclarationExtractor._nutrition_table_regex_fallback(text)
    assert len(rows) >= 5

    rating = rate_product(rows)
    assert rating["status"] == "provisional"
    assert rating["reason_code"] == "OK"
    assert rating["rating_out_of_5"] is not None
    assert rating["rating_out_of_5"] > 0
    assert len(rating["available_nutrients"]) == 5


def test_multiline_ocr_block_table_extraction():
    text = """
    Nutrition Facts per 100g
    Energy (kcal)
    390
    Protein (g)
    9.5
    Total Carbohydrate (g)
    62.0
    Total Fat (g)
    11.0
    Sodium (mg)
    150.0
    """

    rows = DeclarationExtractor._nutrition_table_regex_fallback(text)
    by_name = {row["nutrient"]: row for row in rows}

    assert by_name["energy"]["per_100g"] == "390 kcal"
    assert by_name["protein"]["per_100g"] == "9.5 g"
    assert by_name["carbohydrate"]["per_100g"] == "62.0 g"
    assert by_name["total fat"]["per_100g"] == "11.0 g"
    assert by_name["sodium"]["per_100g"] == "150.0 mg"

