"""
NIRIKSHAK AI — Allergen & Chemical Sensitivity Rules Engine
Detects major statutory food allergens, cross-reactivities, chemical intolerances, and sensitive consumer warnings.
"""

import re
from typing import Dict, List, Any, Optional

ALLERGEN_CATEGORIES: Dict[str, Dict[str, Any]] = {
    "MILK_DAIRY": {
        "display_name": "Milk & Dairy (Lactose / Casein / Whey)",
        "statutory_category": "Major Allergen (FSSAI / FDA / EU)",
        "severity": "CRITICAL",
        "patterns": [
            r"\b(milk|dairy|casein|caseinate|whey|lactose|butter|ghee|cream|cheese|curd|paneer|yogurt|yoghurt|skimmed\s*milk|milk\s*solids|milk\s*fat|buttermilk)\b",
            r"\bins\s*322\(?i\)?\b.*milk",
        ],
        "sensitive_population": "Individuals with Cow's Milk Allergy (CMA) or Lactose Intolerance.",
        "symptoms": "Immediate hives, facial angioedema, wheezing, vomiting, anaphylactic shock; abdominal cramps, bloating, diarrhea.",
        "statutory_advice": "Mandatory 'CONTAINS MILK' declaration required on label under FSSAI Regulations 2020."
    },
    "WHEAT_GLUTEN": {
        "display_name": "Wheat & Gluten",
        "statutory_category": "Major Allergen (FSSAI / FDA / EU)",
        "severity": "HIGH",
        "patterns": [
            r"\b(wheat|gluten|maida|semolina|sooji|suji|atta|barley|rye|malt|spelt|durum|farina|kamut|triticale|refined\s*wheat\s*flour|whole\s*wheat)\b",
            r"\bwheat\s*starch\b",
        ],
        "sensitive_population": "Patients with Celiac Disease, Non-Celiac Gluten Sensitivity, or IgE Wheat Allergy.",
        "symptoms": "Autoimmune atrophy of intestinal villi, chronic malabsorption, severe skin rash (dermatitis herpetiformis), acute breathing difficulty.",
        "statutory_advice": "Mandatory 'CONTAINS WHEAT / GLUTEN' warning."
    },
    "SOY": {
        "display_name": "Soy / Soybean",
        "statutory_category": "Major Allergen (FSSAI / FDA / EU)",
        "severity": "CRITICAL",
        "patterns": [
            r"\b(soy|soya|soybean|edamame|tofu|soy\s*lecithin|soya\s*lecithin|soy\s*protein|soya\s*protein|textured\s*vegetable\s*protein|tvp)\b",
            r"\bins\s*322\b",  # Commonly soy lecithin unless specified
        ],
        "sensitive_population": "Infants and adults with IgE-mediated Soy allergy.",
        "symptoms": "Anaphylaxis, lip swelling, atopic eczema, vomiting, abdominal colic, drop in blood pressure.",
        "statutory_advice": "Mandatory 'CONTAINS SOY' warning."
    },
    "PEANUTS": {
        "display_name": "Peanuts / Groundnuts",
        "statutory_category": "Major Allergen (FSSAI / FDA / EU)",
        "severity": "CRITICAL",
        "patterns": [
            r"\b(peanut|peanuts|groundnut|groundnuts|arachis|monkey\s*nuts?)\b",
            r"\bpeanut\s*butter\b",
            r"\barachis\s*oil\b",
        ],
        "sensitive_population": "Individuals with Peanut Anaphylaxis Hypersensitivity.",
        "symptoms": "Extreme anaphylaxis, laryngeal edema, asphyxiation, cardiovascular collapse; reaction can be triggered by microscopic traces (parts per million).",
        "statutory_advice": "Mandatory 'CONTAINS PEANUT' warning. Emergency epinephrine (EpiPen) carrier alert."
    },
    "TREE_NUTS": {
        "display_name": "Tree Nuts",
        "statutory_category": "Major Allergen (FSSAI / FDA / EU)",
        "severity": "CRITICAL",
        "patterns": [
            r"\b(almond|almonds|cashew|cashews|kaju|walnut|walnuts|akhrot|pistachio|pistachios|pista|hazelnut|hazelnuts|pecan|pecans|macadamia|brazil\s*nut|pine\s*nut|chestnut)\b",
            r"\bprunus\s*amygdalus\b",
        ],
        "sensitive_population": "Individuals allergic to tree nut storage proteins (e.g. vicilins, legumins).",
        "symptoms": "Acute anaphylaxis, throat swelling, hives, gastrointestinal cramping.",
        "statutory_advice": "Mandatory 'CONTAINS TREE NUTS (specify nut)' declaration."
    },
    "EGGS": {
        "display_name": "Eggs & Egg Derivatives",
        "statutory_category": "Major Allergen (FSSAI / FDA / EU)",
        "severity": "CRITICAL",
        "patterns": [
            r"\b(egg|eggs|egg\s*powder|egg\s*white|egg\s*yolk|albumin|ovalbumin|ovomucin|lysozyme|globulin|meringue|mayonnaise)\b",
            r"\bins\s*1105\b",  # Lysozyme from egg
        ],
        "sensitive_population": "Children and adults allergic to egg proteins (ovalbumin/ovomucoid).",
        "symptoms": "Skin flushing, hives, severe atopic eczema, nausea, wheezing, anaphylaxis.",
        "statutory_advice": "Mandatory Non-Veg Brown Dot indicator & 'CONTAINS EGG' warning."
    },
    "FISH_SHELLFISH": {
        "display_name": "Fish & Shellfish (Crustaceans / Molluscs)",
        "statutory_category": "Major Allergen (FSSAI / FDA / EU)",
        "severity": "CRITICAL",
        "patterns": [
            r"\b(fish|prawn|prawns|shrimp|shrimps|crab|crabs|lobster|lobsters|oyster|oysters|squid|squids|clam|clams|scallop|scallops|mollusc|crustacean|anchovy|sardine|tuna|salmon|gelatin\s*from\s*fish)\b",
            r"\bins\s*627\b.*fish",
            r"\bins\s*631\b.*fish",
        ],
        "sensitive_population": "Patients with Parvalbumin or Tropomyosin allergy.",
        "symptoms": "Immediate severe systemic anaphylaxis, facial swelling, asthma, fainting.",
        "statutory_advice": "Non-Veg symbol mandatory; 'CONTAINS FISH/CRUSTACEANS' declaration."
    },
    "SULFITES": {
        "display_name": "Sulfites (> 10 ppm)",
        "statutory_category": "Major Allergen / Respiratory Sensitizer",
        "severity": "HIGH",
        "patterns": [
            r"\b(sulfite|sulphite|sulfites|sulphites|sulfur\s*dioxide|sulphur\s*dioxide|sodium\s*metabisulfite|potassium\s*metabisulfite|bisulfite|bisulphite)\b",
            r"\bins\s*22[0-8]\b",
            r"\be22[0-8]\b",
            r"\bins\s*150d\b",
        ],
        "sensitive_population": "People with steroid-dependent or intrinsic Asthma and Sulfite Oxidase deficiency.",
        "symptoms": "Sudden severe bronchospasm, cyanosis, coughing, abdominal cramps, loss of consciousness.",
        "statutory_advice": "Statutory warning mandatory if sulfite concentration exceeds 10 mg/kg."
    },
    "SESAME": {
        "display_name": "Sesame Seeds & Sesame Oil",
        "statutory_category": "Major Allergen (FDA FASTER Act 2023 / EU)",
        "severity": "CRITICAL",
        "patterns": [
            r"\b(sesame|til|gingelly|tahini|sesamum|benne)\b",
            r"\bsesame\s*oil\b",
        ],
        "sensitive_population": "Individuals sensitized to Ses i 1 to Ses i 7 proteins.",
        "symptoms": "Rapid-onset systemic anaphylaxis, respiratory distress, generalized urticaria.",
        "statutory_advice": "Now classified as the 9th Major Allergen by US FDA; mandatory declaration."
    },
    "MUSTARD": {
        "display_name": "Mustard & Mustard Oil",
        "statutory_category": "Statutory Allergen (EU / Canada / FSSAI)",
        "severity": "HIGH",
        "patterns": [
            r"\b(mustard|sarson|rai|mustard\s*oil|mustard\s*paste|mustard\s*flour|sinapis)\b",
        ],
        "sensitive_population": "Individuals allergic to Bra j 1 storage protein in mustard.",
        "symptoms": "Oral allergy syndrome, swelling of throat and lips, asthma, anaphylaxis.",
        "statutory_advice": "Mandatory allergen declaration."
    },
    "MSG_GLUTAMATE": {
        "display_name": "MSG / Free Glutamate",
        "statutory_category": "Chemical Sensitivity / Neuro-vascular Intolerance",
        "severity": "MODERATE",
        "patterns": [
            r"\b(msg|monosodium\s*glutamate|glutamic\s*acid|yeast\s*extract|autolyzed\s*yeast|hydrolyzed\s*vegetable\s*protein|hvp)\b",
            r"\bins\s*621\b",
            r"\bins\s*627\b",
            r"\bins\s*631\b",
            r"\bins\s*635\b",
        ],
        "sensitive_population": "Glutamate-sensitive individuals, migraine sufferers, asthmatics.",
        "symptoms": "Chinese Restaurant Syndrome: facial pressure, neck burning, pounding migraine, palpitations, sweating.",
        "statutory_advice": "FSSAI requires declaration: 'NOT RECOMMENDED FOR INFANTS BELOW 12 MONTHS'."
    },
    "AZO_DYES": {
        "display_name": "Synthetic Azo Dyes (Tartrazine / Sunset Yellow / Carmoisine)",
        "statutory_category": "Chemical Sensitivity & Pediatric Hyperactivity",
        "severity": "MODERATE-HIGH",
        "patterns": [
            r"\b(tartrazine|sunset\s*yellow|carmoisine|azorubine|ponceau|allura\s*red|brilliant\s*blue)\b",
            r"\bins\s*(102|110|122|124|129|133)\b",
        ],
        "sensitive_population": "Aspirin-sensitive individuals, asthmatics, children with ADHD.",
        "symptoms": "Urticaria, angioedema, bronchoconstriction, attention deficit and behavioral agitation in children.",
        "statutory_advice": "European Union mandatory label: 'May have an adverse effect on activity and attention in children'."
    },
    "ASPARTAME_PHENYLALANINE": {
        "display_name": "Aspartame (Phenylalanine source)",
        "statutory_category": "Metabolic Disorder / Genetic Risk",
        "severity": "CRITICAL",
        "patterns": [
            r"\b(aspartame|phenylalanine)\b",
            r"\bins\s*951\b",
        ],
        "sensitive_population": "Patients with Phenylketonuria (PKU).",
        "symptoms": "Severe irreversible brain damage, neurotoxicity, cognitive impairment, seizures in PKU patients.",
        "statutory_advice": "Mandatory bold warning: 'PHENYLKETONURICS: CONTAINS PHENYLALANINE'."
    },
}

def analyze_allergens_in_text(text: str) -> List[Dict[str, Any]]:
    """
    Scans any ingredient or composition text and flags all detected allergens
    along with severity, sensitive populations, symptoms, and regulatory warnings.
    """
    if not text:
        return []

    clean_text = text.lower()
    detected: List[Dict[str, Any]] = []

    for code, info in ALLERGEN_CATEGORIES.items():
        matched_patterns = []
        for pat in info["patterns"]:
            match = re.search(pat, clean_text, re.IGNORECASE)
            if match:
                matched_patterns.append(match.group(0))

        if matched_patterns:
            detected.append({
                "code": code,
                "display_name": info["display_name"],
                "statutory_category": info["statutory_category"],
                "severity": info["severity"],
                "matched_terms": list(set(matched_patterns)),
                "sensitive_population": info["sensitive_population"],
                "symptoms": info["symptoms"],
                "statutory_advice": info["statutory_advice"]
            })

    # Sort so CRITICAL allergens appear first
    severity_order = {"CRITICAL": 0, "HIGH": 1, "MODERATE-HIGH": 2, "MODERATE": 3, "LOW": 4}
    detected.sort(key=lambda x: severity_order.get(x["severity"], 99))
    return detected
