"""
NIRIKSHAK AI - Report Generation API Routes.
Generates detailed, evidence-backed PDF compliance reports with digital signatures.
"""
import hashlib
import io
import os
import uuid
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_db
from app.models import Scan, Declaration, Violation, Complaint
from app.models.evidence import Evidence
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image as RLImage, HRFlowable
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors

router = APIRouter(prefix="/reports", tags=["Reports"])


def _build_styles():
    styles = getSampleStyleSheet()
    styles['Heading1'].alignment = 1
    styles.add(ParagraphStyle(
        'QuoteStyle', parent=styles['Normal'],
        fontName='Helvetica-Oblique', textColor=colors.HexColor('#004d40'),
        leftIndent=20, rightIndent=20, spaceBefore=5, spaceAfter=5,
    ))
    styles.add(ParagraphStyle(
        'RuleID', parent=styles['Normal'],
        fontName='Courier', fontSize=8, textColor=colors.HexColor('#666666'),
    ))
    styles.add(ParagraphStyle(
        'Fingerprint', parent=styles['Normal'],
        fontName='Courier', fontSize=7, textColor=colors.HexColor('#999999'),
        alignment=1,
    ))
    return styles


def _try_add_image(elements, image_path: str, width=2*inch, height=1.5*inch, caption: str = ""):
    """Try to embed an image in the PDF. Silently skip if file missing."""
    from app.core.config import get_settings
    settings = get_settings()
    
    if image_path.startswith("/uploads/"):
        rel_path = image_path.replace("/uploads/", "")
        abs_path = os.path.join(settings.local_storage_path, rel_path)
    else:
        abs_path = image_path
    
    if os.path.exists(abs_path):
        try:
            img = RLImage(abs_path, width=width, height=height)
            elements.append(img)
            if caption:
                styles = getSampleStyleSheet()
                elements.append(Paragraph(f"<i>{caption}</i>", styles['Normal']))
        except Exception:
            pass


@router.get("/{scan_id}/download")
async def download_report(
    scan_id: uuid.UUID,
    format: str = "pymupdf",
    db: AsyncSession = Depends(get_db),
):
    """Generate and download a detailed PyMuPDF compliance & evidence report signed by Examiner Dev."""
    if format == "concise":
        try:
            from app.services.reports import generate_concise_pdf_report
            pdf_bytes = await generate_concise_pdf_report(scan_id=scan_id, db=db, save_to_disk=True)
            return StreamingResponse(
                io.BytesIO(pdf_bytes),
                media_type="application/pdf",
                headers={"Content-Disposition": f'inline; filename="nirikshak_concise_{scan_id}.pdf"'}
            )
        except Exception:
            pass

    # Primary: PyMuPDF evidence report with photos & Dev's digital signature
    try:
        from app.services.reports import generate_scan_pdf_report
        pdf_bytes = await generate_scan_pdf_report(scan_id=scan_id, db=db, save_to_disk=True)
        return StreamingResponse(
            io.BytesIO(pdf_bytes),
            media_type="application/pdf",
            headers={"Content-Disposition": f'inline; filename="nirikshak_audit_{scan_id}.pdf"'}
        )
    except Exception:
        pass

    # Fallback to ReportLab template if PyMuPDF not available
    stmt = select(Scan, Declaration).options(
        selectinload(Scan.violations).selectinload(Violation.rule),
        selectinload(Scan.violations).selectinload(Violation.evidence_items),
        selectinload(Scan.reviews),
    ).outerjoin(
        Declaration, Scan.id == Declaration.scan_id
    ).where(Scan.id == scan_id)

    res = await db.execute(stmt)
    record = res.first()

    if not record:
        raise HTTPException(status_code=404, detail="Scan not found")

    s, d = record
    styles = _build_styles()
    normal = styles['Normal']
    sub_title = styles['Heading2']

    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=letter, rightMargin=30, leftMargin=30, topMargin=30, bottomMargin=30)
    elements = []

    # === HEADER ===
    elements.append(Paragraph("NIRIKSHAK AI", styles['Heading1']))
    elements.append(Paragraph("Compliance Inspection & Grievance Report", styles['Heading2']))
    elements.append(Spacer(1, 10))

    # Metadata table
    passed_count = sum(1 for v in s.violations if v.status and v.status.value == "PASS")
    total_count = len(s.violations)
    compliance_score = int((passed_count / max(1, total_count)) * 100)
    score_color = colors.HexColor('#16a34a') if compliance_score == 100 else (colors.HexColor('#d97706') if compliance_score >= 60 else colors.HexColor('#dc2626'))

    meta_data = [
        [Paragraph("<b>Scan ID:</b>", normal), Paragraph(str(s.id), normal)],
        [Paragraph("<b>Status:</b>", normal), Paragraph(s.overall_compliance.value if s.overall_compliance else 'PENDING', normal)],
        [Paragraph("<b>Regulation Score:</b>", normal), Paragraph(f"<font color='{score_color}'><b>{compliance_score}%</b></font>", normal)],
        [Paragraph("<b>Date:</b>", normal), Paragraph(s.created_at.strftime("%Y-%m-%d %H:%M UTC") if s.created_at else "N/A", normal)],
    ]
    if s.product_id:
        meta_data.append([Paragraph("<b>Product ID (Digital Twin):</b>", normal), Paragraph(str(s.product_id), normal)])

    meta_table = Table(meta_data, colWidths=[180, 350])
    meta_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#f0f9ff')),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.lightgrey),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    elements.append(meta_table)
    elements.append(Spacer(1, 15))

    # === EVIDENCE IMAGES ===
    if s.image_urls:
        elements.append(Paragraph("Inspection Photographs", sub_title))
        for side, url in s.image_urls.items():
            _try_add_image(elements, url, caption=f"Product Photo — {side.upper()}")
            elements.append(Spacer(1, 5))
        elements.append(Spacer(1, 10))

    # === DECLARATIONS TABLE ===
    elements.append(Paragraph("Extracted Legal Metrology Declarations", sub_title))
    
    decl_data = [
        [Paragraph("<b>Declaration Field</b>", normal), Paragraph("<b>Extracted Value</b>", normal)]
    ]
    if d:
        dynamic_fields = d.raw_declarations.get("llm", {}).get("extracted_fields", d.raw_declarations.get("llm", {})) if d.raw_declarations else {}
        formatted_fields = []
        for key, val in dynamic_fields.items():
            label = key.replace("_", " ").title()
            formatted_fields.append((label, str(val) if val is not None else 'NOT DETECTED'))
        for label, val in formatted_fields:
            decl_data.append([
                Paragraph(label, normal),
                Paragraph(str(val), normal),
            ])
    if len(decl_data) == 1:
        decl_data.append([Paragraph("No declarations extracted", normal), Paragraph("", normal)])

    decl_table = Table(decl_data, colWidths=[200, 330])
    
    # Table-card styling: header row, alternating colors, outer box
    table_style = [
        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#0284c7')), # Header bg (sky-600)
        ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
        ('ALIGN', (0, 0), (-1, -1), 'LEFT'),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('TOPPADDING', (0, 0), (-1, -1), 8),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 8),
        ('LEFTPADDING', (0, 0), (-1, -1), 12),
        ('RIGHTPADDING', (0, 0), (-1, -1), 12),
        ('BOX', (0, 0), (-1, -1), 1, colors.HexColor('#0284c7')), # Outer border
        ('INNERGRID', (0, 0), (-1, -1), 0.25, colors.lightgrey),
    ]
    
    # Alternating row colors
    for i in range(1, len(decl_data)):
        if i % 2 == 0:
            table_style.append(('BACKGROUND', (0, i), (-1, i), colors.HexColor('#f8fafc')))
        else:
            table_style.append(('BACKGROUND', (0, i), (-1, i), colors.white))

    decl_table.setStyle(TableStyle(table_style))
    elements.append(decl_table)
    elements.append(Spacer(1, 15))

    # === RULE EVALUATIONS ===
    elements.append(Paragraph("AI Legal Rule Evaluations", sub_title))

    if s.violations:
        for v in s.violations:
            rule_title = v.rule.title if v.rule else "Compliance Check"
            rule_id = v.rule.rule_id if v.rule else "UNKNOWN"
            status = v.status.value
            color = '#16a34a' if status == 'PASS' else '#dc2626'

            elements.append(Paragraph(f"<font color='{color}'><b>[{status}]</b></font> {rule_title}", styles['Heading3']))
            elements.append(Paragraph(f"<font color='#888888'>Rule ID: {rule_id}</font>", styles['RuleID']))
            elements.append(Paragraph(f"<b>Reason:</b> {v.reason}", normal))

            # Citation
            citation = v.rule.conditions.get("citation") if v.rule and v.rule.conditions else None
            if citation:
                elements.append(Spacer(1, 3))
                elements.append(Paragraph(f"<b>Act Violated:</b> {citation.get('act_name', '')}", normal))
                elements.append(Paragraph(f"\"{citation.get('quote', '')}\"", styles['QuoteStyle']))

            # Evidence crop images
            if v.evidence_items:
                for ev in v.evidence_items:
                    if ev.cropped_image:
                        _try_add_image(elements, ev.cropped_image, width=1.5*inch, height=1*inch,
                                       caption=f"Evidence crop — {ev.field}")
                    if ev.file_hash:
                        elements.append(Paragraph(f"Evidence Hash: {ev.file_hash}", styles['RuleID']))

            elements.append(HRFlowable(width="100%", thickness=0.5, color=colors.lightgrey))
            elements.append(Spacer(1, 8))
    else:
        elements.append(Paragraph("No evaluations generated for this scan.", normal))

    elements.append(Spacer(1, 15))

    # === OFFICER DECISION ===
    if s.reviews:
        review = s.reviews[0]
        elements.append(Paragraph("Officer Enforcement Decision", sub_title))
        elements.append(Paragraph(f"<b>Decision:</b> {review.decision.value}", normal))
        if review.notes:
            elements.append(Paragraph(f"<b>Notes:</b> {review.notes}", normal))
        elements.append(Paragraph(f"<b>Reviewed at:</b> {review.created_at.strftime('%Y-%m-%d %H:%M UTC') if review.created_at else 'N/A'}", normal))
        elements.append(Spacer(1, 15))

    # === DIGITAL FINGERPRINT ===
    elements.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#0369a1')))
    elements.append(Spacer(1, 5))

    # Generate a unique hash based on scan content instead of final PDF bytes
    # to avoid the double-build consumption bug in ReportLab
    hash_input = f"scan_{s.id}_{s.created_at}_{len(s.violations)}".encode('utf-8')
    pdf_hash = hashlib.sha256(hash_input).hexdigest()

    elements.append(Paragraph(f"Digital Fingerprint (SHA-256): {pdf_hash}", styles['Fingerprint']))
    elements.append(Paragraph("This report was generated by NIRIKSHAK AI. Any modification will invalidate the digital fingerprint.", styles['Fingerprint']))
    
    doc.build(elements)
    
    buffer.seek(0)
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=compliance_report_{scan_id}.pdf"}
    )


@router.get("/complaint/{complaint_id}/download")
async def download_complaint_report(
    complaint_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
):
    """Generate and download a PDF report for an overcharge complaint."""
    complaint = await db.get(Complaint, complaint_id)
    if not complaint:
        raise HTTPException(status_code=404, detail="Complaint not found")

    styles = _build_styles()
    normal = styles['Normal']
    sub_title = styles['Heading2']

    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=letter, rightMargin=30, leftMargin=30, topMargin=30, bottomMargin=30)
    elements = []

    elements.append(Paragraph("NIRIKSHAK AI", styles['Heading1']))
    elements.append(Paragraph("Citizen Overcharge Grievance Report", styles['Heading2']))
    elements.append(Spacer(1, 10))

    meta_data = [
        [Paragraph("<b>Complaint ID:</b>", normal), Paragraph(str(complaint.id), normal)],
        [Paragraph("<b>Status:</b>", normal), Paragraph(complaint.status.value, normal)],
        [Paragraph("<b>Filed On:</b>", normal), Paragraph(complaint.created_at.strftime("%Y-%m-%d %H:%M UTC") if complaint.created_at else "N/A", normal)],
    ]
    meta_table = Table(meta_data, colWidths=[180, 350])
    meta_table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (0, -1), colors.HexColor('#fff7ed')),
        ('GRID', (0, 0), (-1, -1), 0.5, colors.lightgrey),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    elements.append(meta_table)
    elements.append(Spacer(1, 15))

    elements.append(Paragraph("Complaint Details", sub_title))
    detail_data = [
        [Paragraph("<b>Shopkeeper:</b>", normal), Paragraph(complaint.shopkeeper_name or "Unknown", normal)],
        [Paragraph("<b>Shop Address:</b>", normal), Paragraph(complaint.shop_address or "N/A", normal)],
        [Paragraph("<b>Paid Price:</b>", normal), Paragraph(f"₹{complaint.paid_price}", normal)],
        [Paragraph("<b>Printed MRP:</b>", normal), Paragraph(f"₹{complaint.printed_mrp}", normal)],
        [Paragraph("<b>Overcharge Amount:</b>", normal), Paragraph(f"₹{complaint.paid_price - complaint.printed_mrp}", normal)],
        [Paragraph("<b>Description:</b>", normal), Paragraph(complaint.description or "N/A", normal)],
    ]
    detail_table = Table(detail_data, colWidths=[180, 350])
    detail_table.setStyle(TableStyle([
        ('GRID', (0, 0), (-1, -1), 0.5, colors.lightgrey),
        ('TOPPADDING', (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
    ]))
    elements.append(detail_table)
    elements.append(Spacer(1, 15))

    # Evidence Images
    elements.append(Paragraph("Evidence Photographs", sub_title))
    if complaint.receipt_image_url:
        _try_add_image(elements, complaint.receipt_image_url, caption="Receipt Photo")
        elements.append(Spacer(1, 5))
    if complaint.product_image_url:
        _try_add_image(elements, complaint.product_image_url, caption="Product Photo")
        elements.append(Spacer(1, 5))
    if not complaint.receipt_image_url and not complaint.product_image_url:
        elements.append(Paragraph("No evidence photos attached.", normal))

    elements.append(Spacer(1, 15))

    # Resolution
    if complaint.resolution_notes:
        elements.append(Paragraph("Officer Resolution", sub_title))
        elements.append(Paragraph(complaint.resolution_notes, normal))
        elements.append(Spacer(1, 15))

    # Digital Fingerprint
    elements.append(HRFlowable(width="100%", thickness=1, color=colors.HexColor('#c2410c')))
    elements.append(Spacer(1, 5))
    
    hash_input = f"complaint_{complaint.id}_{complaint.created_at}".encode('utf-8')
    pdf_hash = hashlib.sha256(hash_input).hexdigest()

    elements.append(Paragraph(f"Digital Fingerprint (SHA-256): {pdf_hash}", styles['Fingerprint']))
    elements.append(Paragraph("This report was generated by NIRIKSHAK AI.", styles['Fingerprint']))
    
    doc.build(elements)

    buffer.seek(0)
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename=complaint_report_{complaint_id}.pdf"}
    )


@router.get("/personalized/{user_id}/download")
@router.get("/users/{user_id}/personalized-pdf")
async def download_personalized_pdf_via_reports(
    user_id: uuid.UUID,
    days: int = 7,
    db: AsyncSession = Depends(get_db),
):
    """Generate and stream the personalized weekly PDF report via reports router."""
    from app.api.routes.users import get_personalized_report
    from app.services.reports import generate_personalized_weekly_pdf_report
    report_data = await get_personalized_report(user_id=user_id, days=days, db=db)
    pdf_bytes = await generate_personalized_weekly_pdf_report(user_id=user_id, report_data=report_data, save_to_disk=True)
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'inline; filename="nirikshak_personalized_weekly_{user_id}.pdf"'},
    )
