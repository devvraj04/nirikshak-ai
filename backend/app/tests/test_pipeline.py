"""
NIRIKSHAK AI - End-to-End Compliance Pipeline & Rule Engine Tests.
"""

import pytest
from app.models.enums import ComplianceStatus
from app.services.extraction.declaration_extractor import DeclarationExtractor, ExtractedDeclarations
from app.services.rules.rule_engine import RuleEngine


def test_rule_engine_synthetic_missing_mrp():
    """Verify deterministic rule engine outputs FAIL when MRP is missing."""
    engine = RuleEngine()
    declarations = ExtractedDeclarations(
        generic_product_name="Atta",
        net_quantity=5.0,
        unit="kg",
        mrp=None,  # Missing MRP
        manufacture_month=8,
        manufacture_year=2026,
        consumer_care_email="care@brand.com",
    )

    report = engine.evaluate_declarations("scan_test_001", declarations)
    assert report.overall_status == ComplianceStatus.FAIL
    assert report.failed_count >= 1

    mrp_rule = next(r for r in report.rule_results if r.rule_id == "RULE-LM-001")
    assert mrp_rule.status == ComplianceStatus.FAIL
    assert "missing" in mrp_rule.reason.lower()
    assert mrp_rule.evidence_package["file_hash"] is not None


def test_rule_engine_synthetic_complete_pass():
    """Verify deterministic rule engine outputs PASS when all mandatory declarations are present."""
    engine = RuleEngine()
    declarations = ExtractedDeclarations(
        manufacturer_name="Nature Foods Ltd",
        generic_product_name="Wheat Atta",
        net_quantity=5.0,
        unit="kg",
        mrp=299.0,
        currency="INR",
        manufacture_month=8,
        manufacture_year=2026,
        consumer_care_email="care@naturefoods.com",
        expiry_date="Best Before 12 months from packaging",
    )

    report = engine.evaluate_declarations("scan_test_002", declarations)
    assert report.overall_status == ComplianceStatus.PASS
    assert report.failed_count == 0
    assert report.passed_count == 7


def test_layered_declaration_extractor_regex():
    """Test Layer 1 regex extraction on realistic package text."""
    extractor = DeclarationExtractor()
    sample_text = """
    NATURE FRESH FORTIFIED ATTA
    Net Wt: 5.0 kg
    MRP Rs. 299.00 (Incl. of all taxes)
    Pkd: 08/2026
    For feedback contact: care@naturefresh.in
    """
    decl = extractor.extract_declarations(sample_text)

    assert decl.mrp == 299.0
    assert decl.net_quantity == 5.0
    assert decl.unit == "kg"
    assert decl.manufacture_month == 8
    assert decl.manufacture_year == 2026
    assert decl.consumer_care_email == "care@naturefresh.in"

