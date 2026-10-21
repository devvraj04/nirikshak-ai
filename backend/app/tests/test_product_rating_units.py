import pytest
from app.services.product_rating import _parse_amount, rate_product


def _rows(**kw):
    names = {"sugars": "Sugars", "sat": "Saturated Fat", "sodium": "Sodium", "protein": "Protein", "fibre": "Dietary Fibre"}
    return [{"nutrient": names[k], "per_100g": v} for k, v in kw.items()]


def test_values_with_units_are_parsed():
    rows = _rows(sugars="4 g", sat="1 g", sodium="100 mg", protein="6 g", fibre="7 g")
    result = rate_product(rows)
    assert result["status"] == "provisional"
    assert result["rating_out_of_5"] == 5.0
    assert result["available_nutrients"]["sodium"] == 100.0


@pytest.mark.parametrize("value,unit,expected", [
    ("0.12 g", "mg", 120.0),      # sodium declared in grams -> mg
    ("120 mg", "mg", 120.0),
    ("500 mcg", "g", 0.0005),
    ("5.2g", "g", 5.2),
    ("1,5 g", "g", 1.5),          # decimal comma
    ("<0.5 g", "g", 0.5),         # upper bound is used as-is
    ("Nil", "g", 0.0),
    ("Trace", "mg", 0.0),
])
def test_parse_amount_converts_units(value, unit, expected):
    assert _parse_amount(value, unit) == pytest.approx(expected)


@pytest.mark.parametrize("value", ["10 %", "100 ml", "n/a", "", "abc", None, True])
def test_parse_amount_refuses_to_guess(value):
    assert _parse_amount(value, "g") is None


def test_plain_numbers_behave_as_before():
    assert _parse_amount(4, "g") == 4.0
    assert _parse_amount("4", "g") == 4.0
    assert _parse_amount(-1, "g") is None


def test_row_unit_is_used_when_value_has_none():
    assert _parse_amount("0.1", "mg", "g") == pytest.approx(100.0)
    assert _parse_amount("5", "g", "kcal") is None


def test_boundary_is_not_pushed_over_by_float_noise():
    rows = _rows(sugars="5 g", sat="1.5 g", sodium="0.12 g", protein="5 g", fibre="6 g")
    assert rate_product(rows)["rating_out_of_5"] == 5.0   # all exactly on the best-band edge
