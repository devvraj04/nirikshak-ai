import sys
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

backend_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(backend_dir))

from app.services.surrogate.surrogate_engine import surrogate_engine

test_products = [
    {
        "name": "Case 1: Vimal Elaichi (Famous Surrogate Pan Masala Case)",
        "brand": "Vimal",
        "product_name": "Silver Coated Elaichi",
        "ingredients": "Cardamom seeds, Silver Leaf, Permitted Flavours, Added Kesar Flavour",
        "claims": [{"claim": "Bolo Zubaan Kesari", "category": "Tagline"}, {"claim": "Shahi Kesar Flavour", "category": "Purity"}],
        "text": "Vimal Silver Coated Elaichi Bolo Zubaan Kesari Net Wt 10g Manufactured by Manikchand Group"
    },
    {
        "name": "Case 2: Kingfisher Club Soda (Alcohol Surrogate Brand Extension)",
        "brand": "Kingfisher",
        "product_name": "Premium Club Soda",
        "ingredients": "Carbonated water, Salts of sodium and magnesium",
        "claims": [{"claim": "The King of Good Times", "category": "Tagline"}],
        "text": "Kingfisher Premium Club Soda 750ml United Breweries Limited"
    },
    {
        "name": "Case 3: Deceptive '100% Real Fruit Juice' with Added Sugars",
        "brand": "Tropic Delight",
        "product_name": "100% Real Mixed Fruit Juice",
        "ingredients": "Water, Reconstituted Fruit Concentrate (12%), Sugar, Acidity Regulator (INS 330), Preservative (INS 211), Synthetic Food Colour (INS 110)",
        "claims": [{"claim": "100% Real Fruit Juice", "category": "Nutrition"}],
        "text": "Tropic Delight 100% Real Mixed Fruit Juice No Added Nasties"
    },
    {
        "name": "Case 4: Clean Compliant Product (Amul Taaza Milk)",
        "brand": "Amul",
        "product_name": "Amul Taaza Homogenised Toned Milk",
        "ingredients": "Toned Milk, Vitamin A, Vitamin D",
        "claims": [{"claim": "Pasteurised Toned Milk", "category": "Process"}],
        "text": "Amul Taaza Homogenised Toned Milk FSSAI Lic No 10012021000071 Net Qty 1L MRP Rs 54"
    }
]

print("=" * 80)
print("TESTING NIRIKSHAK AI SURROGATE ADVERTISING & DARK PATTERN ENGINE")
print("=" * 80)

for case in test_products:
    print(f"\n>>> Running: {case['name']}")
    res = surrogate_engine.analyze_product(
        brand_name=case["brand"],
        product_name=case["product_name"],
        ingredients_list=case["ingredients"],
        brand_claims=case["claims"],
        detected_text=case["text"]
    )
    
    print(f"  Surrogate Flagged:    {res['is_surrogate']}")
    print(f"  Surrogate Risk Score: {res['surrogate_risk_score']}% ({res['risk_level']})")
    print(f"  Parent Category:      {res['parent_restricted_industry']}")
    print(f"  Matched Brand:        {res['matched_restricted_brand']}")
    print(f"  Dark Patterns Found:  {res['dark_patterns_count']}")
    for i, dp in enumerate(res['dark_patterns'], 1):
        print(f"    - [{dp.get('severity', 'MED')}] {dp.get('title')}: {dp.get('detail')[:90]}...")
    print(f"  Legal Citations:      {len(res['legal_violations'])}")
    for lv in res['legal_violations']:
        print(f"    * {lv.get('act')} -> {lv.get('section')}")
    print(f"  Officer Action:       {res['officer_action_recommendation'][:100]}...")
    print(f"  Consumer Warning:     {res['consumer_plain_verdict'][:100]}...")
    print("-" * 80)
