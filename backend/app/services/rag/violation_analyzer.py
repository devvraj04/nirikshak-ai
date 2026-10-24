"""
NIRIKSHAK AI - Legal Metrology RAG Violation Analyzer.

Combines ChromaDB vector retrieval from LMPC Act & Rules with LLM generation
to produce authoritative rule citations, verbatim legal quotes, precise factual reasons,
and statutory penalties under the Legal Metrology Act, 2009.
"""

import json
from typing import Any, Dict, List, Optional
from groq import Groq

from app.core.config import get_settings
from app.core.logging import get_logger
from app.services.rag.chroma_service import ChromaService

logger = get_logger("services.rag.violation_analyzer")
settings = get_settings()

# Authoritative statutory fallback lookup derived directly from the
# Legal Metrology (Packaged Commodities) Rules, 2011 and Legal Metrology Act, 2009.
STATUTORY_DEFAULTS = {
    "RULE-LM-001": {
        "rule_code": "Rule 6(1)(d)",
        "rule_title": "Mandatory Maximum Retail Price (MRP) Declaration",
        "act_name": "Legal Metrology (Packaged Commodities) Rules, 2011",
        "legal_quote": "Rule 6(1)(d): Every pre-packaged commodity shall bear on each package the retail sale price in the form 'Maximum or Max. retail price ₹... inclusive of all taxes' or 'MRP ₹... incl. of all taxes'.",
        "reason": "The package fails to declare the retail sale price inclusive of all taxes (MRP) on any visible panel, depriving the consumer of mandatory statutory price disclosure.",
        "penalty": "Section 36(1) of the Legal Metrology Act, 2009: Fine up to ₹25,000 for first offence, up to ₹50,000 for second offence, and up to ₹1,00,000 or imprisonment up to 1 year for subsequent offences. Non-compliant packages may be seized under Section 15.",
        "severity": "CRITICAL",
    },
    "RULE-LM-002": {
        "rule_code": "Rule 6(1)(b)",
        "rule_title": "Mandatory Net Quantity & Unit Declaration",
        "act_name": "Legal Metrology (Packaged Commodities) Rules, 2011",
        "legal_quote": "Rule 6(1)(b) read with Rule 11 & 13: Every package shall bear a declaration of the net quantity in terms of the standard unit of weight or measure conforming to the metric system (g, kg, ml, l, or number).",
        "reason": "Net quantity or standard unit of measurement is not declared or does not conform to standard metric units specified under Rule 11 and 13.",
        "penalty": "Section 36(1) & (2) of Legal Metrology Act, 2009: Fine up to ₹25,000 for first offence, up to ₹50,000 for second offence, and up to ₹1,00,000 or imprisonment for subsequent offences.",
        "severity": "CRITICAL",
    },
    "RULE-LM-003": {
        "rule_code": "Rule 6(1)(a)",
        "rule_title": "Mandatory Manufacturer / Packer / Importer Details",
        "act_name": "Legal Metrology (Packaged Commodities) Rules, 2011",
        "legal_quote": "Rule 6(1)(a): Every package shall bear the name and complete address of the manufacturer, or where manufacturer is not the packer, the name and address of the manufacturer and packer, or importer.",
        "reason": "Complete manufacturer, packer, or importer name and registered address are absent from the packaging label.",
        "penalty": "Section 36(1) of Legal Metrology Act, 2009: Punishable with a fine up to ₹25,000 for first offence, escalating to ₹50,000 for repeat violations. Possible detention of goods under Section 15.",
        "severity": "CRITICAL",
    },
    "RULE-LM-004": {
        "rule_code": "Rule 6(1)(f)",
        "rule_title": "Mandatory Month & Year of Manufacture / Packing",
        "act_name": "Legal Metrology (Packaged Commodities) Rules, 2011",
        "legal_quote": "Rule 6(1)(f): Every package shall bear the month and year in which the commodity is manufactured or pre-packed or imported in numerical or alphabetic month followed by four-digit year format.",
        "reason": "The month and year of manufacture, packing, or import is not printed or legible on the container or outer carton.",
        "penalty": "Section 36(1) of Legal Metrology Act, 2009: Fine up to ₹25,000 for the first offence, and up to ₹50,000 for subsequent offences.",
        "severity": "HIGH",
    },
    "RULE-LM-005": {
        "rule_code": "Rule 6(1)(g)",
        "rule_title": "Mandatory Consumer Care Contact",
        "act_name": "Legal Metrology (Packaged Commodities) Rules, 2011",
        "legal_quote": "Rule 6(1)(g): Every package shall carry the name, address, telephone number and e-mail address of the person who or the office which can be contacted in case of consumer complaints.",
        "reason": "Consumer care grievance redressal details (telephone helpline, email address, or physical contact address) are missing from the package.",
        "penalty": "Rule 32 of LMPC Rules, 2011 read with Section 36 of Legal Metrology Act, 2009: Fine up to ₹25,000 for initial non-compliance.",
        "severity": "HIGH",
    },
    "RULE-LM-006": {
        "rule_code": "Rule 6(1)(a)",
        "rule_title": "Mandatory Generic / Common Product Name",
        "act_name": "Legal Metrology (Packaged Commodities) Rules, 2011",
        "legal_quote": "Rule 6(1)(a): Every package shall bear thereon the common or generic name of the commodity contained in the package on the Principal Display Panel.",
        "reason": "Generic or common product classification is missing or ambiguous, preventing consumer identification of the commodity.",
        "penalty": "Section 36(1) of Legal Metrology Act, 2009: Fine up to ₹25,000 for the first offence, with compounding provisions under Section 48.",
        "severity": "MEDIUM",
    },
    "RULE-LM-007": {
        "rule_code": "Rule 6(5)",
        "rule_title": "Mandatory Best Before / Expiry Date",
        "act_name": "Legal Metrology (Packaged Commodities) Rules, 2011",
        "legal_quote": "Rule 6(5): Packages of commodities susceptible to degradation with time must prominently bear the 'Best Before' or 'Expiry Date' in month and year format.",
        "reason": "Required Best Before or Expiry date declaration is missing or unreadable on a time-sensitive consumer product.",
        "penalty": "Section 36(1) of Legal Metrology Act, 2009: Fine up to ₹25,000 for first offence, and mandatory stock recall or seizure under Section 15.",
        "severity": "HIGH",
    },
}


class LegalViolationAnalyzer:
    """Service to generate authoritative legal citations, RAG quotes, and penalties for violations."""

    def __init__(self):
        self.chroma = ChromaService()
        self.groq_client = None
        if settings.groq_api_key and settings.groq_api_key != "your_groq_api_key_here":
            try:
                self.groq_client = Groq(api_key=settings.groq_api_key)
            except Exception as e:
                logger.warning(f"Could not initialize Groq client in LegalViolationAnalyzer: {e}")

    def analyze_violation(
        self,
        rule_id: str,
        rule_title: str,
        field_name: str,
        detected_value: Any = None,
        ocr_context: str = "",
    ) -> Dict[str, Any]:
        """
        Analyze a rule failure using ChromaDB vector search and LLM completion.
        
        Returns:
            Dict containing:
                - rule_code: e.g. "Rule 6(1)(d)"
                - rule_title: Rule title
                - act_name: Latest LMPC Act / Amendment
                - legal_quote: Verbatim citation from the law
                - reason: Crisp, legally grounded factual explanation
                - penalty: Exact statutory penalties and legal consequences
                - severity: CRITICAL, HIGH, or MEDIUM
        """
        default_data = STATUTORY_DEFAULTS.get(rule_id, {
            "rule_code": "Rule 6",
            "rule_title": rule_title,
            "act_name": "Legal Metrology (Packaged Commodities) Rules, 2011",
            "legal_quote": f"Mandatory declaration of {field_name} required under Legal Metrology Rules.",
            "reason": f"Mandatory {field_name} is missing from package labeling.",
            "penalty": "Section 36(1) of Legal Metrology Act, 2009: Fine up to ₹25,000 for first offence.",
            "severity": "HIGH",
        })

        # 1. RAG Search in ChromaDB
        retrieved_chunks: List[str] = []
        try:
            query = f"{rule_title} {field_name} declaration mandatory requirement Legal Metrology Packaged Commodities Rules 2011 penalty section 36"
            search_res = self.chroma.search(query=query, top_k=3)
            for doc in search_res:
                content = doc.get("content", "").strip()
                src = doc.get("source", "")
                if content:
                    retrieved_chunks.append(f"[{src}]: {content[:400]}")
        except Exception as e:
            logger.warning(f"ChromaDB search failed for violation analysis ({rule_id}): {e}")

        context_text = "\n\n".join(retrieved_chunks) if retrieved_chunks else "Refer to Legal Metrology (Packaged Commodities) Rules, 2011 and Legal Metrology Act, 2009."

        # 2. If no Groq LLM available, return authoritative statutory defaults
        if not self.groq_client:
            return default_data

        # 3. Call Groq LLM
        prompt = f"""
You are a Senior Legal Metrology Enforcement Officer and legal counsel specializing in the Legal Metrology Act, 2009 and the Legal Metrology (Packaged Commodities) Rules, 2011 (LMPC Rules).

A packaged commodity has been scanned via OCR, and a mandatory compliance rule was VIOLATED.

VIOLATION CONTEXT:
- Rule ID: {rule_id}
- Rule Name: {rule_title}
- Target Field: {field_name}
- Detected Value on Package: {detected_value if detected_value is not None else 'NOT DETECTED / MISSING'}
- OCR Sample: {ocr_context[:300] if ocr_context else 'No readable declaration on scanned faces.'}

RETRIEVED LEGAL KNOWLEDGE (FROM LMPC RAG DATABASE):
\"\"\"
{context_text}
\"\"\"

YOUR TASK:
Produce an authoritative, legally rigorous violation notice for this failed rule.
Do NOT be vague. Provide crisp, professional legal reasoning grounded in the Act.

Return ONLY a JSON object with this exact structure:
{{
  "rule_code": "Rule 6(1)(d)", 
  "act_name": "Legal Metrology (Packaged Commodities) Rules, 2011",
  "legal_quote": "Direct verbatim quotation of the clause from the LMPC Rules/Act",
  "reason": "Crisp, specific, factual explanation of why the product violates this rule based on the package scan",
  "penalty": "Specific statutory penalty citing Section 36(1) or Section 36(2) of the Legal Metrology Act, 2009 and potential compounding/seizure provisions"
}}
"""
        try:
            candidate_models = ["qwen/qwen3.8-27b", "openai/gpt-oss-120b", "openai/gpt-oss-20b", settings.llm_model]
            models_to_try = [m for m in dict.fromkeys(candidate_models) if m]
            content = None

            for model_name in models_to_try:
                try:
                    response = self.groq_client.chat.completions.create(
                        messages=[
                            {"role": "system", "content": "You are a Legal Metrology Compliance Enforcement Engine. Output valid JSON only."},
                            {"role": "user", "content": prompt},
                        ],
                        model=model_name,
                        temperature=0.1,
                        response_format={"type": "json_object"},
                    )
                    content = response.choices[0].message.content
                    if content:
                        break
                except Exception as me:
                    logger.warning(f"Groq model {model_name} failed in violation_analyzer: {me}")

            if not content:
                return default_data

            parsed = json.loads(content)

            return {
                "rule_code": parsed.get("rule_code") or default_data["rule_code"],
                "rule_title": rule_title,
                "act_name": parsed.get("act_name") or default_data["act_name"],
                "legal_quote": parsed.get("legal_quote") or default_data["legal_quote"],
                "reason": parsed.get("reason") or default_data["reason"],
                "penalty": parsed.get("penalty") or default_data["penalty"],
                "severity": default_data.get("severity", "HIGH"),
            }
        except Exception as e:
            logger.error(f"Error generating LLM violation analysis for {rule_id}: {e}")
            return default_data
