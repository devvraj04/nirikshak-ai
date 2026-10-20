#!/usr/bin/env python3
"""
NIRIKSHAK AI — Standalone Ingredient Analysis & Verification Engine CLI
Run directly to inspect any product's ingredients:
    python ingredient_analyzer.py "Refined Wheat Flour, Sugar, Palm Oil, INS 500(ii), INS 322 (Soy), INS 102, INS 211"
    python ingredient_analyzer.py --test
"""

import sys
import os
import json
import argparse
# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

# Ensure backend root is on Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.services.ingredients.ingredient_engine import ingredient_engine

SAMPLE_PRODUCTS = {
    "1. Popular Cream Biscuit (Standard Packaged Food)": (
        "Refined Wheat Flour (Maida) (42%), Sugar, Edible Vegetable Oil (Palm Oil), "
        "Milk Solids (6%), Invert Sugar Syrup, Raising Agents [INS 500(ii), INS 503(ii)], "
        "Emulsifiers [INS 322 (from Soy), INS 471], Iodized Salt, Acidity Regulator (INS 330), "
        "Synthetic Food Color (INS 102 - Tartrazine), Added Artificial Vanilla Flavors"
    ),
    "2. Street Snack Adulteration (Banned Substances)": (
        "Refined Wheat Flour, Water, Yeast, Potassium Bromate, Sugar, Palm Oil, "
        "Artificial Color (Rhodamine B), Metanil Yellow, Preservative (INS 211)"
    ),
    "3. Carbonated Beverage (Preservatives & Dyes)": (
        "Carbonated Water, Sugar, Acidity Regulators (INS 330, INS 331), "
        "Preservative (INS 211 - Sodium Benzoate), Antioxidant (INS 300 - Ascorbic Acid), "
        "Synthetic Colors (INS 110, INS 122), Natural Flavoring Substances"
    ),
    "4. Diet Sugar-Free Confectionery (Aspartame Alert)": (
        "Maltitol, Gum Base, Humectant (INS 422), Artificial Sweeteners [INS 951 (Aspartame), "
        "INS 950 (Acesulfame K)], Emulsifier (INS 322), Glazing Agent (INS 903), Flavorings"
    )
}

def print_banner():
    print("=" * 80)
    print(" 🔬 NIRIKSHAK AI — 100% LLM DYNAMIC INGREDIENT & CHEMICAL SAFETY ENGINE")
    print(" Real-Time Neural Reasoning: FSSAI (India), US FDA, EU EFSA, WHO Codex")
    print(" (Zero Hardcoding — Dynamic AI Chemical & Toxicology Research)")
    print("=" * 80)

def display_analysis_results(result: dict):
    print("\n" + "-" * 80)
    print(f"📊 SUMMARY REPORT")
    print("-" * 80)
    print(f"• Total Ingredients Detected  : {result['total_ingredients_count']}")
    print(f"• Safety Score                : {result['safety_score']} / 100")
    print(f"• Overall Safety Rating       : {result['overall_safety_rating']}")
    print(f"• Executive Summary           : {result['executive_summary']}")

    # 1. BANNED SUBSTANCES SECTION
    banned = result.get("banned_ingredients_detected", [])
    if banned:
        print("\n" + "!" * 80)
        print(f"🚨 CRITICAL ALERT: {len(banned)} BANNED / ILLEGAL INGREDIENT(S) DETECTED!")
        print("!" * 80)
        for idx, item in enumerate(banned, 1):
            ban = item.get("banned_details", {})
            print(f"\n  [{idx}] ⛔ {item['canonical_name'].upper()}")
            print(f"      • Category       : {ban.get('category', 'Hazardous Substance')}")
            print(f"      • Status         : {ban.get('status', 'BANNED')} (Severity: {ban.get('severity', 'CRITICAL')})")
            print(f"      • Banned In      : {', '.join(ban.get('banned_jurisdictions', ['Global']))}")
            print(f"      • Health Hazard  : {ban.get('hazard_summary')}")
            print(f"      • Legal Rule     : {ban.get('fssai_rule')}")
    else:
        print("\n✅ BANNED SUBSTANCES CHECK: PASSED — No prohibited substances found.")

    # 2. STATUTORY ALLERGENS SECTION
    allergens = result.get("statutory_allergens_detected", [])
    if allergens:
        print("\n" + "=" * 80)
        print(f"⚠️  ALLERGEN & CHEMICAL SENSITIVITY ALERTS ({len(allergens)} DETECTED)")
        print("=" * 80)
        for idx, al in enumerate(allergens, 1):
            sev_icon = "🔴" if al['severity'] == "CRITICAL" else ("🟠" if al['severity'] == "HIGH" else "🟡")
            print(f"\n  [{idx}] {sev_icon} ALLERGEN: {al['display_name']} [Severity: {al['severity']}]")
            print(f"      • Sensitive People : {al['sensitive_population']}")
            print(f"      • Symptoms/Reaction: {al['symptoms']}")
            print(f"      • Matched In Words : {', '.join(al['matched_terms'])}")
            print(f"      • Statutory Label  : {al['statutory_advice']}")
    else:
        print("\n✅ ALLERGENS: None of the standard major statutory allergens were detected.")

    # 3. DETAILED INGREDIENT BY INGREDIENT BREAKDOWN
    print("\n" + "=" * 80)
    print("🔍 IN-DEPTH INGREDIENT BREAKDOWN & CHEMICAL MEANINGS")
    print("=" * 80)
    for idx, ingr in enumerate(result.get("all_ingredients", []), 1):
        ins_tag = f" [{ingr['ins_code']}]" if ingr.get("ins_code") else ""
        banned_tag = " ⛔ [BANNED]" if ingr.get("is_banned") else ""
        print(f"\n👉 #{idx}. {ingr['canonical_name'].upper()}{ins_tag}{banned_tag}")
        print(f"   • Functional Class : {ingr['category']}")
        print(f"   • Actual Meaning   : {ingr['what_is_it']}")
        print(f"   • Why It's Added   : {ingr['why_used']}")
        print(f"   • Source / Origin  : {ingr.get('origin', 'Standard')}")
        print(f"   • Adequate Usage   : {ingr.get('adequate_usage', 'Quantum satis')}")
        print(f"   • Recomm. Usage    : {ingr.get('recommended_usage', 'Moderate intake')}")
        addict_lvl = ingr.get('addictiveness_level', 'NONE')
        addict_desc = ingr.get('addictiveness_details', '')
        print(f"   • Addictiveness    : [{addict_lvl}] {addict_desc}")
        print(f"   • Allergy/Risks    : {ingr.get('allergy_and_health_risk', 'No known severe allergic reactions.')}")
        if ingr.get("dietary_flags"):
            print(f"   • Dietary Tags     : {', '.join(ingr['dietary_flags'])}")

        # Print nested additives if present
        subs = ingr.get("nested_sub_ingredients", [])
        if subs:
            print("     ↳ Contains nested components:")
            for sub in subs:
                sub_ban = " [BANNED!]" if sub.get("is_banned") else ""
                print(f"       - {sub['canonical_name']} ({sub['category']}){sub_ban}: {sub['what_is_it']}")

    print("\n" + "=" * 80)
    print("🏁 END OF REPORT")
    print("=" * 80 + "\n")

def run_tests():
    print_banner()
    print("Running Verification Engine against Test Products...\n")
    for title, text in SAMPLE_PRODUCTS.items():
        print("\n" + "#" * 80)
        print(f"TEST PRODUCT: {title}")
        print(f"Raw Ingredients Text: \"{text}\"")
        print("#" * 80)
        analysis = ingredient_engine.analyze_full_product(text)
        display_analysis_results(analysis)

def main():
    parser = argparse.ArgumentParser(description="Nirikshak AI Ingredient Analysis Engine")
    parser.add_argument("ingredients", nargs="?", help="Raw ingredients text string to analyze")
    parser.add_argument("--test", action="store_true", help="Run predefined product test cases")
    parser.add_argument("--json", action="store_true", help="Output raw JSON results")

    args = parser.parse_args()

    if args.test or not args.ingredients:
        run_tests()
        return

    analysis = ingredient_engine.analyze_full_product(args.ingredients)

    if args.json:
        print(json.dumps(analysis, indent=2))
    else:
        print_banner()
        print(f"Raw Input: \"{args.ingredients}\"")
        display_analysis_results(analysis)

if __name__ == "__main__":
    main()
