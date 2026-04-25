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

  PredictionResult({
    required this.fruit,
    required this.stage,
    required this.stageName,
    required this.confidence,
    required this.isRotten,
    required this.color,
    this.nutrients,
    required this.cvRottenDetected,
  });
}

class PredictionService {
  OrtSession? _session;
  Map<String, dynamic>? _nutrientDb;
  Map<String, dynamic>? _modelInfo;
  bool _isInitialized = false;
  String _activeModelName = "Default ResNet18";

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
        _modelInfo = json.decode(await File(customInfoPath).readAsString());
      } catch (e) {
        print("Error loading custom model: $e");
        await _loadDefaultModel();
      }
    } else {
      await _loadDefaultModel();
    }

    // Load Nutrient DB (constant across models)
    final nutrientsJson = await rootBundle.loadString('assets/data/nutrients.json');
    _nutrientDb = json.decode(nutrientsJson);

    _isInitialized = true;
  }

  Future<void> _loadDefaultModel() async {
    final byteData = await rootBundle.load('assets/model/fruit_model.onnx');
    final modelBytes = byteData.buffer.asUint8List();
    _session = OrtSession.fromBuffer(modelBytes, OrtSessionOptions());

    final infoJson = await rootBundle.loadString('assets/data/model_info.json');
    _modelInfo = json.decode(infoJson);
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

  // --- PORTED CV LOGIC ---
  bool isRottenCV(img.Image image, {double brownThreshold = 0.40, double darkThreshold = 0.60}) {
    int brownCount = 0;
    int darkCount = 0;
    int moldCount = 0;
    int totalPixels = image.width * image.height;

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

      if (h >= 5 && h <= 35 && s >= 0.3 && v <= 0.6) {
        brownCount++;
      }
      if (v < 0.15) {
        darkCount++;
      }
      if (h >= 75 && h <= 105 && s >= 0.2 && v >= 0.2) {
        moldCount++;
      }
    }

    double brownRatio = brownCount / totalPixels;
    double darkRatio = darkCount / totalPixels;
    double moldRatio = moldCount / totalPixels;

    return (brownRatio >= brownThreshold) || (darkRatio >= darkThreshold) || (moldRatio >= 0.05);
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

    final probsOrig = (outputOrig[0]?.value as List<List<double>>)[0];
    final probsFlip = (outputFlip[0]?.value as List<List<double>>)[0];
    List<double> avgProbs = List.generate(probsOrig.length, (i) => (probsOrig[i] + probsFlip[i]) / 2.0);

    if (selectedFruit != 'auto') {
      double sum = 0;
      for (int i = 0; i < avgProbs.length; i++) {
        String label = _modelInfo!['class_names'][i];
        if (!label.toLowerCase().contains(selectedFruit.toLowerCase())) {
          avgProbs[i] = 0;
        }
        sum += avgProbs[i];
      }
      if (sum > 0) {
        for (int i = 0; i < avgProbs.length; i++) avgProbs[i] /= sum;
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

    String finalLabel = _modelInfo!['class_names'][bestIdx];
    double finalConf = maxProb;

    final parts = finalLabel.split('_stage_');
    String fruit = parts[0];
    int stage = int.parse(parts[1]);

    bool isRottenCVDetected = isRottenCV(imgOrig);
    bool dbSaysRotten = _nutrientDb![fruit][stage.toString()]['rotten'];
    
    if (dbSaysRotten && !isRottenCVDetected && finalConf < 0.95) {
      double requiredFreshConf = finalConf < 0.60 ? 0.15 : 0.30;
      int bestFreshIdx = -1;
      double bestFreshConf = -1.0;

      for (int i = 0; i < avgProbs.length; i++) {
        String label = _modelInfo!['class_names'][i];
        if (label.startsWith(fruit) && label != finalLabel) {
          final p = label.split('_stage_');
          int s = int.parse(p[1]);
          if (!_nutrientDb![fruit][s.toString()]['rotten']) {
            if (avgProbs[i] > requiredFreshConf && avgProbs[i] > (finalConf * 0.7)) {
              if (avgProbs[i] > bestFreshConf) {
                bestFreshConf = avgProbs[i];
                bestFreshIdx = i;
              }
            }
          }
        }
      }

      if (bestFreshIdx != -1) {
        finalLabel = _modelInfo!['class_names'][bestFreshIdx];
        finalConf = bestFreshConf;
        stage = int.parse(finalLabel.split('_stage_')[1]);
        dbSaysRotten = false;
      }
    }

    bool isRottenFinal = dbSaysRotten || isRottenCVDetected;
    final resultData = _nutrientDb![fruit][stage.toString()];

    return PredictionResult(
      fruit: fruit,
      stage: stage,
      stageName: resultData['name'],
      confidence: finalConf,
      isRotten: isRottenFinal,
      color: resultData['color'],
      nutrients: resultData,
      cvRottenDetected: isRottenCVDetected,
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
