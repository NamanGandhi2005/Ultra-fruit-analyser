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

      if (fruit.toLowerCase() == 'banana') {
        // Ignore small black speckles (normal ripening)
        if (brownRatio < 0.25 && darkRatio < 0.30) {
          return false;
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

    return (brownRatio >= brownRatioThreshold) || (darkRatio >= darkRatioThreshold) || (moldRatio >= 0.06);
  }

  Future<PredictionResult?> predict(String imagePath, {String selectedFruit = 'auto'}) async {
    if (!_isInitialized) await init();

    final imageBytes = await File(imagePath).readAsBytes();
    final rawImage = img.decodeImage(imageBytes);
    if (rawImage == null) return null;

    final imgOrig = img.copyResize(rawImage, width: 224, height: 224);
    final inputOrig = _preprocess(imgOrig);
    final imgFlip = img.copyFlip(imgOrig, direction: img.FlipDirection.horizontal);
    final inputFlip = _preprocess(imgFlip);

    final runOptions = OrtRunOptions();
    final outputOrig = _session!.run(runOptions, {'input': _createTensor(inputOrig)});
    final outputFlip = _session!.run(runOptions, {'input': _createTensor(inputFlip)});

    // Extract Logits
    final List<double> logitsOrig = List<double>.from((outputOrig[0]?.value as List<List<double>>)[0]);
    final List<double> logitsFlip = List<double>.from((outputFlip[0]?.value as List<List<double>>)[0]);
    
    // Apply Softmax
    List<double> probsOrig = _softmax(logitsOrig);
    List<double> probsFlip = _softmax(logitsFlip);

    int probLen = min(probsOrig.length, probsFlip.length);
    List<double> avgProbs = List.generate(probLen, (i) => (probsOrig[i] + probsFlip[i]) / 2.0);

    List<String> classNames = List<String>.from(_modelInfo!['class_names'] ?? []);

    if (selectedFruit != 'auto') {
      double sum = 0;
      String filter = selectedFruit.toLowerCase() + "_";
      for (int i = 0; i < avgProbs.length; i++) {
        if (i >= classNames.length) {
          avgProbs[i] = 0;
          continue;
        }
        String label = classNames[i].toLowerCase();
        if (!label.startsWith(filter)) {
          avgProbs[i] = 0;
        }
        sum += avgProbs[i];
      }

      if (sum > 0.001) {
        for (int i = 0; i < avgProbs.length; i++) avgProbs[i] /= sum;
      } else {
        avgProbs = List.generate(probLen, (i) => (probsOrig[i] + probsFlip[i]) / 2.0);
      }
    }

    int bestIdx = 0;
    double maxProb = -1.0;
    for (int i = 0; i < avgProbs.length; i++) {
      if (avgProbs[i] > maxProb) {
        maxProb = avgProbs[i];
        bestIdx = i;
      }
    }

    String finalLabel = bestIdx < classNames.length ? classNames[bestIdx] : "unknown_0";
    double finalConf = maxProb;

    final parts = finalLabel.split('_stage_');
    String fruit = parts[0];
    int stage = parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : 1;

    String decisionSource = "CNN Inference";
    List<String> corrections = [];

    double brownThresh = (fruit.toLowerCase() == 'orange') ? 0.60 : 0.40;

    bool isRottenCVDetected = false;
    if (hybridEnabled) {
      isRottenCVDetected = isRottenCV(imgOrig, fruit);
    }
    
    var fruitData = Map<String, dynamic>.from(_nutrientDb![fruit.toLowerCase()] ?? _nutrientDb![fruit] ?? {});
    var stageData = Map<String, dynamic>.from(fruitData[stage.toString()] ?? {});
    bool isRottenFinal = stageData['rotten'] ?? false;

    if (hybridEnabled) {

      if (isRottenCVDetected && finalConf < 0.95) {
        isRottenFinal = true;
        decisionSource = "Hybrid Fusion";
        corrections.add("CV Rot Detection Override");
      }
      
      if (isRottenFinal && !isRottenCVDetected && finalConf < 0.85) {
        int bestFreshIdx = -1;
        double bestFreshConf = -1.0;

        for (int i = 0; i < avgProbs.length; i++) {
          if (i >= classNames.length) break;
          String label = classNames[i];
          if (label.startsWith(fruit) && label != finalLabel) {
            final p = label.split('_stage_');
            if (p.length > 1) {
              int s = int.tryParse(p[1]) ?? 1;
              var sData = Map<String, dynamic>.from(fruitData[s.toString()] ?? {});
              if (!(sData['rotten'] ?? false)) {
                if (avgProbs[i] > (finalConf * 0.45)) {
                  if (avgProbs[i] > bestFreshConf) {
                    bestFreshConf = avgProbs[i];
                    bestFreshIdx = i;
                  }
                }
              }
            }
          }
        }

        if (bestFreshIdx != -1) {
          finalLabel = classNames[bestFreshIdx];
          finalConf = bestFreshConf;
          stage = int.tryParse(finalLabel.split('_stage_')[1]) ?? 1;
          stageData = Map<String, dynamic>.from(fruitData[stage.toString()] ?? {});
          isRottenFinal = false;
          decisionSource = "Hybrid Fusion";
          corrections.add("Heuristic-Guided Fresh Correction");
        }
      }

      if (isRottenCVDetected && !isRottenFinal && finalConf < 0.95) {
        isRottenFinal = true;
        decisionSource = "Hybrid Fusion";
        corrections.add("CV Rot Detection Override");
        
        String? rottenStageKey;
        fruitData.forEach((key, value) {
          if (value is Map && value['rotten'] == true) {
            rottenStageKey = key;
          }
        });
        
        if (rottenStageKey != null) {
          stage = int.tryParse(rottenStageKey!) ?? stage;
          stageData = Map<String, dynamic>.from(fruitData[rottenStageKey] ?? {});
        }
      }
    }

    return PredictionResult(
      fruit: fruit,
      stage: stage,
      stageName: stageData['name'] ?? 'Unidentified',
      confidence: finalConf.clamp(0.0, 1.0),
      isRotten: isRottenFinal,
      color: stageData['color'] ?? '#808080',
      nutrients: stageData,
      cvRottenDetected: isRottenCVDetected,
      metadata: {
        'decision_source': decisionSource,
        'corrections': corrections,
        'cv_rot': isRottenCVDetected,
        'hybrid_active': hybridEnabled,
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
