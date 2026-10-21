"""Transparent, deterministic consumer-facing product rating.

Informational screening only; not a validated medical or regulatory score.
"""

import re
from typing import Any


NUTRIENTS = {
    "sugars": (
        "sugars", "total sugars", "sugar", "total sugar", "added sugars", "added sugar",
        "of which sugars", "of which sugar", "of which total sugars", "sucrose",
    ),
    "saturated_fat": (
        "saturated fat", "saturated fats", "saturated_fats",
        "saturated fatty acids", "saturated fatty acid", "sat fat", "sat. fat", "sat fats",
        "sat. fats", "of which saturated fat", "of which saturated fatty acids",
    ),
    "sodium": ("sodium", "salt"),
    "protein": ("protein", "proteins", "crude protein", "total protein"),
    "fibre": (
        "dietary fibre", "dietary fiber", "fibre", "fiber",
        "crude fibre", "crude fiber", "total dietary fibre", "total dietary fiber",
    ),
}

MIN_NUTRIENTS = 3

# The bands in rate_product() assume sodium in mg and every other nutrient in g.
_CANONICAL_UNIT = {"sodium": "mg"}
_UNIT_IN_GRAMS = {"g": 1.0, "gm": 1.0, "mg": 1e-3, "mcg": 1e-6, "µg": 1e-6, "μg": 1e-6, "ug": 1e-6}
_ZERO_WORDS = {"nil", "nill", "zero", "trace", "traces", "absent"}
_AMOUNT_RE = re.compile(r"^\s*[<≤]?\s*(\d+(?:[.,]\d+)?)\s*(mg|mcg|µg|μg|ug|gm|g)?", re.IGNORECASE)


def _clean_name(name: str) -> str:
    """Normalize nutrient names by removing parenthetical units, bullets, and prefixes."""
    cleaned = re.sub(r"\([^)]*\)", "", name)
    cleaned = re.sub(r"^[-*•●\s]+", "", cleaned)
    cleaned = re.sub(r"^(?:of which|which)\s+", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"[:\-_.]", " ", cleaned)
    return " ".join(cleaned.split()).strip().casefold()


def _numeric(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number < 0 or not (-float("inf") < number < float("inf")):
        return None
    return number


def _parse_amount(value: Any, canonical_unit: str = "g", row_unit: Any = None) -> float | None:
    """Parse a label amount into the nutrient's canonical unit (g, or mg for sodium).

    - plain numbers are taken as already being in the canonical unit (unchanged behaviour);
    - strings such as "5.2 g", "380 mg", "0.1g", "<0.5 g" are parsed and converted;
    - "Nil" / "Trace" count as 0;
    - anything ambiguous ("10 %", "100 ml", no number) returns None instead of guessing.
    """
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return _numeric(value)
    if not isinstance(value, str):
        return None

    text = value.strip()
    if text.casefold() in _ZERO_WORDS:
        return 0.0
    match = _AMOUNT_RE.match(text)
    if not match:
        return None
    rest = text[match.end():].lstrip()
    if rest:
        rest_lower = rest.casefold()
        if rest[0] == "%":
            return None
        # Allow trailing descriptors like '(approx.)' or words, but disallow unsupported units like 'ml'
        if rest_lower.startswith("ml") or rest_lower.startswith("l"):
            return None
        if rest[0].isalpha() and not (rest_lower.startswith("approx") or rest_lower.startswith("val")):
            return None

    number = float(match.group(1).replace(",", "."))
    unit = (match.group(2) or "").casefold()
    if not unit and row_unit not in (None, ""):
        unit = str(row_unit).strip().casefold()
        if unit not in _UNIT_IN_GRAMS:
            return None  # row unit is not a mass unit: do not guess
    if not unit:
        unit = canonical_unit
    if unit not in _UNIT_IN_GRAMS:
        return None
    if _UNIT_IN_GRAMS[unit] == _UNIT_IN_GRAMS[canonical_unit]:
        return number  # same unit: no conversion, so no floating-point noise at band edges
    return round(number * _UNIT_IN_GRAMS[unit] / _UNIT_IN_GRAMS[canonical_unit], 6)


def _nutrient_value(rows: list[dict], *names: str, unit: str = "g") -> float | None:
    wanted = {name.casefold() for name in names}
    for row in rows:
        if not isinstance(row, dict):
            continue
        raw_name = str(row.get("nutrient", row.get("name", ""))).strip().casefold()
        clean_name = _clean_name(raw_name)
        matched = (raw_name in wanted or clean_name in wanted)
        if not matched:
            matched = any(alias in raw_name or alias in clean_name for alias in wanted)
        if not matched:
            continue
        is_salt = unit == "mg" and ("salt" in clean_name or "salt" in raw_name) and "sodium" not in clean_name
        target_unit = "g" if is_salt else unit
        for key in (
            "per_100g", "per100g", "per_100_g", "per_100_ml", "per_100ml", "per100ml",
            "per_100gm", "per100gm", "per_100_gm", "amount", "value", "per_serving", "per_serve"
        ):
            if row.get(key) is not None:
                val = _parse_amount(row[key], target_unit, row.get("unit"))
                if val is not None:
                    # Salt to sodium conversion: 1g salt ≈ 400mg sodium
                    if is_salt:
                        val = round(val * 400.0, 2)
                    return val
    return None


def is_non_food_or_medicine(product_category: str | None = None, ocr_text: str | None = None) -> bool:
    """Check if the product is an Ayurvedic medicine, pharmaceutical, cosmetic, or non-food commodity.

    Under FSSAI regulations, mandatory nutritional labelling and energy consistency checks
    apply only to Food and Beverage products. Ayurvedic medicines (AYUSH), allopathic drugs,
    cosmetics, electronics, and general commodities are exempt.
    """
    if product_category:
        cat = str(product_category).lower().strip()
        if cat and cat != "unknown":
            non_food_keywords = (
                "ayurved", "medicine", "pharma", "drug", "lozenge", "pill",
                "cosmetic", "perfume", "fragrance", "deodorant", "soap", "shampoo",
                "electronic", "earphone", "appliance", "stationery", "apparel", "hardware",
                "oral rehydration"
            )
            if any(kw in cat for kw in non_food_keywords):
                return True

    if ocr_text:
        text = str(ocr_text).lower()
        medicine_cues = (
            "ayurvedic proprietary medicine",
            "ayurvedic medicine",
            "an ayurvedic",
            "ayush",
            "mfg. lic. no",
            "mfg.lic.no:nkd/ayu",
            "dosage:",
            "dose: 2 to 3 pills",
            "dose:",
            "chewable pill",
            "for throat relief",
            "oral rehydration salts i.p",
            "pocket perfume",
            "eau de parfum",
            "for external use only",
            "wired earphone",
        )
        has_medicine_cue = any(cue in text for cue in medicine_cues)
        has_nutrition_heading = bool(re.search(r"(?i)\b(?:nutri(?:tion(?:al)?|ment)?\s*(?:information|facts?|values?|declarations?|table))\b", text))
        if has_medicine_cue and not has_nutrition_heading:
            return True

    return False


def rate_product(
    nutrition_table: list[dict] | None,
    ingredients: str | list[str] | None = None,
    product_category: str | None = None,
    ocr_text: str | None = None,
) -> dict:
    rows = nutrition_table if isinstance(nutrition_table, list) else []

    if is_non_food_or_medicine(product_category, ocr_text) and not rows:
        cat_name = product_category if product_category and str(product_category).lower() != "unknown" else "Ayurvedic Medicine / Non-Food"
        return {
            "status": "not_applicable",
            "rating_out_of_5": None,
            "score_out_of_100": None,
            "components": {
                "nutrition": None,
                "ingredients": None,
                "evidence_completeness": 0.0,
            },
            "available_nutrients": {},
            "reasons": [
                f"Nutritional rating is not applicable to {cat_name}."
            ],
            "limitations": [
                f"This product is an {cat_name}. Under FSSAI regulations, mandatory nutritional labelling (Energy, Protein, Carbs, Fats) applies only to Food & Beverage items."
            ],
            "rubric_version": "provisional-1.1",
            "reason_code": "NOT_APPLICABLE_NON_FOOD",
            "user_message": (
                f"Nutritional rating is not applicable to {cat_name}. "
                "Nutritional panels are mandated under FSSAI only for food and beverage commodities."
            ),
            "next_step": None,
        }
    values = {
        key: _nutrient_value(rows, *aliases, unit=_CANONICAL_UNIT.get(key, "g"))
        for key, aliases in NUTRIENTS.items()
    }
    available = {key: value for key, value in values.items() if value is not None}

    ingredient_text = (
        " ".join(ingredients)
        if isinstance(ingredients, list)
        else ingredients
        if isinstance(ingredients, str)
        else ""
    ).strip()

    limitations = [
        "This provisional screening rubric is not a validated nutrition rating."
    ]
    if ingredient_text:
        limitations.append(
            "Ingredient text is available, but ingredient quality has not been scored or assessed."
        )
    else:
        limitations.append("Ingredient information is unavailable.")

    evidence_score = round(len(available) / len(NUTRIENTS) * 100, 1)
    nutrition_score = None
    reasons = []

    if len(available) >= MIN_NUTRIENTS:
        points = []

        bands = {
            "sugars": lambda v: 1.0 if v <= 5 else 0.5 if v <= 15 else 0.0,
            "saturated_fat": lambda v: 1.0 if v <= 1.5 else 0.5 if v <= 5 else 0.0,
            "sodium": lambda v: 1.0 if v <= 120 else 0.5 if v <= 600 else 0.0,
            "protein": lambda v: 1.0 if v >= 5 else 0.5 if v >= 1 else 0.0,
            "fibre": lambda v: 1.0 if v >= 6 else 0.5 if v >= 3 else 0.0,
        }
        points = [bands[key](value) for key, value in available.items()]
        nutrition_score = round(sum(points) / len(points) * 100, 1)
        reasons.append(
            "Provisional screening uses available per-100-g/ml nutrient values."
        )
    else:
        limitations.append(
            f"At least {MIN_NUTRIENTS} recognized nutrients with comparable "
            "per-100-g/ml values are required for screening."
        )

    components = {
        "nutrition": nutrition_score,
        "ingredients": None,
        "evidence_completeness": evidence_score,
    }

    result = {
        "status": "inconclusive" if nutrition_score is None else "provisional",
        "rating_out_of_5": (
            None if nutrition_score is None else round(nutrition_score / 20, 1)
        ),
        "score_out_of_100": nutrition_score,
        "components": components,
        "available_nutrients": available,
        "reasons": reasons,
        "limitations": limitations,
        "rubric_version": "provisional-1.1",
    }
    if nutrition_score is None:
        if not rows:
            result["reason_code"] = "NO_NUTRITION_TABLE"
            result["user_message"] = (
                "No nutrition table was found on the scanned faces of this pack, "
                "so a nutrition rating cannot be given."
            )
        else:
            result["reason_code"] = "INSUFFICIENT_NUTRITION_DATA"
            result["user_message"] = (
                f"Only {len(available)} of {len(NUTRIENTS)} supported nutrients could be read as "
                f"per-100 g/ml values; at least {MIN_NUTRIENTS} are needed."
            )
        result["next_step"] = (
            "Scan the side, back panel or blister card that carries the nutrition information, "
            "then analyse again."
        )
    else:
        result["reason_code"] = "OK"
    return result

