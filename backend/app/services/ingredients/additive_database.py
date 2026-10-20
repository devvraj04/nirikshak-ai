"""
NIRIKSHAK AI — Chemical Additive & INS/E-Number Dictionary
Comprehensive database of food additives, technical chemicals, functions, origins, and explanations.
"""

from typing import Dict, Any

INS_ADDITIVES: Dict[str, Dict[str, Any]] = {
    # ------------------ COLORS (100 - 199) ------------------
    "100": {
        "name": "Curcumin / Turmeric",
        "ins_number": "INS 100",
        "e_number": "E100",
        "functional_class": "Natural Colorant / Antioxidant",
        "what_is_it": "Natural yellow-orange polyphenol pigment extracted directly from the rhizomes of the turmeric plant (Curcuma longa).",
        "why_used": "Adds a vibrant golden yellow color to confectionery, mustard, curry mixes, cheese, and baked goods; also acts as a natural antioxidant.",
        "origin": "Plant-derived (Turmeric root)",
        "allergy_risk": "Low. Very rare contact dermatitis or mild stomach upset at very high concentrations. Generally safe for almost everyone.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
    "102": {
        "name": "Tartrazine (FD&C Yellow No. 5)",
        "ins_number": "INS 102",
        "e_number": "E102",
        "functional_class": "Synthetic Food Color (Azo Dye)",
        "what_is_it": "A synthetic coal-tar derived lemon-yellow mono-azo dye with the chemical formula C16H9N4Na3O9S2.",
        "why_used": "Imparts a stable, bright lemon-yellow hue to soft drinks, candies, chips, jelly crystals, and instant noodles at low cost.",
        "origin": "Synthetic (Petroleum / Coal-tar derivative)",
        "allergy_risk": "HIGH ALLERGENIC SENSITIVITY. Known cross-reactivity with aspirin (acetylsalicylic acid). Triggers acute urticaria (hives), asthma attacks, eczema flare-ups, and hyperactive behavior / ADHD symptoms in children. Requires mandatory warning in EU.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "110": {
        "name": "Sunset Yellow FCF (FD&C Yellow No. 6)",
        "ins_number": "INS 110",
        "e_number": "E110",
        "functional_class": "Synthetic Food Color (Azo Dye)",
        "what_is_it": "A synthetic petroleum-derived sulfonated azo dye producing an orange-yellow shade.",
        "why_used": "Provides an appetizing orange color to orange sodas, cheese sauces, snack crackers, jellies, and confectionery.",
        "origin": "Synthetic (Petroleum-derived)",
        "allergy_risk": "MODERATE-HIGH ALLERGENIC POTENTIAL. Can provoke bronchospasm, urticaria, rhinitis, and gastric irritation, especially in individuals with asthma or salicylate sensitivity. Banned in Norway and Finland; requires Southampton hyperactivity warning in EU.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "122": {
        "name": "Azorubine / Carmoisine",
        "ins_number": "INS 122",
        "e_number": "E122",
        "functional_class": "Synthetic Red Color (Azo Dye)",
        "what_is_it": "A synthetic disodium salt azo dye creating a deep red to maroon color.",
        "why_used": "Used in berry-flavored drinks, jams, jelly sweets, marzipan, and cake decorations.",
        "origin": "Synthetic (Coal-tar / Petroleum)",
        "allergy_risk": "HIGH SENSITIVITY. Strong trigger for allergic reactions, hives, angioedema (facial swelling), and worsening of asthma symptoms. Banned in the USA, Canada, and Japan.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "124": {
        "name": "Ponceau 4R (Cochineal Red A)",
        "ins_number": "INS 124",
        "e_number": "E124",
        "functional_class": "Synthetic Red Color (Azo Dye)",
        "what_is_it": "A synthetic reddish-crimson azo dye (not derived from insects, unlike cochineal).",
        "why_used": "Gives bright red coloring to strawberry drinks, tomato soups, dessert mixes, and confectionery.",
        "origin": "Synthetic (Petrochemicals)",
        "allergy_risk": "HIGH ALLERGY RISK. Recognized trigger of contact dermatitis, severe hives, and asthma in sensitized individuals. Banned by US FDA.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "127": {
        "name": "Erythrosine (FD&C Red No. 3)",
        "ins_number": "INS 127",
        "e_number": "E127",
        "functional_class": "Synthetic Cherry-Pink Color (Organoiodine)",
        "what_is_it": "An organoiodine fluorone compound imparting an intense cherry-pink hue.",
        "why_used": "Used in cocktail cherries (maraschino cherries), cake icing, and sausage casings.",
        "origin": "Synthetic",
        "allergy_risk": "MODERATE. Increases thyroid hormone levels and induces thyroid tumors in animal bioassays. FDA banned it from cosmetics and externally applied drugs in 1990; food phase-out ongoing.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "129": {
        "name": "Allura Red AC (FD&C Red No. 40)",
        "ins_number": "INS 129",
        "e_number": "E129",
        "functional_class": "Synthetic Red Color (Azo Dye)",
        "what_is_it": "A dark red azo dye synthesized from petroleum distillates.",
        "why_used": "The most widely used red food coloring in candies, soft drinks, cereals, and baked snacks.",
        "origin": "Synthetic (Petroleum)",
        "allergy_risk": "MODERATE-HIGH. Can trigger urticaria, allergic rhinitis, and bowel inflammation in sensitive individuals. Southampton 6 dye linked to ADHD in children.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "133": {
        "name": "Brilliant Blue FCF (FD&C Blue No. 1)",
        "ins_number": "INS 133",
        "e_number": "E133",
        "functional_class": "Synthetic Blue Color (Triarylmethane)",
        "what_is_it": "A synthetic triphenylmethane dye producing an electric cyan blue tint.",
        "why_used": "Used in blue raspberry sweets, syrups, popsicles, mouthwashes, and energy drinks.",
        "origin": "Synthetic (Aromatic hydrocarbons)",
        "allergy_risk": "MODERATE. Low systemic absorption through gastrointestinal tract, but can cause contact hypersensitivity, eczema, and mild asthma exacerbations.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "150a": {
        "name": "Caramel I (Plain Caramel)",
        "ins_number": "INS 150a",
        "e_number": "E150a",
        "functional_class": "Natural / Processed Colorant",
        "what_is_it": "Brown coloring produced by controlled heating of carbohydrates without ammonium or sulfite compounds.",
        "why_used": "Provides natural light brown color to spirits, vinegars, and baked goods.",
        "origin": "Plant-derived carbohydrates (Sugar, Corn, Wheat)",
        "allergy_risk": "LOW. Very safe. If derived from wheat starch, celiac individuals should check gluten purity, but usually gluten-free.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
    "150d": {
        "name": "Caramel IV (Sulfite Ammonia Caramel)",
        "ins_number": "INS 150d",
        "e_number": "E150d",
        "functional_class": "Colorant (Dark Brown)",
        "what_is_it": "Caramelized carbohydrate prepared in the presence of both sulfite and ammonium compounds.",
        "why_used": "The signature dark brown color in cola beverages, dark beers, gravies, soy sauces, and chocolate syrups.",
        "origin": "Synthetic / Processed carbohydrates",
        "allergy_risk": "SULFITE & TOXIN WARNING. Contains residual sulfites (triggering severe reactions in asthmatics) and traces of 4-Methylimidazole (4-MEI), a potential carcinogen regulated under California Prop 65.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "160a": {
        "name": "Beta-Carotene",
        "ins_number": "INS 160a",
        "e_number": "E160a",
        "functional_class": "Natural Colorant / Provitamin A",
        "what_is_it": "Red-orange carotenoid pigment naturally found in carrots, sweet potatoes, and algae, converted by the body into Vitamin A.",
        "why_used": "Adds yellow-orange color to margarine, butter, juices, cheeses, and puddings.",
        "origin": "Plant extract or microbial fermentation",
        "allergy_risk": "VERY LOW. Non-toxic. High chronic intake may cause harmless temporary skin yellowing (carotenodermia).",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
    "171": {
        "name": "Titanium Dioxide",
        "ins_number": "INS 171",
        "e_number": "E171",
        "functional_class": "White Mineral Pigment",
        "what_is_it": "Naturally occurring oxide of titanium processed into insoluble micro- and nano-particles.",
        "why_used": "Creates an opaque, bright white finish in chewing gums, skimmed milk, candy coatings, and sauces.",
        "origin": "Mineral (Refined titanium ore)",
        "allergy_risk": "BANNED IN EU. EFSA ban in 2022: nanoparticles accumulate in gut tissues and genotoxicity (cellular DNA damage) could not be ruled out.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },

    # ------------------ PRESERVATIVES (200 - 299) ------------------
    "200": {
        "name": "Sorbic Acid",
        "ins_number": "INS 200",
        "e_number": "E200",
        "functional_class": "Antimicrobial Preservative",
        "what_is_it": "A naturally occurring unsaturated fatty acid, commercially synthesized, that inhibits yeast and mold growth.",
        "why_used": "Prevents mold and yeast spoilage in cheeses, yogurts, dried fruits, wine, and baked goods.",
        "origin": "Synthetic (Organic synthesis)",
        "allergy_risk": "LOW-MODERATE. Occasional contact dermatitis or mild skin irritation. Generally metabolized by the human body like dietary fatty acids.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "202": {
        "name": "Potassium Sorbate",
        "ins_number": "INS 202",
        "e_number": "E202",
        "functional_class": "Antimicrobial Preservative",
        "what_is_it": "The potassium salt of sorbic acid, highly water-soluble.",
        "why_used": "Extensively used to extend shelf-life by suppressing mold, yeast, and fungi in jams, beverages, sauces, cheese, and syrups.",
        "origin": "Synthetic",
        "allergy_risk": "LOW-MODERATE. Hypersensitivity reactions can cause mild itching, hives, or stinging sensations on sensitive skin.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "211": {
        "name": "Sodium Benzoate",
        "ins_number": "INS 211",
        "e_number": "E211",
        "functional_class": "Antimicrobial Preservative",
        "what_is_it": "The sodium salt of benzoic acid, effective in acidic foods (pH below 4.5).",
        "why_used": "Prevents bacterial and fungal fermentation in carbonated drinks, fruit juices, pickles, condiments, and medicines.",
        "origin": "Synthetic (from toluene)",
        "allergy_risk": "MODERATE-HIGH ALLERGENIC SENSITIVITY. Triggers asthma attacks, chronic urticaria, and eczema. CRITICAL INTERACTION: When combined with Vitamin C (Ascorbic Acid / INS 300) in beverages, it can chemically react to form Benzene, a known human carcinogen.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "220": {
        "name": "Sulfur Dioxide",
        "ins_number": "INS 220",
        "e_number": "E220",
        "functional_class": "Sulfite Preservative & Antioxidant",
        "what_is_it": "Inorganic gas with pungent odor, used as a powerful preservative and bleaching agent.",
        "why_used": "Prevents oxidation and bacterial spoilage in wine, dried apricots, raisins, juices, and peeled potatoes.",
        "origin": "Chemical synthesis / Mineral sulfur",
        "allergy_risk": "SEVERE STATUTORY ALLERGEN. Asthmatics are at severe risk of bronchospasm, anaphylactoid reactions, chest tightness, and sudden collapse. Mandatory warning required if > 10 ppm.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "223": {
        "name": "Sodium Metabisulfite",
        "ins_number": "INS 223",
        "e_number": "E223",
        "functional_class": "Sulfite Preservative & Dough Relaxant",
        "what_is_it": "An inorganic salt containing sodium and metabisulfite ions that releases sulfur dioxide in solution.",
        "why_used": "Relaxes gluten in biscuit and cracker manufacturing for uniform dough sheeting; preserves dried fruits, dehydrated potatoes, and wines.",
        "origin": "Synthetic",
        "allergy_risk": "SEVERE ALLERGEN. Can cause acute anaphylaxis, wheezing, headache, flushing, and severe asthmatic constriction.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "250": {
        "name": "Sodium Nitrite",
        "ins_number": "INS 250",
        "e_number": "E250",
        "functional_class": "Curing Agent / Preservative / Color Fixative",
        "what_is_it": "An inorganic salt used in meat preservation.",
        "why_used": "Inhibits lethal Clostridium botulinum bacteria and fixes the distinctive pink color and flavor in bacon, ham, hot dogs, and sausages.",
        "origin": "Synthetic",
        "allergy_risk": "HIGH HEALTH RISK. Reacts with dietary amines at high cooking heat to form Nitrosamines, which are potent Group 1 carcinogens (colorectal and gastric cancer). Rare methemoglobinemia risk in infants.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "282": {
        "name": "Calcium Propionate",
        "ins_number": "INS 282",
        "e_number": "E282",
        "functional_class": "Mold Inhibitor / Preservative",
        "what_is_it": "The calcium salt of propionic acid, an organic acid that stops mold spore germination.",
        "why_used": "Allows pre-packaged bread, burger buns, pizza crusts, and baked tortillas to remain mold-free on store shelves for weeks.",
        "origin": "Synthetic / Fermentation",
        "allergy_risk": "MODERATE BEHAVIORAL & SENSITIVITY RISK. Linked to irritability, restlessness, inattention, and sleep disturbance in young children, as well as recurring migraines in sensitive adults.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },

    # ------------------ ANTIOXIDANTS & ACIDITY REGULATORS (300 - 399) ------------------
    "300": {
        "name": "Ascorbic Acid (Vitamin C)",
        "ins_number": "INS 300",
        "e_number": "E300",
        "functional_class": "Antioxidant / Flour Improver / Nutrient",
        "what_is_it": "Water-soluble organic vitamin (L-ascorbic acid) manufactured via microbial fermentation of glucose.",
        "why_used": "Prevents browning in cut fruits and juices; strengthens gluten in bread dough; provides essential Vitamin C.",
        "origin": "Microbial fermentation of plant glucose",
        "allergy_risk": "VERY LOW. Natural essential human nutrient. Extremely rare corn allergy if glucose derived from corn is unrefined.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
    "319": {
        "name": "TBHQ (Tert-Butylhydroquinone)",
        "ins_number": "INS 319",
        "e_number": "E319",
        "functional_class": "Synthetic Antioxidant",
        "what_is_it": "A synthetic aromatic organic compound derived from butane and petroleum distillates.",
        "why_used": "Highly effective antioxidant preventing rancidity in frying oils, packaged chips, crackers, frozen fish, and instant noodles.",
        "origin": "Synthetic (Petroleum-derived)",
        "allergy_risk": "MODERATE-HIGH HEALTH HAZARD. Associated with vision disturbances, immune system dysfunction (suppresses T-cell response), and DNA damage in animal bioassays. Strictly limited to 200 mg/kg of fat.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "320": {
        "name": "BHA (Butylated Hydroxyanisole)",
        "ins_number": "INS 320",
        "e_number": "E320",
        "functional_class": "Synthetic Antioxidant",
        "what_is_it": "A synthetic phenolic antioxidant mixture of two isomeric organic compounds.",
        "why_used": "Preserves fats and oils from oxidative rancidity in snack foods, breakfast cereals, chewing gum, and butter.",
        "origin": "Synthetic",
        "allergy_risk": "HIGH TOXICITY CONCERN. Classified by the US National Toxicology Program as 'reasonably anticipated to be a human carcinogen'. Endocrine disruptor affecting estrogen and thyroid signaling.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "321": {
        "name": "BHT (Butylated Hydroxytoluene)",
        "ins_number": "INS 321",
        "e_number": "E321",
        "functional_class": "Synthetic Antioxidant",
        "what_is_it": "A lipophilic synthetic toluene-derived organic chemical.",
        "why_used": "Stabilizes fats and fat-soluble vitamins in processed foods, chips, and cereal packaging liners.",
        "origin": "Synthetic",
        "allergy_risk": "MODERATE-HIGH. Endocrine disruptor, respiratory sensitizer, and liver enzyme disruptor. Banned or restricted in foods in several European nations and Japan.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "322": {
        "name": "Lecithin (Soy / Sunflower / Egg)",
        "ins_number": "INS 322",
        "e_number": "E322",
        "functional_class": "Natural Emulsifier",
        "what_is_it": "A natural mixture of phospholipids and glycolipids extracted from soybeans, sunflower seeds, or egg yolks.",
        "why_used": "Binds oil and water together, lowers chocolate viscosity so it flows smoothly, and prevents fat bloom in confectionery.",
        "origin": "Plant (Soybean / Sunflower) or Animal (Egg yolk)",
        "allergy_risk": "MAJOR ALLERGEN TRIGGER (IF SOY OR EGG). If derived from Soy, poses immediate anaphylaxis/allergy risk to individuals with soy allergies. Must clearly state botanical origin (e.g., 'Soy Lecithin'). Sunflower lecithin is allergen-free.",
        "dietary_flags": ["Vegetarian", "Vegan (if plant-sourced)"]
    },
    "330": {
        "name": "Citric Acid",
        "ins_number": "INS 330",
        "e_number": "E330",
        "functional_class": "Acidity Regulator / Flavoring / Antioxidant Synergist",
        "what_is_it": "A weak tricarboxylic organic acid naturally found in lemons/oranges, commercially produced by fermentation of molasses/sugar using Aspergillus niger mold.",
        "why_used": "Imparts a clean, tart, sour flavor to sodas, candies, and jams; acts as a natural preservative by lowering pH.",
        "origin": "Microbial fermentation (Aspergillus niger / sugar)",
        "allergy_risk": "LOW TO MILD. Individuals with severe black mold (Aspergillus) hypersensitivity or citrus sensitivities may experience joint pains, gastrointestinal cramps, or canker sores from manufactured citric acid.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
    "331": {
        "name": "Sodium Citrates",
        "ins_number": "INS 331",
        "e_number": "E331",
        "functional_class": "Buffering Agent / Emulsifying Salt",
        "what_is_it": "Sodium salts of citric acid (monosodium, disodium, and trisodium citrate).",
        "why_used": "Controls acidity in gelatin, soft drinks, and energy drinks; acts as an emulsifying salt in processed cheese to prevent oil separation when melted.",
        "origin": "Synthetic / Fermentation",
        "allergy_risk": "VERY LOW. Safe and easily metabolized through the Krebs citric acid cycle.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },

    # ------------------ EMULSIFIERS, STABILIZERS, THICKENERS (400 - 499) ------------------
    "407": {
        "name": "Carrageenan",
        "ins_number": "INS 407",
        "e_number": "E407",
        "functional_class": "Gelling Agent / Thickener / Stabilizer",
        "what_is_it": "A family of natural linear sulfated polysaccharides extracted from red edible seaweeds (Chondrus crispus).",
        "why_used": "Gives creamy mouthfeel to almond milk, chocolate milk, ice cream, yogurts, and deli meats without adding fat.",
        "origin": "Plant-based (Red seaweed)",
        "allergy_risk": "HIGH GUT SENSITIVITY. Known to cause mucosal gastrointestinal inflammation, bloating, irritable bowel syndrome (IBS) flares, and colitis symptoms. Degraded carrageenan (poligeenan) is a proven animal carcinogen.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
    "412": {
        "name": "Guar Gum",
        "ins_number": "INS 412",
        "e_number": "E412",
        "functional_class": "Natural Thickener & Viscosity Modifier",
        "what_is_it": "A galactomannan polysaccharide extracted from the endosperm of guar beans (Cyamopsis tetragonoloba).",
        "why_used": "Extremely high water-binding capacity; prevents ice crystal formation in ice creams, thickens sauces and salad dressings.",
        "origin": "Plant (Guar bean)",
        "allergy_risk": "LOW-MODERATE. High soluble fiber content may cause abdominal gas, bloating, or loose stools in people with sensitive digestion or SIBO.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
    "415": {
        "name": "Xanthan Gum",
        "ins_number": "INS 415",
        "e_number": "E415",
        "functional_class": "Thickener & Rheology Control Agent",
        "what_is_it": "A microbial heteropolysaccharide produced by the bacterial fermentation of glucose by Xanthomonas campestris.",
        "why_used": "Maintains uniform suspension of spices in salad dressings, provides elasticity and structure to gluten-free bread.",
        "origin": "Microbial fermentation (often grown on corn, wheat, or dairy sugar)",
        "allergy_risk": "MODERATE HIDDEN ALLERGEN. The fermentation growth substrate can trigger reactions in individuals with severe corn, wheat, or dairy allergies. Also acts as a laxative in high quantities.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "471": {
        "name": "Mono- and Diglycerides of Fatty Acids",
        "ins_number": "INS 471",
        "e_number": "E471",
        "functional_class": "Emulsifier & Texture Softener",
        "what_is_it": "Glycerol molecules bound to one or two fatty acids, derived from plant oils (palm/soy) or animal tallow.",
        "why_used": "Softens bread crumb, delays staling, blends fats and liquids in margarine, peanut butter, and baked cakes.",
        "origin": "Plant or Animal (Palm oil, soybean oil, or animal fats)",
        "allergy_risk": "DIETARY / RELIGIOUS CONCERN. May contain traces of trans fats. Strict vegetarians, vegans, Halal, and Kosher consumers must verify source (can be animal-derived unless specified plant-based).",
        "dietary_flags": ["Vegetarian (if plant source)", "Vegan (if plant source)"]
    },
    "472e": {
        "name": "DATEM (Diacetyl Tartaric Acid Esters of Mono- and Diglycerides)",
        "ins_number": "INS 472e",
        "e_number": "E472e",
        "functional_class": "Dough Conditioner & Emulsifier",
        "what_is_it": "A synthetic emulsifier produced from mono/diglycerides reacted with tartaric acid and acetic anhydride.",
        "why_used": "Strengthens gluten matrix in commercial bread making, enabling high volume, springy texture, and fine crumb.",
        "origin": "Plant or Animal fats + Tartaric acid",
        "allergy_risk": "LOW TOXICITY. Can be derived from animal fat or plant oil. Very low allergenicity.",
        "dietary_flags": ["Check origin for Halal/Kosher"]
    },
    "476": {
        "name": "Polyglycerol Polyricinoleate (PGPR)",
        "ins_number": "INS 476",
        "e_number": "E476",
        "functional_class": "Viscosity Reducer / Emulsifier",
        "what_is_it": "A synthetic polymer made from glycerol and condensed castor oil fatty acids.",
        "why_used": "Massively reduces the viscosity of melted chocolate, allowing manufacturers to replace expensive cocoa butter with cheap vegetable fats.",
        "origin": "Castor oil beans + Glycerol",
        "allergy_risk": "LOW. Very low allergenicity. High doses may cause mild gastrointestinal discomfort.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },

    # ------------------ ACIDITY REGULATORS & LEAVENING AGENTS (500 - 599) ------------------
    "500": {
        "name": "Sodium Carbonates (Baking Soda)",
        "ins_number": "INS 500",
        "e_number": "E500",
        "functional_class": "Leavening Agent / Acidity Regulator",
        "what_is_it": "Inorganic mineral salts: Sodium hydrogen carbonate (baking soda) and sodium carbonate.",
        "why_used": "Releases carbon dioxide gas when heated or combined with acid, causing cakes, cookies, and noodles to rise.",
        "origin": "Mineral (Trona ore or Solvay process)",
        "allergy_risk": "VERY LOW. Non-allergenic. High sodium contribution for hypertensive individuals.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
    "503": {
        "name": "Ammonium Carbonates (Baker's Ammonia)",
        "ins_number": "INS 503",
        "e_number": "E503",
        "functional_class": "Leavening Agent",
        "what_is_it": "Ammonium bicarbonate and ammonium carbamate.",
        "why_used": "Gives exceptionally crispy texture to dry biscuits and thin crackers; evaporates completely during baking leaving no residual moisture.",
        "origin": "Chemical synthesis",
        "allergy_risk": "VERY LOW. Completely vaporizes as ammonia gas and CO2 during baking.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
    "551": {
        "name": "Silicon Dioxide (Silica)",
        "ins_number": "INS 551",
        "e_number": "E551",
        "functional_class": "Anti-Caking Agent",
        "what_is_it": "A chemical compound of silicon and oxygen, identical in formula to quartz/sand, processed into an ultra-fine amorphous powder.",
        "why_used": "Absorbs ambient moisture and coats particles, allowing salt, spices, instant coffee, and soup powders to flow freely without clumping.",
        "origin": "Mineral / Synthetic synthesis",
        "allergy_risk": "MODERATE. Non-allergenic, but contains sub-micron and nano-particles. European Food Safety Authority (EFSA) raised concerns over chronic internal tissue accumulation of silica nanoparticles.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },

    # ------------------ FLAVOR ENHANCERS (600 - 699) ------------------
    "621": {
        "name": "Monosodium Glutamate (MSG)",
        "ins_number": "INS 621",
        "e_number": "E621",
        "functional_class": "Flavor Enhancer (Umami)",
        "what_is_it": "The sodium salt of glutamic acid, an amino acid, produced by bacterial fermentation of sugarcane, sugar beets, or tapioca.",
        "why_used": "Activates the L-glutamate taste receptors on the tongue, creating an intense savory, meaty, 'umami' flavor in chips, soups, seasonings, and processed meats.",
        "origin": "Fermentation of plant starches (Corynebacterium glutamicum)",
        "allergy_risk": "MSG SENSITIVITY SYNDROME. In sensitive individuals, causes flushing, chest tightness, numbness/burning at the back of neck, throbbing headaches, heart palpitations, and sweating. Not a true IgE allergy, but a profound neurological/vascular food intolerance.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
    "627": {
        "name": "Disodium Guanylate",
        "ins_number": "INS 627",
        "e_number": "E627",
        "functional_class": "Flavor Enhancer Synergist",
        "what_is_it": "Sodium salt of guanosine monophosphate (GMP), an organic nucleotide produced from dried fish or fermented tapioca.",
        "why_used": "Acts in synergy with MSG to multiply savory flavor intensity up to 8-fold; used in potato chips, instant noodles, and savory biscuits.",
        "origin": "Microbial fermentation or dried fish / sardines",
        "allergy_risk": "GOUT & PURINE WARNING. Metabolizes into purines and uric acid; can trigger acute gout flare-ups and kidney stones in susceptible patients. Check source for fish allergy or strict vegetarian diet.",
        "dietary_flags": ["Vegetarian (if microbial)", "Vegan (if microbial)"]
    },
    "631": {
        "name": "Disodium Inosinate",
        "ins_number": "INS 631",
        "e_number": "E631",
        "functional_class": "Flavor Enhancer Synergist",
        "what_is_it": "Sodium salt of inosinic acid, naturally abundant in meat and fish tissues, commercially fermented or extracted from meat/fish.",
        "why_used": "Combined with MSG and Disodium Guanylate (forming 'I+G') to create rich savory flavors in snack seasonings and bouillon cubes.",
        "origin": "Fermented tapioca starch, or animal/fish extract (sardines/meat)",
        "allergy_risk": "GOUT & ALLERGEN ALERT. Contraindicated in hyperuricemia/gout. If sourced from fish or animal, poses risk to fish-allergic or vegetarian/Halal consumers.",
        "dietary_flags": ["Check origin (often animal or fish)"]
    },
    "635": {
        "name": "Disodium 5'-Ribonucleotides",
        "ins_number": "INS 635",
        "e_number": "E635",
        "functional_class": "Flavor Enhancer Blend",
        "what_is_it": "A synergistic 50:50 mixture of Disodium Inosinate (INS 631) and Disodium Guanylate (INS 627).",
        "why_used": "Gives intense savory depth at tiny concentrations in instant noodle tastemakers, corn snacks, and fast food coatings.",
        "origin": "Fermentation or animal/fish extracts",
        "allergy_risk": "ALLERGIC RASH WARNING. Can trigger acute, itchy, erythematous skin rashes (ribonucleotide rash / itchy skin lesions) within 30 hours of ingestion. Also triggers gout.",
        "dietary_flags": ["Check origin"]
    },

    # ------------------ ARTIFICIAL SWEETENERS (900 - 999) ------------------
    "950": {
        "name": "Acesulfame Potassium (Ace-K)",
        "ins_number": "INS 950",
        "e_number": "E950",
        "functional_class": "Non-Caloric Artificial Sweetener",
        "what_is_it": "A synthetic calorie-free potassium salt of 6-methyl-1,2,3-oxathiazine-4(3H)-one 2,2-dioxide; ~200 times sweeter than sucrose.",
        "why_used": "Provides quick sweet onset with high heat stability for baking and diet beverages; blended with aspartame/sucralose to mask bitter aftertastes.",
        "origin": "Synthetic",
        "allergy_risk": "MODERATE CONCERN. Contains methylene chloride (a carcinogen) during synthesis. Animal studies suggest disruption of gut microbiota and potential insulin response alteration.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "951": {
        "name": "Aspartame",
        "ins_number": "INS 951",
        "e_number": "E951",
        "functional_class": "Low-Calorie High-Intensity Sweetener",
        "what_is_it": "A synthetic methyl ester of the aspartic acid/phenylalanine dipeptide; ~200 times sweeter than table sugar.",
        "why_used": "Sweetens diet sodas, sugar-free chewing gums, low-calorie yogurts, and diabetic desserts.",
        "origin": "Synthetic peptide synthesis",
        "allergy_risk": "PHENYLKETONURIA (PKU) LIFE-THREATENING RISK. People with PKU lack the enzyme to metabolize phenylalanine, leading to toxic brain accumulation, severe intellectual disability, and seizures. Mandatory statutory warning: 'CONTAINS PHENYLALANINE'. Classified by WHO/IARC as Group 2B possibly carcinogenic.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "955": {
        "name": "Sucralose",
        "ins_number": "INS 955",
        "e_number": "E955",
        "functional_class": "Non-Caloric Artificial Sweetener",
        "what_is_it": "Chlorinated sucrose derivative where three hydroxyl groups are substituted with chlorine atoms; ~600 times sweeter than sugar.",
        "why_used": "Sweetens calorie-free drinks, protein powders, syrups, and baked products because it is heat-stable.",
        "origin": "Synthetic chlorination of sucrose",
        "allergy_risk": "MODERATE GUT DYSBIOSIS. Can significantly diminish beneficial gut bacteria (bifidobacteria/lactobacilli); releases chloropropanols (toxic compounds) when heated above 120°C in cooking.",
        "dietary_flags": ["Vegetarian", "Vegan"]
    },
    "960": {
        "name": "Steviol Glycosides (Stevia)",
        "ins_number": "INS 960",
        "e_number": "E960",
        "functional_class": "Natural High-Intensity Sweetener",
        "what_is_it": "Natural glycosides (Rebaudioside A and Stevioside) extracted and purified from the leaves of Stevia rebaudiana.",
        "why_used": "Zero-calorie plant sweetener ~250–300 times sweeter than sucrose; used in natural diet drinks, chocolates, and teas.",
        "origin": "Plant-derived (Stevia rebaudiana leaves)",
        "allergy_risk": "LOW-MODERATE ASTERACEAE ALLERGY. Related to ragweed, daisies, chrysanthemums, and marigolds; individuals with ragweed allergies may experience cross-reactive allergic symptoms or mild gastrointestinal bloating.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"]
    },
}

# Everyday food base ingredients with technical details and allergen triggers
COMMON_FOOD_INGREDIENTS: Dict[str, Dict[str, Any]] = {
    "refined wheat flour": {
        "canonical_name": "Refined Wheat Flour (Maida)",
        "category": "Cereal Grain / Refined Carbohydrate",
        "what_is_it": "Endosperm of wheat grain with germ and bran mechanically stripped away, finely milled and often bleached.",
        "why_used": "Primary structural base for biscuits, cakes, noodles, breads, buns, and fried snacks.",
        "origin": "Plant (Triticum aestivum)",
        "allergy_risk": "MAJOR STATUTORY ALLERGEN (GLUTEN & WHEAT). Dangerous for individuals with Celiac Disease (causes autoimmune destruction of intestinal villi), Non-Celiac Gluten Sensitivity, and IgE-mediated Wheat Allergy. Triggers anaphylaxis, eczema, severe diarrhea, and malnutrition.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": True,
        "allergen_type": "Gluten / Wheat"
    },
    "palm oil": {
        "canonical_name": "Palm Oil / Palmolein",
        "category": "Vegetable Fat",
        "what_is_it": "Edible vegetable oil extracted from the mesocarp (reddish pulp) of the fruit of oil palms (Elaeis guineensis).",
        "why_used": "Extremely inexpensive, naturally semi-solid at room temperature without hydrogenation, high smoke point for deep frying snacks, potato chips, and instant noodles.",
        "origin": "Plant (Oil Palm fruit)",
        "allergy_risk": "VERY LOW ALLERGY RISK. High cardiovascular health concern: contains ~50% saturated palmitic acid, which elevates LDL (bad) cholesterol and increases atherogenic cardiovascular disease risk. High environmental deforestation impact.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": False
    },
    "milk solids": {
        "canonical_name": "Milk Solids / Dairy Solids",
        "category": "Dairy",
        "what_is_it": "The dehydrated protein, fat, and carbohydrate fractions (casein, whey, lactose, milk fat) of cow or buffalo milk.",
        "why_used": "Imparts creaminess, browning, rich dairy flavor, and texture in chocolates, biscuits, toffees, ice creams, and baked goods.",
        "origin": "Animal (Bovine milk)",
        "allergy_risk": "MAJOR STATUTORY ALLERGEN (DAIRY & LACTOSE). 1) Cow's milk protein allergy (IgE mediated to casein/whey) causing hives, respiratory distress, and anaphylaxis in children. 2) Lactose intolerance causing abdominal bloating, painful cramps, and diarrhea.",
        "dietary_flags": ["Vegetarian", "Non-Vegan"],
        "is_allergen": True,
        "allergen_type": "Milk / Dairy"
    },
    "whey powder": {
        "canonical_name": "Whey Powder / Whey Protein",
        "category": "Dairy Protein",
        "what_is_it": "The liquid remaining after milk has been curdled and strained during cheese making, concentrated and spray dried.",
        "why_used": "Provides high protein content, water-binding, and smooth mouthfeel in protein bars, baby foods, and confectionery.",
        "origin": "Animal (Milk byproduct)",
        "allergy_risk": "MAJOR ALLERGEN (MILK). Triggers acute milk allergy and lactose intolerance.",
        "dietary_flags": ["Vegetarian", "Non-Vegan"],
        "is_allergen": True,
        "allergen_type": "Milk / Dairy"
    },
    "cocoa solids": {
        "canonical_name": "Cocoa Solids / Cocoa Powder",
        "category": "Confectionery / Plant extract",
        "what_is_it": "Non-fat component of chocolate, ground from roasted, fermented, and defatted cocoa beans (Theobroma cacao).",
        "why_used": "Provides chocolate flavor, dark brown color, and polyphenolic antioxidants in chocolates and baked goods.",
        "origin": "Plant (Cacao tree)",
        "allergy_risk": "LOW-MODERATE. Contains natural theobromine and caffeine (migraine/insomnia trigger in sensitive individuals). Rare true cocoa allergy.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": False
    },
    "cocoa butter": {
        "canonical_name": "Cocoa Butter",
        "category": "Plant Fat",
        "what_is_it": "Pure pale-yellow edible fat extracted from cocoa beans, melting sharply at 34–38°C (human body temperature).",
        "why_used": "Gives real chocolate its luxurious 'melt-in-your-mouth' sensation and glossy snap.",
        "origin": "Plant (Cacao seed)",
        "allergy_risk": "VERY LOW. Highly biocompatible vegetable fat.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": False
    },
    "invert sugar": {
        "canonical_name": "Invert Sugar Syrup",
        "category": "Sweetener",
        "what_is_it": "An equimolar liquid mixture of glucose and fructose produced by hydrolyzing sucrose with acid or enzymes.",
        "why_used": "Sweeter than regular sugar, acts as a humectant to retain baked product moisture, and prevents crystallization in icings and confectionery.",
        "origin": "Processed plant sucrose (Sugarcane/Sugar beet)",
        "allergy_risk": "LOW ALLERGY RISK. High glycemic index and fructose content; promotes insulin resistance, tooth decay, fatty liver, and metabolic syndrome.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": False
    },
    "maltodextrin": {
        "canonical_name": "Maltodextrin",
        "category": "Polysaccharide Bulking Agent",
        "what_is_it": "A moderately sweet white hygroscopic powder produced from partial enzymatic hydrolysis of corn, potato, or wheat starch.",
        "why_used": "Adds bulk, smooth texture, carrier for powdered flavors and spice mixes, and thickener in processed foods.",
        "origin": "Plant starch (Corn, Potato, Rice, or Wheat)",
        "allergy_risk": "MODERATE. Extremely high glycemic index (GI 85–105), spiking blood glucose faster than table sugar; if derived from wheat, may contain trace gluten. Negatively alters intestinal microbiome by thinning protective gut mucus.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": False
    },
    "high fructose corn syrup": {
        "canonical_name": "High Fructose Corn Syrup (HFCS)",
        "category": "Liquid Sweetener",
        "what_is_it": "Enzymatically processed corn syrup where glucose isomerase converts glucose into fructose (typically HFCS 42 or HFCS 55).",
        "why_used": "Cheap liquid sweetener that enhances browning, moisture retention, and shelf life in sodas, breads, sauces, and yogurts.",
        "origin": "Plant (Zea mays / Corn starch)",
        "allergy_risk": "METABOLIC HAZARD & CORN ALLERGEN. Hepatic metabolism bypasses phosphofructokinase regulation, driving non-alcoholic fatty liver disease (NAFLD), visceral adiposity, and hyperuricemia. Triggers corn hypersensitivity.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": True,
        "allergen_type": "Corn / Maize"
    },
    "peanut oil": {
        "canonical_name": "Peanut Oil / Groundnut Oil",
        "category": "Plant Oil / Major Allergen",
        "what_is_it": "Oil pressed from the seeds of Arachis hypogaea (peanuts/groundnuts).",
        "why_used": "High smoke point frying oil for potato chips, namkeens, and Asian stir-fries.",
        "origin": "Plant (Peanut / Legume)",
        "allergy_risk": "CRITICAL LIFE-THREATENING ALLERGEN. Unrefined or cold-pressed peanut oil contains peanut protein capable of inducing fatal anaphylactic shock, laryngeal edema, and respiratory collapse.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": True,
        "allergen_type": "Peanuts"
    },
    "soy protein isolate": {
        "canonical_name": "Soy Protein Isolate",
        "category": "Plant Protein",
        "what_is_it": "Defatted soybean flakes stripped of fiber and carbohydrates to yield 90%+ pure protein.",
        "why_used": "Adds protein to protein bars, vegetarian meat alternatives, baby formulas, and health supplements.",
        "origin": "Plant (Glycine max / Soybean)",
        "allergy_risk": "MAJOR STATUTORY ALLERGEN (SOY). Triggers severe allergic reactions, angioedema, gastrointestinal anaphylaxis, and atopic dermatitis in children.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": True,
        "allergen_type": "Soy"
    },
    "hydrolyzed vegetable protein": {
        "canonical_name": "Hydrolyzed Vegetable Protein (HVP)",
        "category": "Flavoring / Umami Source",
        "what_is_it": "Vegetable protein (soy, corn, or wheat) broken down into free amino acids (including free glutamic acid) using hydrochloric acid.",
        "why_used": "Adds savory, meaty bouillon flavor to instant noodles, seasoning mixes, soups, and processed snacks as a natural alternative to MSG.",
        "origin": "Plant protein (Soy, Wheat, or Corn)",
        "allergy_risk": "CONCEALED ALLERGEN & MSG-LIKE SENSITIVITY. Contains 10–30% natural free glutamate, triggering glutamate sensitivity symptoms. Often contains unlisted soy or wheat gluten allergens.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": True,
        "allergen_type": "Soy / Gluten / Glutamate"
    },
    "yeast extract": {
        "canonical_name": "Yeast Extract / Autolyzed Yeast",
        "category": "Flavor Enhancer",
        "what_is_it": "De-walled yeast cells (Saccharomyces cerevisiae) broken down by their own enzymes to liberate natural nucleic acids and glutamic acid.",
        "why_used": "Provides natural savory broth taste to snacks, chips, canned soups, and vegan cheeses.",
        "origin": "Microbial (Baker's or Brewer's Yeast)",
        "allergy_risk": "GLUTAMATE & YEAST INTOLERANCE. Rich in natural free glutamate (provoking MSG-like intolerance) and high in purines (gout risk). Can aggravate yeast sensitivities and Crohn's disease.",
        "dietary_flags": ["Vegetarian", "Vegan", "Halal", "Kosher"],
        "is_allergen": False
    },
    "hydrogenated vegetable oil": {
        "canonical_name": "Hydrogenated Vegetable Oil / Vanaspati (Trans Fats)",
        "category": "Industrial Fat",
        "what_is_it": "Liquid vegetable oil chemically reacted with hydrogen in the presence of a nickel catalyst to solidify it.",
        "why_used": "Provides long shelf stability, solid texture, and flaky crusts in biscuits, pastries, cookies, and fried street foods at minimal cost.",
        "origin": "Synthetic / Chemically modified vegetable oil",
        "allergy_risk": "MAJOR CARDIOVASCULAR HEALTH RISK. Contains industrial Trans Fatty Acids (TFAs). Directly elevates LDL, depresses HDL, and is the leading dietary cause of coronary artery disease. Banned by WHO ('REPLACE' initiative) and restricted to < 2% by FSSAI.",
        "dietary_flags": ["Vegetarian", "Vegan"],
        "is_allergen": False
    }
}
