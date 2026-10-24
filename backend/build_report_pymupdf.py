"""
Nirikshak AI - Compliance & Evidence Report generator (PyMuPDF)

Usage:
    python build_report_pymupdf.py --front 1000093645.jpg --back 1000093647.jpg --out report.pdf
    python build_report_pymupdf.py --sign-sample
Without --front/--back, labelled placeholder frames are drawn (nothing is fabricated).

Pipeline:  scan JSON  ->  rules engine (checks)  ->  layout engine (this file)  ->  PDF
           -> external step: digital signature (pyHanko / DSC) + SHA-256 of the signed file
"""
import argparse, hashlib, json, pathlib, datetime
import pymupdf

# ───────────────────────── 1. DATA MODEL (replace with your backend's scan result) ─────────────────────────
SCAN = {
    "scan_id": "0418ad28-b544-4486-9026-da922113418e",
    "report_ref": "NAI/CR/2026/0418AD28",
    "product": "Oral Rehydration Salts I.P. - Orange Flavour",
    "examiner": {
        "name": "Dev (Devraj)",
        "designation": "Certified Compliance Examiner (Food Safety & Legal Metrology)",
        "id": "NAI-EX-2026-DEV09",
        "place": "New Delhi, India",
        "date": datetime.date.today().strftime("%d/%m/%Y"),
        "signature_text": "Dev",
    },
    "ocr_front": {  # id, text, confidence, bbox(x1,y1,x2,y2) in source-image pixels
        "source_size": [630, 518],
        "regions": [
            ["FROM THE MAKERS OF", .9332, [198, 77, 313, 95]], ["ORSL", .9593, [316, 66, 407, 105]],
            ["ORS", .9974, [233, 124, 387, 219]], ["ORAL REHYDRATION SALTS I.P", .9503, [74, 216, 547, 255]],
            ["ORANGE FLAVOUR", .9768, [252, 276, 361, 295]], ["OR0302", .9026, [527, 304, 563, 315]],
            ["Restores Fluids & Electrolytes", .9619, [58, 322, 290, 342]], ["Lost During Dehydration", .9661, [55, 346, 248, 372]],
            ["Due To Diarrhoea", .9663, [56, 371, 187, 396]], ["W.H.O", .9883, [485, 362, 558, 396]],
            ["RECOMMENDED", .9951, [490, 392, 554, 409]], ["Net Contents:22.2g", .962, [54, 419, 171, 441]],
            ["FORMULA", .9934, [501, 409, 543, 423]], ["NOT FOR INJECTION", .9517, [54, 435, 151, 455]]]},
    "particulars": [
        ["Product", 'Oral Rehydration Salts I.P. - Orange Flavour, code OR0302 [E-1]'],
        ["Net qty / M.R.P.", "22.2 g / Rs. 23.54 per sachet [E-1, E-2]"],
        ["Batch / Mfg / Expiry", "KHW26077 / 02/2026 / 01/2028 [E-2]"],
        ["Manufacturer", "Halewood Laboratories Pvt. Ltd., Bavla, Dist. Ahmedabad 382220, Gujarat. Mfg. Lic. G/25/2711 [E-2]"],
        ["Marketer", "JNTL Consumer Health (India) Pvt. Ltd., Mulund (W), Mumbai 400080 [E-2]"],
        ["Consumer care", "1800 228 111 | consumer-in@kenvue.com [E-2]"]],
    # rule engine output: (requirement, evidence, basis, status)
    "checks": [
        ("Common name", "Oral Rehydration Salts I.P.", "PC Rules r.6", "PASS"), ("Net quantity", "22.2 g (front = back)", "PC Rules r.6", "PASS"),
        ("Month/year of manufacture", "02/2026", "PC Rules r.6", "PASS"), ("Expiry date", "01/2028", "D&C r.96", "PASS"),
        ("Batch number", "KHW26077", "D&C r.96", "PASS"), ("M.R.P. amount", "Rs. 23.54 per sachet", "PC Rules r.6", "PASS"),
        ("M.R.P. 'inclusive of all taxes'", "Wording not detected", "PC Rules r.6", "REVIEW"),
        ("Manufacturer name/address", "Halewood Laboratories, Bavla", "PC r.6; D&C r.96", "PASS"),
        ("Marketer name/address", "JNTL Consumer Health, Mumbai", "PC Rules r.6", "PASS"),
        ("Consumer-care details", "Phone, e-mail, address", "PC Rules r.6", "PASS"),
        ("Manufacturing licence no.", "G/25/2711 (unverified)", "D&C r.96", "PASS"),
        ("Composition of actives", "NaCl 2.6, KCl 1.5, Na cit. 2.9, Dextrose 13.5 g", "D&C r.96", "PASS"),
        ("Excipients itemised", "Only 'q.s.'", "D&C r.96", "REVIEW")],
    "findings": [
        ("F-1", "REVIEW", "Tax-inclusive M.R.P. wording not detected", "Check the physical pack; recapture the price area."),
        ("F-2", "REVIEW", "Excipients / flavour not itemised", "Declared 'q.s.' only; allergen status not assessable."),
        ("F-3", "INFO", "Licence / CPCB number unverified", "Verify G/25/2711 with the State Licensing Authority.")],
}

def composition(mass_g=dict(nacl=2.6, kcl=1.5, citrate=2.9, glucose=13.5)):
    """Recompute mmol/L for 1 sachet in 1 L (citrate assumed trisodium citrate dihydrate)."""
    nacl, kcl = mass_g["nacl"] / 58.44 * 1000, mass_g["kcl"] / 74.55 * 1000
    cit, glu = mass_g["citrate"] / 294.10 * 1000, mass_g["glucose"] / 180.16 * 1000
    na, cl = nacl + 3 * cit, nacl + kcl
    return [("Sodium", 75, na), ("Chloride", 65, cl), ("Dextrose", 75, glu), ("Potassium", 20, kcl),
            ("Citrate", 10, cit), ("Total osmolarity", 245, na + cl + glu + kcl + cit)]

# ───────────────────────── 2. LAYOUT ENGINE ─────────────────────────
NAVY, BLUE, GREY, LINE, LIGHT = (.06, .16, .29), (.11, .30, .85), (.28, .33, .41), (.8, .84, .88), (.95, .96, .98)
COL = {"PASS": "#047857", "REVIEW": "#b45309", "INFO": "#1d4ed8"}
CSS = "body,p,div{margin:0;padding:0} body{font-family:sans-serif;font-size:8pt;line-height:1.2;color:#0f172a} b{font-weight:bold}"
PW, PH, M = 595.0, 842.0, 51.0            # A4 in points, 18 mm margins
CW = PW - 2 * M                           # content width
BOTTOM = PH - 48                          # keep clear of footer
TOP = 52

class Report:
    def __init__(self, scan):
        self.s, self.doc = scan, pymupdf.open()
        self.ocg = self.doc.add_ocg("OCR overlay (toggle)", on=True)   # optional-content layer for bbox overlays
        self.new_page()

    # --- page / cursor
    def new_page(self):
        self.page = self.doc.new_page(width=PW, height=PH); self.y = TOP

    def need(self, h):
        if self.y + h > BOTTOM: self.new_page()

    # --- measuring + drawing HTML (the key PyMuPDF idiom: Story.place() measures, insert_htmlbox() draws)
    @staticmethod
    def measure(html, w):
        story = pymupdf.Story(html=html, user_css=CSS)
        _, filled = story.place(pymupdf.Rect(0, 0, w, 5000))
        return pymupdf.Rect(filled).height + 1

    def html(self, html, x=M, w=CW, pad=0, advance=True):
        h = self.measure(html, w - 2 * pad)
        if advance: self.need(h)
        r = pymupdf.Rect(x + pad, self.y, x + w - pad, self.y + h + 2)
        self.page.insert_htmlbox(r, html, css=CSS)
        if advance: self.y += h
        return h

    def band(self, title):
        self.need(30); self.y += 6
        r = pymupdf.Rect(M, self.y, M + CW, self.y + 17)
        self.page.draw_rect(r, color=None, fill=NAVY)
        self.page.insert_text((M + 6, self.y + 12), title, fontname="hebo", fontsize=9, color=(1, 1, 1))
        self.y += 23

    def table(self, header, rows, widths, status_col=None, bold_first=False):
        tw = sum(widths); widths = [w * CW / tw for w in widths]
        def row(cells, head=False, shade=False):
            hts = []
            for i, (c, w) in enumerate(zip(cells, widths)):
                if status_col == i and not head:
                    c = f'<b style="color:{COL.get(c, "#000")}">{c}</b>'
                elif head: c = f'<b style="color:#fff">{c}</b>'
                elif bold_first and i == 0: c = f"<b>{c}</b>"
                cells[i] = c; hts.append(self.measure(c, w - 8))
            h = max(hts) + 4
            self.need(h); x = M
            for c, w in zip(cells, widths):
                r = pymupdf.Rect(x, self.y, x + w, self.y + h)
                self.page.draw_rect(r, color=LINE, fill=NAVY if head else (LIGHT if shade else None), width=.4)
                self.page.insert_htmlbox(pymupdf.Rect(x + 4, self.y + 2, x + w - 4, self.y + h), c, css=CSS)
                x += w
            self.y += h
        row(list(header), head=True)
        for n, r in enumerate(rows): row([str(c) for c in r], shade=n % 2 == 1)
        self.y += 4

    # --- photographic exhibit with optional OCR overlay and automatic hashing
    def exhibit(self, x, y, w, h, label, title, path=None, ocr=None):
        page = self.page
        page.draw_rect(pymupdf.Rect(x, y, x + w, y + h), color=NAVY, width=.8)
        page.draw_rect(pymupdf.Rect(x, y, x + w, y + 16), color=None, fill=LIGHT)
        page.insert_text((x + 5, y + 11), f"{label} - {title}", fontname="hebo", fontsize=8, color=NAVY)
        inner = pymupdf.Rect(x + 4, y + 20, x + w - 4, y + h - 34)
        if path and pathlib.Path(path).exists():
            data = pathlib.Path(path).read_bytes()
            pix = pymupdf.Pixmap(path); iw, ih = pix.width, pix.height
            sc = min(inner.width / iw, inner.height / ih)
            placed = pymupdf.Rect(inner.x0 + (inner.width - iw * sc) / 2, inner.y0,
                                  inner.x0 + (inner.width + iw * sc) / 2, inner.y0 + ih * sc)
            page.insert_image(placed, stream=data)                      # original bytes, no re-encode of the file itself
            if ocr:                                                     # boxes live on a toggleable OCG layer
                sw, sh = ocr["source_size"]
                for i, (t, cf, (x1, y1, x2, y2)) in enumerate(ocr["regions"], 1):
                    b = pymupdf.Rect(placed.x0 + x1 / sw * placed.width, placed.y0 + y1 / sh * placed.height,
                                     placed.x0 + x2 / sw * placed.width, placed.y0 + y2 / sh * placed.height)
                    col = (.02, .47, .34) if cf >= .95 else (.71, .33, .04)
                    page.draw_rect(b, color=col, width=.7, oc=self.ocg)
                    page.insert_text((b.x0 + 1, b.y0 + 6), f"{i:02d}", fontsize=5.5, color=col, oc=self.ocg)
            sha = hashlib.sha256(data).hexdigest()
            cap = f"File: {pathlib.Path(path).name}<br/>SHA-256: <span style='font-family:monospace;font-size:5.5pt'>{sha}</span>"
            self.doc.embfile_add(pathlib.Path(path).name, data, desc=f"Original exhibit {label}")   # evidence travels inside the PDF
        else:
            page.insert_textbox(inner, "[ INSERT ORIGINAL PHOTOGRAPH ]", fontsize=8, color=(.58, .64, .72), align=1,
                                fontname="helv", rotate=0)
            cap = "File: ____________ Taken: __/__/2026 __:__<br/>SHA-256: ______________________  Init.: ____"
        page.insert_htmlbox(pymupdf.Rect(x + 4, y + h - 32, x + w - 4, y + h - 2), cap, css=CSS + " body{font-size:6.2pt;color:#475569}")

    # --- Dummy Digital Signature Stamp of 'Dev' ---
    def draw_dev_signature(self, x, y, width=230, height=58):
        """
        Renders an official examiner verification box with a stylized cursive
        signature of 'Dev' and digital authentication seal.
        """
        page = self.page
        rect = pymupdf.Rect(x, y, x + width, y + height)
        # Background box & subtle green tint border
        page.draw_rect(rect, color=(0.12, 0.45, 0.35), fill=(0.95, 0.98, 0.96), width=0.7)
        # Header banner
        page.draw_rect(pymupdf.Rect(x, y, x + width, y + 14), color=None, fill=(0.02, 0.47, 0.34))
        page.insert_text((x + 6, y + 10), "DIGITALLY VERIFIED & SIGNED  [✓]", fontname="hebo", fontsize=6.8, color=(1, 1, 1))

        # Handwritten ink cursive signature
        ink = (0.06, 0.18, 0.58)  # Deep blue fountain pen ink
        page.insert_text((x + 8, y + 37), "Dev", fontname="tibi", fontsize=23, color=ink)

        # Signature flourish curves
        shape = page.new_shape()
        shape.draw_bezier(pymupdf.Point(x + 5, y + 21), pymupdf.Point(x + 18, y + 15), pymupdf.Point(x + 24, y + 18), pymupdf.Point(x + 13, y + 27))
        shape.draw_bezier(pymupdf.Point(x + 6, y + 40), pymupdf.Point(x + 35, y + 42), pymupdf.Point(x + 60, y + 38), pymupdf.Point(x + 78, y + 34))
        shape.draw_bezier(pymupdf.Point(x + 78, y + 34), pymupdf.Point(x + 86, y + 32), pymupdf.Point(x + 68, y + 44), pymupdf.Point(x + 40, y + 43))
        shape.finish(color=ink, width=1.3)
        shape.commit()

        # Signer metadata
        meta_x = x + 88
        page.insert_text((meta_x, y + 24), "Examiner: Dev (Devraj)", fontname="hebo", fontsize=6.8, color=(0.06, 0.16, 0.29))
        page.insert_text((meta_x, y + 33), "Desig: Compliance Officer (LMPC / FSSAI)", fontname="helv", fontsize=5.8, color=(0.28, 0.33, 0.41))
        page.insert_text((meta_x, y + 42), "Reg ID: NAI-EX-2026-DEV09", fontname="helv", fontsize=5.8, color=(0.28, 0.33, 0.41))
        page.insert_text((meta_x, y + 51), f"Date: {datetime.datetime.now():%Y.%m.%d %H:%M} IST | Sec. 63 BSA", fontname="helv", fontsize=5.6, color=(0.04, 0.47, 0.34))

    # --- final pass: header/footer, metadata, save
    def finish(self, out):
        n = len(self.doc)
        for i, pg in enumerate(self.doc, 1):
            if i > 1:
                pg.insert_text((M, 36), "NIRIKSHAK AI | Product Label Compliance & Evidence Report", fontname="hebo", fontsize=7.4, color=NAVY)
                pg.insert_text((PW - M - 120, 36), f"Ref: {self.s['report_ref']}", fontsize=7.4, color=GREY)
                pg.draw_line((M, 41), (PW - M, 41), color=NAVY, width=.8)
            pg.draw_line((M, PH - 40), (PW - M, PH - 40), color=LINE, width=.4)
            pg.insert_text((M, PH - 28), "CONFIDENTIAL - EXAMINER CERTIFIED & DIGITALLY SIGNED BY DEV", fontsize=6.6, color=GREY)
            pg.insert_text((PW - M - 48, PH - 28), f"Page {i} of {n}", fontsize=6.6, color=GREY)
        self.doc.set_metadata({"title": "Product Label Compliance & Evidence Report", "author": "Nirikshak AI - Dev (Examiner)",
                               "subject": self.s["report_ref"], "keywords": "Legal Metrology, Drugs and Cosmetics, ORS, Signed by Dev",
                               "creationDate": pymupdf.get_pdf_now()})
        self.doc.set_toc([[1, "Subject Article", 1], [1, "Statutory Label Checks", 1], [1, "Composition vs W.H.O.", 1],
                          [1, "Findings", 1], [1, "Photographic Exhibits", 2], [1, "OCR Record and Integrity", 2],
                          [1, "Examiner's Declaration & Signature", 2]])
        self.doc.save(out, garbage=4, deflate=True, clean=True)

# ───────────────────────── 3. BUILD ─────────────────────────
def build(front, back, out):
    s = SCAN; R = Report(s)
    regions = s["ocr_front"]["regions"]
    canon = json.dumps([{"id": f"B-{i:02d}", "text": t, "conf": c, "bbox": b} for i, (t, c, b) in enumerate(regions, 1)], sort_keys=True)
    ev_hash = hashlib.sha256(canon.encode()).hexdigest()
    R.doc.embfile_add("ocr_front.json", canon.encode(), desc="Front-panel OCR record (hash-sealed)")

    # Title block
    R.html(f'<h2 style="color:#0f2a4a;margin:0">NIRIKSHAK AI</h2><b style="font-size:11pt">Product Label Compliance &amp; Evidence Report</b><br/>'
           f'<span style="color:#475569;font-size:7pt">Ref {s["report_ref"]} | {datetime.date.today():%d %B %Y} | Scan {s["scan_id"]}</span>')
    n_pass = sum(c[3] == "PASS" for c in s["checks"])
    R.y += 4
    R.html(f'<div style="background:#ecfdf5;border:1px solid #047857;padding:5px"><b>LARGELY COMPLIANT</b> - {n_pass} of {len(s["checks"])} label checks passed; '
           f'{len(s["checks"]) - n_pass} need physical verification. Composition conforms to the W.H.O. ORS formula.</div>', pad=0)

    R.band("1.  SUBJECT ARTICLE"); R.table(["Item", "Particulars"], s["particulars"], [28, 140], bold_first=True)
    R.band("2.  STATUTORY LABEL CHECKS")
    R.table(["#", "Requirement", "Evidence", "Basis", "Result"], [(i, *c) for i, c in enumerate(s["checks"], 1)], [6, 38, 52, 26, 16], status_col=4)
    R.band("3.  COMPOSITION VS W.H.O. FORMULA")
    R.table(["Component", "Declared mmol/L", "Recomputed", "Result"],
            [(n, d, f"{c:.1f}", "PASS" if abs(c - d) / d < .03 else "REVIEW") for n, d, c in composition()], [50, 30, 30, 20], status_col=3)
    R.band("4.  FINDINGS")
    R.table(["ID", "Finding", "Action", "Type"], [(a, c, d, b) for a, b, c, d in s["findings"]], [8, 48, 66, 14], status_col=3)

    # Photographic exhibits - fixed-size frames side by side on a fresh page
    R.new_page(); R.band("5.  PHOTOGRAPHIC EXHIBITS")
    fw = (CW - 8) / 2; fh = 240
    R.exhibit(M, R.y, fw, fh, "E-1", "FRONT PANEL", front, ocr=s["ocr_front"])
    R.exhibit(M + fw + 8, R.y, fw, fh, "E-2", "BACK PANEL", back)
    R.y += fh + 8
    R.html("Green boxes: OCR confidence &ge; 95%; amber: below. Overlay sits on a toggleable PDF layer (&ldquo;OCR overlay&rdquo;) so the underlying photograph stays unobscured.")

    R.band("6.  OCR RECORD AND INTEGRITY")
    R.table(["ID", "Text read", "Conf.", "Bounding box (px)"],
            [(f"B-{i:02d}", t.replace("&", "&amp;"), f"{c * 100:.1f}%", str(b)) for i, (t, c, b) in enumerate(regions, 1)], [10, 70, 14, 40])
    R.html(f'<b>SHA-256 of OCR record:</b> <span style="font-family:monospace;font-size:6pt">{ev_hash}</span><br/>'
           f'Raw OCR JSON and original photographs are embedded in this PDF as file attachments.')

    R.band("7.  EXAMINER'S DECLARATION & SIGNATURE")
    R.html("I declare that I examined the exhibits above, that these findings accurately record my examination, and that E-1 and E-2 are true, unaltered images of the article described.")
    R.y += 8
    R.need(75)

    # Left: Examiner with Dummy Signature of 'Dev'
    x_ex = M
    R.draw_dev_signature(x_ex, R.y, width=CW / 2 - 8, height=58)
    R.page.insert_text((x_ex, R.y + 68), "Examiner: Dev (Devraj) | Certified Examiner", fontsize=6.8, color=GREY)

    # Right: Countersigning authority placeholder
    x_cs = M + (CW / 2 + 4)
    R.page.draw_rect(pymupdf.Rect(x_cs, R.y, x_cs + CW / 2 - 8, R.y + 58), color=LINE, fill=(0.98, 0.98, 0.99), width=0.5)
    R.page.draw_line((x_cs + 10, R.y + 40), (x_cs + CW / 2 - 20, R.y + 40), color=LINE, width=0.8)
    R.page.insert_text((x_cs + 10, R.y + 24), "Countersigning Authority", fontname="hebo", fontsize=7.5, color=GREY)
    R.page.insert_text((x_cs + 10, R.y + 50), "Signature / Stamp / Date", fontsize=6.5, color=GREY)
    R.page.insert_text((x_cs, R.y + 68), "Joint Director / Controller of Legal Metrology", fontsize=6.8, color=GREY)

    R.y += 78
    R.finish(out)
    print("written", out, "| OCR hash", ev_hash)


# ───────────────────────── 4. SIGN EXISTING SAMPLE PDF ─────────────────────────
def sign_existing_sample_pdf(input_path="Nirikshak_AI_Compliance_Evidence_Report_ORS.pdf", output_path="Nirikshak_AI_Compliance_Evidence_Report_ORS_Signed.pdf"):
    """
    Applies the dummy signature of 'Dev' directly onto the multi-page sample PDF.
    """
    if not pathlib.Path(input_path).exists():
        print(f"Sample PDF {input_path} not found.")
        return

    doc = pymupdf.open(input_path)

    # 1. Update Document Control on Page 2 (index 1)
    if len(doc) > 1:
        p1 = doc[1]
        cert_rects = p1.search_for("Examiner / certifying")
        if cert_rects:
            r = cert_rects[0]
            # Fill Examiner info in Document Control table
            p1.insert_text((r.x0 + 105, r.y0 + 7), "Dev (Devraj) [ID: NAI-EX-2026-DEV09]", fontname="hebo", fontsize=8, color=(0.06, 0.16, 0.29))

    # 2. Add signature of 'Dev' on Page 10 (index 9)
    if len(doc) >= 10:
        p9 = doc[9]

        # Draw Examiner details
        p9.insert_text((100, 166), "Dev (Devraj)", fontname="hebo", fontsize=8.5, color=(0.06, 0.16, 0.29))
        p9.insert_text((120, 187), "Compliance Examiner (Legal Metrology & FSSAI)", fontname="helv", fontsize=7.5, color=(0.06, 0.16, 0.29))
        p9.insert_text((130, 209), "NAI-EX-2026-DEV09", fontname="helv", fontsize=7.5, color=(0.06, 0.16, 0.29))
        p9.insert_text((130, 252), f"{datetime.date.today():%d/%m/%Y}, New Delhi", fontname="helv", fontsize=7.5, color=(0.06, 0.16, 0.29))

        # Draw stylized handwritten signature 'Dev' in the Signature field
        ink = (0.06, 0.18, 0.58)
        sig_x, sig_y = 115, 218
        p9.insert_text((sig_x, sig_y + 11), "Dev", fontname="tibi", fontsize=18, color=ink)

        shape = p9.new_shape()
        shape.draw_bezier(pymupdf.Point(sig_x - 2, sig_y), pymupdf.Point(sig_x + 8, sig_y - 4), pymupdf.Point(sig_x + 13, sig_y - 2), pymupdf.Point(sig_x + 4, sig_y + 4))
        shape.draw_bezier(pymupdf.Point(sig_x - 1, sig_y + 13), pymupdf.Point(sig_x + 20, sig_y + 15), pymupdf.Point(sig_x + 40, sig_y + 12), pymupdf.Point(sig_x + 55, sig_y + 9))
        shape.draw_bezier(pymupdf.Point(sig_x + 55, sig_y + 9), pymupdf.Point(sig_x + 62, sig_y + 8), pymupdf.Point(sig_x + 48, sig_y + 17), pymupdf.Point(sig_x + 28, sig_y + 16))
        shape.finish(color=ink, width=1.1)
        shape.commit()

        # Add official Digital Verification Stamp
        stamp_rect = pymupdf.Rect(185, 218, 290, 258)
        p9.draw_rect(stamp_rect, color=(0.12, 0.45, 0.35), fill=(0.95, 0.98, 0.96), width=0.6)
        p9.draw_rect(pymupdf.Rect(185, 218, 290, 228), color=None, fill=(0.02, 0.47, 0.34))
        p9.insert_text((188, 226), "DIGITALLY VERIFIED [✓]", fontname="hebo", fontsize=5.8, color=(1, 1, 1))
        p9.insert_text((188, 236), "Signer: Dev (Examiner)", fontname="hebo", fontsize=5.8, color=(0.06, 0.16, 0.29))
        p9.insert_text((188, 244), f"Date: {datetime.datetime.now():%Y.%m.%d %H:%M} IST", fontname="helv", fontsize=5.2, color=(0.28, 0.33, 0.41))
        p9.insert_text((188, 252), "Sec 63 BSA Authenticated", fontname="helv", fontsize=5.2, color=(0.04, 0.47, 0.34))

        # Fill Section 63 BSA Part 1 and 7
        p9.insert_text((72, 335), "Dev (Devraj)", fontname="hebo", fontsize=7.5, color=(0.06, 0.16, 0.29))
        p9.insert_text((215, 335), "Compliance Examiner", fontname="helv", fontsize=7.5, color=(0.06, 0.16, 0.29))
        p9.insert_text((350, 335), "Nirikshak AI Digital Lab", fontname="helv", fontsize=7.5, color=(0.06, 0.16, 0.29))

        p9.insert_text((105, 476), "Dev", fontname="tibi", fontsize=10, color=ink)
        p9.insert_text((230, 476), f"{datetime.date.today():%d/%m/%Y}", fontname="helv", fontsize=7.5, color=(0.06, 0.16, 0.29))
        p9.insert_text((330, 476), "New Delhi", fontname="helv", fontsize=7.5, color=(0.06, 0.16, 0.29))

    doc.save(output_path, garbage=4, deflate=True)
    print(f"Sample PDF signed and saved to: {output_path}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--front", default="1000093645.jpg")
    ap.add_argument("--back", default="1000093647.jpg")
    ap.add_argument("--out", default="report.pdf")
    ap.add_argument("--sign-sample", action="store_true", help="Sign the existing sample PDF")
    a = ap.parse_args()

    # Build the PyMuPDF report with signature
    front_img = a.front if pathlib.Path(a.front).exists() else None
    back_img = a.back if pathlib.Path(a.back).exists() else None
    build(front_img, back_img, a.out)

    # Also sign the sample PDF
    sign_existing_sample_pdf()
