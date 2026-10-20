export interface Complaint {
  complaint_id: string;
  citizen_id: string;
  paid_price: number;
  printed_mrp: number;
  shopkeeper_name?: string;
  shop_address?: string;
  status: 'SUBMITTED' | 'UNDER_REVIEW' | 'RESOLVED' | 'REJECTED';
  description?: string;
  created_at: string;
  receipt_image_url?: string;
  product_image_url?: string;
  resolution_notes?: string;
}

export interface ScanEvaluation {
  rule_title: string;
  status: 'PASS' | 'FAIL' | 'REVIEW' | string;
  reason: string;
  citation?: {
    act_name?: string;
    rule_reference?: string;
    quote?: string;
    section?: string;
  };
}

export interface OcrBoundingBox {
  text: string;
  bbox: number[][]; // [[x1, y1], [x2, y2], [x3, y3], [x4, y4]]
  score?: number;
  detected_angle?: number;
  normalized?: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
}

export interface BrandClaim {
  claim: string;
  category?: string;
  context?: string;
  verification_note?: string;
  highlight?: boolean;
}

export interface DeclarationTableRow {
  attribute: string;
  value: string;
  category: 'Statutory Declaration' | 'Brand Claim' | 'Product Specification' | 'Contact & Care' | 'Classification' | string;
  is_brand_claim: boolean;
  highlight?: boolean;
}

export interface OcrTranscription {
  image_side?: string;
  side?: string;
  image_url?: string;
  detected_text?: string;
  text?: string;
  raw_text?: string;
  confidence?: number;
  boxes_count?: number;
  lines_detected?: number;
  bounding_boxes?: OcrBoundingBox[];
}

export interface ScanItem {
  scan_id: string;
  status: string;
  overall_compliance: 'PASS' | 'FAIL' | 'REVIEW' | string;
  image_urls?: Record<string, string>;
  all_detected_text?: string;
  ocr_transcriptions?: OcrTranscription[];
  created_at: string;
  manufacturer_name?: string;
  product_name?: string;
  is_resolved: boolean;
  decision?: string;
  extracted_declarations?: Record<string, any>;
  brand_claims?: BrandClaim[];
  summary_sentences?: string[] | string;
  declarations_table?: DeclarationTableRow[];
  front_panel_table?: any[];
  back_panel_table?: any[];
  left_panel_table?: any[];
  right_panel_table?: any[];
  product_category?: string;
  ingredients_list?: string;
  ingredient_analysis?: IngredientAnalysis;
  surrogate_analysis?: SurrogateAnalysis;
  compliance_summary?: {
    passed_rules: number;
    failed_rules: number;
    review_rules: number;
    compliance_score: number;
  };
  evaluations?: ScanEvaluation[];
}

export interface DarkPatternItem {
  type: string;
  severity: 'CRITICAL' | 'HIGH' | 'MEDIUM' | 'LOW' | string;
  title: string;
  detail: string;
  legal_citation?: {
    act?: string;
    section?: string;
    heading?: string;
    text?: string;
  };
}

export interface LegalViolationItem {
  act: string;
  section: string;
  penalty_clause?: string;
  max_penalty?: string;
}

export interface SurrogateAnalysis {
  is_surrogate: boolean;
  surrogate_risk_score: number;
  risk_level: 'CRITICAL' | 'HIGH' | 'MEDIUM' | 'CLEAN' | string;
  parent_restricted_industry?: string;
  matched_restricted_brand?: string | null;
  camouflaged_sku_type?: string | null;
  surrogate_explanation: string;
  dark_patterns?: DarkPatternItem[];
  dark_patterns_count: number;
  legal_violations?: LegalViolationItem[];
  officer_action_recommendation: string;
  consumer_plain_verdict: string;
}

export interface AnalyzedIngredient {
  raw_text: string;
  canonical_name: string;
  ins_code?: string | null;
  category: string;
  what_is_it: string;
  why_used: string;
  origin: string;
  adequate_usage?: string;
  recommended_usage?: string;
  addictiveness_level?: 'HIGH' | 'MODERATE' | 'LOW' | 'NONE' | string;
  addictiveness_details?: string;
  allergy_and_health_risk: string;
  is_banned: boolean;
  banned_details?: Record<string, any>;
  allergens_detected?: string[];
  allergen_details?: any[];
  dietary_flags?: string[];
}

export interface IngredientAnalysis {
  total_ingredients_count: number;
  overall_safety_rating: string;
  safety_score: number;
  is_compliant: boolean;
  banned_ingredients_count: number;
  banned_ingredients_detected: AnalyzedIngredient[];
  statutory_allergens_count: number;
  statutory_allergens_detected: any[];
  all_ingredients: AnalyzedIngredient[];
  executive_summary: string;
}

export interface BrandRating {
  manufacturer_name: string;
  total_scans: number;
  passed_scans: number;
  ai_compliance_score: number;
  officer_rating?: 'RED' | 'YELLOW' | 'GREEN' | null;
  officer_notes?: string | null;
  last_rated_at?: string | null;
}

export interface BrandHistoryRecord {
  scan_id: string;
  date: string;
  status: string;
  product_name?: string;
}

export interface BrandDetail {
  manufacturer_name: string;
  total_scans: number;
  compliance_score: number;
  officer_rating?: string | null;
  officer_rating_notes?: string | null;
  history: BrandHistoryRecord[];
}

export interface Citation {
  citation_id: string;
  document: string;
  rule: string;
  excerpt: string;
}

export interface ChatMessage {
  id: string;
  sender: 'user' | 'assistant';
  text: string;
  citations?: Citation[];
  suggested_followups?: string[];
  timestamp: string;
}
