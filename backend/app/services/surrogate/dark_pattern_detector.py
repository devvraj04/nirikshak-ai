"""
NIRIKSHAK AI — Deterministic Dark Pattern & Misleading Packaging Detector.

Flags deceptive packaging, deceptive claims, hidden asterisks, and trademark camouflage
against factual ingredients and statutory declarations.
"""

import re
from typing import Dict, Any, List, Optional
from .surrogate_database import RESTRICTED_PARENT_BRANDS, KNOWN_CAMOUFLAGE_SKUS, STATUTORY_CITATIONS


class DarkPatternDetector:
    """Detects packaging dark patterns, camouflage, and deceptive marketing claims."""

    def __init__(self):
        # Synthetic food colors that contradict "Natural / Pure / Real" claims
        self.synthetic_colors = [
            "ins 102", "tartrazine",
            "ins 110", "sunset yellow",
            "ins 122", "carmoisine",
            "ins 124", "ponceau 4r",
            "ins 127", "erythrosine",
            "ins 132", "indigotine",
            "ins 133", "brilliant blue",
            "ins 143", "fast green"
        ]

        # Artificial flavors that contradict natural claims
        self.artificial_flavor_keywords = [
            "artificial flavour", "artificial flavor", "nature identical flavour",
            "nature identical flavor", "synthetic flavour", "flavouring substance"
        ]

        # Sugar substitutes / fillers that contradict "No Sugar / Sugar Free"
        self.sugar_camouflages = [
            "maltodextrin", "high fructose corn syrup", "corn syrup",
            "invert sugar syrup", "glucose syrup", "maltose", "dextrose",
            "sucralose", "aspartame", "acesulfame", "polyols", "sorbitol", "maltitol"
        ]

    def match_restricted_brand(self, brand_name: str, product_name: str, text_corpus: str = "") -> Optional[Dict[str, Any]]:
        """
        Check if the brand or product name matches any restricted umbrella parent brand.
        """
        combined = f"{brand_name} {product_name} {text_corpus}".lower()

        for key, entry in RESTRICTED_PARENT_BRANDS.items():
            # Exact or word boundary match for brand name
            pattern = rf"\b{re.escape(key)}\b"
            if re.search(pattern, combined):
                return entry

        return None

    def detect_camouflage_sku(self, product_name: str, text_corpus: str = "") -> Optional[str]:
        """
        Check if the product name corresponds to a typical surrogate Trojan horse SKU.
        """
        search_target = f"{product_name} {text_corpus}".lower()
        for sku in KNOWN_CAMOUFLAGE_SKUS:
            if sku in search_target:
                return sku
        return None

    def analyze_dark_patterns(
        self,
        brand_name: str,
        product_name: str,
        ingredients_list: str = "",
        brand_claims: Optional[List[Dict[str, Any]]] = None,
        detected_text: str = ""
    ) -> List[Dict[str, Any]]:
        """
        Runs comprehensive dark pattern heuristics across brand, claims, and ingredients.
        """
        dark_patterns = []
        ingr_lower = (ingredients_list or "").lower()
        all_text = f"{brand_name} {product_name} {detected_text}".lower()

        claims_text_list = []
        if brand_claims:
            for c in brand_claims:
                if isinstance(c, dict):
                    claims_text_list.append(str(c.get("claim", "")))
                elif isinstance(c, str):
                    claims_text_list.append(c)

        claims_corpus = " ".join(claims_text_list).lower()
        full_context = f"{all_text} {claims_corpus}"

        # ---------------------------------------------------------------------
        # Pattern 1: Surrogate Trademark Camouflage
        # ---------------------------------------------------------------------
        matched_brand = self.match_restricted_brand(brand_name, product_name, detected_text)
        camouflaged_sku = self.detect_camouflage_sku(product_name, detected_text)

        if matched_brand and camouflaged_sku:
            dark_patterns.append({
                "type": "SURROGATE_BRAND_CAMOUFLAGE",
                "severity": "CRITICAL",
                "title": f"Illegal Surrogate Advertising Camouflage ({matched_brand['canonical_brand']})",
                "detail": (
                    f"Product '{product_name}' appears to serve as a surrogate brand extension for "
                    f"prohibited '{matched_brand['prohibited_product']}'. Under CCPA 2022 Guidelines, using "
                    f"the identical brand name and trade dress for '{camouflaged_sku}' without independent brand distinction "
                    f"is a violation."
                ),
                "legal_citation": STATUTORY_CITATIONS["CCPA_SEC_8"]
            })
        elif matched_brand and not camouflaged_sku:
            # Umbrella brand match even if product name isn't an exact elaichi/soda
            dark_patterns.append({
                "type": "RESTRICTED_UMBRELLA_BRAND",
                "severity": "HIGH",
                "title": f"Restricted Parent Brand Trademark Overlap ({matched_brand['canonical_brand']})",
                "detail": (
                    f"Brand '{matched_brand['canonical_brand']}' is a recognized umbrella trademark for restricted "
                    f"{matched_brand['parent_category'].replace('_', ' ')}. Cross-category marketing requires "
                    f"audited compliance with the Genuine Brand Extension criteria."
                ),
                "legal_citation": STATUTORY_CITATIONS["CCPA_SEC_8"]
            })

        # ---------------------------------------------------------------------
        # Pattern 2: False "100% Real" / "Pure Kesar" Claim vs Artificial Ingredients
        # ---------------------------------------------------------------------
        kesar_claims = re.search(r"\b(kesar|saffron|shahi kesar|pure kesar)\b", full_context)
        if kesar_claims:
            has_real_saffron = "saffron" in ingr_lower or "kesar" in ingr_lower
            has_artificial = any(c in ingr_lower for c in self.synthetic_colors) or any(f in ingr_lower for f in self.artificial_flavor_keywords)
            if has_artificial and not has_real_saffron:
                dark_patterns.append({
                    "type": "DECEPTIVE_LUXURY_CLAIM",
                    "severity": "HIGH",
                    "title": "Misleading 'Kesar/Saffron' Premium Claim",
                    "detail": (
                        "Package prominently features 'Kesar' / 'Saffron' branding, but factual ingredient list contains "
                        "synthetic food colours (INS 102/110) or artificial flavouring substances with no real saffron."
                    ),
                    "legal_citation": STATUTORY_CITATIONS["FSS_ACT_SEC_24"]
                })

        # ---------------------------------------------------------------------
        # Pattern 3: Misleading "100% Fruit Juice" / "Natural" with Added Sugars
        # ---------------------------------------------------------------------
        juice_claims = re.search(r"\b(100%\s*(?:real\s*)?(?:fruit\s*)?juice|pure\s*juice|all\s*natural\s*juice)\b", full_context)
        if juice_claims:
            has_added_sugar = any(w in ingr_lower for w in ["sugar", "added sugar", "reconstituted", "concentrate", "liquid glucose", "preservative"])
            if has_added_sugar:
                dark_patterns.append({
                    "type": "DECEPTIVE_NUTRITION_CLAIM",
                    "severity": "HIGH",
                    "title": "Prohibited '100% Fruit Juice' Claim with Added Sugar/Concentrate",
                    "detail": (
                        "FSSAI directive (June 2024) prohibits the claim '100% Fruit Juice' on products made from "
                        "concentrate, added sugars, or added water. Such claims mislead consumers into believing the product is fresh squeezed."
                    ),
                    "legal_citation": STATUTORY_CITATIONS["FSSAI_ADV_REG_4"]
                })

        # ---------------------------------------------------------------------
        # Pattern 4: False "Sugar-Free" with Camouflaged Glycemic Sweeteners
        # ---------------------------------------------------------------------
        sugar_free_claim = re.search(r"\b(sugar[\s-]*free|zero\s*sugar|no\s*sugar)\b", full_context)
        if sugar_free_claim:
            found_sugar_camouflage = [s for s in self.sugar_camouflages if s in ingr_lower]
            if found_sugar_camouflage:
                dark_patterns.append({
                    "type": "CAMOUFLAGED_SUGAR_SUBSTITUTES",
                    "severity": "MEDIUM",
                    "title": "Hidden Glycemic Agents in 'Sugar-Free' Product",
                    "detail": (
                        f"Product claims 'Sugar Free' on front panel, but ingredients contain hidden glycemic carbohydrates "
                        f"or intense sweeteners ({', '.join(found_sugar_camouflage[:3])}) without prominent front-panel disclosure."
                    ),
                    "legal_citation": STATUTORY_CITATIONS["FSSAI_ADV_REG_4"]
                })

        # ---------------------------------------------------------------------
        # Pattern 5: Unsubstantiated "Immunity Booster" or Medical Claims
        # ---------------------------------------------------------------------
        immunity_match = re.search(r"\b(boosts?\s*immunity|immunity\s*boost(?:er)?|protects?\s*from\s*(?:diseases?|viruses?|illness))\b", full_context)
        if immunity_match:
            dark_patterns.append({
                "type": "UNSUBSTANTIATED_HEALTH_CLAIM",
                "severity": "MEDIUM",
                "title": "Unsubstantiated 'Immunity Booster' Claim",
                "detail": (
                    f"Claim '{immunity_match.group(0)}' used without approved clinical efficacy under FSSAI Advertising Regulations 2018. "
                    "Commercial food products cannot make disease-prevention or therapeutic claims."
                ),
                "legal_citation": STATUTORY_CITATIONS["FSS_ACT_SEC_24"]
            })

        # ---------------------------------------------------------------------
        # Pattern 6: Disclaimers in Microscopic Footnotes (Contradictory Asterisk)
        # ---------------------------------------------------------------------
        has_asterisk = "*" in detected_text or "creative visualization" in all_text or "for representative purposes only" in all_text
        if has_asterisk and (claims_text_list or len(detected_text) > 200):
            if "creative visualization" in all_text or "representative purposes" in all_text:
                dark_patterns.append({
                    "type": "CONTRADICTORY_DISCLAIMER_ASTERISK",
                    "severity": "LOW",
                    "title": "Deceptive Visual Representation (Contradictory Disclaimer)",
                    "detail": (
                        "Headline artwork or ingredient imagery is negated by fine-print disclaimer "
                        "('Creative visualization only'). Under CCPA Guidelines 2022, fine-print disclaimers cannot contradict the primary impression."
                    ),
                    "legal_citation": STATUTORY_CITATIONS["CCPA_SEC_8"]
                })

        return dark_patterns
