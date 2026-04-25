import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/prediction_service.dart';
import '../services/notification_service.dart';
import '../services/database_service.dart';
import '../services/cloud_service.dart';
import '../models/user.dart';
import '../models/scan_model.dart';
import 'login_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'raspberry_pi_screen.dart';
import 'scanning_overlay.dart';
import 'recipe_list_widget.dart';

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
  List<String> _batchPaths = [];
  Map<String, PredictionResult> _batchResults = {};
  int _batchIndex = 0;
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
    
    if (!_showCamera) {
      setState(() {
        _showCamera = true;
        _pickedImagePath = null;
        _lastResult = null;
        _status = "Ready to scan";
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = "Capturing...";
    });

    try {
      final xFile = await _controller!.takePicture();
      setState(() {
        _showCamera = false;
        _pickedImagePath = xFile.path;
        _lastResult = null;
        _status = "Image captured. Tap START to analyze.";
      });
    } catch (e) {
      setState(() => _status = "Error: $e");
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _analyzeFromGallery() async {
    if (_isProcessing) return;
    final List<XFile> images = await _picker.pickMultiImage(
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (images.isEmpty) return;

    if (images.length > 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select up to 10 images')));
      return;
    }

    setState(() {
      _showCamera = false;
      _pickedImagePath = images.first.path;
      _batchPaths = images.map((e) => e.path).toList();
      _batchResults = {};
      _batchIndex = 0;
      _lastResult = null;
      _status = images.length > 1 ? "Batch selected (${images.length} images). Tap START." : "Image picked. Tap START to analyze.";
    });
  }

  Future<void> _runBatchAnalysis() async {
    if (_batchPaths.isEmpty) return;

    for (int i = 0; i < _batchPaths.length; i++) {
      if (!mounted) return;
      setState(() {
        _batchIndex = i;
        _pickedImagePath = _batchPaths[i];
        _lastResult = null;
      });
      
      await Future.delayed(const Duration(milliseconds: 500));
      await _runPrediction();
      
      if (_lastResult != null) {
        _batchResults[_batchPaths[i]] = _lastResult!;
      }
    }
    
    setState(() {
      _status = "Batch complete! Tap thumbnails to review.";
    });
  }

  Future<void> _runPrediction() async {
    if (_pickedImagePath == null || _isProcessing) return;

    setState(() {
      _isProcessing = true;
      _status = _batchPaths.length > 1 ? "Analyzing image ${_batchIndex + 1}/${_batchPaths.length}..." : "Analyzing image...";
    });

    try {
      final path = _pickedImagePath!;
      final predictionService = Provider.of<PredictionService>(context, listen: false);
      final result = await predictionService.predict(path, selectedFruit: _selectedFruit);

      if (result != null) {
        String? savedPath;
        if (!widget.user.isGuest) {
          final appDir = await getApplicationDocumentsDirectory();
          final fileName = p.basename(path);
          final newPath = p.join(appDir.path, "scan_${DateTime.now().millisecondsSinceEpoch}_$fileName");
          await File(path).copy(newPath);
          savedPath = newPath;

          final dbService = DatabaseService();
          final scan = Scan(
            userId: widget.user.username,
            imagePath: newPath,
            fruit: result.fruit,
            stage: result.stage,
            stageName: result.stageName,
            confidence: result.confidence,
            isRotten: result.isRotten,
            dateTime: DateTime.now(),
            nutrients: result.nutrients ?? {},
            color: result.color,
          );
          final id = await dbService.insertScan(scan);
          
          // Re-create scan with assigned ID for cloud sync
          final scanWithId = Scan(
            id: id,
            userId: scan.userId,
            imagePath: scan.imagePath,
            fruit: scan.fruit,
            stage: scan.stage,
            stageName: scan.stageName,
            confidence: scan.confidence,
            isRotten: scan.isRotten,
            dateTime: scan.dateTime,
            nutrients: scan.nutrients,
            color: scan.color,
          );

          // Trigger Cloud Backup
          final cloudService = CloudService();
          cloudService.uploadScan(scanWithId, widget.user.username);

          final prefs = await SharedPreferences.getInstance();
          widget.user.analysisCount++;
          await widget.user.save(prefs);
        }

        setState(() {
          _lastResult = result;
          if (_batchPaths.length <= 1) {
            _status = result.isRotten ? "🚫 ROTTEN DETECTED!" : "✅ FRESH FRUIT";
          }
        });

        if (result.isRotten) {
          final prefs = await SharedPreferences.getInstance();
          final settings = NotificationSettings.fromPrefs(prefs);
          final notificationService = NotificationService();
          final msg = '''🚨 ROTTEN ALERT!\nFruit: ${result.fruit}\nConf: ${(result.confidence * 100).toStringAsFixed(1)}%''';
          await notificationService.sendTelegramAlert(settings, msg, imagePath: savedPath ?? path);
        }
      }
    } catch (e) {
      setState(() => _status = "Error: $e");
    } finally {
      setState(() => _isProcessing = false);
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text('FRUIT ANALYZER', 
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2, color: theme.colorScheme.onSurface)
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.1), // Increased opacity
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.menu_rounded, color: theme.colorScheme.onSurface, size: 20),
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        backgroundColor: Colors.transparent,
      ),
      drawer: _buildDrawer(context),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: kToolbarHeight + 40),
              if (_batchPaths.length > 1)
                Container(
                  height: 100,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _batchPaths.length,
                    itemBuilder: (context, index) {
                      final path = _batchPaths[index];
                      final isSelected = _pickedImagePath == path;
                      final result = _batchResults[path];
                      
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _pickedImagePath = path;
                            _batchIndex = index;
                            _lastResult = result;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 80,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? theme.colorScheme.primary : Colors.white10,
                              width: 2,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Positioned.fill(child: Image.file(File(path), fit: BoxFit.cover)),
                              if (result != null)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Icon(
                                    result.isRotten ? Icons.error : Icons.check_circle,
                                    color: result.isRotten ? Colors.red : Colors.green,
                                    size: 16,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10))
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_showCamera)
                        SizedBox.expand(child: CameraPreview(_controller!))
                      else if (_pickedImagePath != null)
                        PhotoView(
                          imageProvider: FileImage(File(_pickedImagePath!)),
                          backgroundDecoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: PhotoViewComputedScale.covered * 4,
                          enableRotation: false,
                        ),
                      
                      // Bottom gradient - IGNORE POINTER to allow zoom
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                                stops: const [0.7, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),

                      if (_isProcessing) const ScanningOverlay(),
                      
                      // Status Pill
                      Positioned(
                        bottom: 24,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurface.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
                          ),
                          child: Text(_status.toUpperCase(), 
                            style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: theme.colorScheme.onSurface)),
                        ),
                      ),

                      // Reset Button (Glassmorphic)
                      if (!_showCamera)
                        Positioned(
                          top: 20,
                          right: 20,
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _showCamera = true;
                              _pickedImagePath = null;
                              _batchPaths = [];
                              _batchResults = {};
                              _lastResult = null;
                              _status = "Ready to scan";
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.onSurface.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
                              ),
                              child: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface, size: 20),
                            ),
                          ),
                        )
                    ],
                  ),
                ),
              ),

              if (_lastResult != null)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _buildModernResultCard(_lastResult!),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Row(
                  children: [
                    _buildIconButton(
                      icon: Icons.photo_library_outlined,
                      onTap: _analyzeFromGallery,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildMainActionButton(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainActionButton() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    bool isStart = !_showCamera && _pickedImagePath != null && _lastResult == null;
    
    return GestureDetector(
      onTap: isStart ? (_batchPaths.length > 1 ? _runBatchAnalysis : _runPrediction) : _analyzeFromCamera,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isStart 
              ? [const Color(0xFF4F8CFF), const Color(0xFF7C5CFF)] 
              : [theme.colorScheme.onSurface.withOpacity(0.1), theme.colorScheme.onSurface.withOpacity(0.05)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isStart ? Colors.white30 : theme.colorScheme.onSurface.withOpacity(0.1)),
          boxShadow: isStart ? [BoxShadow(color: const Color(0xFF4F8CFF).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))] : [],
        ),
        child: Center(
          child: Text(
            isStart ? ( _batchPaths.length > 1 ? "ANALYZE BATCH" : "START ANALYSIS") : "CAPTURE PHOTO",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold, 
              fontSize: 14, 
              letterSpacing: 1, 
              color: isStart ? Colors.white : theme.colorScheme.onSurface
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({required IconData icon, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 64,
        width: 64,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.1)),
        ),
        child: Icon(icon, color: theme.colorScheme.onSurface, size: 24),
      ),
    );
  }

  Widget _buildModernResultCard(PredictionResult result) {
    final theme = Theme.of(context);
    final accentColor = Color(int.parse(result.color.replaceAll('#', '0xff')));
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
        boxShadow: [
          if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.fruit.toUpperCase(), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                  Text(result.stageName, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: result.isRotten ? const Color(0xFFFF5A5F).withOpacity(0.1) : accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: result.isRotten ? const Color(0xFFFF5A5F).withOpacity(0.3) : accentColor.withOpacity(0.3)),
                ),
                child: Text(
                  result.isRotten ? "ROTTEN" : "FRESH",
                  style: TextStyle(color: result.isRotten ? const Color(0xFFFF5A5F) : accentColor, fontWeight: FontWeight.bold, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text("${(result.confidence * 100).toStringAsFixed(0)}%", style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: result.confidence,
                    backgroundColor: theme.colorScheme.onSurface.withOpacity(0.05),
                    color: theme.colorScheme.primary,
                    minHeight: 6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!result.isRotten && result.nutrients != null)
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.5,
              children: [
                _buildMetricPill("Sugar", "${result.nutrients!['sugar_g']}g", Icons.grain_rounded),
                _buildMetricPill("Vit C", "${result.nutrients!['vitamin_c_mg']}mg", Icons.bolt_rounded),
                _buildMetricPill("Fiber", "${result.nutrients!['fiber_g']}g", Icons.grass_rounded),
                _buildMetricPill("Calories", "${result.nutrients!['calories']}", Icons.fire_hydrant_alt_rounded),
              ],
            ),
          
          if (result.isRotten)
             Text("HEALTH HAZARD: DO NOT CONSUME", style: GoogleFonts.poppins(color: const Color(0xFFFF5A5F), fontWeight: FontWeight.bold, fontSize: 12)),
          
          if (result.stage >= (result.fruit == 'banana' ? 7 : 4))
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: _buildRecipeCTA(result.isRotten ? "Discover non-food uses" : "Explore 5-min recipes", isRotten: result.isRotten),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurface.withOpacity(0.6)),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.6))),
              Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Drawer(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 80, 24, 40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark 
                  ? [const Color(0xFF1C1F2A), const Color(0xFF0D0F14)]
                  : [const Color(0xFFFFFFFF), const Color(0xFFF0F2F8)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFF4F8CFF), Color(0xFF7C5CFF)]),
                    boxShadow: [BoxShadow(color: const Color(0xFF4F8CFF).withOpacity(0.3), blurRadius: 15)],
                  ),
                  child: Center(
                    child: Text(widget.user.username[0].toUpperCase(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 20),
                Text(widget.user.username, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                Text(widget.user.isGuest ? "Guest Access" : widget.user.email, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13)),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: CloudService.syncStatus,
                  builder: (context, status, child) {
                    bool isActive = status != "Idle" && status != "Sync Complete";
                    return Row(
                      children: [
                        Icon(
                          status == "Sync Complete" ? Icons.cloud_done : Icons.cloud_sync,
                          size: 14, 
                          color: status.contains("Error") ? Colors.redAccent : (status == "Sync Complete" ? Colors.green : theme.colorScheme.primary),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10, 
                            fontWeight: FontWeight.bold, 
                            letterSpacing: 1,
                            color: status.contains("Error") ? Colors.redAccent : (status == "Sync Complete" ? Colors.green : theme.colorScheme.primary),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)),
                        ]
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _buildDrawerItem(Icons.analytics_outlined, "Analysis Insights", trailing: "${widget.user.analysisCount}"),
                _buildDrawerItem(Icons.settings_remote_rounded, "Pi 5 Remote Control", onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const RaspberryPiScreen()));
                }),
                _buildDrawerItem(Icons.history_rounded, "Scan History", onTap: () {
                  Navigator.pop(context);
                  if (widget.user.isGuest) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History requires account login.')));
                  } else {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(user: widget.user)));
                  }
                }),
                _buildDrawerItem(Icons.settings_outlined, "Settings", onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
                }),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text("TARGET FRUIT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedFruit,
                        isExpanded: true,
                        dropdownColor: theme.cardTheme.color,
                        style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
                        items: _fruitOptions.map((f) => DropdownMenuItem(value: f, child: Text(f.toUpperCase()))).toList(),
                        onChanged: (val) => setState(() => _selectedFruit = val!),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(24),
            child: OutlinedButton(
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen())),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                side: const BorderSide(color: Color(0xFFFF5A5F)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(widget.user.isGuest ? "SIGN IN" : "LOGOUT", style: const TextStyle(color: Color(0xFFFF5A5F), fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, {String? trailing, VoidCallback? onTap}) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurface.withOpacity(0.7), size: 22),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface)),
      trailing: trailing != null ? Text(trailing, style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)) : null,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildRecipeCTA(String message, {required bool isRotten}) {
    return InkWell(
      onTap: () => _showRecipesDialog(_lastResult!.fruit, isRotten: isRotten),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.restaurant_menu, color: Colors.orange, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.orange, size: 14),
          ],
        ),
      ),
    );
  }

  void _showRecipesDialog(String fruit, {required bool isRotten}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (_, controller) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: const EdgeInsets.all(20),
          child: RecipeListWidget(fruit: fruit, isRotten: isRotten, scrollController: controller),
        ),
      ),
    );
  }
}
