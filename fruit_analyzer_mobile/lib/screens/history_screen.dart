import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import '../models/scan_model.dart';
import '../models/user.dart';
import '../services/database_service.dart';
import '../services/cloud_service.dart';

class HistoryScreen extends StatefulWidget {
  final User user;
  const HistoryScreen({super.key, required this.user});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DatabaseService _dbService = DatabaseService();
  final CloudService _cloudService = CloudService();
  List<Scan> _scans = [];
  bool _isLoading = true;
  String _filterFruit = 'All';
  final List<String> _fruits = ['All', 'Banana', 'Orange', 'Mango', 'Apple'];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    
    // Attempt to upload any scans that failed previously (e.g. offline)
    await _cloudService.syncPendingScans(widget.user.username);

    // Sync from cloud first to recover missing items
    await _cloudService.syncDown(widget.user.username);

    final scans = _filterFruit == 'All' 
      ? await _dbService.getAllScans(widget.user.username) 
      : await _dbService.getScansByFruit(widget.user.username, _filterFruit.toLowerCase());
    
    if (!mounted) return;
    setState(() {
      _scans = scans;
      _isLoading = false;
    });
  }

  Future<void> _deleteScan(Scan scan) async {
    if (scan.id != null) {
      await _dbService.deleteScan(scan.id!);
      await _cloudService.deleteScan(widget.user.username, scan.dateTime.millisecondsSinceEpoch.toString());
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('HISTORY', 
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2, color: theme.colorScheme.onSurface)
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: _fruits.map((fruit) {
                final isSelected = _filterFruit == fruit;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _filterFruit = fruit);
                      _loadHistory();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: isSelected ? Colors.white30 : theme.colorScheme.onSurface.withOpacity(0.1)),
                        boxShadow: [
                          if (isSelected) BoxShadow(color: theme.colorScheme.primary.withOpacity(0.3), blurRadius: 10),
                          if (!isDark && !isSelected) BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4),
                        ],
                      ),
                      child: Text(
                        fruit,
                        style: TextStyle(
                          color: isSelected ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.6),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: theme.colorScheme.primary))
                : _scans.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _scans.length,
                        itemBuilder: (context, index) {
                          final scan = _scans[index];
                          return _buildModernScanCard(scan);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 80, color: theme.colorScheme.onSurface.withOpacity(0.1)),
          const SizedBox(height: 24),
          Text("NO SCAN HISTORY", 
            style: GoogleFonts.poppins(fontSize: 14, color: theme.colorScheme.onSurface.withOpacity(0.4), fontWeight: FontWeight.bold, letterSpacing: 2)),
          const SizedBox(height: 8),
          Text("Your AI analysis results will appear here.", 
            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildModernScanCard(Scan scan) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dateStr = DateFormat('MMM dd • hh:mm a').format(scan.dateTime);
    final statusColor = Color(int.parse(scan.color.replaceAll('#', '0xff')));

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Dismissible(
        key: Key(scan.id.toString()),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFF5A5F).withOpacity(0.2),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5A5F)),
        ),
        onDismissed: (_) {
          _deleteScan(scan);
        },
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.05)),
            boxShadow: [
              if (!isDark) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 6,
                  color: scan.isRotten ? const Color(0xFFFF5A5F) : statusColor,
                ),
                const SizedBox(width: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: Image.file(
                        File(scan.imagePath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: theme.colorScheme.onSurface.withOpacity(0.05), 
                          child: Icon(Icons.broken_image, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.2))
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(scan.fruit.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                      Text(scan.stageName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      Text(dateStr, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.4))),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    scan.isSynced ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded,
                    size: 16, 
                    color: scan.isSynced ? theme.colorScheme.primary.withOpacity(0.5) : Colors.orange.withOpacity(0.5),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text("${(scan.confidence * 100).toStringAsFixed(0)}%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.2)),
                  onPressed: () => _showScanDetails(scan),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showScanDetails(Scan scan) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ScanDetailSheet(scan: scan),
    );
  }
}

class _ScanDetailSheet extends StatelessWidget {
  final Scan scan;
  const _ScanDetailSheet({required this.scan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat('EEEE, MMM dd, yyyy • hh:mm a').format(scan.dateTime);
    final color = Color(int.parse(scan.color.replaceAll('#', '0xff')));

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: SizedBox(
                      height: 300,
                      child: PhotoView(
                        imageProvider: FileImage(File(scan.imagePath)),
                        backgroundDecoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(scan.fruit.toUpperCase(), 
                            style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                          Text(scan.stageName, 
                            style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withOpacity(0.5)),
                        ),
                        child: Text("${(scan.confidence * 100).toStringAsFixed(1)}%", 
                          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 8),
                  Text(dateStr, style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
                  const Divider(height: 32),

                  if (scan.isRotten) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.redAccent),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text("Health Hazard: This fruit is identified as rotten and should not be consumed.",
                              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Text("Nutritional Information", 
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 12),
                  
                  _buildNutrientRow(context, "Calories", "${scan.nutrients['calories'] ?? 'N/A'}", Icons.local_fire_department, Colors.orange),
                  _buildNutrientRow(context, "Sugar", "${scan.nutrients['sugar_g'] ?? 'N/A'} mg", Icons.grain, Colors.pink),
                  _buildNutrientRow(context, "Vitamin C", "${scan.nutrients['vitamin_c_mg'] ?? 'N/A'} mg", Icons.health_and_safety, Colors.green),
                  _buildNutrientRow(context, "Fiber", "${scan.nutrients['fiber_g'] ?? 'N/A'} mg", Icons.grass, Colors.brown),
                  
                  const SizedBox(height: 20),
                  
                  Text("Storage Tip", 
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const SizedBox(height: 8),
                  Text(
                    _getStorageTip(scan.fruit, scan.stage),
                    style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7), height: 1.5),
                  ),
                  
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientRow(BuildContext context, String label, String value, IconData icon, Color color) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurface)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  String _getStorageTip(String fruit, int stage) {
    if (fruit.toLowerCase() == 'banana') {
      if (stage < 4) return "Keep at room temperature to ripen. Hang them to avoid bruising.";
      if (stage > 6) return "Peel and freeze for smoothies, or use for banana bread.";
      return "Eat now or refrigerate to slow down further ripening (skin will turn black, but fruit stays good).";
    }
    if (fruit.toLowerCase() == 'apple') {
      return "Store in a cool, dark place or the refrigerator crisper drawer to keep them crunchy.";
    }
    if (fruit.toLowerCase() == 'mango') {
      if (stage < 3) return "Keep at room temperature until soft to the touch.";
      return "Once ripe, store in the refrigerator for up to 5 days.";
    }
    return "Keep in a cool place away from direct sunlight.";
  }
}
