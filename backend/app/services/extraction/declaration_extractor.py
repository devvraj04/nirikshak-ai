"""
NIRIKSHAK AI - Layered Declaration Extraction Service.

Extracts mandatory Legal Metrology product declarations from OCR text using a 3-layer pipeline:
- Layer 1: Regex & Deterministic Extraction
- Layer 2: Groq LLM Full-Content Extraction (Zero Hallucination, Nothing Hidden)
- Layer 3: Validation & Field Normalization
"""

import json
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from groq import Groq

from app.core.config import get_settings
from app.core.logging import get_logger

logger = get_logger("services.extraction.declaration_extractor")
settings = get_settings()


@dataclass
class ExtractedDeclarations:
    """Dataclass holding extracted Legal Metrology fields and confidence metadata."""
    manufacturer_name: Optional[str] = None
    packer_name: Optional[str] = None
    importer_name: Optional[str] = None
    generic_product_name: Optional[str] = None
    net_quantity: Optional[float] = None
    unit: Optional[str] = None
    mrp: Optional[float] = None
    currency: str = "INR"
    manufacture_month: Optional[int] = None
    manufacture_year: Optional[int] = None
    consumer_care_name: Optional[str] = None
    consumer_care_phone: Optional[str] = None
    consumer_care_email: Optional[str] = None
    consumer_care_address: Optional[str] = None
    expiry_date: Optional[str] = None
    batch_number: Optional[str] = None
    product_category: str = "Unknown"
    brand_claims: Optional[List[Dict[str, Any]]] = None
    summary_sentences: Optional[List[str]] = None
    declarations_table: Optional[List[Dict[str, Any]]] = None
    front_panel_table: Optional[List[Dict[str, Any]]] = None
    back_panel_table: Optional[List[Dict[str, Any]]] = None
    left_panel_table: Optional[List[Dict[str, Any]]] = None
    right_panel_table: Optional[List[Dict[str, Any]]] = None
    all_key_value_pairs: Optional[List[Dict[str, Any]]] = None
    # ---- Full verbatim text blocks (not truncated, not summarised) ----
    ingredients_list: Optional[str] = None
    nutrition_table: Optional[List[Dict[str, Any]]] = None
    allergen_info: Optional[str] = None
    storage_instructions: Optional[str] = None
    usage_instructions: Optional[str] = None
    composition: Optional[str] = None
    certifications: Optional[List[str]] = None
    legal_disclaimer: Optional[str] = None
    other_text_blocks: Optional[List[Dict[str, str]]] = None
    # -------------------------------------------------------------------
    dynamic_fields: Dict[str, Any] = None
    field_confidence: Dict[str, float] = None
    raw_extractions: Dict[str, Any] = None


class DeclarationExtractor:
    """3-Layer Declaration Extractor."""

    def __init__(self):
        self.groq_client = None
        if settings.groq_api_key and settings.groq_api_key != "your_groq_api_key_here":
            try:
                self.groq_client = Groq(api_key=settings.groq_api_key)
            except Exception as e:
                logger.warning(f"Could not initialize Groq client: {e}")


    
    @staticmethod
    def _nutrition_table_regex_fallback(text: str) -> List[Dict[str, Any]]:
        """Extract nutrition rows from label OCR text with support for parenthetical units,
        two-column values (100g and serving), multi-line OCR blocks, and varied headers."""
        if not text:
            return []

        # Check for explicit basis or nutrition table heading
        basis_match = re.search(
            r"(?i)\b(?:per\s*(100\s*(?:g|gm|gms|ml|g\s*\/\s*ml)|serving|serve|pack|portion)|approximate\s*values\s*per\s*(100\s*(?:g|gm|gms|ml)))\b",
            text,
        )
        heading_match = re.search(
            r"(?i)\b(?:nutrition(?:al)?\s+(?:information|facts?|values?|declarations?|table)|typical\s+values)\b",
            text,
        )

        # Do not guess when text has neither a nutrition heading nor a reporting basis
        if not basis_match and not heading_match:
            return []

        basis_raw = (basis_match.group(1) if basis_match and basis_match.group(1) else (basis_match.group(2) if basis_match else "")) or ""
        basis_text = basis_raw.lower().replace(" ", "")
        value_key = "per_serving" if basis_text in {"serving", "serve", "pack", "portion"} else "per_100g"

        has_100g_mention = bool(re.search(r"(?i)\b(?:100\s*(?:g|gm|gms|ml))\b", text))
        has_serving_mention = bool(re.search(r"(?i)\b(?:serving|serve|portion|pack)\b", text))

        nutrient_specs = [
            ("energy", r"(?:energy(?:\s+value)?|caloric\s+value|calories|calorie)", "kcal"),
            ("protein", r"(?:protein|proteins|total\s+protein|crude\s+protein)", "g"),
            ("carbohydrate", r"(?:total\s+carbohydrates?|carbohydrates?|carbs)", "g"),
            ("added sugars", r"(?:added\s+sugars?|of\s+which\s+added\s+sugars?)", "g"),
            ("sugars", r"(?:total\s+sugars?|sugars?|sucrose)", "g"),
            ("saturated fat", r"(?:saturated\s+fatty\s+acids?|saturated\s+fats?|sat\.?\s*fats?)", "g"),
            ("trans fat", r"(?:trans\s+fatty\s+acids?|trans\s+fats?)", "g"),
            ("total fat", r"(?:total\s+fats?|fats?|total\s+lipids?|lipids?)", "g"),
            ("cholesterol", r"cholesterol", "mg"),
            ("dietary fibre", r"(?:total\s+dietary\s+fib(?:re|er)|dietary\s+fib(?:re|er)|fib(?:re|er)|crude\s+fib(?:re|er))", "g"),
            ("sodium", r"sodium", "mg"),
            ("salt", r"salt", "g"),
        ]

        rows: List[Dict[str, Any]] = []
        seen = set()
        lines = [line.strip() for line in text.splitlines() if line.strip()]

        for i, line in enumerate(lines):
            for canonical_name, name_pattern, default_unit in nutrient_specs:
                if canonical_name in seen:
                    continue

                match = re.search(
                    rf"(?i)^\s*[-*•●]?\s*(?:(?:of\s+which|which)\s+)?({name_pattern})"
                    r"(?:\s*\(([^)]*)\))?\s*[:\-=~]?\s*"
                    r"([<≤]?\s*\d+(?:[.,]\d+)?)\s*(kcal|kj|g|gm|mg|mcg|µg|ug)?"
                    r"(?:\s+([<≤]?\s*\d+(?:[.,]\d+)?)\s*(kcal|kj|g|gm|mg|mcg|µg|ug)?)?",
                    line,
                )

                val1, unit1, val2, unit2 = None, None, None, None

                if match:
                    paren_content = (match.group(2) or "").strip()
                    val1 = match.group(3)
                    unit1 = match.group(4) or None
                    val2 = match.group(5) or None
                    unit2 = match.group(6) or None

                    if not unit1 and paren_content:
                        unit_in_paren = re.search(r"(?i)\b(kcal|kj|g|gm|mg|mcg|µg|ug)\b", paren_content)
                        if unit_in_paren:
                            unit1 = unit_in_paren.group(1).lower()

                    if not unit1:
                        unit1 = default_unit
                else:
                    # Lookahead: Name on line i, value on line i+1
                    name_only_match = re.search(
                        rf"(?i)^\s*[-*•●]?\s*(?:(?:of\s+which|which)\s+)?({name_pattern})(?:\s*\(([^)]*)\))?\s*[:\-=~]?\s*$",
                        line,
                    )
                    if name_only_match and i + 1 < len(lines):
                        next_line = lines[i + 1]
                        val_match = re.match(
                            r"^\s*([<≤]?\s*\d+(?:[.,]\d+)?)\s*(kcal|kj|g|gm|mg|mcg|µg|ug)?(?:\s+([<≤]?\s*\d+(?:[.,]\d+)?)\s*(kcal|kj|g|gm|mg|mcg|µg|ug)?)?",
                            next_line,
                        )
                        if val_match:
                            paren_content = (name_only_match.group(2) or "").strip()
                            val1 = val_match.group(1)
                            unit1 = val_match.group(2) or None
                            val2 = val_match.group(3) or None
                            unit2 = val_match.group(4) or None
                            if not unit1 and paren_content:
                                unit_in_paren = re.search(r"(?i)\b(kcal|kj|g|gm|mg|mcg|µg|ug)\b", paren_content)
                                if unit_in_paren:
                                    unit1 = unit_in_paren.group(1).lower()
                            if not unit1:
                                unit1 = default_unit

                if val1 is not None:
                    seen.add(canonical_name)
                    row: Dict[str, Any] = {
                        "nutrient": canonical_name,
                        "per_serving": None,
                        "per_100g": None,
                        "unit": unit1,
                        "source_text": line,
                    }

                    formatted_val1 = f"{val1} {unit1}".strip() if unit1 else str(val1)

                    if val2 is not None:
                        formatted_val2 = f"{val2} {unit2 or unit1}".strip() if (unit2 or unit1) else str(val2)
                        row["per_100g"] = formatted_val1
                        row["per_serving"] = formatted_val2
                    else:
                        row[value_key] = formatted_val1
                        if value_key == "per_serving" and has_100g_mention:
                            row["per_100g"] = formatted_val1
                        elif value_key == "per_100g" and not row["per_serving"]:
                            row["per_100g"] = formatted_val1

                    rows.append(row)
                    break

        return rows

    # =========================================================================
    # LAYER 1: REGEX EXTRACTION
    # =========================================================================
    def extract_layer1_regex(self, text: str) -> Dict[str, Any]:
        """Extract key fields using regex patterns (fast, deterministic fallback)."""
        results = {}

        mrp_match = re.search(
            r"(?i)(?:mrp|rs\.?|₹|max\.?\s*retail\s*price)[\s:]*(?:incl\.?\s*of\s*all\s*taxes)?[\s:]*₹?\s*(\d+(?:\.\d{1,2})?)",
            text,
        )
        if mrp_match:
            try:
                results["mrp"] = float(mrp_match.group(1))
                results["currency"] = "INR"
            except ValueError:
                pass

        net_qty_match = re.search(
            r"(?i)(?:net\s*(?:qty|quantity|weight|wt)|content)[\s:]*(\d+(?:\.\d+)?)\s*(g|kg|ml|l|liter|litres|pcs|n|units?)",
            text,
        )
        if net_qty_match:
            try:
                results["net_quantity"] = float(net_qty_match.group(1))
                results["unit"] = net_qty_match.group(2).lower()
            except ValueError:
                pass

        date_match = re.search(
            r"(?i)(?:mfd|pkd|mfg|manufactured|packed|date)[\s:]*(\d{1,2})[/.-](\d{2,4})",
            text,
        )
        if date_match:
            try:
                m = int(date_match.group(1))
                y = int(date_match.group(2))
                if y < 100:
                    y += 2000
                if 1 <= m <= 12 and 2000 <= y <= 2030:
                    results["manufacture_month"] = m
                    results["manufacture_year"] = y
            except ValueError:
                pass

        email_match = re.search(r"[\w.-]+@[\w.-]+\.[a-zA-Z]{2,}", text)
        if email_match:
            results["consumer_care_email"] = email_match.group(0)

        phone_match = re.search(
            r"(?i)(?:phone|tel|contact|helpline|customer\s*care|call)[\s:]*([+\d\s-]{8,15})",
            text,
        )
        if phone_match:
            phone_str = phone_match.group(1).strip()
            if len(re.sub(r"\D", "", phone_str)) >= 8:
                results["consumer_care_phone"] = phone_str

        batch_match = re.search(
            r"(?i)(?:b\.?\s*no\.?|batch\s*(?:no\.?|number|#)?|lot\s*(?:no\.?|#)?)[\s:]*([A-Za-z0-9\/-]+)",
            text,
        )
        if batch_match:
            b_val = batch_match.group(1).strip()
            if len(b_val) >= 2 and not b_val.lower().startswith("date"):
                results["batch_number"] = b_val

        # Quick grab of full ingredients section
        ingr_match = re.search(
            r"(?i)\b(?:ingredients?|composition)\b\s*[:\-]?\s*([\s\S]{10,800}?)(?=\n\n|\Z|(?:nutritional|storage|allergen|best before|mfg|manufactured|packed|mrp|max\.?\s*retail))",
            text,
        )
        if ingr_match:
            results["ingredients_list_regex"] = ingr_match.group(1).strip()

        allergen_match = re.search(
            r"(?i)(?:allerg(?:en|y)\s*(?:advice|info(?:rmation)?|declaration)?|may\s+contain|contains?.*?(?:milk|wheat|soy|peanut|nut|gluten|egg|fish|shellfish))[\s\S]{0,400}?(?=\n\n|\Z)",
            text,
        )
        if allergen_match:
            results["allergen_info_regex"] = allergen_match.group(0).strip()

        return results

    # =========================================================================
    # LAYER 2: GROQ LLM FULL-CONTENT EXTRACTION (ZERO HALLUCINATION)
    # =========================================================================
    def extract_layer2_llm(self, text: str) -> Dict[str, Any]:
        """
        Extract ALL structured content from packaging OCR using Groq LLaMA.
        The LLM reproduces every piece of text verbatim — no truncation, no summaries,
        no invented values. Nothing is hidden.
        """
        if not self.groq_client:
            logger.info("Groq API key not set or invalid; skipping LLM extraction layer.")
            return {}

        prompt = (
            "You are a strict packaging information extraction engine with ZERO-HALLUCINATION policy.\n"
            "You are given raw OCR text from a product package (may include front and back labels).\n\n"
            "===========================================================\n"
            "ABSOLUTE RULES — FOLLOW EVERY RULE WITHOUT EXCEPTION:\n"
            "===========================================================\n"
            "RULE 1 — ZERO HALLUCINATION: Extract ONLY text, numbers, and phrases that LITERALLY appear in the OCR below.\n"
            "          Do NOT invent, guess, paraphrase, or add anything not in the OCR text. Not even a single word.\n"
            "RULE 2 — VERBATIM REPRODUCTION: For large text blocks (ingredients, nutrition, composition, storage,\n"
            "          allergen, instructions, disclaimer), copy the text EXACTLY as it appears in the OCR.\n"
            "          Do NOT truncate, summarize, or shorten them. Every character matters.\n"
            "RULE 3 — NOTHING HIDDEN: Every single piece of text in the OCR must appear somewhere in your output.\n"
            "          Nothing should be skipped. If a section does not fit any named field, put it in 'other_text_blocks'.\n"
            "RULE 4 — PANEL ASSIGNMENT: Use [FRONT LABEL] and [BACK LABEL] markers (if present) to assign items.\n"
            "          If no markers, use context clues to determine front vs back.\n"
            "RULE 5 — NULL FOR MISSING: If a field is genuinely not present in the OCR, set it to null.\n"
            "          Never fabricate a value.\n\n"
            "Return a single valid JSON object with EXACTLY these fields:\n\n"
            "{\n"
            '  "product_category": "string inferred from product type in OCR (e.g. Snack Food, Biscuit, Beverage, Cosmetic)",\n'
            '  "extracted_fields": {\n'
            '    "generic_product_name": "verbatim from OCR or null",\n'
            '    "brand_name": "verbatim from OCR or null",\n'
            '    "manufacturer_name": "verbatim from OCR or null",\n'
            '    "packer_name": "verbatim from OCR or null",\n'
            '    "importer_name": "verbatim from OCR or null",\n'
            '    "net_quantity": "number float or null",\n'
            '    "unit": "g or kg or ml or l or pcs or null",\n'
            '    "mrp": "number float or null",\n'
            '    "currency": "INR",\n'
            '    "manufacture_month": "integer 1-12 or null",\n'
            '    "manufacture_year": "integer or null",\n'
            '    "expiry_date": "verbatim from OCR or null",\n'
            '    "batch_number": "verbatim from OCR or null",\n'
            '    "consumer_care_name": "verbatim from OCR or null",\n'
            '    "consumer_care_phone": "verbatim from OCR or null",\n'
            '    "consumer_care_email": "verbatim from OCR or null",\n'
            '    "consumer_care_address": "verbatim full address from OCR or null",\n'
            '    "fssai_license_number": "verbatim from OCR or null",\n'
            '    "country_of_origin": "verbatim from OCR or null",\n'
            '    "barcode": "verbatim from OCR or null"\n'
            "  },\n\n"
            '  "ingredients_list": "COMPLETE VERBATIM text of the Ingredients/Composition/Contains section EXACTLY as printed - word for word, comma for comma. null if not present.",\n\n'
            '  "composition": "If there is a separate Composition section distinct from Ingredients, copy it verbatim here. null if same as ingredients_list or not present.",\n\n'
            '  "nutrition_table": [\n'
            "    {\n"
            '      "nutrient": "nutrient name verbatim from OCR",\n'
            '      "per_serving": "value verbatim or null",\n'
            '      "per_100g": "value verbatim or null",\n'
            '      "unit": "unit string verbatim or null"\n'
            "    }\n"
            "  ],\n\n"
            '  "allergen_info": "COMPLETE VERBATIM allergen declaration from OCR (e.g. Contains: Milk, Wheat. May contain traces of Peanuts.). null if not present.",\n\n'
            '  "storage_instructions": "COMPLETE VERBATIM storage/handling instructions from OCR. null if not present.",\n\n'
            '  "usage_instructions": "COMPLETE VERBATIM usage, preparation, serving, or directions-for-use text from OCR. null if not present.",\n\n'
            '  "certifications": ["list of verbatim certification/mark strings found in OCR. Empty list [] if none."],\n\n'
            '  "legal_disclaimer": "COMPLETE VERBATIM legal disclaimer, advisory note, or statutory warning from OCR. null if not present.",\n\n'
            '  "other_text_blocks": [\n'
            "    {\n"
            '      "label": "Section heading or description from OCR",\n'
            '      "text": "COMPLETE VERBATIM text of that section",\n'
            '      "panel": "front or back"\n'
            "    }\n"
            "  ],\n\n"
            '  "front_panel_table": [\n'
            "    {\n"
            '      "key": "field name",\n'
            '      "value": "verbatim value from OCR",\n'
            '      "category": "one of: Statutory Declaration, Brand Identity, Brand Claim, Product Identity, Statutory Emblem",\n'
            '      "is_brand_claim": true\n'
            "    }\n"
            "  ],\n\n"
            '  "back_panel_table": [\n'
            "    {\n"
            '      "key": "field name",\n'
            '      "value": "verbatim value from OCR",\n'
            '      "category": "one of: Statutory Declaration, Consumer Care, Regulatory License, Nutrition, Ingredients, Storage, Allergen, Instructions, Contact",\n'
            '      "is_brand_claim": false\n'
            "    }\n"
            "  ],\n\n"
            '  "all_key_value_pairs": [\n'
            "    {\n"
            '      "key": "parameter name",\n'
            '      "value": "verbatim value from OCR",\n'
            '      "panel": "front or back or general",\n'
            '      "category": "statutory or nutrition or ingredients or contact or claim or instructions or allergen or certification or identity or other",\n'
            '      "is_brand_claim": false\n'
            "    }\n"
            "  ],\n\n"
            '  "brand_claims": [\n'
            "    {\n"
            '      "claim": "EXACT VERBATIM promotional/quality/health/dietary claim from OCR",\n'
            '      "category": "e.g. Health and Nutrition, Purity and Quality, Taste and Sensory, Dietary",\n'
            '      "panel": "front or back",\n'
            '      "verification_note": "Voluntary marketing claim. Subject to consumer verification.",\n'
            '      "highlight": true\n'
            "    }\n"
            "  ],\n\n"
            '  "summary_sentences": [\n'
            '    "3-5 sentences describing the product STRICTLY based on what is in the raw OCR. No invented facts."\n'
            "  ],\n\n"
            '  "declarations_table": [\n'
            "    {\n"
            '      "attribute": "declaration name",\n'
            '      "value": "verbatim value",\n'
            '      "category": "Statutory Declaration or Brand Claim or Specification or Nutritional or Ingredients or Contact",\n'
            '      "panel": "front or back",\n'
            '      "is_brand_claim": false,\n'
            '      "highlight": false\n'
            "    }\n"
            "  ]\n"
            "}\n\n"
            f"RAW OCR TEXT (extract everything from this - miss nothing):\n\"\"\"\n{text}\n\"\"\""
        )

        try:
            candidate_models = [settings.llm_model, "llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768"]
            models_to_try = [m for m in dict.fromkeys(candidate_models) if m]
            content = None

            for model_name in models_to_try:
                try:
                    chat_completion = self.groq_client.chat.completions.create(
                        messages=[
                            {
                                "role": "system",
                                "content": (
                                    "You are a strict packaging label extraction engine. "
                                    "Respond with ONLY valid JSON. "
                                    "Never hallucinate. Never truncate ingredient lists or nutritional tables. "
                                    "Copy all text verbatim from the OCR input."
                                ),
                            },
                            {"role": "user", "content": prompt},
                        ],
                        model=model_name,
                        temperature=0.0,
                        response_format={"type": "json_object"},
                    )
                    content = chat_completion.choices[0].message.content
                    if content:
                        break
                except Exception as me:
                    logger.warning(f"Groq model {model_name} failed in declaration_extractor: {me}")

            if not content:
                return {}

            parsed = json.loads(content)
            logger.info("Groq LLM full-content extraction succeeded.")
            return parsed
        except Exception as e:
            logger.error(f"Groq LLM extraction error: {e}")
            return {}

    # =========================================================================
    # DETERMINISTIC BRAND CLAIMS & SUMMARY FALLBACK HELPERS
    # =========================================================================
    @staticmethod
    def _detect_brand_claims(ocr_text: str) -> List[Dict[str, Any]]:
        """Extract brand marketing claims, health promises, and slogans from OCR text."""
        claims = []
        if not ocr_text:
            return claims

        claim_patterns = [
            (r"(?i)\b(100%\s*(?:pure|natural|veg|vegetarian|organic|whole\s*wheat|cotton|recycled))\b", "Purity & Quality"),
            (r"(?i)\b(no\s*(?:added\s*sugar|preservatives|artificial\s*flavou?rs?|msg|colors?|colours?|cholesterol))\b", "Health & Ingredients"),
            (r"(?i)\b(zero\s*(?:trans\s*fat|cholesterol|sugar|calories))\b", "Nutrition & Health"),
            (r"(?i)\b(rich\s*in\s*(?:protein|fiber|fibre|calcium|iron|vitamins?|antioxidants?))\b", "Nutritional Benefit"),
            (r"(?i)\b(clinically\s*(?:proven|tested|approved))\b", "Clinical & Scientific"),
            (r"(?i)\b(dermatologically\s*(?:tested|approved))\b", "Safety & Testing"),
            (r"(?i)\b(traditional\s*(?:recipe|indian|taste|blend))\b", "Heritage & Taste"),
            (r"(?i)\b(crispy\s*(?:spiced|fried|baked)?\s*(?:potato|noodles|chips|flavour))\b", "Taste & Sensory"),
            (r"(?i)\b(guaranteed\s*(?:quality|freshness|purity|satisfaction))\b", "Brand Guarantee"),
            (r"(?i)\b(authentic\s*(?:taste|flavor|flavour|ingredients?))\b", "Authenticity"),
            (r"(?i)\b(eco\s*friendly|biodegradable|sustainable|cruelty\s*free)\b", "Environmental & Ethics"),
            (r"(?i)\b(best\s*quality|premium\s*quality|finest\s*quality)\b", "Quality Assertion"),
        ]

        seen = set()
        for line in ocr_text.splitlines():
            line_str = line.strip()
            if not line_str or line_str.startswith("["):
                continue
            for pattern, cat in claim_patterns:
                match = re.search(pattern, line_str)
                if match:
                    claim_text = line_str
                    if len(claim_text) > 80:
                        claim_text = match.group(0)
                    if claim_text.lower() not in seen:
                        seen.add(claim_text.lower())
                        claims.append({
                            "claim": claim_text,
                            "category": cat,
                            "context": f"Package disclosure: \"{line_str}\"",
                            "verification_note": f"Voluntary marketing claim under {cat}. Subject to consumer verification under CP Act 2019.",
                            "highlight": True,
                        })
        return claims

    @staticmethod
    def _build_front_panel_table(merged: Dict[str, Any], brand_claims: List[Dict[str, Any]], ocr_text: str) -> List[Dict[str, Any]]:
        """Construct structured table of key-value pairs strictly present on the FRONT face."""
        table = []
        if merged.get("generic_product_name"):
            table.append({
                "key": "Generic Product Name",
                "value": str(merged["generic_product_name"]),
                "category": "Statutory Declaration",
                "panel": "front",
                "is_brand_claim": False,
            })
        if merged.get("brand_name"):
            table.append({
                "key": "Brand Name",
                "value": str(merged["brand_name"]),
                "category": "Brand Identity",
                "panel": "front",
                "is_brand_claim": False,
            })
        if merged.get("net_quantity") is not None:
            unit_val = merged.get("unit") or ""
            table.append({
                "key": "Net Quantity",
                "value": f"{merged['net_quantity']} {unit_val}".strip(),
                "category": "Statutory Declaration",
                "panel": "front",
                "is_brand_claim": False,
            })
        lower_ocr = ocr_text.lower()
        if "100% veg" in lower_ocr or "vegetarian" in lower_ocr or "pure veg" in lower_ocr:
            table.append({
                "key": "Dietary Indicator",
                "value": "Vegetarian (Green Dot Emblem)",
                "category": "Statutory Emblem",
                "panel": "front",
                "is_brand_claim": False,
            })
        elif "non-veg" in lower_ocr or "non veg" in lower_ocr:
            table.append({
                "key": "Dietary Indicator",
                "value": "Non-Vegetarian (Brown Dot Emblem)",
                "category": "Statutory Emblem",
                "panel": "front",
                "is_brand_claim": False,
            })
        for claim_obj in brand_claims:
            claim_text = claim_obj.get("claim") or ""
            cat = claim_obj.get("category") or "Quality Assertion"
            if claim_text:
                table.append({
                    "key": f"Front Claim: {cat}",
                    "value": f"\u201c{claim_text}\u201d",
                    "category": "Brand Claim",
                    "panel": "front",
                    "is_brand_claim": True,
                })
        return table

    @staticmethod
    def _build_back_panel_table(merged: Dict[str, Any], brand_claims: List[Dict[str, Any]], ocr_text: str) -> List[Dict[str, Any]]:
        """Construct structured table of key-value pairs strictly present on the BACK face."""
        table = []
        if merged.get("mrp") is not None:
            cur = merged.get("currency") or "INR"
            symbol = "\u20b9" if cur == "INR" else cur
            table.append({
                "key": "Maximum Retail Price (MRP)",
                "value": f"{symbol} {merged['mrp']} (Incl. of all taxes)",
                "category": "Statutory Declaration",
                "panel": "back",
                "is_brand_claim": False,
            })
        m = merged.get("manufacture_month")
        y = merged.get("manufacture_year")
        if m and y:
            table.append({
                "key": "Date of Manufacture / Packing",
                "value": f"{m:02d}/{y}",
                "category": "Statutory Declaration",
                "panel": "back",
                "is_brand_claim": False,
            })
        elif y:
            table.append({
                "key": "Year of Manufacture",
                "value": str(y),
                "category": "Statutory Declaration",
                "panel": "back",
                "is_brand_claim": False,
            })
        if merged.get("expiry_date"):
            table.append({
                "key": "Expiry / Best Before Date",
                "value": str(merged["expiry_date"]),
                "category": "Statutory Declaration",
                "panel": "back",
                "is_brand_claim": False,
            })
        if merged.get("batch_number"):
            table.append({
                "key": "Batch / Lot Identifier",
                "value": str(merged["batch_number"]),
                "category": "Statutory Declaration",
                "panel": "back",
                "is_brand_claim": False,
            })
        if merged.get("manufacturer_name"):
            table.append({
                "key": "Manufacturer Name & Address",
                "value": str(merged["manufacturer_name"]),
                "category": "Statutory Declaration",
                "panel": "back",
                "is_brand_claim": False,
            })
        if merged.get("packer_name"):
            table.append({
                "key": "Packer Details",
                "value": str(merged["packer_name"]),
                "category": "Statutory Declaration",
                "panel": "back",
                "is_brand_claim": False,
            })
        if merged.get("importer_name"):
            table.append({
                "key": "Importer Details",
                "value": str(merged["importer_name"]),
                "category": "Statutory Declaration",
                "panel": "back",
                "is_brand_claim": False,
            })
        if merged.get("consumer_care_phone"):
            table.append({
                "key": "Consumer Helpline",
                "value": str(merged["consumer_care_phone"]),
                "category": "Consumer Care",
                "panel": "back",
                "is_brand_claim": False,
            })
        if merged.get("consumer_care_email"):
            table.append({
                "key": "Consumer Email",
                "value": str(merged["consumer_care_email"]),
                "category": "Consumer Care",
                "panel": "back",
                "is_brand_claim": False,
            })
        if merged.get("consumer_care_address"):
            table.append({
                "key": "Consumer Care Address",
                "value": str(merged["consumer_care_address"]),
                "category": "Consumer Care",
                "panel": "back",
                "is_brand_claim": False,
            })
        fssai_match = re.search(r"(?i)(?:fssai|lic\.?\s*no\.?)[\s:]*([0-9]{14})", ocr_text)
        if fssai_match:
            table.append({
                "key": "FSSAI License No.",
                "value": fssai_match.group(1),
                "category": "Regulatory License",
                "panel": "back",
                "is_brand_claim": False,
            })
        return table

    @staticmethod
    def _extract_side_ocr_text(ocr_text: str, side: str) -> str:
        """Extract text chunk corresponding to [SIDE LABEL]."""
        tag = f"[{side.upper()} LABEL]"
        if tag not in ocr_text:
            return ""
        parts = ocr_text.split(tag)
        if len(parts) > 1:
            chunk = parts[1].split("[")[0]
            return chunk.strip()
        return ""

    @classmethod
    def _build_left_panel_table(cls, merged: Dict[str, Any], ocr_text: str) -> List[Dict[str, Any]]:
        """Construct structured table of key-value pairs strictly on the LEFT face."""
        table = []
        left_text = cls._extract_side_ocr_text(ocr_text, "left")
        if left_text:
            for line in left_text.splitlines():
                line = line.strip()
                if ":" in line and len(line) > 3:
                    k, v = line.split(":", 1)
                    if k.strip() and v.strip():
                        table.append({
                            "key": k.strip(),
                            "value": v.strip(),
                            "category": "Left Panel Declaration",
                            "panel": "left",
                            "is_brand_claim": False,
                        })
        return table

    @classmethod
    def _build_right_panel_table(cls, merged: Dict[str, Any], ocr_text: str) -> List[Dict[str, Any]]:
        """Construct structured table of key-value pairs strictly on the RIGHT face."""
        table = []
        right_text = cls._extract_side_ocr_text(ocr_text, "right")
        if right_text:
            for line in right_text.splitlines():
                line = line.strip()
                if ":" in line and len(line) > 3:
                    k, v = line.split(":", 1)
                    if k.strip() and v.strip():
                        table.append({
                            "key": k.strip(),
                            "value": v.strip(),
                            "category": "Right Panel Declaration",
                            "panel": "right",
                            "is_brand_claim": False,
                        })
        return table

    @staticmethod
    def _build_all_key_value_pairs(
        merged: Dict[str, Any],
        brand_claims: List[Dict[str, Any]],
        front_table: List[Dict[str, Any]],
        back_table: List[Dict[str, Any]],
        left_table: Optional[List[Dict[str, Any]]] = None,
        right_table: Optional[List[Dict[str, Any]]] = None,
    ) -> List[Dict[str, Any]]:
        """Construct comprehensive master list of all key-value pairs without loss of detail."""
        pairs: List[Dict[str, Any]] = []
        seen: set = set()

        for panel, table in (
            ("front", front_table),
            ("back", back_table),
            ("left", left_table or []),
            ("right", right_table or []),
        ):
            for item in table or []:
                if not isinstance(item, dict):
                    continue
                key = item.get("key") or item.get("attribute") or ""
                if not key:
                    continue
                value = str(item.get("value") or "")
                identity = (key.lower(), value.lower(), panel)
                if identity in seen:
                    continue
                seen.add(identity)
                entry = dict(item)
                entry.update({
                    "key": key,
                    "value": value,
                    "panel": item.get("panel") or panel,
                    "category": item.get("category", "General"),
                    "is_brand_claim": item.get("is_brand_claim", False),
                })
                pairs.append(entry)

        return pairs

    @staticmethod
    def _build_declarations_table(merged: Dict[str, Any], brand_claims: List[Dict[str, Any]], product_category: str) -> List[Dict[str, Any]]:
        """Construct a structured, formatted table of all declarations and highlighted brand claims."""
        table = []

        if merged.get("generic_product_name"):
            table.append({
                "attribute": "Generic Product Name",
                "value": str(merged["generic_product_name"]),
                "category": "Statutory Declaration",
                "is_brand_claim": False,
                "highlight": False,
            })
        if product_category and product_category != "Unknown":
            table.append({
                "attribute": "Product Category",
                "value": str(product_category),
                "category": "Classification",
                "is_brand_claim": False,
                "highlight": False,
            })
        if merged.get("mrp") is not None:
            cur = merged.get("currency") or "INR"
            symbol = "\u20b9" if cur == "INR" else cur
            table.append({
                "attribute": "Maximum Retail Price (MRP)",
                "value": f"{symbol} {merged['mrp']} (Incl. of all taxes)",
                "category": "Statutory Declaration",
                "is_brand_claim": False,
                "highlight": False,
            })
        if merged.get("net_quantity") is not None:
            unit_val = merged.get("unit") or ""
            table.append({
                "attribute": "Net Quantity",
                "value": f"{merged['net_quantity']} {unit_val}".strip(),
                "category": "Statutory Declaration",
                "is_brand_claim": False,
                "highlight": False,
            })
        m = merged.get("manufacture_month")
        y = merged.get("manufacture_year")
        if m and y:
            table.append({
                "attribute": "Month & Year of Manufacture / Packing",
                "value": f"{m:02d}/{y}",
                "category": "Statutory Declaration",
                "is_brand_claim": False,
                "highlight": False,
            })
        elif y:
            table.append({
                "attribute": "Year of Manufacture",
                "value": str(y),
                "category": "Statutory Declaration",
                "is_brand_claim": False,
                "highlight": False,
            })
        if merged.get("expiry_date"):
            table.append({
                "attribute": "Expiry / Best Before Date",
                "value": str(merged["expiry_date"]),
                "category": "Statutory Declaration",
                "is_brand_claim": False,
                "highlight": False,
            })
        if merged.get("batch_number"):
            table.append({
                "attribute": "Batch / Lot Identifier",
                "value": str(merged["batch_number"]),
                "category": "Statutory Declaration",
                "is_brand_claim": False,
                "highlight": False,
            })
        if merged.get("manufacturer_name"):
            table.append({
                "attribute": "Manufacturer Name & Address",
                "value": str(merged["manufacturer_name"]),
                "category": "Statutory Declaration",
                "is_brand_claim": False,
                "highlight": False,
            })
        if merged.get("packer_name"):
            table.append({
                "attribute": "Packer Details",
                "value": str(merged["packer_name"]),
                "category": "Statutory Declaration",
                "is_brand_claim": False,
                "highlight": False,
            })
        if merged.get("importer_name"):
            table.append({
                "attribute": "Importer Details",
                "value": str(merged["importer_name"]),
                "category": "Statutory Declaration",
                "is_brand_claim": False,
                "highlight": False,
            })
        care_contacts = []
        if merged.get("consumer_care_phone"):
            care_contacts.append(f"Phone: {merged['consumer_care_phone']}")
        if merged.get("consumer_care_email"):
            care_contacts.append(f"Email: {merged['consumer_care_email']}")
        if merged.get("consumer_care_address"):
            care_contacts.append(f"Address: {merged['consumer_care_address']}")
        if care_contacts:
            table.append({
                "attribute": "Consumer Grievance Redressal",
                "value": " | ".join(care_contacts),
                "category": "Contact & Care",
                "is_brand_claim": False,
                "highlight": False,
            })
        for claim_obj in brand_claims:
            claim_text = claim_obj.get("claim") or ""
            claim_cat = claim_obj.get("category") or "Brand Claim"
            if claim_text:
                table.append({
                    "attribute": f"Brand Claim: {claim_cat}",
                    "value": claim_text,
                    "category": "Brand Claim",
                    "is_brand_claim": True,
                    "highlight": True,
                })

        return table

    @staticmethod
    def _build_summary_sentences(merged: Dict[str, Any], brand_claims: List[Dict[str, Any]], product_category: str) -> List[str]:
        """Construct natural narrative sentences describing the package info with brand claims highlighted."""
        sentences = []

        prod = merged.get("generic_product_name") or "Pre-packaged commodity"
        mrp = merged.get("mrp")
        cur = merged.get("currency") or "INR"
        symbol = "\u20b9" if cur == "INR" else cur
        qty = merged.get("net_quantity")
        unit_val = merged.get("unit") or ""

        s1 = f"This packaging represents {prod}"
        if qty:
            s1 += f" with a declared net quantity of {qty} {unit_val}".strip()
        if mrp:
            s1 += f", priced at {symbol} {mrp} inclusive of all statutory taxes."
        else:
            s1 += "."
        sentences.append(s1)

        m = merged.get("manufacture_month")
        y = merged.get("manufacture_year")
        exp = merged.get("expiry_date")
        batch = merged.get("batch_number")
        mfg_str = f"{m:02d}/{y}" if (m and y) else (str(y) if y else None)

        s2_parts = []
        if mfg_str:
            s2_parts.append(f"manufactured in {mfg_str}")
        if exp:
            s2_parts.append(f"valid until expiry date {exp}")
        if batch:
            s2_parts.append(f"under batch lot {batch}")
        mfr = merged.get("manufacturer_name")
        if mfr:
            s2_parts.append(f"by {mfr}")
        if s2_parts:
            sentences.append("The product was " + ", ".join(s2_parts) + ".")

        care_phone = merged.get("consumer_care_phone")
        care_email = merged.get("consumer_care_email")
        if care_phone or care_email:
            care_details = []
            if care_phone:
                care_details.append(f"helpline {care_phone}")
            if care_email:
                care_details.append(f"email {care_email}")
            sentences.append(f"Customer grievance redressal is provided via {' and '.join(care_details)}.")

        if brand_claims:
            claim_texts = [f"'{c['claim']}'" for c in brand_claims if c.get("claim")]
            if len(claim_texts) == 1:
                sentences.append(
                    f"Prominent Brand Claim Highlight: The packaging prominently asserts {claim_texts[0]} as a distinguished product guarantee."
                )
            elif len(claim_texts) > 1:
                joined_claims = ", ".join(claim_texts[:-1]) + " and " + claim_texts[-1]
                sentences.append(
                    f"Prominent Brand Claims Highlight: The brand emphasizes key marketing claims including {joined_claims} across the packaging faces."
                )

        return sentences

    # =========================================================================
    # LAYER 3: VALIDATION & MERGING PIPELINE
    # =========================================================================
    def extract_declarations(self, ocr_text: str) -> "ExtractedDeclarations":
        """
        Execute full 3-layer extraction pipeline.
        Merges regex, LLM extractions, and applies validation rules.
        """
        l1 = self.extract_layer1_regex(ocr_text)
        l2_raw = self.extract_layer2_llm(ocr_text)

        l2 = l2_raw.get("extracted_fields", l2_raw) if isinstance(l2_raw, dict) else {}
        product_category = l2_raw.get("product_category", "Unknown") if isinstance(l2_raw, dict) else "Unknown"

        merged: Dict[str, Any] = {}
        confidence_scores: Dict[str, float] = {}

        field_names = [
            "manufacturer_name", "packer_name", "importer_name",
            "generic_product_name", "net_quantity", "unit", "mrp", "currency",
            "manufacture_month", "manufacture_year", "expiry_date", "batch_number",
            "consumer_care_name", "consumer_care_phone",
            "consumer_care_email", "consumer_care_address",
        ]

        for fn in field_names:
            val = l1.get(fn) or l2.get(fn)
            if val is not None:
                merged[fn] = val
                if fn in l1 and fn in l2:
                    confidence_scores[fn] = 0.95
                elif fn in l1:
                    confidence_scores[fn] = 0.90
                else:
                    confidence_scores[fn] = 0.80
            else:
                merged[fn] = None
                confidence_scores[fn] = 0.0

        # Normalisations
        if merged.get("mrp") is not None:
            try:
                merged["mrp"] = float(merged["mrp"])
                if merged["mrp"] <= 0:
                    merged["mrp"] = None
            except (ValueError, TypeError):
                merged["mrp"] = None

        if merged.get("net_quantity") is not None:
            try:
                merged["net_quantity"] = float(merged["net_quantity"])
            except (ValueError, TypeError):
                merged["net_quantity"] = None

        if not merged.get("manufacture_month") and not merged.get("manufacture_year"):
            mfg_date_str = l2.get("manufacture_date") or l2.get("mfg_date") or l2.get("manufactured_date")
            if mfg_date_str and isinstance(mfg_date_str, str):
                date_match = re.search(r"(\d{4})[-/.](\d{1,2})|(\d{1,2})[-/.](\d{2,4})", mfg_date_str)
                if date_match:
                    try:
                        if date_match.group(1):
                            merged["manufacture_year"] = int(date_match.group(1))
                            merged["manufacture_month"] = int(date_match.group(2))
                        else:
                            mv = int(date_match.group(3))
                            yv = int(date_match.group(4))
                            merged["manufacture_month"] = mv
                            merged["manufacture_year"] = yv if yv >= 100 else yv + 2000
                    except (ValueError, TypeError):
                        pass

        unit_str = str(merged.get("unit") or "").lower().strip()
        if unit_str in ["liter", "litres", "ltr"]:
            merged["unit"] = "l"
        elif unit_str in ["grams", "gm"]:
            merged["unit"] = "g"
        elif unit_str in ["kilogram", "kgs"]:
            merged["unit"] = "kg"
        elif unit_str in ["milliliter", "mls"]:
            merged["unit"] = "ml"

        brand_claims = l2_raw.get("brand_claims") if isinstance(l2_raw, dict) else None
        if not brand_claims or not isinstance(brand_claims, list) or len(brand_claims) == 0:
            brand_claims = self._detect_brand_claims(ocr_text)

        front_panel_table = l2_raw.get("front_panel_table") if isinstance(l2_raw, dict) else None
        if not front_panel_table or not isinstance(front_panel_table, list) or len(front_panel_table) == 0:
            front_panel_table = self._build_front_panel_table(merged, brand_claims, ocr_text)

        back_panel_table = l2_raw.get("back_panel_table") if isinstance(l2_raw, dict) else None
        if not back_panel_table or not isinstance(back_panel_table, list) or len(back_panel_table) == 0:
            back_panel_table = self._build_back_panel_table(merged, brand_claims, ocr_text)

        left_panel_table = l2_raw.get("left_panel_table") if isinstance(l2_raw, dict) else None
        if not left_panel_table or not isinstance(left_panel_table, list) or len(left_panel_table) == 0:
            left_panel_table = self._build_left_panel_table(merged, ocr_text)

        right_panel_table = l2_raw.get("right_panel_table") if isinstance(l2_raw, dict) else None
        if not right_panel_table or not isinstance(right_panel_table, list) or len(right_panel_table) == 0:
            right_panel_table = self._build_right_panel_table(merged, ocr_text)

        all_key_value_pairs = l2_raw.get("all_key_value_pairs") if isinstance(l2_raw, dict) else None
        if not all_key_value_pairs or not isinstance(all_key_value_pairs, list) or len(all_key_value_pairs) == 0:
            all_key_value_pairs = self._build_all_key_value_pairs(merged, brand_claims, front_panel_table, back_panel_table, left_panel_table, right_panel_table)

        declarations_table = l2_raw.get("declarations_table") if isinstance(l2_raw, dict) else None
        if not declarations_table or not isinstance(declarations_table, list) or len(declarations_table) == 0:
            declarations_table = self._build_declarations_table(merged, brand_claims, product_category)

        summary_sentences = l2_raw.get("summary_sentences") if isinstance(l2_raw, dict) else None
        if not summary_sentences or not isinstance(summary_sentences, list) or len(summary_sentences) == 0:
            summary_sentences = self._build_summary_sentences(merged, brand_claims, product_category)

        # Full verbatim text blocks
        ingredients_list = (l2_raw.get("ingredients_list") if isinstance(l2_raw, dict) else None) or l1.get("ingredients_list_regex")

        nutrition_table = (
            (l2_raw.get("nutrition_table")
            or l2_raw.get("nutritional_table")
            or l2_raw.get("nutrition")
            or l2_raw.get("nutritional_information")
            or l2_raw.get("nutrition_facts"))
            if isinstance(l2_raw, dict)
            else None
        )

        # Normalize dictionary format to list of dicts
        if isinstance(nutrition_table, dict):
            converted = []
            for k, v in nutrition_table.items():
                if isinstance(v, dict):
                    converted.append({"nutrient": k, **v})
                else:
                    converted.append({"nutrient": k, "per_100g": str(v), "unit": None})
            nutrition_table = converted

        # Get deterministic fallback rows
        fallback_rows = self._nutrition_table_regex_fallback(ocr_text)

        if not isinstance(nutrition_table, list) or not nutrition_table:
            nutrition_table = fallback_rows
        elif fallback_rows:
            # If LLM returned a partial list missing core nutrients, merge from fallback
            existing_nutrients = {
                re.sub(r"[:\-_.\s]", "", str(r.get("nutrient", "")).lower())
                for r in nutrition_table if isinstance(r, dict)
            }
            for f_row in fallback_rows:
                f_norm = re.sub(r"[:\-_.\s]", "", str(f_row.get("nutrient", "")).lower())
                if f_norm and not any(f_norm in e or e in f_norm for e in existing_nutrients):
                    nutrition_table.append(f_row)
                    existing_nutrients.add(f_norm)
        
        allergen_info = (l2_raw.get("allergen_info") if isinstance(l2_raw, dict) else None) or l1.get("allergen_info_regex")
        storage_instructions = l2_raw.get("storage_instructions") if isinstance(l2_raw, dict) else None
        usage_instructions = l2_raw.get("usage_instructions") if isinstance(l2_raw, dict) else None
        composition = l2_raw.get("composition") if isinstance(l2_raw, dict) else None
        certifications = l2_raw.get("certifications") if isinstance(l2_raw, dict) else None
        legal_disclaimer = l2_raw.get("legal_disclaimer") if isinstance(l2_raw, dict) else None
        other_text_blocks = l2_raw.get("other_text_blocks") if isinstance(l2_raw, dict) else None

        return ExtractedDeclarations(
            manufacturer_name=merged.get("manufacturer_name"),
            packer_name=merged.get("packer_name"),
            importer_name=merged.get("importer_name"),
            generic_product_name=merged.get("generic_product_name"),
            net_quantity=merged.get("net_quantity"),
            unit=merged.get("unit"),
            mrp=merged.get("mrp"),
            currency=merged.get("currency") or "INR",
            manufacture_month=merged.get("manufacture_month"),
            manufacture_year=merged.get("manufacture_year"),
            consumer_care_name=merged.get("consumer_care_name"),
            consumer_care_phone=merged.get("consumer_care_phone"),
            consumer_care_email=merged.get("consumer_care_email"),
            consumer_care_address=merged.get("consumer_care_address"),
            expiry_date=merged.get("expiry_date"),
            batch_number=merged.get("batch_number"),
            product_category=product_category,
            brand_claims=brand_claims,
            summary_sentences=summary_sentences,
            declarations_table=declarations_table,
            front_panel_table=front_panel_table,
            back_panel_table=back_panel_table,
            left_panel_table=left_panel_table,
            right_panel_table=right_panel_table,
            all_key_value_pairs=all_key_value_pairs,
            ingredients_list=ingredients_list,
            nutrition_table=nutrition_table if isinstance(nutrition_table, list) else None,
            allergen_info=allergen_info,
            storage_instructions=storage_instructions,
            usage_instructions=usage_instructions,
            composition=composition,
            certifications=certifications if isinstance(certifications, list) else None,
            legal_disclaimer=legal_disclaimer,
            other_text_blocks=other_text_blocks if isinstance(other_text_blocks, list) else None,
            dynamic_fields=l2,
            field_confidence=confidence_scores,
            raw_extractions={
                "regex": l1,
                "llm": l2_raw,
                "brand_claims": brand_claims,
                "summary_sentences": summary_sentences,
                "declarations_table": declarations_table,
                "front_panel_table": front_panel_table,
                "back_panel_table": back_panel_table,
                "left_panel_table": left_panel_table,
                "right_panel_table": right_panel_table,
                "all_key_value_pairs": all_key_value_pairs,
                "ingredients_list": ingredients_list,
                "nutrition_table": nutrition_table if isinstance(nutrition_table, list) else None,
                "allergen_info": allergen_info,
                "storage_instructions": storage_instructions,
                "usage_instructions": usage_instructions,
                "composition": composition,
                "certifications": certifications if isinstance(certifications, list) else None,
                "legal_disclaimer": legal_disclaimer,
                "other_text_blocks": other_text_blocks if isinstance(other_text_blocks, list) else None,
            },
        )
