import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/pi_service.dart';
import '../services/history_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class RaspberryPiScreen extends StatefulWidget {
  const RaspberryPiScreen({super.key});

  @override
  State<RaspberryPiScreen> createState() => _RaspberryPiScreenState();
}

class _RaspberryPiScreenState extends State<RaspberryPiScreen> {
  double _focusValue = 5.0;
  bool _isManualFocus = false;
  String _selectedFruit = 'auto';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<PiService>(context, listen: false).connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    final piService = Provider.of<PiService>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pi 5 Fruit Analyser"),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Icon(
              Icons.link,
              color: piService.isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Live Feed Section
          Expanded(
            flex: 2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (piService.isConnected)
                  Image.network(
                    piService.streamUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.black,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.red, size: 40),
                            const Text("Stream Unavailable", style: TextStyle(color: Colors.white)),
                            TextButton(
                              onPressed: () => piService.refreshStream(), 
                              child: const Text("Retry Stream")
                            )
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    color: Colors.black87,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                
                // Scanning Frame Overlay
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),

                // Connection status overlay if disconnected
                if (!piService.isConnected)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off, color: Colors.white, size: 50),
                          const SizedBox(height: 10),
                          Text("Connecting to ${piService.ip}...", style: const TextStyle(color: Colors.white)),
                          TextButton(
                            onPressed: () => _showIpDialog(context, piService),
                            child: const Text("Change IP"),
                          )
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Controls Section
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Badge
                    if (piService.latestResult != null)
                      _buildStatusCard(piService.latestResult!, theme),
                    
                    const SizedBox(height: 20),
                    const Text("Focus Control", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    Row(
                      children: [
                        const Text("Auto"),
                        Switch(
                          value: _isManualFocus,
                          onChanged: (val) {
                            setState(() => _isManualFocus = val);
                            piService.setFocus(val ? 'manual' : 'auto', pos: _focusValue);
                          },
                        ),
                        const Text("Manual"),
                      ],
                    ),
                    if (_isManualFocus)
                      Slider(
                        value: _focusValue,
                        min: 0.0,
                        max: 10.0,
                        divisions: 100,
                        label: _focusValue.toStringAsFixed(1),
                        onChanged: (val) {
                          setState(() => _focusValue = val);
                        },
                        onChangeEnd: (val) {
                          piService.setFocus('manual', pos: val);
                        },
                      ),

                    const SizedBox(height: 20),
                    const Text("Analysis Mode", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueAccent)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: ['auto', 'apple', 'banana', 'mango', 'orange'].map((mode) {
                        return ChoiceChip(
                          label: Text(mode.toUpperCase()),
                          selected: _selectedFruit == mode,
                          selectedColor: Colors.blueAccent.withOpacity(0.3),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedFruit = mode);
                              piService.setFruitMode(mode);
                            }
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: piService.isConnected ? () => piService.triggerScan() : null,
                        icon: const Icon(Icons.analytics),
                        label: const Text("TRIGGER ANALYSIS NOW"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(PiResult res, ThemeData theme) {
    return Card(
      elevation: 4,
      color: res.isRotten ? theme.colorScheme.error.withOpacity(0.1) : theme.colorScheme.secondary.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      res.fruit.toUpperCase(),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      res.isRotten ? "⚠️ ROTTEN DETECTED" : "✅ FRESH & HEALTHY",
                      style: TextStyle(
                        color: res.isRotten ? theme.colorScheme.error : theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  "${(res.confidence * 100).toStringAsFixed(1)}%",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            if (res.nutrients.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _nutrientIcon(FontAwesomeIcons.cubes, "${res.nutrients['sugar_g']}g"),
                  _nutrientIcon(FontAwesomeIcons.bolt, "${res.nutrients['calories']}"),
                  _nutrientIcon(FontAwesomeIcons.appleWhole, "${res.nutrients['fiber_g']}g"),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _nutrientIcon(IconData icon, String value) {
    return Column(
      children: [
        FaIcon(icon, size: 20, color: Colors.grey),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _showIpDialog(BuildContext context, PiService piService) {
    final controller = TextEditingController(text: piService.ip);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Pi 5 IP Address"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "192.168.1.65"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              piService.setIp(controller.text.trim());
              piService.connect();
              Navigator.pop(context);
            },
            child: const Text("Connect"),
          ),
        ],
      ),
    );
  }
}
