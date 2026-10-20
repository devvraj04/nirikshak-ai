"""
NIRIKSHAK AI — Data-Driven Versioned Compliance Rule Engine.

Loads rule definitions from rule_definitions.yaml at runtime.
To update rules, edit the YAML file — no code changes needed.
"""

import hashlib
import os
import yaml
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from app.models.enums import ComplianceStatus
from app.services.extraction.declaration_extractor import ExtractedDeclarations
from app.services.rag.violation_analyzer import LegalViolationAnalyzer

RULES_YAML_PATH = os.path.join(os.path.dirname(__file__), "rule_definitions.yaml")


@dataclass
class RuleEvaluationResult:
    """Evaluation result for a single legal rule."""
    rule_id: str
    rule_title: str
    field_name: str
    status: ComplianceStatus  # PASS, FAIL, REVIEW, NOT_APPLICABLE
    reason: str
    detected_value: Any
    confidence: float
    evidence_package: Dict[str, Any]
    citation: Optional[Dict[str, str]] = None
    penalty: Optional[str] = None
    rule_code: Optional[str] = None


@dataclass
class ComplianceReport:
    """Overall product compliance evaluation report."""
    scan_id: str
    overall_status: ComplianceStatus
    total_rules_evaluated: int
    passed_count: int
    failed_count: int
    review_count: int
    rule_results: List[RuleEvaluationResult] = field(default_factory=list)
    rule_definitions_version: str = "unknown"


class RuleEngine:
    """Versioned, data-driven deterministic compliance evaluator.
    
    Loads all rule definitions from rule_definitions.yaml. The YAML version
    is tracked alongside every evaluation for full auditability.
    """

    def __init__(self, rules_path: str = RULES_YAML_PATH):
        self._rules_path = rules_path
        self._rule_defs: List[Dict[str, Any]] = []
        self._version: str = "unknown"
        self._authority: str = ""
        self._load_rules()
        self.violation_analyzer = LegalViolationAnalyzer()

    def _load_rules(self):
        """Load rule definitions from YAML file."""
        with open(self._rules_path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
        self._version = data.get("version", "unknown")
        self._authority = data.get("authority", "")
        self._rule_defs = data.get("rules", [])

    @property
    def VERSION(self) -> str:
        return self._version

    def generate_sha256(self, content: str) -> str:
        """Generate SHA-256 tamper-proof hash for evidence package."""
        return hashlib.sha256(content.encode("utf-8")).hexdigest()

    def _get_citation(
        self,
        rule_def: Dict[str, Any],
        rag_context: Optional[Dict[str, Any]],
    ) -> Optional[Dict[str, str]]:
        """Search RAG context for a citation matching the rule's keywords."""
        keywords = rule_def.get("citation_keywords", "")
        act_ref = rule_def.get("act_reference", "Legal Metrology (Packaged Commodities) Rules, 2011")

        if not rag_context or not rag_context.get("retrieved_documents"):
            # Fallback: use the act_reference and rule description as the quote
            return {
                "act_name": act_ref,
                "quote": rule_def.get("description", "").strip()[:200] + "...",
            }

        for doc in rag_context["retrieved_documents"]:
            text_content = doc.get("content", "")
            for kw in keywords.split():
                kw_lower = kw.lower()
                text_lower = text_content.lower()
                idx = text_lower.find(kw_lower)
                if idx != -1:
                    start = max(0, idx - 100)
                    end = min(len(text_content), idx + len(kw) + 300)
                    snippet = text_content[start:end].replace('\n', ' ').strip()
                    doc_name = act_ref
                    return {"act_name": doc_name, "quote": f"...{snippet}..."}

        # Fallback to first doc
        first_doc = rag_context["retrieved_documents"][0]
        fallback_text = first_doc.get("content", "").replace('\n', ' ')[:400]
        doc_name = act_ref
        return {"act_name": doc_name, "quote": f"{fallback_text}..."}

    def _get_field_val(self, declarations: ExtractedDeclarations, field_path: str) -> Any:
        val = getattr(declarations, field_path, None)
        if val is None and hasattr(declarations, 'dynamic_fields') and declarations.dynamic_fields:
            val = declarations.dynamic_fields.get(field_path)
        return val

    def _evaluate_single_rule(
        self,
        rule_def: Dict[str, Any],
        declarations: ExtractedDeclarations,
        scan_id: str,
        source_image_url: str,
        rag_context: Optional[Dict[str, Any]],
        ocr_text: str = "",
    ) -> RuleEvaluationResult:
        """Evaluate a single rule definition against extracted declarations."""

        rule_id = rule_def["id"]
        rule_title = rule_def["title"]
        condition = rule_def["condition"]
        cond_type = condition["type"]
        review_threshold = rule_def.get("review_threshold", 0.0)

        # Check Category Applicability
        applicable_categories = rule_def.get("applicable_categories")
        if applicable_categories and hasattr(declarations, 'product_category'):
            if declarations.product_category != "Unknown" and declarations.product_category not in applicable_categories:
                # Rule does not apply to this category
                return RuleEvaluationResult(
                    rule_id=rule_id,
                    rule_title=rule_title,
                    status=ComplianceStatus.PASS,
                    reason=f"Rule not applicable to Product Category: {declarations.product_category}",
                    evidence_package={"file_hash": None, "source_image": source_image_url},
                    citation=None,
                )

        status = ComplianceStatus.FAIL
        reason = ""
        detected_value = None
        confidence = 0.0

        if cond_type == "field_present_and_positive":
            field_path = condition["field_path"]
            val = self._get_field_val(declarations, field_path)
            conf = (declarations.field_confidence or {}).get(field_path, 0.0)
            confidence = conf

            if val is not None and (isinstance(val, (int, float)) and val > 0):
                status = ComplianceStatus.PASS
                currency = self._get_field_val(declarations, "currency") or "INR"
                reason = f"{rule_title.split('(')[0].strip()} is clearly declared: {currency} {val}"
                detected_value = f"{currency} {val}"
            elif conf > 0.0 and conf < review_threshold:
                status = ComplianceStatus.REVIEW
                reason = f"{rule_title} declaration is uncertain or unreadable from OCR scan"
            else:
                status = ComplianceStatus.FAIL
                reason = f"{rule_title} declaration is missing on package label"

        elif cond_type == "field_and_unit_present":
            field_path = condition["field_path"]
            unit_path = condition["unit_field_path"]
            val = self._get_field_val(declarations, field_path)
            unit = self._get_field_val(declarations, unit_path)
            conf = (declarations.field_confidence or {}).get(field_path, 0.0)
            confidence = conf

            if val is not None and unit:
                status = ComplianceStatus.PASS
                reason = f"Net Quantity clearly declared: {val} {unit}"
                detected_value = f"{val} {unit}"
            else:
                status = ComplianceStatus.FAIL
                reason = f"{rule_title} declaration is missing on package label"

        elif cond_type == "any_field_present":
            field_paths = condition["field_paths"]
            found_val = None
            for fp in field_paths:
                v = self._get_field_val(declarations, fp)
                if v:
                    found_val = v
                    break

            if found_val:
                status = ComplianceStatus.PASS
                reason = f"{rule_title.split('(')[0].strip()} present: {found_val}"
                detected_value = found_val
                confidence = 0.85
            else:
                status = ComplianceStatus.FAIL
                reason = f"{rule_title} declaration is missing"
                confidence = 0.0

        elif cond_type == "fields_present":
            field_paths = condition["field_paths"]
            all_present = all(self._get_field_val(declarations, fp) for fp in field_paths)

            if all_present:
                vals = [str(self._get_field_val(declarations, fp)) for fp in field_paths]
                detected_value = "/".join(vals)
                status = ComplianceStatus.PASS
                reason = f"{rule_title.split('(')[0].strip()} declared: {detected_value}"
                confidence = 0.90
            else:
                status = ComplianceStatus.FAIL
                reason = f"{rule_title} is missing"
                confidence = 0.0

        elif cond_type == "field_present":
            field_path = condition["field_path"]
            val = self._get_field_val(declarations, field_path)
            if val:
                status = ComplianceStatus.PASS
                reason = f"{rule_title.split('(')[0].strip()} present: {val}"
                detected_value = val
                confidence = 0.85
            else:
                status = ComplianceStatus.FAIL
                reason = f"{rule_title} declaration is missing"
                confidence = 0.0

        # Ground violations with RAG + LLM analysis
        citation = None
        penalty = None
        rule_code = rule_def.get("act_reference", "").split("—")[0].strip()

        if status in [ComplianceStatus.FAIL, ComplianceStatus.REVIEW]:
            try:
                advisory = self.violation_analyzer.analyze_violation(
                    rule_id=rule_id,
                    rule_title=rule_title,
                    field_name=rule_def.get("field", ""),
                    detected_value=detected_value,
                    ocr_context=ocr_text,
                )
                rule_code = advisory.get("rule_code") or rule_code
                penalty = advisory.get("penalty")
                if advisory.get("reason"):
                    advisory_reason = advisory.get("reason")
                    if status == ComplianceStatus.FAIL and "missing" in reason.lower():
                        reason = f"{reason}. Advisory: {advisory_reason}"
                    else:
                        reason = advisory_reason
                citation = {
                    "act_name": advisory.get("act_name", rule_def.get("act_reference", "Legal Metrology (Packaged Commodities) Rules, 2011")),
                    "quote": advisory.get("legal_quote", ""),
                    "rule_reference": rule_code or rule_def.get("act_reference", ""),
                }
            except Exception as e:
                citation = self._get_citation(rule_def, rag_context)

        # Build evidence package
        field_name = rule_def["field"]
        ev_content = f"{scan_id}:{field_name}:{detected_value}:{status.value}:{self._version}"
        evidence_package = {
            "rule_id": rule_id,
            "field": field_name,
            "detected_value": detected_value,
            "source_image": source_image_url,
            "ocr_confidence": confidence,
            "rule_version": self._version,
            "rule_definitions_version": self._version,
            "severity": rule_def.get("severity", "MEDIUM"),
            "act_reference": rule_def.get("act_reference", ""),
            "file_hash": self.generate_sha256(ev_content),
        }

        return RuleEvaluationResult(
            rule_id=rule_id,
            rule_title=rule_title,
            field_name=field_name,
            status=status,
            reason=reason,
            detected_value=detected_value,
            confidence=confidence,
            evidence_package=evidence_package,
            citation=citation,
            penalty=penalty,
            rule_code=rule_code,
        )

    def evaluate_declarations(
        self,
        scan_id: str,
        declarations: ExtractedDeclarations,
        source_image_url: str = "/uploads/scan.jpg",
        rag_context: Optional[Dict[str, Any]] = None,
        ocr_text: str = "",
    ) -> ComplianceReport:
        """
        Evaluate extracted declarations against all rules loaded from YAML.
        """
        results: List[RuleEvaluationResult] = []

        for rule_def in self._rule_defs:
            result = self._evaluate_single_rule(
                rule_def=rule_def,
                declarations=declarations,
                scan_id=scan_id,
                source_image_url=source_image_url,
                rag_context=rag_context,
                ocr_text=ocr_text,
            )
            results.append(result)

        failed = [r for r in results if r.status == ComplianceStatus.FAIL]
        review = [r for r in results if r.status == ComplianceStatus.REVIEW]
        passed = [r for r in results if r.status == ComplianceStatus.PASS]

        if failed:
            overall = ComplianceStatus.FAIL
        elif review:
            overall = ComplianceStatus.REVIEW
        else:
            overall = ComplianceStatus.PASS

        return ComplianceReport(
            scan_id=scan_id,
            overall_status=overall,
            total_rules_evaluated=len(results),
            passed_count=len(passed),
            failed_count=len(failed),
            review_count=len(review),
            rule_results=results,
            rule_definitions_version=self._version,
        )
