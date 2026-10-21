
"""Nutrition arithmetic audit for OCR-extracted packaged-food labels.

This is a screening calculation, not a legal compliance determination.
The simple energy formula must be adapted when product-specific factors apply.
"""

import re
from typing import Any


def _number(value: Any) -> float | None:
    """Extract numeric value from an OCR field, prioritizing kcal for energy."""
    if value is None:
        return None

    if isinstance(value, (int, float)):
        return float(value)

    text = str(value).strip().replace(",", "")
    # If energy has both kcal and kJ, prioritize kcal
    kcal_match = re.search(r"(\d+(?:\.\d+)?)\s*(?:kcal|cal)\b", text, re.IGNORECASE)
    if kcal_match:
        try:
            return float(kcal_match.group(1))
        except ValueError:
            pass

    kj_match = re.search(r"(\d+(?:\.\d+)?)\s*kj\b", text, re.IGNORECASE)
    if kj_match:
        try:
            return round(float(kj_match.group(1)) / 4.184, 1)
        except ValueError:
            pass

    match = re.search(r"[-+]?\d*\.?\d+", text)
    if not match:
        return None

    try:
        return float(match.group())
    except ValueError:
        return None


def _name(row: dict) -> str:
    raw = str(row.get("nutrient", row.get("name", ""))).lower().strip()
    cleaned = re.sub(r"\([^)]*\)", "", raw)
    cleaned = re.sub(r"^[-*•●\s]+", "", cleaned)
    return " ".join(cleaned.split()).strip()


def _amount(row: dict) -> float | None:
    # Prefer per-100-g/ml value when available, fallback to other column aliases.
    for key in (
        "per_100g", "per100g", "per_100_g", "per_100_ml", "per_100ml", "per100ml",
        "per_100gm", "per100gm", "amount", "value", "per_serving", "per_serve"
    ):
        if row.get(key) is not None:
            val = _number(row[key])
            if val is not None:
                return val
    return None


from app.services.product_rating import is_non_food_or_medicine


def audit_nutrition_table(
    rows: list[dict],
    tolerance_kcal: float = 10.0,
    product_category: str | None = None,
    ocr_text: str | None = None,
) -> dict:
    """Estimate energy from macronutrients and compare with declared energy."""
    if is_non_food_or_medicine(product_category, ocr_text) and not rows:
        cat_name = product_category if product_category and str(product_category).lower() != "unknown" else "Ayurvedic Medicine / Non-Food"
        return {
            "status": "not_applicable",
            "method": "general_atwater_4_4_9",
            "reason": f"Energy check is not applicable to {cat_name}.",
            "reason_code": "NOT_APPLICABLE_NON_FOOD",
            "user_message": (
                f"Energy consistency check applies to food and beverage nutrition tables, "
                f"which are not mandatory for {cat_name}."
            ),
            "next_step": None,
            "missing_nutrients": [],
            "declared_energy_kcal": None,
            "calculated_energy_kcal": None,
            "difference_kcal": None,
            "tolerance_kcal": tolerance_kcal,
        }

    nutrients: dict[str, float] = {}

    for row in rows:
        if not isinstance(row, dict):
            continue

        name = _name(row)
        amount = _amount(row)
        if amount is None or amount < 0:
            continue

        # Match nutrient names accurately, handling parenthetical units and plural forms.
        if "protein" in name or "proteins" in name:
            nutrients["protein"] = amount
        elif "carbohydrate" in name or "carbohydrates" in name or "carbs" in name:
            nutrients["carbohydrate"] = amount
        elif (
            ("total fat" in name or "fat" in name or "fats" in name or "lipid" in name)
            and "saturated" not in name
            and "trans" not in name
        ):
            nutrients["fat"] = amount
        elif "energy" in name or "calorie" in name or "calories" in name or "kcal" in name:
            nutrients["declared_energy"] = amount

    required = ("protein", "carbohydrate", "fat")
    missing = [key for key in required if key not in nutrients]

    if missing:
        return {
            "status": "inconclusive",
            "method": "general_atwater_4_4_9",
            "reason": "Required macronutrient values are missing.",
            "reason_code": "NO_NUTRITION_TABLE" if not nutrients else "MISSING_MACRONUTRIENTS",
            "user_message": (
                "No nutrition table was found on the scanned faces of this pack, so the energy cannot be checked."
                if not nutrients
                else "A nutrition table was found, but it is missing: " + ", ".join(missing)
                + ". The energy check needs protein, carbohydrate and fat."
            ),
            "next_step": (
                "Scan the side, back panel or blister card that carries the nutrition information, then analyse again."
                if not nutrients
                else "Re-scan the nutrition panel closer so every row is readable, then analyse again."
            ),
            "missing_nutrients": missing,
            "declared_energy_kcal": nutrients.get("declared_energy"),
            "calculated_energy_kcal": None,
            "difference_kcal": None,
            "tolerance_kcal": tolerance_kcal,
        }

    # Basic screening estimate only. Fibre and other energy contributors
    # are not included in this simplified formula.
    calculated = (
        4 * nutrients["protein"]
        + 4 * nutrients["carbohydrate"]
        + 9 * nutrients["fat"]
    )

    declared = nutrients.get("declared_energy")
    difference = round(calculated - declared, 2) if declared is not None else None

    if declared is None:
        status = "inconclusive"
    elif abs(difference) <= tolerance_kcal:
        status = "within_screening_tolerance"
    else:
        status = "review_required"

    return {
        "status": status,
        "method": "general_atwater_4_4_9",
        "basis": "per_100g_or_100ml",
        "declared_energy_kcal": declared,
        "calculated_energy_kcal": round(calculated, 2),
        "difference_kcal": difference,
        "tolerance_kcal": tolerance_kcal,
        "nutrients_used_g": {
            key: nutrients[key] for key in required
        },
        "warning": (
            "Screening estimate only. Confirm units, serving basis, "
            "applicable energy factors, fibre/polyols and label rounding "
            "before drawing a compliance conclusion."
        ),
    }
