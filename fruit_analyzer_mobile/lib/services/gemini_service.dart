import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  final String _apiKey = 'AIzaSyDz3E4FPdGdc_O2Na9pTqNzh1vzxSGf3yA';
  final String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';

  Future<String> getAISuggestions(String fruit, {bool isRotten = false}) async {
    final prompt = isRotten
        ? "Give me 5 creative non-food household uses for a rotten $fruit. Keep it concise and practical."
        : "Give me 3-4 quick and healthy recipe ideas for a very ripe $fruit. Keep descriptions brief and helpful.";

    final url = Uri.parse('$_baseUrl?key=$_apiKey');
    
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String text = data['candidates'][0]['content']['parts'][0]['text'];
        return text.trim();
      } else {
        print('Gemini API Error: ${response.statusCode} - ${response.body}');
        return "Sorry, I couldn't generate suggestions right now. (Status: ${response.statusCode})";
      }
    } catch (e) {
      print('Gemini Service Exception: $e');
      return "Error connecting to AI service. Please check your internet.";
    }
  }
}
