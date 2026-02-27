import 'dart:convert';
import 'package:http/http.dart' as http;

class Recipe {
  final String title;
  final String imageUrl;
  final String sourceUrl;
  final bool isLocal;

  Recipe({required this.title, required this.imageUrl, required this.sourceUrl, this.isLocal = false});

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      title: json['title'] ?? 'Unknown Recipe',
      imageUrl: json['image'] ?? '',
      sourceUrl: json['sourceUrl'] ?? 'https://spoonacular.com',
    );
  }
}

class RecipeService {
  static const String _apiKey = 'c7a40660655d4094a9191d57922d56d7'; 
  static const String _baseUrl = 'https://api.spoonacular.com/recipes';

  // LOCAL KNOWLEDGE BASE (Guaranteed to work offline and without API limits)
  final Map<String, List<Recipe>> _localRecipes = {
    'banana': [
      Recipe(
        title: 'Ultimate 5-Minute Banana Bread', 
        imageUrl: 'https://images.unsplash.com/photo-1538083024336-555cf8943ddc?w=400', 
        sourceUrl: 'https://www.allrecipes.com/recipe/20144/banana-banana-bread/',
        isLocal: true,
      ),
      Recipe(
        title: 'Healthy Banana Smoothie', 
        imageUrl: 'https://images.unsplash.com/photo-1550583724-b26ec2d97618?w=400', 
        sourceUrl: 'https://www.foodnetwork.com/recipes/banana-smoothie-recipe-1943563',
        isLocal: true,
      ),
    ],
    'mango': [
      Recipe(
        title: 'Quick Mango Chutney', 
        imageUrl: 'https://images.unsplash.com/photo-1591073113125-e46713c829ed?w=400', 
        sourceUrl: 'https://www.simplyrecipes.com/recipes/mango_chutney/',
        isLocal: true,
      ),
      Recipe(
        title: 'Mango Sorbet (2 Ingredients)', 
        imageUrl: 'https://images.unsplash.com/photo-1505322101000-19457cff32ba?w=400', 
        sourceUrl: 'https://www.allrecipes.com/recipe/237513/easy-mango-sorbet/',
        isLocal: true,
      ),
    ],
    'apple': [
      Recipe(
        title: 'Classic Apple Sauce', 
        imageUrl: 'https://images.unsplash.com/photo-1567306226416-28f0efdc88ce?w=400', 
        sourceUrl: 'https://www.simplyrecipes.com/recipes/applesauce/',
        isLocal: true,
      ),
      Recipe(
        title: 'Easy Apple Crisp', 
        imageUrl: 'https://images.unsplash.com/photo-1568571780765-9276ac8b75a2?w=400', 
        sourceUrl: 'https://www.allrecipes.com/recipe/12409/apple-crisp-ii/',
        isLocal: true,
      ),
    ],
    'orange': [
      Recipe(
        title: 'Fresh Orange Marmalade', 
        imageUrl: 'https://images.unsplash.com/photo-1589927986089-35812388d1f4?w=400', 
        sourceUrl: 'https://www.allrecipes.com/recipe/24514/orange-marmalade/',
        isLocal: true,
      ),
      Recipe(
        title: 'Orange Glazed Chicken', 
        imageUrl: 'https://images.unsplash.com/photo-1527477396000-e27163b481c2?w=400', 
        sourceUrl: 'https://www.foodnetwork.com/recipes/food-network-kitchen/orange-chicken-3363255',
        isLocal: true,
      ),
    ],
  };

  Future<List<Recipe>> getRecipesForFruit(String fruit, {bool isRotten = false}) async {
    final cleanFruit = fruit.toLowerCase().trim();
    
    // 1. Try Local first (Instant & Reliable)
    if (_localRecipes.containsKey(cleanFruit)) {
      return _localRecipes[cleanFruit]!;
    }

    // 2. Fallback to API if not in local DB
    return _fetchFromApi(cleanFruit, isRotten: isRotten);
  }

  Future<List<Recipe>> _fetchFromApi(String fruit, {bool isRotten = false}) async {
    final query = isRotten ? '$fruit household uses' : '$fruit recipes';
    final url = '$_baseUrl/complexSearch?apiKey=$_apiKey&query=$query&number=5&addRecipeInformation=true';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List results = data['results'] ?? [];
        return results.map((json) => Recipe.fromJson(json)).toList();
      }
    } catch (e) {
      print('Recipe API Error: $e');
    }
    return [];
  }
}
