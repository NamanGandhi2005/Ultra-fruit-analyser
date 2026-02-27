import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/recipe_service.dart';

class RecipeListWidget extends StatefulWidget {
  final String fruit;
  final bool isRotten;
  final ScrollController scrollController;
  const RecipeListWidget({super.key, required this.fruit, required this.isRotten, required this.scrollController});

  @override
  State<RecipeListWidget> createState() => _RecipeListWidgetState();
}

class _RecipeListWidgetState extends State<RecipeListWidget> {
  final RecipeService _recipeService = RecipeService();
  List<Recipe> _recipes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRecipes();
  }

  Future<void> _fetchRecipes() async {
    final recipes = await _recipeService.getRecipesForFruit(widget.fruit, isRotten: widget.isRotten);
    if (mounted) {
      setState(() {
        _recipes = recipes;
        _isLoading = false;
      });
    }
  }

  Future<void> _launchUrl(String url) async {
    if (!await launchUrl(Uri.parse(url))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    if (_recipes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off, size: 60, color: Colors.grey),
              const SizedBox(height: 16),
              const Text("No API results found.", 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text("The recipe API might be at its daily limit (free tier).", 
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  final query = widget.isRotten ? "${widget.fruit} non food uses" : "best ${widget.fruit} overripe recipes";
                  _launchUrl("https://www.google.com/search?q=$query");
                },
                icon: const Icon(Icons.language),
                label: const Text("OPEN GOOGLE SEARCH"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _fetchRecipes();
                },
                child: const Text("RETRY API FETCH"),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: widget.scrollController,
      itemCount: _recipes.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text("${widget.fruit.toUpperCase()} ${widget.isRotten ? 'USES' : 'RECIPES'}", 
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1)),
                Text(widget.isRotten ? "Non-food ways to use rotten fruit." : "Reduce waste by using overripe fruit!", style: const TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        final recipe = _recipes[index - 1];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: InkWell(
            onTap: () => _launchUrl(recipe.sourceUrl),
            child: Row(
              children: [
                Image.network(recipe.imageUrl, width: 100, height: 100, fit: BoxFit.cover),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      recipe.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
                const SizedBox(width: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}
