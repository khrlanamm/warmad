import 'package:flutter/material.dart';

/// The pin mark with the "warmad" wordmark below it.
class WarmadLogo extends StatelessWidget {
  const WarmadLogo({super.key, this.width = 140});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/warmad-splash.png',
      width: width,
      semanticLabel: 'Warmad',
    );
  }
}
