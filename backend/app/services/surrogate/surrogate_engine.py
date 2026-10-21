"""
NIRIKSHAK AI — Surrogate Advertising & Dark Pattern Intelligence Engine.

Hybrid architecture combining:
  1. Fast deterministic legal registry & regex heuristic scanner
  2. Groq LLaMA 3.1 LLM legal auditor for statutory CCPA & FSSAI citations
  3. Actionable enforcement notice generation for field officers
"""

import os
import json
import logging
import urllib.request
import urllib.error
from typing import Dict, Any, List, Optional

from .surrogate_database import RESTRICTED_PARENT_BRANDS, STATUTORY_CITATIONS
from .dark_pattern_detector import DarkPatternDetector

logger = logging.getLogger("services.surrogate_engine")


def _get_api_key_and_model() -> tuple[str, str]:
    """Retrieve Groq API key and model from environment or settings."""
    api_key = os.environ.get("GROQ_API_KEY", "").strip()
    model = os.environ.get("LLM_MODEL", "llama-3.1-8b-instant").strip()

    if not api_key:
        try:
            from app.core.config import get_settings
            settings = get_settings()
            api_key = settings.groq_api_key or ""
            model = settings.llm_model or model
        except Exception:
            pass

    if not api_key:
        env_paths = [
            os.path.join(os.getcwd(), ".env"),
            os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".env"),
            os.path.join(os.path.dirname(__file__), "..", "..", "..", ".env"),
        ]
        for p in env_paths:
            if os.path.exists(p):
                try:
                    with open(p, "r", encoding="utf-8") as f:
                        for line in f:
                            line = line.strip()
                            if line.startswith("GROQ_API_KEY="):
                                api_key = line.split("=", 1)[1].strip().strip('"').strip("'")
                            elif line.startswith("LLM_MODEL="):
                                model = line.split("=", 1)[1].strip().strip('"').strip("'")
                except Exception:
                    pass
                if api_key:
                    break

    return api_key, model


class SurrogateAdEngine:
    """
    Flagship NIRIKSHAK AI Engine for Surrogate Advertising and Dark Pattern Verification.
    """

    def __init__(self):
        self.detector = DarkPatternDetector()
        self.api_key, self.default_model = _get_api_key_and_model()
        self.groq_client = None

        if self.api_key:
            try:
                from groq import Groq
                self.groq_client = Groq(api_key=self.api_key)
            except Exception as e:
                logger.warning(f"Could not initialize Groq SDK client for Surrogate Engine: {e}")
                self.groq_client = None

    def _call_llm_json(self, prompt: str) -> Optional[Dict[str, Any]]:
        """Call Groq LLM and parse structured JSON result."""
        if not self.api_key:
            return None

        # 1. Try Groq SDK
        if self.groq_client:
            try:
                response = self.groq_client.chat.completions.create(
                    model=self.default_model,
                    messages=[
                        {
                            "role": "system",
                            "content": (
                                "You are NIRIKSHAK AI's Senior Legal Metrology and FSSAI Regulatory Enforcement Officer. "
                                "Your role is to detect surrogate advertisements, brand extension camouflage (CCPA 2022 Sec 8), "
                                "and deceptive packaging dark patterns (FSSAI 2018 Sec 4, FSS Act Sec 24/53). "
                                "Output strictly valid, well-formed JSON only. Never wrap in markdown blocks, never add commentary."
                            )
                        },
                        {"role": "user", "content": prompt}
                    ],
                    response_format={"type": "json_object"},
                    temperature=0.1,
                    max_tokens=2048,
                )
                text = response.choices[0].message.content.strip()
                return json.loads(text)
            except Exception as e:
                logger.warning(f"Groq SDK call failed in Surrogate Engine: {e}. Trying HTTP fallback...")

        # 2. HTTP urllib fallback
        try:
            payload = json.dumps({
                "model": self.default_model,
                "messages": [
                    {
                        "role": "system",
                        "content": "You are NIRIKSHAK AI Legal Regulatory Officer. Output strict JSON only without markdown or prefix."
                    },
                    {"role": "user", "content": prompt}
                ],
                "response_format": {"type": "json_object"},
                "temperature": 0.1,
                "max_tokens": 2048
            }).encode("utf-8")

            req = urllib.request.Request(
                "https://api.groq.com/openai/v1/chat/completions",
                data=payload,
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {self.api_key}",
                    "User-Agent": "NirikshakAI/1.0"
                }
            )
            with urllib.request.urlopen(req, timeout=20) as resp:
                resp_json = json.loads(resp.read().decode("utf-8"))
                content = resp_json["choices"][0]["message"]["content"].strip()
                return json.loads(content)
        except Exception as e:
            logger.error(f"HTTP fallback LLM call failed in Surrogate Engine: {e}")
            return None

    def analyze_product(
        self,
        brand_name: str,
        product_name: str,
        ingredients_list: str = "",
        brand_claims: Optional[List[Dict[str, Any]]] = None,
        detected_text: str = ""
    ) -> Dict[str, Any]:
        """
        Executes end-to-end Surrogate Advertising & Dark Pattern evaluation.
        """
        # Step 1: Run deterministic scanner
        deterministic_patterns = self.detector.analyze_dark_patterns(
            brand_name=brand_name,
            product_name=product_name,
            ingredients_list=ingredients_list,
            brand_claims=brand_claims,
            detected_text=detected_text
        )

        matched_brand = self.detector.match_restricted_brand(brand_name, product_name, detected_text)
        is_camouflaged = self.detector.detect_camouflage_sku(product_name, detected_text) is not None

        # Calculate preliminary risk score
        risk_score = 0
        if matched_brand and is_camouflaged:
            risk_score = 95
        elif matched_brand:
            risk_score = 75
        elif any(p["severity"] == "HIGH" for p in deterministic_patterns):
            risk_score = 65
        elif any(p["severity"] == "MEDIUM" for p in deterministic_patterns):
            risk_score = 40
        elif deterministic_patterns:
            risk_score = 25

        # Step 2: Dynamically evaluate with LLM reasoning (Groq LLaMA 3.1)
        llm_verdict = None
        if self.api_key and (brand_name or product_name or detected_text or brand_claims or matched_brand or deterministic_patterns):
            prompt = f"""
            Analyze the following Indian packaged product for Surrogate Advertising (under CCPA 2022 Guidelines Section 8) 
            and Deceptive Marketing / Dark Patterns (under FSSAI Advertising and Claims Regulations 2018):

            - Declared Brand Name: {brand_name}
            - Product / SKU Name: {product_name}
            - Ingredients List: {ingredients_list or 'Not declared / not found'}
            - Brand Claims: {json.dumps(brand_claims or [])}
            - Full Detected OCR Text: {detected_text[:1200]}

            Return JSON matching this exact structure:
            {{
              "is_surrogate": true/false,
              "surrogate_confidence": 0 to 100,
              "parent_restricted_industry": "TOBACCO_PAN_MASALA" | "ALCOHOL_LIQUOR" | "MISCLASSIFIED_HEALTH_DRINK" | "NONE",
              "matched_restricted_brand": "string or null",
              "camouflaged_sku_type": "string or null",
              "surrogate_explanation": "Detailed regulatory explanation",
              "dark_patterns": [
                 {{
                    "type": "SURROGATE_CAMOUFLAGE | DECEPTIVE_CLAIM | HIDDEN_DISCLAIMER | UNPROVEN_HEALTH_CLAIM",
                    "severity": "CRITICAL | HIGH | MEDIUM | LOW",
                    "title": "Short title",
                    "detail": "Factual comparison of label claim vs reality",
                    "statute_violated": "Exact legal rule and section"
                 }}
              ],
              "legal_violations": [
                 {{
                    "act": "Name of Act or Regulation",
                    "section": "Section / Regulation number",
                    "penalty_clause": "Specific statutory penalty description",
                    "max_penalty": "Penalty amount e.g. Up to Rs 10 Lakhs or Rs 50 Lakhs"
                 }}
              ],
              "officer_action_recommendation": "Step by step instruction for field officer (e.g. Issue Show Cause Notice under Sec 53)",
              "consumer_plain_verdict": "Clear, friendly explanation for consumer informing if this is a surrogate ad"
            }}
            """
            llm_verdict = self._call_llm_json(prompt)

        # Step 3: Synthesize final output
        if llm_verdict and isinstance(llm_verdict, dict) and "is_surrogate" in llm_verdict:
            final_is_surrogate = bool(llm_verdict.get("is_surrogate")) or (matched_brand and is_camouflaged)
            final_confidence = max(risk_score, int(llm_verdict.get("surrogate_confidence", risk_score)))
            parent_cat = llm_verdict.get("parent_restricted_industry")
            if not parent_cat or parent_cat == "NONE":
                parent_cat = matched_brand["parent_category"] if matched_brand else "NONE"

            # Merge patterns
            merged_patterns = list(deterministic_patterns)
            for dp in llm_verdict.get("dark_patterns", []):
                if not any(existing.get("title") == dp.get("title") for existing in merged_patterns):
                    merged_patterns.append({
                        "type": dp.get("type", "DECEPTIVE_CLAIM"),
                        "severity": dp.get("severity", "MEDIUM"),
                        "title": dp.get("title", "Misleading Representation"),
                        "detail": dp.get("detail", ""),
                        "legal_citation": {
                            "act": dp.get("statute_violated", "FSSAI Regulations, 2018"),
                            "section": "General Misleading Claims",
                            "text": dp.get("detail", "")
                        }
                    })

            legal_violations = llm_verdict.get("legal_violations", [])
            if not legal_violations and matched_brand:
                legal_violations.append({
                    "act": "Central Consumer Protection Authority Guidelines, 2022",
                    "section": "Section 8 (Prohibition of Surrogate Advertising)",
                    "penalty_clause": "Section 21 of Consumer Protection Act, 2019",
                    "max_penalty": "Penalty up to ₹10 Lakhs (First offence) / ₹50 Lakhs (Subsequent)"
                })

            return {
                "is_surrogate": final_is_surrogate,
                "surrogate_risk_score": final_confidence,
                "risk_level": "CRITICAL" if final_confidence >= 80 else ("HIGH" if final_confidence >= 60 else ("MEDIUM" if final_confidence >= 35 else "CLEAN")),
                "parent_restricted_industry": parent_cat,
                "matched_restricted_brand": llm_verdict.get("matched_restricted_brand") or (matched_brand["canonical_brand"] if matched_brand else None),
                "camouflaged_sku_type": llm_verdict.get("camouflaged_sku_type") or product_name,
                "surrogate_explanation": llm_verdict.get("surrogate_explanation") or (
                    f"Product shares trademark and trade dress with restricted {parent_cat.replace('_', ' ')}."
                    if final_is_surrogate else "No surrogate advertising indicators found."
                ),
                "dark_patterns": merged_patterns,
                "dark_patterns_count": len(merged_patterns),
                "legal_violations": legal_violations,
                "officer_action_recommendation": llm_verdict.get("officer_action_recommendation") or (
                    "Issue Show Cause Notice under Section 53 of the Food Safety and Standards Act, 2006 for misleading advertisement."
                    if final_is_surrogate else "Standard compliance review."
                ),
                "consumer_plain_verdict": llm_verdict.get("consumer_plain_verdict") or (
                    "⚠️ Warning: This product shares the brand name, typography, and trade packaging of a restricted tobacco/pan masala line."
                    if final_is_surrogate else "Product packaging does not exhibit surrogate camouflage."
                )
            }

        # Step 4: Deterministic Fallback Synthesis (when LLM is offline or no Groq key)
        is_surrogate_flag = bool(matched_brand and is_camouflaged)
        parent_category = matched_brand["parent_category"] if matched_brand else "NONE"
        canonical_brand_name = matched_brand["canonical_brand"] if matched_brand else None

        legal_violations = []
        if is_surrogate_flag and matched_brand:
            legal_violations.append({
                "act": "Central Consumer Protection Authority Guidelines, 2022",
                "section": "Section 8 (Prohibition of Surrogate Advertising)",
                "penalty_clause": "Section 21 of Consumer Protection Act, 2019",
                "max_penalty": "Penalty up to ₹10 Lakhs (First offence) / ₹50 Lakhs (Subsequent)"
            })
            legal_violations.append({
                "act": "Food Safety and Standards Act, 2006",
                "section": "Section 53 (Penalty for Misleading Advertisement)",
                "penalty_clause": "Adjudication by Adjudicating Officer",
                "max_penalty": "Penalty up to ₹10 Lakhs"
            })
        elif matched_brand:
            legal_violations.append({
                "act": "CCPA Guidelines 2022",
                "section": "Section 8(2) - Genuine Brand Extension Verification",
                "penalty_clause": "Requires commercial turnover audit of brand extension",
                "max_penalty": "Audit Notice"
            })

        for dp in deterministic_patterns:
            cit = dp.get("legal_citation", {})
            if cit and isinstance(cit, dict):
                legal_violations.append({
                    "act": cit.get("act", "FSS Act, 2006"),
                    "section": cit.get("section", "Section 24"),
                    "penalty_clause": cit.get("heading", "Misleading claims"),
                    "max_penalty": "Section 53 / Section 52 Penalty"
                })

        officer_rec = (
            f"URGENT: Initiate show-cause inquiry against manufacturer for brand '{canonical_brand_name}' "
            f"under CCPA Guidelines 2022 Section 8 and FSS Act Section 53. Request audited sales volume records."
            if is_surrogate_flag else (
                "Review flagged deceptive claims and request manufacturer claim substantiation."
                if deterministic_patterns else "Product complies with advertising norms."
            )
        )

        consumer_msg = (
            f"⚠️ Caution: '{canonical_brand_name}' is a prominent {parent_category.replace('_', ' ')} brand. "
            f"This '{product_name}' appears to be a surrogate product designed to promote restricted commodities."
            if is_surrogate_flag else (
                f"Notice: Package contains {len(deterministic_patterns)} potential misleading marketing claim(s)."
                if deterministic_patterns else "✅ No surrogate advertising or misleading dark patterns detected."
            )
        )

        return {
            "is_surrogate": is_surrogate_flag,
            "surrogate_risk_score": risk_score,
            "risk_level": "CRITICAL" if risk_score >= 80 else ("HIGH" if risk_score >= 60 else ("MEDIUM" if risk_score >= 35 else "CLEAN")),
            "parent_restricted_industry": parent_category,
            "matched_restricted_brand": canonical_brand_name,
            "camouflaged_sku_type": product_name if is_camouflaged else None,
            "surrogate_explanation": (
                f"Product '{product_name}' uses the trademark and branding of restricted {parent_category} brand '{canonical_brand_name}'."
                if is_surrogate_flag else "No surrogate brand camouflage identified."
            ),
            "dark_patterns": deterministic_patterns,
            "dark_patterns_count": len(deterministic_patterns),
            "legal_violations": legal_violations,
            "officer_action_recommendation": officer_rec,
            "consumer_plain_verdict": consumer_msg
        }


# Global singleton instance for easy import across backend
surrogate_engine = SurrogateAdEngine()
