import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/gemini_service.dart';

class RecipeListWidget extends StatefulWidget {
  final String fruit;
  final bool isRotten;
  final ScrollController scrollController;
  const RecipeListWidget({super.key, required this.fruit, required this.isRotten, required this.scrollController});

  @override
  State<RecipeListWidget> createState() => _RecipeListWidgetState();
}

class _RecipeListWidgetState extends State<RecipeListWidget> {
  final GeminiService _geminiService = GeminiService();
  String _suggestions = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAISuggestions();
  }

  Future<void> _fetchAISuggestions() async {
    final suggestions = await _geminiService.getAISuggestions(widget.fruit, isRotten: widget.isRotten);
    if (mounted) {
      setState(() {
        _suggestions = suggestions;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.orange),
            const SizedBox(height: 16),
            Text("AI is thinking...", style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: widget.scrollController,
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
          const SizedBox(height: 24),
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
              Text(
                "GEMINI AI SUGGESTIONS",
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold, 
                  letterSpacing: 1.2,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.isRotten 
                ? "Sustainable ways to use your rotten ${widget.fruit}" 
                : "Quick & healthy ideas for your ${widget.fruit}",
            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13),
          ),
          const Divider(height: 40),
          MarkdownBody(
            data: _suggestions,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: theme.colorScheme.onSurface, height: 1.5, fontSize: 15),
              h3: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, height: 2),
              listBullet: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() => _isLoading = true);
                _fetchAISuggestions();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text("GENERATE NEW IDEAS"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
