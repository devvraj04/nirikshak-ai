import os
import sys
import time
import ssl
import shutil
import urllib.request
import urllib.parse
from pathlib import Path

sys.stdout.reconfigure(encoding='utf-8')

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
}

# Master list of FSSAI Documents for Nirikshak AI RAG
DOCUMENTS = [
    # --- 1. FOOD SAFETY AND STANDARDS RULES, 2011 (Requested Page: https://fssai.gov.in/food-law/rules-2011) ---
    {
        "filename": "FSSAI_Rules_2011_Compendium.pdf",
        "url": "https://fssai.gov.in/docs/food-law/rules-2011/FSS_Gazete_Rules_2011_compendium.pdf",
        "description": "Compendium of Food Safety and Standards Rules, 2011 (Consolidated official version with all amendments)"
    },
    {
        "filename": "FSSAI_Rules_2011_Original_Gazette.pdf",
        "url": "https://fssai.gov.in/docs/food-law/rules-2011/FSS_Gazete_Rules_2011.pdf",
        "description": "Food Safety and Standards Rules, 2011 (Original Gazette Notification)"
    },
    {
        "filename": "FSSAI_Rules_2011_Amendment_1.pdf",
        "url": "https://fssai.gov.in/docs/food-law/rules-2011/Amend_1_Rule_21_12_2017.pdf",
        "description": "FSS Rules 2011 First Amendment (21.12.2017)"
    },
    {
        "filename": "FSSAI_Rules_2011_Amendment_2.pdf",
        "url": "https://fssai.gov.in/docs/food-law/rules-2011/Amend_2_Rule_21_12_2017.pdf",
        "description": "FSS Rules 2011 Second Amendment (21.12.2017)"
    },
    {
        "filename": "FSSAI_Rules_2011_Amendment_3.pdf",
        "url": "https://fssai.gov.in/docs/food-law/rules-2011/Amend_3_Rule_21_12_2017.pdf",
        "description": "FSS Rules 2011 Third Amendment (21.12.2017)"
    },
    {
        "filename": "FSSAI_Rules_2011_Amendment_4.pdf",
        "url": "https://fssai.gov.in/docs/food-law/rules-2011/Rule_Gazatte.pdf",
        "description": "FSS Rules 2011 Fourth Amendment Gazette"
    },
    {
        "filename": "FSSAI_Rules_2011_Amendment_5.pdf",
        "url": "https://fssai.gov.in/docs/food-law/rules-2011/Gazette_rule_amendment.pdf",
        "description": "FSS Rules 2011 Fifth Amendment Gazette"
    },
    {
        "filename": "FSSAI_Rules_2011_FSO_Qualification_Rule_2_1_3.pdf",
        "url": "https://fssai.gov.in/docs/food-law/rules-2011/Gazette_Notification_Qualification_for_FSO2.pdf",
        "description": "Notification dated 21.09.2023 - Food Safety Officer Qualification under Rule 2.1.3"
    },
    {
        "filename": "FSSAI_Rules_2011_FSO_Equivalent_Qualification_2025.pdf",
        "url": "https://fssai.gov.in/docs/food-law/rules-2011/Gazette_fso.pdf",
        "description": "Notification dated 28.03.2025 - Equivalent Qualification of Food Safety Officer"
    },

    # --- 2. FOOD SAFETY AND STANDARDS ACT, 2006 (Parent Act) ---
    {
        "filename": "FSSAI_Act_2006_Food_Safety_and_Standards_Act.pdf",
        "url": "https://fssai.gov.in/docs/food-law/act-2006/Food_Safety_and_Standards_Act_2006.pdf",
        "description": "Food Safety and Standards Act, 2006 (English statutory text)"
    },
    {
        "filename": "FSSAI_Act_2006_Compendium.pdf",
        "url": "https://fssai.gov.in/docs/food-law/act-2006/Compendium_FSS_Act.pdf",
        "description": "Compendium of Food Safety and Standards Act, 2006"
    },

    # --- 3. LABELLING AND DISPLAY REGULATIONS, 2020 (Crucial for Package & Nutrition Scanning) ---
    {
        "filename": "FSSAI_Regulations_Labelling_and_Display_2020_Compendium_VIII.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Comp_Labelling%20Display_Version%20VIII_09_09_2025.pdf",
        "description": "Compendium of Food Safety and Standards (Labelling and Display) Regulations, 2020 (Version VIII, Sep 2025)"
    },
    {
        "filename": "FSSAI_Regulations_Labelling_and_Display_2020_Original_Gazette.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/5fd87c6a0f6adGazette_Notification_Labelling_Display_14_12_2020.pdf",
        "description": "Food Safety and Standards (Labelling and Display) Regulations, 2020 (Original Gazette)"
    },
    {
        "filename": "FSSAI_Regulations_Labelling_and_Display_Amendment_2022_09.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/amendments/labelling-display/Gazette_Notification_FSS_Label_12_09_2022.pdf",
        "description": "Labelling & Display Gazette Amendment (12.09.2022)"
    },
    {
        "filename": "FSSAI_Regulations_Labelling_and_Display_Amendment_2022_10.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/amendments/labelling-display/Gazette_Notification_Labelling_14_10_2022.pdf",
        "description": "Labelling & Display Gazette Amendment (14.10.2022)"
    },
    {
        "filename": "FSSAI_Regulations_Labelling_and_Display_Oil_Sweetener_2021.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/amendments/labelling-display/Gazette_Notification_Oil_Sweetner_16_09_2021.pdf",
        "description": "Labelling & Display Amendment for Edible Oils and Non-nutritive Sweeteners (16.09.2021)"
    },
    {
        "filename": "FSSAI_Regulations_Labelling_Nutritional_Bold_Font_2026.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/amendments/labelling-display/Notification dt 24_03_2026_NRC.pdf",
        "description": "FSSAI Notification regarding Mandatory Bold Font & Bigger Size for Salt, Sugar, and Fat declarations"
    },

    # --- 4. ADVERTISING AND CLAIMS REGULATIONS, 2018 (For Misleading Claims, Immunity Claims, Dark Patterns) ---
    {
        "filename": "FSSAI_Regulations_Advertising_and_Claims_2018_Compendium.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Compendium_Advertising_Claims_Regulations_14_12_2022.pdf",
        "description": "Compendium of Food Safety and Standards (Advertising and Claims) Regulations, 2018"
    },
    {
        "filename": "FSSAI_Regulations_Advertising_and_Claims_2018_Original_Gazette.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Gazette_Notification_Advertising_Claims_27_11_2018.pdf",
        "description": "Advertising and Claims Regulations, 2018 (Original Gazette)"
    },
    {
        "filename": "FSSAI_Regulations_Advertising_and_Claims_Amendment_2022_09.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/amendments/advertising-claims/Gazette_Notification_Advertisement_01_09_2022.pdf",
        "description": "Advertising & Claims Gazette Amendment (01.09.2022)"
    },
    {
        "filename": "FSSAI_Regulations_Advertising_and_Claims_Amendment_2022_12.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/amendments/advertising-claims/Gazette_Notification_Amendment_14_12_2022.pdf",
        "description": "Advertising & Claims Gazette Amendment (14.12.2022)"
    },

    # --- 5. PACKAGING REGULATIONS, 2018 (For Package Integrity, Materials, rPET Standards) ---
    {
        "filename": "FSSAI_Regulations_Packaging_2018_Compendium_V.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Compendium_Packaging_V_%2002-04-2025.pdf",
        "description": "Compendium of Food Safety and Standards (Packaging) Regulations (Version V, 2025)"
    },
    {
        "filename": "FSSAI_Regulations_Packaging_2018_Original_Gazette.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Gazette_Notification_Packaging_03_01_2019.pdf",
        "description": "Food Safety and Standards (Packaging) Regulations, 2018 (Original Gazette)"
    },
    {
        "filename": "FSSAI_Regulations_Packaging_Recycled_PET_rPET_Guidelines.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Guidelines%20for%20acceptance%20of%20recycled%20Polyethylene%20terephthalate_PET_as%20Food%20Contact%20Material(1).pdf",
        "description": "Guidelines for acceptance of recycled Polyethylene terephthalate (PET) as Food Contact Material (FCM-rPET)"
    },

    # --- 6. CONTAMINANTS, TOXINS AND RESIDUES, 2011 (Banned Ingredients, Residues, Heavy Metals) ---
    {
        "filename": "FSSAI_Regulations_Contaminants_Toxins_and_Residues_2011.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Contaminants_Regulations.pdf",
        "description": "Food Safety and Standards (Contaminants, Toxins and Residues) Regulations, 2011"
    },

    # --- 7. FOOD ADDITIVES & PRODUCT STANDARDS COMPENDIUM ---
    {
        "filename": "FSSAI_Regulations_Food_Additives_2011.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Food_Additives_Regulations.pdf",
        "description": "Food Safety and Standards (Food Products Standards and Food Additives) Regulations, 2011"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch01_General.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/1_%20Chapter%201%20(General).pdf",
        "description": "Food Standards Compendium - Chapter 1 (General Definitions & Principles)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch02_1_Dairy_Products_and_Analogues.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Chapter%202_1_Dairy_products_and_analogues.pdf",
        "description": "Food Standards Compendium - Chapter 2.1 (Dairy products and analogues)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch02_2_Fats_Oils_and_Fat_Emulsions.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Chapter%202_2_Fats_oils%20and%20fat%20emulsions.pdf",
        "description": "Food Standards Compendium - Chapter 2.2 (Fats, oils and fat emulsions)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch02_3_Fruit_and_Vegetable_Products.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Chapter%202_3_Fruit_Vegetable_products.pdf",
        "description": "Food Standards Compendium - Chapter 2.3 (Fruit & Vegetable products)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch02_4_Cereals_and_Cereal_Products.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Chapter%202_4_Cereals_and_Cereal_products.pdf",
        "description": "Food Standards Compendium - Chapter 2.4 (Cereals and Cereal products)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch02_7_Sweets_and_Confectionary.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Chapter%202_7%20(Sweets%20and%20Confectionary).pdf",
        "description": "Food Standards Compendium - Chapter 2.7 (Sweets & Confectionary)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch02_8_Sweetening_Agents_Honey.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Chapter%202_8%20(Sweetening%20agents%20including%20Honey).pdf",
        "description": "Food Standards Compendium - Chapter 2.8 (Sweetening agents including Honey)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch02_9_Salt_Spices_Condiments.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Chapter%202_9_Salt_Spices_Condiments%20and%20related%20products.pdf",
        "description": "Food Standards Compendium - Chapter 2.9 (Salt, Spices, Condiments and related products)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch02_10_Beverages.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Chapter%202_10_BEVERAGES_Other%20than%20Dairy%20and%20Fruits%20Vegetables%20based.pdf",
        "description": "Food Standards Compendium - Chapter 2.10 (Beverages other than Dairy/Fruit based)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch02_11_Other_Food_Products_Ingredients.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/12_%20Chapter%202_11%20(Other%20food%20product%20and%C2%A0%20ingredients).pdf",
        "description": "Food Standards Compendium - Chapter 2.11 (Other food product and ingredients)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch02_12_Proprietary_Food.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/13_%20Chapter%202_12%20(Proprietary%20Food).pdf",
        "description": "Food Standards Compendium - Chapter 2.12 (Proprietary Food)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Ch03_Substances_Added_to_Food_Additives.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Chapter%203_Substances%20added%20to%20food(1).pdf",
        "description": "Food Standards Compendium - Chapter 3 (Substances added to food - Permitted Food Additives)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Appendix_A_Permitted_Additives_List.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Appendix%20A(4).pdf",
        "description": "Food Standards Compendium - Appendix A (List of Permitted Food Additives & Maximum Limits)"
    },
    {
        "filename": "FSSAI_Food_Standards_Compendium_Appendix_B_Microbiological_Requirements.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/compendium/food-products-standards/Appendix%20B(1).pdf",
        "description": "Food Standards Compendium - Appendix B (Microbiological requirements)"
    },

    # --- 8. LICENSING & REGISTRATION REGULATIONS, 2011 ---
    {
        "filename": "FSSAI_Regulations_Licensing_and_Registration_2011_Compendium.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Compendium_Licensing_Regulations_04_08_2021.pdf",
        "description": "Compendium of Licensing and Registration of Food Businesses Regulations, 2011"
    },
    {
        "filename": "FSSAI_Regulations_Licensing_and_Registration_2011_Original.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Licensing_Regulations.pdf",
        "description": "Licensing and Registration of Food Businesses Regulation, 2011 (Original)"
    },

    # --- 9. PROHIBITION AND RESTRICTION OF SALES ---
    {
        "filename": "FSSAI_Regulations_Prohibition_and_Restriction_of_Sales_Compendium.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Comp_Prohibition%20and%20Restrcition%20of%20sales%20XI_01042025.pdf",
        "description": "Compendium of Prohibition and Restriction of Sales Regulation, 2011 (Version XI)"
    },

    # --- 10. LABORATORY AND SAMPLING ANALYSIS ---
    {
        "filename": "FSSAI_Regulations_Laboratory_and_Sampling_Analysis_Compendium.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Compendium_Lab_Sample_Regulations_04_03_2021.pdf",
        "description": "Compendium of Laboratory and Sampling Analysis Regulations, 2011"
    },

    # --- 11. SPECIAL REGULATIONS (Fortification, Vegan, Organic, Nutraceuticals) ---
    {
        "filename": "FSSAI_Regulations_Fortification_of_Food_2018_Compendium.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Compendium_Food_Fortification_Regulations_05_06_2022.pdf",
        "description": "Compendium of Food Safety and Standards (Fortification of Food) Regulations, 2018"
    },
    {
        "filename": "FSSAI_Regulations_Vegan_Foods_2022.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/62ac3f9dba33cGazette_Notification_Vegan_Food_17_06_2022.pdf",
        "description": "Food Safety and Standards (Vegan Foods) Regulations, 2022 (Vegan Logo & Requirements)"
    },
    {
        "filename": "FSSAI_Regulations_Organic_Food_2017_Compendium.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Compendium_Organic_Food_05_06_2022.pdf",
        "description": "Compendium of Food Safety and Standards (Organic Food) Regulations, 2017 (Jaivik Bharat)"
    },
    {
        "filename": "FSSAI_Regulations_Health_Supplements_Nutraceuticals_2016_Compendium.pdf",
        "url": "https://fssai.gov.in/docs/food-law/regulations/Compendium_Nutra_29_09_2021.pdf",
        "description": "Compendium of Health Supplements, Nutraceuticals, Special Dietary Use Regulations, 2016"
    }
]

def download_file(url: str, dest_path: Path, max_retries: int = 3) -> bool:
    # URL encode path while keeping scheme and host intact
    parsed = urllib.parse.urlsplit(url)
    encoded_path = urllib.parse.quote(urllib.parse.unquote(parsed.path))
    clean_url = urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, encoded_path, parsed.query, parsed.fragment))
    
    for attempt in range(1, max_retries + 1):
        try:
            req = urllib.request.Request(clean_url, headers=HEADERS)
            with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
                if resp.status == 200:
                    data = resp.read()
                    if len(data) > 1000 and data.startswith(b'%PDF'):
                        dest_path.write_bytes(data)
                        return True
                    else:
                        print(f"      [Warning] Response did not start with %PDF or too small ({len(data)} bytes).")
        except Exception as e:
            print(f"      [Attempt {attempt}/{max_retries}] Error: {e}")
            time.sleep(1)
    return False

def main():
    root_dir = Path(__file__).resolve().parent.parent
    
    # Paths to populate
    target_dirs = [
        root_dir / "rag_documents",
        root_dir / "rag_documetns"
    ]
    
    for td in target_dirs:
        td.mkdir(parents=True, exist_ok=True)

    print(f"Total documents to download: {len(DOCUMENTS)}")
    print(f"Target directories:")
    for td in target_dirs:
        print(f"  - {td}")
    print("=" * 80)

    downloaded = 0
    failed = []

    for i, doc in enumerate(DOCUMENTS, start=1):
        fn = doc["filename"]
        url = doc["url"]
        desc = doc["description"]
        print(f"[{i:02d}/{len(DOCUMENTS):02d}] {fn}")
        print(f"     Description: {desc}")
        print(f"     Source URL:  {url}")

        primary_dest = target_dirs[0] / fn
        
        # Download to primary directory
        success = False
        if primary_dest.exists() and primary_dest.stat().st_size > 5000:
            print(f"     -> Already exists ({primary_dest.stat().st_size / 1024:.1f} KB). Skipping re-download.")
            success = True
        else:
            success = download_file(url, primary_dest)
            if success:
                size_kb = primary_dest.stat().st_size / 1024
                print(f"     -> Downloaded successfully ({size_kb:.1f} KB)!")
            else:
                print(f"     -> FAILED to download.")
                failed.append(fn)

        # Copy to secondary directory
        if success:
            downloaded += 1
            for secondary_dir in target_dirs[1:]:
                sec_dest = secondary_dir / fn
                shutil.copy2(primary_dest, sec_dest)

        print("-" * 80)

    # Also, ensure all existing PCR files from rag_documetns are copied into rag_documents
    src_dir = root_dir / "rag_documetns"
    dst_dir = root_dir / "rag_documents"
    for item in src_dir.glob("*.pdf"):
        target_file = dst_dir / item.name
        if not target_file.exists():
            shutil.copy2(item, target_file)

    print("\n" + "=" * 80)
    print("DOWNLOAD AND SYNC SUMMARY:")
    print(f"  Total Requested FSSAI Documents: {len(DOCUMENTS)}")
    print(f"  Successfully Downloaded:         {downloaded}")
    print(f"  Failed:                          {len(failed)}")
    if failed:
        print(f"  Failed List: {failed}")
    print(f"  Total PDFs in rag_documents:     {len(list(dst_dir.glob('*.pdf')))}")
    print(f"  Total PDFs in rag_documetns:     {len(list(src_dir.glob('*.pdf')))}")
    print("=" * 80)

if __name__ == "__main__":
    main()
