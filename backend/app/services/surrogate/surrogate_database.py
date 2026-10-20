"""
NIRIKSHAK AI — Surrogate Advertising & Restricted Brands Knowledge Base.

Contains statutory registries, restricted parent brand lists, camouflage classifications,
and legal citation frameworks across:
  - CCPA Guidelines for Prevention of Misleading Advertisements, 2022 (Sec 8)
  - FSSAI Advertising and Claims Regulations, 2018 (Sec 4 & 5)
  - Food Safety and Standards Act, 2006 (Sec 24, 52, 53)
  - COTPA, 2003 (Sec 5)
  - Cable Television Networks (Regulation) Rules (Rule 7)
"""

from typing import Dict, Any, List

# =============================================================================
# 1. RESTRICTED PARENT BRANDS & UMBRELLA TRADEMARKS (INDIAN REGISTRY)
# =============================================================================
RESTRICTED_PARENT_BRANDS: Dict[str, Dict[str, Any]] = {
    # ---- A. TOBACCO, PAN MASALA & GUTKHA UMBRELLA BRANDS ----
    "vimal": {
        "canonical_brand": "Vimal",
        "parent_category": "TOBACCO_PAN_MASALA",
        "prohibited_product": "Vimal Gutkha / Pan Masala",
        "common_camouflages": ["elaichi", "silver coated elaichi", "kesar elaichi", "mouth freshener", "cardamom seeds"],
        "governing_laws": [
            "CCPA Guidelines 2022 Section 8(1) - Surrogate Advertising Prohibition",
            "COTPA 2003 Section 5 - Ban on Tobacco Promotion",
            "FSSAI (Prohibition and Restrictions on Sales) Regulations 2011 Reg 2.3.4"
        ],
        "penalty_section": "Food Safety and Standards Act 2006 Section 53 (Misleading Advertisement) & CCPA 2019 Section 21"
    },
    "kamla pasand": {
        "canonical_brand": "Kamla Pasand",
        "parent_category": "TOBACCO_PAN_MASALA",
        "prohibited_product": "Kamla Pasand Pan Masala / Zarda",
        "common_camouflages": ["silver coated elaichi", "elaichi", "mouth freshener", "perfume", "pan flavour"],
        "governing_laws": [
            "CCPA Guidelines 2022 Section 8",
            "COTPA 2003 Section 5",
            "FSSAI Advertising & Claims Regulations 2018 Section 4"
        ],
        "penalty_section": "FSS Act 2006 Section 53 & CCPA Section 21"
    },
    "rajnigandha": {
        "canonical_brand": "Rajnigandha",
        "parent_category": "TOBACCO_PAN_MASALA",
        "prohibited_product": "Rajnigandha Flavoured Pan Masala",
        "common_camouflages": ["silver pearls", "silver coated elaichi", "mouth freshener", "pearls", "perfumery"],
        "governing_laws": [
            "CCPA Guidelines 2022 Section 8",
            "COTPA 2003 Section 5",
            "FSSAI Advertising & Claims Regulations 2018 Section 4"
        ],
        "penalty_section": "FSS Act 2006 Section 53 & CCPA Section 21"
    },
    "pan bahar": {
        "canonical_brand": "Pan Bahar",
        "parent_category": "TOBACCO_PAN_MASALA",
        "prohibited_product": "Pan Bahar Pan Masala",
        "common_camouflages": ["crystal elaichi", "mouth freshener", "heritage elaichi"],
        "governing_laws": [
            "CCPA Guidelines 2022 Section 8",
            "COTPA 2003 Section 5"
        ],
        "penalty_section": "FSS Act 2006 Section 53 & CCPA Section 21"
    },
    "dilbagh": {
        "canonical_brand": "Dilbagh",
        "parent_category": "TOBACCO_PAN_MASALA",
        "prohibited_product": "Dilbagh Pan Masala / Gutkha",
        "common_camouflages": ["elaichi", "mouth freshener", "chewing confectionery"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "COTPA 2003 Section 5"],
        "penalty_section": "FSS Act 2006 Section 53 & CCPA Section 21"
    },
    "shikhar": {
        "canonical_brand": "Shikhar",
        "parent_category": "TOBACCO_PAN_MASALA",
        "prohibited_product": "Shikhar Gutkha / Pan Masala",
        "common_camouflages": ["elaichi", "scented supari", "mouth freshener"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "COTPA 2003 Section 5"],
        "penalty_section": "FSS Act 2006 Section 53 & CCPA Section 21"
    },
    "manikchand": {
        "canonical_brand": "Manikchand",
        "parent_category": "TOBACCO_PAN_MASALA",
        "prohibited_product": "Manikchand Gutkha",
        "common_camouflages": ["packaged drinking water", "elaichi", "tea"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "COTPA 2003 Section 5"],
        "penalty_section": "FSS Act 2006 Section 53 & CCPA Section 21"
    },
    "baba": {
        "canonical_brand": "Baba",
        "parent_category": "TOBACCO_PAN_MASALA",
        "prohibited_product": "Baba Zarda / Chewing Tobacco",
        "common_camouflages": ["silver coated supari", "elaichi", "perfumery", "betel nut mixture"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "COTPA 2003 Section 5"],
        "penalty_section": "FSS Act 2006 Section 53 & CCPA Section 21"
    },
    "rajshree": {
        "canonical_brand": "Rajshree",
        "parent_category": "TOBACCO_PAN_MASALA",
        "prohibited_product": "Rajshree Pan Masala",
        "common_camouflages": ["silver coated elaichi", "mouth freshener"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "COTPA 2003 Section 5"],
        "penalty_section": "FSS Act 2006 Section 53 & CCPA Section 21"
    },
    "chaini khaini": {
        "canonical_brand": "Chaini Khaini",
        "parent_category": "TOBACCO_PAN_MASALA",
        "prohibited_product": "Chaini Khaini Filter Chewing Tobacco",
        "common_camouflages": ["herbal pouches", "spiced mixture", "mouth freshener"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "COTPA 2003 Section 5"],
        "penalty_section": "FSS Act 2006 Section 53 & CCPA Section 21"
    },

    # ---- B. ALCOHOL & LIQUOR UMBRELLA BRANDS ----
    "kingfisher": {
        "canonical_brand": "Kingfisher",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "Kingfisher Beer / Strong Alcoholic Beverage",
        "common_camouflages": ["packaged drinking water", "club soda", "storm soda", "energy drink", "calendar"],
        "governing_laws": [
            "CCPA Guidelines 2022 Section 8",
            "Cable Television Networks Rules 1994 Rule 7(2)(viii)",
            "FSSAI Advertising & Claims Regulations 2018 Section 4"
        ],
        "penalty_section": "CCPA 2019 Section 21 & FSS Act 2006 Section 53"
    },
    "carlsberg": {
        "canonical_brand": "Carlsberg",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "Carlsberg Beer",
        "common_camouflages": ["club soda", "packaged drinking water", "glasses"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "Cable TV Networks Rule 7"],
        "penalty_section": "CCPA 2019 Section 21"
    },
    "tuborg": {
        "canonical_brand": "Tuborg",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "Tuborg Beer",
        "common_camouflages": ["zero soda", "club soda", "packaged drinking water", "music nights"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "Cable TV Networks Rule 7"],
        "penalty_section": "CCPA 2019 Section 21"
    },
    "royal challenge": {
        "canonical_brand": "Royal Challenge",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "Royal Challenge Whisky",
        "common_camouflages": ["packaged drinking water", "sports gear", "club soda"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "Cable TV Networks Rule 7"],
        "penalty_section": "CCPA 2019 Section 21"
    },
    "mcdowell's": {
        "canonical_brand": "McDowell's No. 1",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "McDowell's No. 1 Whisky / Brandy / Rum",
        "common_camouflages": ["club soda", "packaged drinking water", "platinum soda"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "Cable TV Networks Rule 7"],
        "penalty_section": "CCPA 2019 Section 21"
    },
    "imperial blue": {
        "canonical_brand": "Imperial Blue",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "Imperial Blue Superior Grain Whisky",
        "common_camouflages": ["superhit music cds", "packaged drinking water", "club soda", "music nights"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "Cable TV Networks Rule 7"],
        "penalty_section": "CCPA 2019 Section 21"
    },
    "blenders pride": {
        "canonical_brand": "Blenders Pride",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "Blenders Pride Rare Premium Whisky",
        "common_camouflages": ["fashion tour", "packaged drinking water", "club soda"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "Cable TV Networks Rule 7"],
        "penalty_section": "CCPA 2019 Section 21"
    },
    "officer's choice": {
        "canonical_brand": "Officer's Choice",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "Officer's Choice Prestige Whisky",
        "common_camouflages": ["packaged drinking water", "blue soda", "snacks"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "Cable TV Networks Rule 7"],
        "penalty_section": "CCPA 2019 Section 21"
    },
    "royal stag": {
        "canonical_brand": "Royal Stag",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "Royal Stag Deluxe Whisky",
        "common_camouflages": ["mega music cds", "packaged drinking water", "club soda", "cricket gear"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "Cable TV Networks Rule 7"],
        "penalty_section": "CCPA 2019 Section 21"
    },
    "magic moments": {
        "canonical_brand": "Magic Moments",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "Magic Moments Vodka",
        "common_camouflages": ["music studio", "packaged drinking water", "electropop soda"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "Cable TV Networks Rule 7"],
        "penalty_section": "CCPA 2019 Section 21"
    },
    "bacardi": {
        "canonical_brand": "Bacardi",
        "parent_category": "ALCOHOL_LIQUOR",
        "prohibited_product": "Bacardi Rum",
        "common_camouflages": ["music cds", "mix'r club soda", "ginger ale", "merchandise"],
        "governing_laws": ["CCPA Guidelines 2022 Section 8", "Cable TV Networks Rule 7"],
        "penalty_section": "CCPA 2019 Section 21"
    },

    # ---- C. MISCLASSIFIED HEALTH DRINKS (FSSAI APRIL 2024 DIRECTIVE) ----
    "bournvita": {
        "canonical_brand": "Cadbury Bournvita",
        "parent_category": "MISCLASSIFIED_HEALTH_DRINK",
        "prohibited_product": "Malt-based cereal milk powder with ~50g/100g sugar",
        "common_camouflages": ["health drink", "energy drink", "growth formula", "immunity booster"],
        "governing_laws": [
            "FSSAI Directive No. 12-4/2023-RCD (April 2024) - Directing removal of 'Health Drink' from e-commerce",
            "FSSAI Advertising and Claims Regulations 2018 Reg 7(2)"
        ],
        "penalty_section": "FSS Act 2006 Section 52 (Misbranded Food) & Section 53 (Misleading Advertisement)"
    },
    "horlicks": {
        "canonical_brand": "Horlicks",
        "parent_category": "MISCLASSIFIED_HEALTH_DRINK",
        "prohibited_product": "Malt-based cereal powder labeled as health drink",
        "common_camouflages": ["health drink", "taller stronger sharper", "immunity drink"],
        "governing_laws": [
            "FSSAI Directive No. 12-4/2023-RCD",
            "FSSAI Advertising and Claims Regulations 2018 Reg 7"
        ],
        "penalty_section": "FSS Act 2006 Section 52 & 53"
    }
}

# =============================================================================
# 2. COMMON CAMOUFLAGE PRODUCT TYPES
# =============================================================================
KNOWN_CAMOUFLAGE_SKUS = [
    "silver coated elaichi",
    "silver elaichi",
    "elaichi",
    "kesar elaichi",
    "mouth freshener",
    "silver pearls",
    "pan flavour",
    "packaged drinking water",
    "club soda",
    "soda",
    "sparkling water",
    "music cd",
    "music cds",
    "playing cards",
    "perfumery",
    "attar",
    "calendar",
    "cricket gear",
]

# =============================================================================
# 3. STATUTORY SECTIONS AND CITATION CODES
# =============================================================================
STATUTORY_CITATIONS = {
    "CCPA_SEC_8": {
        "act": "Central Consumer Protection Authority (CCPA) Guidelines, 2022",
        "section": "Section 8(1) & 8(2)",
        "heading": "Prohibition of Surrogate Advertising",
        "text": "No surrogate advertisement or indirect advertisement shall be made for goods or services whose advertising is prohibited or restricted by law, using the brand name, logo, color scheme, layout or trademark associated with such restricted goods."
    },
    "FSS_ACT_SEC_24": {
        "act": "Food Safety and Standards Act, 2006",
        "section": "Section 24",
        "heading": "Restrictions on Advertisement and Search",
        "text": "No advertisement shall be made of any food which is misleading or deceiving or contravenes the provisions of this Act, the rules and regulations made thereunder."
    },
    "FSS_ACT_SEC_53": {
        "act": "Food Safety and Standards Act, 2006",
        "section": "Section 53",
        "heading": "Penalty for Misleading Advertisement",
        "text": "Any person who publishes, or is a party to the publication of an advertisement, which falsely describes any food, or is likely to mislead as to the nature or substance or quality thereof, shall be liable to a penalty which may extend to ten lakh rupees."
    },
    "FSSAI_ADV_REG_4": {
        "act": "Food Safety and Standards (Advertising and Claims) Regulations, 2018",
        "section": "Regulation 4",
        "heading": "General Principles of Advertising and Claims",
        "text": "Claims must be truthful, unambiguous, meaningful, not misleading, and must not encourage unwholesome dietary practices or use brand names to circumvent restrictions."
    },
    "COTPA_SEC_5": {
        "act": "Cigarettes and Other Tobacco Products Act, 2003 (COTPA)",
        "section": "Section 5",
        "heading": "Prohibition of Advertisement of Cigarettes and Other Tobacco Products",
        "text": "No person engaged in the production, supply or distribution of cigarettes or other tobacco products shall advertise and no person shall take part in any advertisement which directly or indirectly suggests or promotes the use or consumption of cigarettes or any other tobacco product."
    }
}
