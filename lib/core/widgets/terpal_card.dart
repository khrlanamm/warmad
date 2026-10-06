import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Green card with the yellow scalloped awning edge from the logo.
///
/// The awning is the brand motif. Use it sparingly, for example on the cash
/// card of the home screen.
class TerpalCard extends StatelessWidget {
  const TerpalCard({super.key, required this.child});

  final Widget child;

  static const _awningHeight = 18.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: AppColors.green,
        child: Stack(
          children: [
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _awningHeight,
              child: CustomPaint(painter: _AwningPainter()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                _awningHeight + 18,
                20,
                20,
              ),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _AwningPainter extends CustomPainter {
  const _AwningPainter();

  static const _scallopWidth = 44.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.yellow;
    final count = (size.width / _scallopWidth).round().clamp(1, 100);
    final width = size.width / count;
    final band = size.height / 2;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, band), paint);
    for (var i = 0; i < count; i++) {
      // Each scallop is the lower half of an ellipse hanging from the band.
      canvas.drawOval(Rect.fromLTWH(i * width, 0, width, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_AwningPainter oldDelegate) => false;
}
