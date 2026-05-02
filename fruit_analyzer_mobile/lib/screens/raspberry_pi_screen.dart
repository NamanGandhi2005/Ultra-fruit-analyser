import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/pi_service.dart';
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
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final piService = Provider.of<PiService>(context, listen: false);
      piService.connect();
      
      // Start frame polling every 100ms
      _pollingTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) {
        if (mounted && piService.isConnected) {
          piService.fetchFrame();
        }
      });
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final piService = Provider.of<PiService>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pi 5 Live Feed"),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Icon(
              Icons.circle,
              size: 12,
              color: piService.isConnected ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Live Feed Section using Memory Polling
          Expanded(
            flex: 2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  color: Colors.black,
                  width: double.infinity,
                  child: piService.currentFrame != null
                      ? Image.memory(
                          piService.currentFrame!,
                          gaplessPlayback: true,
                          fit: BoxFit.contain,
                        )
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.blueAccent),
                              SizedBox(height: 10),
                              Text("Initializing Feed...", style: TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                ),
                
                // Scanning Frame Overlay
                Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),

                if (!piService.isConnected)
                  Container(
                    color: Colors.black87,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi_off, color: Colors.white, size: 50),
                          const SizedBox(height: 10),
                          Text("Pi Offline at ${piService.ip}", style: const TextStyle(color: Colors.white)),
                          TextButton(
                            onPressed: () => _showIpDialog(context, piService),
                            child: const Text("Update IP"),
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
                    if (piService.latestResult != null)
                      _buildStatusCard(piService.latestResult!, theme),
                    
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Automated Analysis", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent)),
                        Switch(
                          value: piService.latestResult?.automatedEnabled ?? true,
                          onChanged: (val) {
                            piService.setAutomation(val);
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Text("Lens Control", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Row(
                      children: [
                        const Text("AF"),
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
                        onChanged: (val) => setState(() => _focusValue = val),
                        onChangeEnd: (val) => piService.setFocus('manual', pos: val),
                      ),

                    const SizedBox(height: 20),
                    const Text("Analysis Priority", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: ['auto', 'apple', 'banana', 'mango', 'orange'].map((mode) {
                        return ChoiceChip(
                          label: Text(mode.toUpperCase()),
                          selected: _selectedFruit == mode,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedFruit = mode);
                              piService.setFruitMode(mode);
                            }
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),
                    const Text("Display Controls", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Display 1", style: TextStyle(fontSize: 12, color: Colors.grey)),
                              DropdownButton<String>(
                                isExpanded: true,
                                value: piService.latestResult?.display1Mode ?? 'result',
                                items: ['result', 'status', 'custom'].map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value.toUpperCase(), style: const TextStyle(fontSize: 12)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val == "custom") {
                                    _showCustomTextDialog(context, piService, 1);
                                  } else if (val != null) {
                                    piService.setDisplay(1, val);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Display 2", style: TextStyle(fontSize: 12, color: Colors.grey)),
                              DropdownButton<String>(
                                isExpanded: true,
                                value: piService.latestResult?.display2Mode ?? 'result',
                                items: ['result', 'status', 'custom'].map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value.toUpperCase(), style: const TextStyle(fontSize: 12)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val == "custom") {
                                    _showCustomTextDialog(context, piService, 2);
                                  } else if (val != null) {
                                    piService.setDisplay(2, val);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: piService.isConnected ? () => piService.triggerScan() : null,
                        icon: const Icon(Icons.refresh),
                        label: const Text("FORCE NEW SCAN"),
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
                    Text(res.fruit.toUpperCase(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                    Text(res.stageName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    Text(
                      res.isRotten ? "⚠ ROTTEN DETECTED" : "✔ FRESH & HEALTHY",
                      style: TextStyle(
                        color: res.isRotten ? theme.colorScheme.error : theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Text("${(res.confidence * 100).toStringAsFixed(0)}%", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
        FaIcon(icon, size: 16, color: Colors.grey),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }

  void _showCustomTextDialog(BuildContext context, PiService piService, int lcd) {
    final l1Controller = TextEditingController();
    final l2Controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Custom Text - Display $lcd"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: l1Controller, decoration: const InputDecoration(hintText: "Line 1 (max 16 chars)"), maxLength: 16),
            TextField(controller: l2Controller, decoration: const InputDecoration(hintText: "Line 2 (max 16 chars)"), maxLength: 16),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              piService.setDisplay(lcd, "custom", l1: l1Controller.text, l2: l2Controller.text);
              Navigator.pop(context);
            },
            child: const Text("Set Text"),
          ),
        ],
      ),
    );
  }

  void _showIpDialog(BuildContext context, PiService piService) {
    final controller = TextEditingController(text: piService.ip);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Pi 5 Connection"),
        content: TextField(
          controller: controller, 
          decoration: const InputDecoration(
            hintText: "e.g. 192.168.1.x or https://xyz.ngrok.io",
            helperText: "Enter Local IP or Public Tunnel URL",
          ),
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
