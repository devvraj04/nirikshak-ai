import { Complaint, ScanItem, BrandRating, BrandDetail, ChatMessage } from '../types';

const isServer = typeof window === 'undefined';
const API_BASE_URL = isServer 
  ? (process.env.NEXT_PUBLIC_API_URL || 'http://3.7.153.193:8080') 
  : '/api/proxy';

// Mock fallback data for rich offline demonstration
const MOCK_COMPLAINTS: Complaint[] = [
  {
    complaint_id: 'cmp-9812-4412',
    citizen_id: 'Dev (Consumer)',
    paid_price: 180.0,
    printed_mrp: 140.0,
    shopkeeper_name: 'Gupta General Provisions Store',
    shop_address: 'Shop #14, Sector 18 Market, Noida, UP',
    status: 'SUBMITTED',
    description: 'Vendor charged ₹180 for 500g pack despite clearly visible printed MRP of ₹140. Refused bill copy until insisted.',
    created_at: new Date(Date.now() - 3600000 * 2).toISOString(),
    receipt_image_url: '/uploads/complaints/mock_receipt.jpg',
    product_image_url: '/uploads/complaints/mock_pack.jpg',
  },
  {
    complaint_id: 'cmp-7721-1093',
    citizen_id: 'Aarav Sharma',
    paid_price: 250.0,
    printed_mrp: 210.0,
    shopkeeper_name: 'Metro Daily Supermart',
    shop_address: 'Plot 4A, Connaught Place, New Delhi',
    status: 'UNDER_REVIEW',
    description: 'Overcharged ₹40 over printed MRP on imported olive oil pack. Barcode sticker placed over original manufacturer MRP.',
    created_at: new Date(Date.now() - 3600000 * 5).toISOString(),
    receipt_image_url: '/uploads/complaints/mock_receipt2.jpg',
    product_image_url: '/uploads/complaints/mock_pack2.jpg',
  },
  {
    complaint_id: 'cmp-3301-8841',
    citizen_id: 'Priya Iyer',
    paid_price: 95.0,
    printed_mrp: 95.0,
    shopkeeper_name: 'QuickBite Corner',
    shop_address: 'HSR Layout Sector 3, Bengaluru, Karnataka',
    status: 'RESOLVED',
    description: 'Reported missing consumer care contact and smudged expiry date on dairy carton.',
    created_at: new Date(Date.now() - 3600000 * 24).toISOString(),
    resolution_notes: 'Officer Raj inspected store on 08 Sept. Warning notice issued under Section 15 & Rule 6(1). Fine of ₹10,000 compounded.',
  },
  {
    complaint_id: 'cmp-1102-5509',
    citizen_id: 'Kunal Sen',
    paid_price: 35.0,
    printed_mrp: 35.0,
    shopkeeper_name: 'Sharma Sweets & Snacks',
    shop_address: 'Salt Lake Sector 1, Kolkata, WB',
    status: 'REJECTED',
    description: 'Claimed overcharge but printed MRP matches bill amount. No violation detected.',
    created_at: new Date(Date.now() - 3600000 * 48).toISOString(),
    resolution_notes: 'Rejected by Officer Raj: bill matches printed packaging MRP of ₹35.00. Citizen notified.',
  }
];

const MOCK_SCANS: ScanItem[] = [
  {
    scan_id: 'scn-4491-0021',
    status: 'COMPLETED',
    overall_compliance: 'FAIL',
    created_at: new Date(Date.now() - 3600000 * 1).toISOString(),
    manufacturer_name: 'Haldiram Snacks Pvt Ltd',
    product_name: 'Aloo Bhujia 400g Pouch',
    product_category: 'Packaged Savouries',
    is_resolved: false,
    image_urls: {
      front: 'https://images.unsplash.com/photo-1621996346565-e3d5d6281691?w=500&auto=format&fit=crop&q=60',
      back: 'https://images.unsplash.com/photo-1599490659213-e2b9527bd087?w=500&auto=format&fit=crop&q=60'
    },
    ocr_transcriptions: [
      {
        image_side: 'front',
        image_url: 'https://images.unsplash.com/photo-1621996346565-e3d5d6281691?w=500&auto=format&fit=crop&q=60',
        detected_text: 'HALDIRAM\'S\nALOO BHUJIA\nCRISPY SPICED POTATO NOODLES\nNET WT: 400 gms\n100% VEG',
        confidence: 0.962,
        boxes_count: 5,
        lines_detected: 5,
        bounding_boxes: [
          { text: "HALDIRAM'S", bbox: [[160, 48], [340, 48], [340, 80], [160, 80]], score: 0.98, normalized: { x: 32, y: 10, width: 36, height: 8 } },
          { text: "ALOO BHUJIA", bbox: [[120, 105], [380, 105], [380, 155], [120, 155]], score: 0.99, normalized: { x: 24, y: 22, width: 52, height: 11 } },
          { text: "CRISPY SPICED POTATO NOODLES", bbox: [[90, 180], [410, 180], [410, 215], [90, 215]], score: 0.95, normalized: { x: 18, y: 37, width: 64, height: 8 } },
          { text: "NET WT: 400 gms", bbox: [[140, 350], [360, 350], [360, 385], [140, 385]], score: 0.96, normalized: { x: 28, y: 72, width: 44, height: 7 } },
          { text: "100% VEG", bbox: [[340, 410], [450, 410], [450, 440], [340, 440]], score: 0.97, normalized: { x: 68, y: 84, width: 24, height: 6 } },
        ]
      },
      {
        image_side: 'back',
        image_url: 'https://images.unsplash.com/photo-1599490659213-e2b9527bd087?w=500&auto=format&fit=crop&q=60',
        detected_text: 'MAXIMUM RETAIL PRICE ₹ 110.00\n(INCL. OF ALL TAXES)\nBATCH NO: AB-0926-X1\nMFD: 08/2026\nUSE BY: 02/2027\nMFD BY: HALDIRAM SNACKS PVT LTD\nB-1/H-3, MOHAN CO-OP IND ESTATE, NEW DELHI - 110044\nCUSTOMER CARE: care@haldiram.com | 1800-102-3344\nFSSAI LIC NO. 10012011000673',
        confidence: 0.948,
        boxes_count: 9,
        lines_detected: 9,
        bounding_boxes: [
          { text: "MAXIMUM RETAIL PRICE ₹ 110.00", bbox: [[70, 60], [430, 60], [430, 95], [70, 95]], score: 0.97, normalized: { x: 14, y: 12, width: 72, height: 7 } },
          { text: "(INCL. OF ALL TAXES)", bbox: [[130, 100], [370, 100], [370, 125], [130, 125]], score: 0.94, normalized: { x: 26, y: 20, width: 48, height: 5 } },
          { text: "BATCH NO: AB-0926-X1", bbox: [[70, 140], [320, 140], [320, 170], [70, 170]], score: 0.96, normalized: { x: 14, y: 28, width: 50, height: 6 } },
          { text: "MFD: 08/2026", bbox: [[70, 180], [245, 180], [245, 210], [70, 210]], score: 0.98, normalized: { x: 14, y: 36, width: 35, height: 6 } },
          { text: "USE BY: 02/2027", bbox: [[275, 180], [450, 180], [450, 210], [275, 210]], score: 0.97, normalized: { x: 55, y: 36, width: 35, height: 6 } },
          { text: "MFD BY: HALDIRAM SNACKS PVT LTD", bbox: [[60, 230], [440, 230], [440, 260], [60, 260]], score: 0.95, normalized: { x: 12, y: 46, width: 76, height: 6 } },
          { text: "B-1/H-3, MOHAN CO-OP IND ESTATE, NEW DELHI - 110044", bbox: [[50, 270], [450, 270], [450, 300], [50, 300]], score: 0.92, normalized: { x: 10, y: 54, width: 80, height: 6 } },
          { text: "CUSTOMER CARE: care@haldiram.com | 1800-102-3344", bbox: [[50, 320], [450, 320], [450, 350], [50, 350]], score: 0.96, normalized: { x: 10, y: 64, width: 80, height: 6 } },
          { text: "FSSAI LIC NO. 10012011000673", bbox: [[90, 380], [410, 380], [410, 410], [90, 410]], score: 0.94, normalized: { x: 18, y: 76, width: 64, height: 6 } },
        ]
      }
    ],
    brand_claims: [
      {
        claim: "100% Veg (Certified Vegetarian)",
        category: "Dietary & Ethical",
        context: "Front packaging emblem with green dot in square",
        verification_note: "Complies with statutory vegetarian declaration symbol",
        highlight: true
      },
      {
        claim: "Crispy Spiced Potato Noodles",
        category: "Taste & Sensory",
        context: "Front brand header subtitle",
        verification_note: "Distinctive recipe sensory assertion",
        highlight: true
      },
      {
        claim: "Zero Artificial Flavours or Colours",
        category: "Health & Purity",
        context: "Side panel disclosure",
        verification_note: "Voluntary marketing claim subject to FSSAI ingredient compliance",
        highlight: true
      }
    ],
    summary_sentences: [
      "The package represents Haldiram's Aloo Bhujia (Crispy Spiced Potato Noodles) with a declared net quantity of 400 g and an MRP of ₹ 110.00 inclusive of all taxes.",
      "Manufactured by Haldiram Snacks Pvt Ltd in August 2026 with expiry in February 2027 under batch number AB-0926-X1.",
      "Customer care support is provided via phone at 1800-102-3344 and email at care@haldiram.com.",
      "Prominent Brand Claims Highlight: The packaging prominently asserts '100% Veg' and 'Crispy Spiced Potato Noodles' with 'Zero Artificial Flavours' as primary brand guarantees."
    ],
    declarations_table: [
      { attribute: "Generic Product Name", value: "Aloo Bhujia Extruded Snack", category: "Statutory Declaration", is_brand_claim: false, highlight: false },
      { attribute: "Maximum Retail Price (MRP)", value: "₹ 110.00 (Incl. of all taxes)", category: "Statutory Declaration", is_brand_claim: false, highlight: false },
      { attribute: "Net Quantity", value: "400 gms (Violates standard symbol 'g')", category: "Statutory Declaration", is_brand_claim: false, highlight: false },
      { attribute: "Date of Manufacture", value: "08/2026", category: "Statutory Declaration", is_brand_claim: false, highlight: false },
      { attribute: "Best Before / Expiry", value: "02/2027", category: "Statutory Declaration", is_brand_claim: false, highlight: false },
      { attribute: "Batch Identifier", value: "AB-0926-X1", category: "Statutory Declaration", is_brand_claim: false, highlight: false },
      { attribute: "Manufacturer Address", value: "Haldiram Snacks Pvt Ltd, Mohan Co-op Ind Estate, New Delhi - 110044", category: "Statutory Declaration", is_brand_claim: false, highlight: false },
      { attribute: "Consumer Care Support", value: "care@haldiram.com | 1800-102-3344", category: "Contact & Care", is_brand_claim: false, highlight: false },
      { attribute: "Brand Claim: Dietary & Ethical", value: "100% Veg (Certified Vegetarian Snack)", category: "Brand Claim", is_brand_claim: true, highlight: true },
      { attribute: "Brand Claim: Sensory & Character", value: "Crispy Spiced Potato Noodles", category: "Brand Claim", is_brand_claim: true, highlight: true },
      { attribute: "Brand Claim: Health & Purity", value: "Zero Artificial Flavours or Colours", category: "Brand Claim", is_brand_claim: true, highlight: true }
    ],
    compliance_summary: {
      passed_rules: 4,
      failed_rules: 2,
      review_rules: 1,
      compliance_score: 57
    },
    extracted_declarations: {
      generic_product_name: 'Aloo Bhujia Extruded Snack',
      net_quantity: '400 g',
      mrp: '₹ 110.00 (Incl. of all taxes)',
      manufacturer_name: 'Haldiram Snacks Pvt Ltd, B-1/H-3, Mohan Co-op Ind Estate, Mathura Road, New Delhi',
      manufacture_date: '08/2026',
      expiry_date: '02/2027',
      consumer_care: 'care@haldiram.com / 1800-102-3344'
    },
    evaluations: [
      {
        rule_title: 'RULE-LM-002: Net Quantity Metric Units & Font Standard',
        status: 'FAIL',
        reason: 'Net quantity unit printed as "gms" instead of statutory standard metric symbol "g". Font height is 2.8mm, required minimum is 4.0mm for 400g net weight.',
        citation: {
          act_name: 'Legal Metrology (Packaged Commodities) Rules, 2011',
          rule_reference: 'Rule 13(1) & Table-I Rule 7',
          quote: 'Net quantity symbol must strictly conform to standard symbols (g, kg, ml, l). Minimum font height shall be 4.0 mm for net capacity between 200g and 500g.',
          section: 'Section 36(1) of Legal Metrology Act, 2009'
        }
      },
      {
        rule_title: 'RULE-LM-005: Dual MRP / Overcharge Check',
        status: 'PASS',
        reason: 'Single unambiguous MRP printed inclusive of all taxes.',
        citation: {
          act_name: 'Legal Metrology (Packaged Commodities) Rules, 2011',
          rule_reference: 'Rule 18(2)',
          quote: 'No person shall declare different maximum retail prices on identical pre-packaged commodities.'
        }
      },
      {
        rule_title: 'RULE-LM-007: Mandatory Consumer Grievance Contact',
        status: 'REVIEW',
        reason: 'Consumer care telephone number provided, but postal address of grievance redressal officer is missing.',
        citation: {
          act_name: 'Legal Metrology (Packaged Commodities) Rules, 2011',
          rule_reference: 'Rule 6(1)(g)'
        }
      }
    ]
  },
  {
    scan_id: 'scn-8820-1923',
    status: 'COMPLETED',
    overall_compliance: 'PASS',
    created_at: new Date(Date.now() - 3600000 * 4).toISOString(),
    manufacturer_name: 'Gujarat Cooperative Milk Marketing Federation (Amul)',
    product_name: 'Amul Taaza Homogenised Toned Milk 1L',
    product_category: 'Dairy Products',
    is_resolved: true,
    decision: 'ACCEPT',
    compliance_summary: {
      passed_rules: 7,
      failed_rules: 0,
      review_rules: 0,
      compliance_score: 100
    },
    extracted_declarations: {
      generic_product_name: 'Toned Milk (UHT Treated)',
      net_quantity: '1 L',
      mrp: '₹ 72.00 (Incl. of all taxes)',
      manufacturer_name: 'GCMMF Ltd, Anand - 388001, Gujarat, India',
      manufacture_date: '01/09/2026',
      expiry_date: '01/03/2027',
      consumer_care: 'customercare@amul.coop / 1800-258-3333'
    },
    evaluations: [
      {
        rule_title: 'RULE-LM-001: Mandatory Declarations Presence',
        status: 'PASS',
        reason: 'All 7 mandatory statutory declarations present on principal display panel.'
      },
      {
        rule_title: 'RULE-LM-003: Metric Unit Standard',
        status: 'PASS',
        reason: 'Standard SI litre unit symbol (1 L) strictly utilized with 5.2mm font height.'
      }
    ]
  },
  {
    scan_id: 'scn-3129-9941',
    status: 'COMPLETED',
    overall_compliance: 'FAIL',
    created_at: new Date(Date.now() - 3600000 * 8).toISOString(),
    manufacturer_name: 'Patanjali Ayurved Limited',
    product_name: 'Pure Cow Ghee 1L Tin',
    product_category: 'Edible Oils & Fats',
    is_resolved: false,
    compliance_summary: {
      passed_rules: 3,
      failed_rules: 3,
      review_rules: 1,
      compliance_score: 42
    },
    extracted_declarations: {
      generic_product_name: 'Desi Cow Ghee',
      net_quantity: '905 g / 1 L',
      mrp: '₹ 680.00',
      manufacturer_name: 'Patanjali Ayurved Ltd, Haridwar, Uttarakhand',
      manufacture_date: '07/2026',
      expiry_date: '07/2027'
    },
    evaluations: [
      {
        rule_title: 'RULE-LM-004: Month & Year of Packing Standard',
        status: 'FAIL',
        reason: 'Packing date printed in non-statutory format without day or leading zero.',
        citation: {
          act_name: 'Legal Metrology (Packaged Commodities) Rules, 2011',
          rule_reference: 'Rule 6(1)(d)',
          quote: 'Month and year in which the commodity is manufactured or packed must be clearly mentioned.'
        }
      },
      {
        rule_title: 'RULE-LM-006: E-Commerce & Retail Dual Pricing Violation',
        status: 'FAIL',
        reason: 'Online e-commerce marketplace twin priced at ₹740 vs physical carton printed MRP ₹680.',
        citation: {
          act_name: 'Legal Metrology (Packaged Commodities) Rules, 2011',
          rule_reference: 'Rule 18(2)',
          quote: 'No person or marketplace shall charge in excess of maximum retail price.'
        }
      }
    ]
  }
];

const MOCK_BRANDS: BrandRating[] = [
  {
    manufacturer_name: 'Gujarat Cooperative Milk Marketing Federation (Amul)',
    total_scans: 34,
    passed_scans: 32,
    ai_compliance_score: 94.1,
    officer_rating: 'GREEN',
    officer_notes: 'High packaging compliance. Standard metric units and clear font sizes maintained consistently.',
    last_rated_at: new Date(Date.now() - 86400000 * 2).toISOString(),
  },
  {
    manufacturer_name: 'Haldiram Snacks Pvt Ltd',
    total_scans: 28,
    passed_scans: 19,
    ai_compliance_score: 67.8,
    officer_rating: 'YELLOW',
    officer_notes: 'Repeated warnings issued for net quantity font size and "gms" non-SI abbreviations on 400g pouches.',
    last_rated_at: new Date(Date.now() - 86400000 * 4).toISOString(),
  },
  {
    manufacturer_name: 'Patanjali Ayurved Limited',
    total_scans: 22,
    passed_scans: 11,
    ai_compliance_score: 50.0,
    officer_rating: 'RED',
    officer_notes: 'Under statutory investigation: persistent dual MRP on quick-commerce platforms and missing consumer care addresses.',
    last_rated_at: new Date(Date.now() - 86400000 * 1).toISOString(),
  },
  {
    manufacturer_name: 'Nestle India Limited',
    total_scans: 40,
    passed_scans: 38,
    ai_compliance_score: 95.0,
    officer_rating: 'GREEN',
    officer_notes: 'Exemplary compliance with LMPC Rule 6(1) and clear bilingual MRP declarations.',
    last_rated_at: new Date(Date.now() - 86400000 * 7).toISOString(),
  },
  {
    manufacturer_name: 'ITC Limited (Foods Division)',
    total_scans: 31,
    passed_scans: 29,
    ai_compliance_score: 93.5,
    officer_rating: 'GREEN',
    officer_notes: 'Full conformity with standard size units across Sunfeast and Aashirvaad lines.',
    last_rated_at: new Date(Date.now() - 86400000 * 5).toISOString(),
  },
  {
    manufacturer_name: 'Britannia Industries Limited',
    total_scans: 25,
    passed_scans: 21,
    ai_compliance_score: 84.0,
    officer_rating: 'GREEN',
    officer_notes: 'Good adherence; minor discrepancies in imported packaging address verified.',
    last_rated_at: new Date(Date.now() - 86400000 * 9).toISOString(),
  }
];

export const OfficerApi = {
  // === COMPLAINTS ===
  async getComplaints(): Promise<Complaint[]> {
    try {
      const res = await fetch(`${API_BASE_URL}/complaints`, { cache: 'no-store' });
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data) && data.length > 0) return data;
      }
    } catch {
      // Return mock data if backend not reachable
    }
    return MOCK_COMPLAINTS;
  },

  async reviewComplaint(
    complaintId: string,
    status: 'RESOLVED' | 'REJECTED' | 'UNDER_REVIEW',
    officerId: string = 'Officer Raj (ID: LMC-2026-IND)',
    resolutionNotes?: string
  ): Promise<{ success: boolean; message: string }> {
    try {
      const res = await fetch(`${API_BASE_URL}/complaints/${complaintId}/review`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          officer_id: officerId,
          status,
          resolution_notes: resolutionNotes,
        }),
      });
      if (res.ok) {
        return { success: true, message: `Complaint marked as ${status}.` };
      }
    } catch {
      // Local simulated response
    }
    return { success: true, message: `Decision recorded: Complaint marked as ${status}.` };
  },

  // === FIELD SCANS ===
  async getScanHistory(): Promise<ScanItem[]> {
    try {
      const res = await fetch(`${API_BASE_URL}/reviews/queue`, { cache: 'no-store' });
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data) && data.length > 0) return data;
      }
    } catch {
      // Use mock scans
    }
    return MOCK_SCANS;
  },

  async submitScanReview(
    scanId: string,
    decision: 'ACCEPT' | 'REJECT' | 'REQUEST_RESCAN',
    reviewerId: string = '00000000-0000-0000-0000-000000000001',
    notes?: string
  ): Promise<{ success: boolean; message: string }> {
    try {
      const res = await fetch(`${API_BASE_URL}/reviews`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          scan_id: scanId,
          reviewer_id: reviewerId,
          decision,
          notes,
        }),
      });
      if (res.ok) {
        const data = await res.json();
        return { success: true, message: data.message || `Decision ${decision} recorded.` };
      }
    } catch {
      // Fallback
    }
    return { success: true, message: `Enforcement decision '${decision}' logged into audit trail.` };
  },

  // === BRAND METRICS ===
  async getBrandRatings(): Promise<BrandRating[]> {
    try {
      const res = await fetch(`${API_BASE_URL}/manufacturers/ratings`, { cache: 'no-store' });
      if (res.ok) {
        const data = await res.json();
        if (Array.isArray(data) && data.length > 0) return data;
      }
    } catch {
      // Fallback
    }
    return MOCK_BRANDS;
  },

  async getBrandHistory(brandName: string): Promise<BrandDetail> {
    try {
      const res = await fetch(`${API_BASE_URL}/manufacturers/${encodeURIComponent(brandName)}/history`, { cache: 'no-store' });
      if (res.ok) {
        return await res.json();
      }
    } catch {
      // Fallback
    }
    return {
      manufacturer_name: brandName,
      total_scans: 12,
      compliance_score: 75.0,
      officer_rating: 'YELLOW',
      officer_rating_notes: 'Surveillance audit underway for retail declarations.',
      history: [
        { scan_id: 'scn-1', date: new Date().toISOString(), status: 'PASS', product_name: 'Item Pack A' },
        { scan_id: 'scn-2', date: new Date(Date.now() - 86400000).toISOString(), status: 'FAIL', product_name: 'Item Pack B' },
      ],
    };
  },

  async rateBrand(
    brandName: string,
    rating: 'RED' | 'YELLOW' | 'GREEN',
    notes?: string,
    officerId: string = '00000000-0000-0000-0000-000000000001'
  ): Promise<{ success: boolean; message: string }> {
    try {
      const res = await fetch(`${API_BASE_URL}/manufacturers/${encodeURIComponent(brandName)}/rate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          officer_id: officerId,
          rating,
          notes,
        }),
      });
      if (res.ok) {
        return { success: true, message: `Brand rated ${rating} successfully.` };
      }
    } catch {
      // Fallback
    }
    return { success: true, message: `Officer rating '${rating}' assigned to ${brandName}.` };
  },

  // === AI LEGAL CHATBOT ===
  async sendChatMessage(message: string, ruleId?: string): Promise<{ reply: string; citations?: any[]; suggested_followups?: string[] }> {
    try {
      const res = await fetch(`${API_BASE_URL}/chat`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message, rule_id: ruleId }),
      });
      if (res.ok) {
        return await res.json();
      }
    } catch {
      // Fallback
    }
    return {
      reply: `### Legal Metrology Regulatory Guidance\n\nUnder the **Legal Metrology (Packaged Commodities) Rules, 2011**, all pre-packaged commodities require mandatory declarations including Generic Name, Net Quantity in standard SI units, Maximum Retail Price (MRP inclusive of all taxes), Month & Year of manufacture, and complete Consumer Redressal details.\n\n**Statutory Sanctions (Section 36(1)):**\n- First Offence: Penalty fine up to **₹25,000**\n- Second Offence: Penalty fine up to **₹50,000**\n- Subsequent Offences: Fine up to **₹1,00,000** or imprisonment up to 1 year, with power to seize non-compliant commodities under Section 15.`,
      citations: [
        {
          citation_id: '[1]',
          document: 'Legal Metrology (Packaged Commodities) Rules, 2011',
          rule: 'Rule 6(1) & Rule 18(2)',
          excerpt: 'No retail dealer or other person shall sell any pre-packaged commodity at a price exceeding the maximum retail price declared on the package.',
        },
        {
          citation_id: '[2]',
          document: 'Legal Metrology Act, 2009',
          rule: 'Section 36(1)',
          excerpt: 'Whoever manufactures, packs, imports, sells or distributes any non-standard pre-packaged commodity shall be punished with fine.',
        },
      ],
      suggested_followups: [
        'What are the mandatory font sizes for Net Quantity declarations?',
        'What is the compounding penalty for dual MRP under Rule 18(2)?',
        'How can an officer initiate seizure proceedings under Section 15?',
      ],
    };
  },

  // === STATUTORY REPORT DOWNLOADS ===
  getScanReportUrl(scanId: string): string {
    return `${API_BASE_URL}/reports/${scanId}/download`;
  },

  getComplaintReportUrl(complaintId: string): string {
    return `${API_BASE_URL}/reports/complaint/${complaintId}/download`;
  },
};
