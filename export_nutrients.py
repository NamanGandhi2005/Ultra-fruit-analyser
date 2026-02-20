import json

# Manually extracted from prediction.py to ensure accuracy
NUTRIENT_DB = {
    'banana': {
        1: {'name': 'Very Unripe', 'color': '#90EE90', 'rotten': False, 'sugar_g': 19, 'vitamin_c_mg': 0.2, 'fiber_g': 1.5, 'calories': 89, 'benefits': 'High in resistant starch'},
        2: {'name': 'Unripe', 'color': '#98FB98', 'rotten': False, 'sugar_g': 28, 'vitamin_c_mg': 0.2, 'fiber_g': 2.5, 'calories': 95, 'benefits': 'Prebiotic fiber source'},
        3: {'name': 'Slightly Ripe', 'color': '#ADFF2F', 'rotten': False, 'sugar_g': 52, 'vitamin_c_mg': 0.3, 'fiber_g': 2.0, 'calories': 105, 'benefits': 'Balanced starch/sugar'},
        4: {'name': 'Moderately Ripe', 'color': '#FFFF00', 'rotten': False, 'sugar_g': 183, 'vitamin_c_mg': 0.3, 'fiber_g': 3.0, 'calories': 110, 'benefits': 'Good energy source'},
        5: {'name': 'Ripe', 'color': '#FFD700', 'rotten': False, 'sugar_g': 272, 'vitamin_c_mg': 0.3, 'fiber_g': 1.2, 'calories': 115, 'benefits': 'Easy to digest'},
        6: {'name': 'Very Ripe', 'color': '#FFA500', 'rotten': False, 'sugar_g': 316, 'vitamin_c_mg': 0.3, 'fiber_g': 1.0, 'calories': 120, 'benefits': 'High antioxidants'},
        7: {'name': 'Fully Ripe', 'color': '#FF8C00', 'rotten': False, 'sugar_g': 323, 'vitamin_c_mg': 0.3, 'fiber_g': 0.8, 'calories': 125, 'benefits': 'Maximum sweetness'},
        8: {'name': 'Overripe', 'color': '#FF6347', 'rotten': False, 'sugar_g': 361, 'vitamin_c_mg': 0.3, 'fiber_g': 0.6, 'calories': 130, 'benefits': 'Great for baking'},
        9: {'name': 'Rotten', 'color': '#8B0000', 'rotten': True, 'sugar_g': 373, 'vitamin_c_mg': 0.1, 'fiber_g': 0.3, 'calories': 135, 'benefits': 'Do not consume'}
    },
    'apple': {
        1: {'name': 'Unripe', 'color': '#90EE90', 'rotten': False, 'sugar_g': 8, 'vitamin_c_mg': 5, 'fiber_g': 2.5, 'calories': 52, 'benefits': 'Firm and tart'},
        2: {'name': 'Ripe', 'color': '#ADFF2F', 'rotten': False, 'sugar_g': 12, 'vitamin_c_mg': 7, 'fiber_g': 3.0, 'calories': 58, 'benefits': 'Balanced flavor'},
        3: {'name': 'Rotten', 'color': '#8B0000', 'rotten': True, 'sugar_g': 18, 'vitamin_c_mg': 4, 'fiber_g': 1.5, 'calories': 65, 'benefits': 'Do not consume'}
    },
    'orange': {
        1: {'name': 'Very Unripe', 'color': '#90EE90', 'rotten': False, 'sugar_g': 6, 'vitamin_c_mg': 57, 'fiber_g': 2.0, 'calories': 45, 'benefits': 'High citric acid'},
        2: {'name': 'Unripe', 'color': '#98FB98', 'rotten': False, 'sugar_g': 7, 'vitamin_c_mg': 52, 'fiber_g': 2.2, 'calories': 50, 'benefits': 'Tart flavor'},
        3: {'name': 'Ripe', 'color': '#FFA500', 'rotten': False, 'sugar_g': 9, 'vitamin_c_mg': 47, 'fiber_g': 2.5, 'calories': 60, 'benefits': 'Sweet and tangy'},
        4: {'name': 'Very Ripe', 'color': '#FF8C00', 'rotten': False, 'sugar_g': 8, 'vitamin_c_mg': 48, 'fiber_g': 2.3, 'calories': 65, 'benefits': 'Max juiciness'},
        5: {'name': 'Rotten', 'color': '#8B0000', 'rotten': True, 'sugar_g': 8, 'vitamin_c_mg': 50, 'fiber_g': 1.5, 'calories': 70, 'benefits': 'Do not consume'}
    },
    'mango': {
        1: {'name': 'Very Unripe', 'color': '#90EE90', 'rotten': False, 'sugar_g': 5, 'vitamin_c_mg': 20, 'fiber_g': 3.0, 'calories': 50, 'benefits': 'Crunchy, for salads'},
        2: {'name': 'Unripe', 'color': '#98FB98', 'rotten': False, 'sugar_g': 10, 'vitamin_c_mg': 30, 'fiber_g': 2.5, 'calories': 65, 'benefits': 'Firm texture'},
        3: {'name': 'Ripe', 'color': '#FFD700', 'rotten': False, 'sugar_g': 18, 'vitamin_c_mg': 45, 'fiber_g': 2.0, 'calories': 80, 'benefits': 'Sweet and juicy'},
        4: {'name': 'Rotten', 'color': '#8B0000', 'rotten': True, 'sugar_g': 22, 'vitamin_c_mg': 25, 'fiber_g': 1.0, 'calories': 90, 'benefits': 'Do not consume'}
    }
}

with open('nutrients.json', 'w') as f:
    json.dump(NUTRIENT_DB, f, indent=4)
print("✅ Nutrients exported to nutrients.json")
