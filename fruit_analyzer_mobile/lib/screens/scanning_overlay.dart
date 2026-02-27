import 'package:flutter/material.dart';

class ScanningOverlay extends StatefulWidget {
  const ScanningOverlay({super.key});

  @override
  State<ScanningOverlay> createState() => _ScanningOverlayState();
}

class _ScanningOverlayState extends State<ScanningOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Stack(
          children: [
            // Semi-transparent dark overlay
            Container(color: Colors.black.withOpacity(0.3)),
            
            // Scanning Line
            Positioned(
              top: _animation.value * MediaQuery.of(context).size.height * 0.4, // Approximation of container height
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.8),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                  gradient: const LinearGradient(
                    colors: [Colors.transparent, Colors.cyanAccent, Colors.transparent],
                  ),
                ),
              ),
            ),

            // Corner Brackets
            _buildCorner(top: 20, left: 20, isTop: true, isLeft: true),
            _buildCorner(top: 20, right: 20, isTop: true, isLeft: false),
            _buildCorner(bottom: 20, left: 20, isTop: false, isLeft: true),
            _buildCorner(bottom: 20, right: 20, isTop: false, isLeft: false),

            // Scanning Text
            const Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "ANALYZING...",
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 4,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "PROCESSING NEURAL DATA",
                    style: TextStyle(color: Colors.cyanAccent, fontSize: 10, letterSpacing: 2),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCorner({double? top, double? bottom, double? left, double? right, required bool isTop, required bool isLeft}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? const BorderSide(color: Colors.cyanAccent, width: 4) : BorderSide.none,
            bottom: !isTop ? const BorderSide(color: Colors.cyanAccent, width: 4) : BorderSide.none,
            left: isLeft ? const BorderSide(color: Colors.cyanAccent, width: 4) : BorderSide.none,
            right: !isLeft ? const BorderSide(color: Colors.cyanAccent, width: 4) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
