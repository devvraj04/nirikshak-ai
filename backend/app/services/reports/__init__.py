"""
NIRIKSHAK AI - Reports Generation Services Package
Provides PyMuPDF compliance & evidence report generators and digital endorsement tools.
"""

from .pymupdf_report_generator import generate_scan_pdf_report
from .concise_report_generator import generate_concise_pdf_report
from .personalized_weekly_report_generator import generate_personalized_weekly_pdf_report

__all__ = [
    "generate_scan_pdf_report",
    "generate_concise_pdf_report",
    "generate_personalized_weekly_pdf_report",
]
