import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/prediction_service.dart';
import '../services/notification_service.dart';
import '../models/user.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final User user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String _status = "Ready to scan";
  PredictionResult? _lastResult;
  String _selectedFruit = 'auto';
  final List<String> _fruitOptions = ['auto', 'banana', 'orange', 'mango', 'apple'];
  final ImagePicker _picker = ImagePicker();
  
  String? _pickedImagePath;
  bool _showCamera = true;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras[0], ResolutionPreset.medium, enableAudio: false);
    await _controller!.initialize();
    if (mounted) setState(() => _isInitialized = true);
  }

  Future<void> _analyzeFromCamera() async {
    if (_isProcessing || _controller == null) return;
    
    // Resume camera if it was hidden
    if (!_showCamera) {
      setState(() {
        _showCamera = true;
        _pickedImagePath = null;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = "Capturing...";
    });

    try {
      final xFile = await _controller!.takePicture();
      await _runPrediction(xFile.path);
    } catch (e) {
      setState(() => _status = "Error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _analyzeFromGallery() async {
    if (_isProcessing) return;
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isProcessing = true;
      _showCamera = false;
      _pickedImagePath = image.path;
      _status = "Analyzing gallery image...";
    });

    try {
      await _runPrediction(image.path);
    } catch (e) {
      setState(() => _status = "Error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _runPrediction(String path) async {
    final predictionService = Provider.of<PredictionService>(context, listen: false);
    final result = await predictionService.predict(path, selectedFruit: _selectedFruit);

    if (result != null) {
      setState(() {
        _lastResult = result;
        _status = result.isRotten ? "🚫 ROTTEN DETECTED!" : "✅ FRESH FRUIT";
      });

      // Update User Stats
      final prefs = await SharedPreferences.getInstance();
      widget.user.analysisCount++;
      await widget.user.save(prefs);

      // Notifications
      if (result.isRotten) {
        final settings = NotificationSettings.fromPrefs(prefs);
        final notificationService = NotificationService();
        final msg = '''🚨 ROTTEN ALERT!
Fruit: ${result.fruit}
Conf: ${(result.confidence * 100).toStringAsFixed(1)}%''';
        await notificationService.sendTelegramAlert(settings, msg, imagePath: path);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Fruit Analyzer Pro', 
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 20)
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          // User Stats Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: theme.colorScheme.primary,
                        child: Text(widget.user.username[0].toUpperCase(), 
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      Text(widget.user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text("Analyses: ${widget.user.analysisCount}", 
                    style: TextStyle(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          
          // Fruit Selector Dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedFruit,
                  isExpanded: true,
                  hint: const Text("Filter by fruit type"),
                  items: _fruitOptions.map((f) => DropdownMenuItem(value: f, child: Text(f.toUpperCase(), 
                    style: const TextStyle(fontSize: 14)))).toList(),
                  onChanged: (val) => setState(() => _selectedFruit = val!),
                ),
              ),
            ),
          ),

          // Main View Area (Camera or Picked Image)
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (_showCamera)
                    SizedBox.expand(child: CameraPreview(_controller!))
                  else if (_pickedImagePath != null)
                    SizedBox.expand(child: Image.file(File(_pickedImagePath!), fit: BoxFit.cover)),
                  
                  // Processing Overlay
                  if (_isProcessing) 
                    Container(
                      color: Colors.black54,
                      child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                  
                  // Status Badge
                  Positioned(
                    bottom: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.5)),
                      ),
                      child: Text(_status, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),

                  // Reset to Camera Button
                  if (!_showCamera)
                    Positioned(
                      top: 15,
                      right: 15,
                      child: FloatingActionButton.small(
                        backgroundColor: Colors.white,
                        onPressed: () => setState(() => _showCamera = true),
                        child: const Icon(Icons.camera_alt, color: Colors.black87),
                      ),
                    )
                ],
              ),
            ),
          ),

          // Result Sheet
          if (_lastResult != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 0,
                color: Color(int.parse(_lastResult!.color.replaceAll('#', '0xff'))).withOpacity(0.15),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${_lastResult!.fruit.toUpperCase()} • ${_lastResult!.stageName}",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text("${(_lastResult!.confidence * 100).toStringAsFixed(1)}%", 
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: _lastResult!.confidence,
                          minHeight: 8,
                          backgroundColor: Colors.white12,
                          color: Color(int.parse(_lastResult!.color.replaceAll('#', '0xff'))),
                        ),
                      ),
                      if (_lastResult!.isRotten) ...[
                        const SizedBox(height: 12),
                        const Text("🚫 DO NOT CONSUME. Health hazard detected.", 
                          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ] else if (_lastResult!.nutrients != null) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 0,
                          children: [
                            _statLabel("Sugar", "${_lastResult!.nutrients!['sugar_g']}g"),
                            _statLabel("Vit C", "${_lastResult!.nutrients!['vitamin_c_mg']}mg"),
                            _statLabel("Fiber", "${_lastResult!.nutrients!['fiber_g']}g"),
                            _statLabel("Cal", "${_lastResult!.nutrients!['calories']}"),
                          ],
                        ),
                      ]
                    ],
                  ),
                ),
              ),
            ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _analyzeFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text("GALLERY"),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: theme.colorScheme.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _analyzeFromCamera,
                    icon: Icon(_showCamera ? Icons.camera : Icons.refresh),
                    label: Text(_showCamera ? "ANALYZE NOW" : "RESUME CAMERA"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 4,
                      shadowColor: theme.colorScheme.primary.withOpacity(0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _statLabel(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(8)),
      child: Text("$label: $value", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
    );
  }
}
