import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class PredictionResult {
  final String fruit;
  final int stage;
  final String stageName;
  final double confidence;
  final bool isRotten;
  final String color;
  final Map<String, dynamic>? nutrients;
  final bool cvRottenDetected;
  final Map<String, dynamic> metadata;

  PredictionResult({
    required this.fruit,
    required this.stage,
    required this.stageName,
    required this.confidence,
    required this.isRotten,
    required this.color,
    this.nutrients,
    required this.cvRottenDetected,
    required this.metadata,
  });
}

class PredictionService {
  OrtSession? _session;
  Map<String, dynamic>? _nutrientDb;
  Map<String, dynamic>? _modelInfo;
  bool _isInitialized = false;
  String _activeModelName = "Default ResNet18";
  bool hybridEnabled = false;

  bool get isInitialized => _isInitialized;
  String get activeModelName => _activeModelName;

  Future<void> init() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    final customModelPath = prefs.getString('custom_model_path');
    final customInfoPath = prefs.getString('custom_info_path');
    _activeModelName = prefs.getString('active_model_name') ?? "Default ResNet18";

    if (customModelPath != null && File(customModelPath).existsSync() &&
        customInfoPath != null && File(customInfoPath).existsSync()) {
      try {
        final modelBytes = await File(customModelPath).readAsBytes();
        _session = OrtSession.fromBuffer(modelBytes, OrtSessionOptions());
        final String infoStr = await File(customInfoPath).readAsString();
        _modelInfo = Map<String, dynamic>.from(json.decode(infoStr));
      } catch (e) {
        print("Error loading custom model: $e");
        await _loadDefaultModel();
      }
    } else {
      await _loadDefaultModel();
    }

    // Load Nutrient DB with proper casting
    final nutrientsJson = await rootBundle.loadString('assets/data/nutrients.json');
    _nutrientDb = Map<String, dynamic>.from(json.decode(nutrientsJson));

    _isInitialized = true;
  }

  Future<void> _loadDefaultModel() async {
    final byteData = await rootBundle.load('assets/model/fruit_model.onnx');
    final modelBytes = byteData.buffer.asUint8List();
    _session = OrtSession.fromBuffer(modelBytes, OrtSessionOptions());

    final infoJson = await rootBundle.loadString('assets/data/model_info.json');
    _modelInfo = Map<String, dynamic>.from(json.decode(infoJson));
    _activeModelName = "Default ResNet18";
  }

  Future<void> updateModel(Uint8List onnxBytes, Map<String, dynamic> info, String name) async {
    final directory = await getApplicationDocumentsDirectory();
    final modelFile = File('${directory.path}/custom_model.onnx');
    final infoFile = File('${directory.path}/custom_info.json');

    await modelFile.writeAsBytes(onnxBytes);
    await infoFile.writeAsString(json.encode(info));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_model_path', modelFile.path);
    await prefs.setString('custom_info_path', infoFile.path);
    await prefs.setString('active_model_name', name);

    _session?.release();
    _session = OrtSession.fromBuffer(onnxBytes, OrtSessionOptions());
    _modelInfo = info;
    _activeModelName = name;
  }

  Future<void> resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_model_path');
    await prefs.remove('custom_info_path');
    await prefs.remove('active_model_name');
    
    _session?.release();
    _isInitialized = false;
    await init();
  }

  // Softmax Implementation
  List<double> _softmax(List<double> logits) {
    double maxLogit = logits.reduce(max);
    List<double> exps = logits.map((l) => exp(l - maxLogit)).toList();
    double sumExps = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sumExps).toList();
  }

  // --- REFINED CV LOGIC (Kept but only active if hybridEnabled is true) ---
  bool isRottenCV(img.Image image, String fruit) {
    int brownCount = 0;
    int darkCount = 0;
    int moldCount = 0;
    int totalPixels = image.width * image.height;

    bool isWarmColorFruit = (fruit.toLowerCase() == 'orange' || fruit.toLowerCase() == 'mango');
    double brownRatioThreshold = isWarmColorFruit ? 0.30 : 0.15;
    double darkRatioThreshold = isWarmColorFruit ? 0.45 : 0.35;

    for (var pixel in image) {
      double r = pixel.r / 255.0;
      double g = pixel.g / 255.0;
      double b = pixel.b / 255.0;

      double maxVal = [r, g, b].reduce(max);
      double minVal = [r, g, b].reduce(min);
      double delta = maxVal - minVal;

      double h = 0;
      if (delta != 0) {
        if (maxVal == r) h = (g - b) / delta % 6;
        else if (maxVal == g) h = (b - r) / delta + 2;
        else h = (r - g) / delta + 4;
        h *= 60;
      }
      if (h < 0) h += 360;

      double s = maxVal == 0 ? 0 : delta / maxVal;
      double v = maxVal;

      if (isWarmColorFruit) {
         if (h >= 5 && h <= 50 && s >= 0.2 && s <= 0.65 && v >= 0.05 && v <= 0.55) {
           brownCount++;
         }
      }
      
      if (fruit.toLowerCase() == 'apple') {
        if (h >= 10 && h <= 60 && s >= 0.18 && v >= 0.08 && v <= 0.65) {
          brownCount++;
        }
      }

      if (v < 0.12) {
        darkCount++;
      }

      if (h >= 60 && h <= 200 && s <= 0.25 && v >= 0.25) {
        moldCount++;
      }
    }

    double brownRatio = brownCount / totalPixels;
    double darkRatio = darkCount / totalPixels;
    double moldRatio = moldCount / totalPixels;

    if (fruit.toLowerCase() == 'banana') {
      // Ignore small black speckles (normal ripening)
      if (brownRatio < 0.25 && darkRatio < 0.30) {
        return false;
      }
    }

    return (brownRatio >= brownRatioThreshold) || (darkRatio >= darkRatioThreshold) || (moldRatio >= 0.06);
  }

  Future<PredictionResult?> predict(String imagePath, {String selectedFruit = 'auto'}) async {
    if (!_isInitialized) await init();
    final imageBytes = await File(imagePath).readAsBytes();
    final rawImage = img.decodeImage(imageBytes);
    if (rawImage == null) {
      throw Exception("Image decoding failed");
    }
    // --- Resize ---
    final imgOrig = img.copyResize(rawImage, width: 224, height: 224);

    // --- Preprocess ---
    final inputOrig = _preprocess(imgOrig);
    final imgFlip = img.copyFlip(imgOrig, direction: img.FlipDirection.horizontal);
    final inputFlip = _preprocess(imgFlip);

    // --- Inference ---
    final runOptions = OrtRunOptions();
    final outputOrig = _session!.run(runOptions, {'input': _createTensor(inputOrig)});
    final outputFlip = _session!.run(runOptions, {'input': _createTensor(inputFlip)});

    // --- Extract logits safely ---
    if (outputOrig.isEmpty || outputFlip.isEmpty) {
      throw Exception("Model output is empty");
    }

    final logitsOrig = List<double>.from((outputOrig[0]!.value as List<List<double>>)[0]);
    final logitsFlip = List<double>.from((outputFlip[0]!.value as List<List<double>>)[0]);

    if (logitsOrig.length != logitsFlip.length) {
      throw Exception("Logit size mismatch between TTA passes");
    }

    // --- ✅ CORRECT TTA: average logits, NOT probabilities ---
    final avgLogits = List<double>.generate(
      logitsOrig.length,
      (i) => (logitsOrig[i] + logitsFlip[i]) / 2.0,
    );

    final probs = _softmax(avgLogits);

    // --- Class names ---
    final classNames = List<String>.from(_modelInfo!['class_names'] ?? []);
    if (classNames.isEmpty) {
      throw Exception("class_names missing in model_info");
    }

    if (probs.length != classNames.length) {
      throw Exception("Mismatch: probs=${probs.length}, classes=${classNames.length}");
    }

    // --- Optional fruit filter (robust) ---
    List<double> filteredProbs = List.from(probs);

    if (selectedFruit != 'auto') {
      final fruitKey = selectedFruit.toLowerCase().trim();

      double sum = 0.0;
      for (int i = 0; i < filteredProbs.length; i++) {
        final label = classNames[i].toLowerCase();

        if (!label.contains('${fruitKey}_stage_')) {
          filteredProbs[i] = 0.0;
        }

        sum += filteredProbs[i];
      }

      // Renormalize safely
      if (sum > 1e-6) {
        for (int i = 0; i < filteredProbs.length; i++) {
          filteredProbs[i] /= sum;
        }
      } else {
        // fallback: revert to original probs
        filteredProbs = List.from(probs);
      }
    }

    // --- Argmax ---
    int bestIdx = 0;
    double bestProb = filteredProbs[0];

    for (int i = 1; i < filteredProbs.length; i++) {
      if (filteredProbs[i] > bestProb) {
        bestProb = filteredProbs[i];
        bestIdx = i;
      }
    }

    // --- Validate index ---
    if (bestIdx >= classNames.length) {
      throw Exception("Invalid prediction index: $bestIdx");
    }

    final finalLabel = classNames[bestIdx];

    // --- Parse label STRICTLY ---
    if (!finalLabel.contains('_stage_')) {
      throw Exception("Malformed label: $finalLabel");
    }

    final parts = finalLabel.split('_stage_');
    if (parts.length != 2) {
      throw Exception("Invalid label format: $finalLabel");
    }

    final fruit = parts[0].trim().toLowerCase();

    final stage = int.tryParse(parts[1]);
    if (stage == null) {
      throw Exception("Stage parsing failed for label: $finalLabel");
    }

    // --- DB lookup (STRICT, no silent fallback) ---
    if (!_nutrientDb!.containsKey(fruit)) {
      throw Exception("Fruit not found in DB: $fruit");
    }

    final fruitData = Map<String, dynamic>.from(_nutrientDb![fruit]);

    final stageKey = stage.toString();
    if (!fruitData.containsKey(stageKey)) {
      throw Exception("Stage $stageKey missing for fruit $fruit");
    }

    final stageData = Map<String, dynamic>.from(fruitData[stageKey]);

    // --- Rotten logic ---
    bool isRottenFinal = stageData['rotten'] ?? false;

    bool isRottenCVDetected = false;
    if (hybridEnabled) {
      isRottenCVDetected = isRottenCV(imgOrig, fruit);
    }

    // --- Hybrid override (optional) ---
    String decisionSource = "CNN";
    List<String> corrections = [];

    if (hybridEnabled) {
      if (isRottenCVDetected && bestProb < 0.95) {
        isRottenFinal = true;
        decisionSource = "Hybrid";
        corrections.add("CV override");
      }
    }

    // --- Debug logs (KEEP during testing) ---
    print("Prediction Debug:");
    print("  Label: $finalLabel");
    print("  Fruit: $fruit | Stage: $stage");
    print("  Confidence: $bestProb");

    return PredictionResult(
      fruit: fruit,
      stage: stage,
      stageName: stageData['name'] ?? 'Unknown',
      confidence: bestProb.clamp(0.0, 1.0),
      isRotten: isRottenFinal,
      color: stageData['color'] ?? '#808080',
      nutrients: stageData,
      cvRottenDetected: isRottenCVDetected,
      metadata: {
        'decision_source': decisionSource,
        'corrections': corrections,
        'hybrid_active': hybridEnabled
      },
    );
  }

  Float32List _preprocess(img.Image resizedImage) {
    final Float32List inputData = Float32List(1 * 3 * 224 * 224);
    final mean = [0.485, 0.456, 0.406];
    final std = [0.229, 0.224, 0.225];

    int pixelCount = 0;
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resizedImage.getPixel(x, y);
        inputData[pixelCount] = (pixel.r / 255.0 - mean[0]) / std[0];
        inputData[pixelCount + 224 * 224] = (pixel.g / 255.0 - mean[1]) / std[1];
        inputData[pixelCount + 2 * 224 * 224] = (pixel.b / 255.0 - mean[2]) / std[2];
        pixelCount++;
      }
    }
    return inputData;
  }

  OrtValueTensor _createTensor(Float32List data) {
    return OrtValueTensor.createTensorWithDataList(data, [1, 3, 224, 224]);
  }
}
