
"""Nutrition arithmetic audit for OCR-extracted packaged-food labels.

This is a screening calculation, not a legal compliance determination.
The simple energy formula must be adapted when product-specific factors apply.
"""

import re
from typing import Any


def _number(value: Any) -> float | None:
    """Extract the first numeric value from an OCR field."""
    if value is None:
        return None

    if isinstance(value, (int, float)):
        return float(value)

    text = str(value).strip().replace(",", "")
    match = re.search(r"[-+]?\d*\.?\d+", text)
    if not match:
        return None

    try:
        return float(match.group())
    except ValueError:
        return None


def _name(row: dict) -> str:
    return str(row.get("nutrient", row.get("name", ""))).lower().strip()


def _amount(row: dict) -> float | None:
    # Prefer the per-100-g/ml value when available.
    for key in ("per_100g", "per100g", "per_100_ml", "amount"):
        if row.get(key) is not None:
            return _number(row[key])
    return None


def audit_nutrition_table(
    rows: list[dict],
    tolerance_kcal: float = 10.0,
) -> dict:
    """Estimate energy from macronutrients and compare with declared energy."""
    nutrients: dict[str, float] = {}

    for row in rows:
        if not isinstance(row, dict):
            continue

        name = _name(row)
        amount = _amount(row)
        if amount is None or amount < 0:
            continue

        # Only match nutrient names, not arbitrary text.
        if "protein" in name:
            nutrients["protein"] = amount
        elif "carbohydrate" in name or name == "carbs":
            nutrients["carbohydrate"] = amount
        elif name == "fat" or "total fat" in name:
            nutrients["fat"] = amount
        elif "energy" in name or "calorie" in name:
            nutrients["declared_energy"] = amount

    required = ("protein", "carbohydrate", "fat")
    missing = [key for key in required if key not in nutrients]

    if missing:
        return {
            "status": "inconclusive",
            "method": "general_atwater_4_4_9",
            "reason": "Required macronutrient values are missing.",
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
