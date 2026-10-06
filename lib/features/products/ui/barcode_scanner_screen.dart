import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';

/// Full screen camera that returns the first barcode it reads, or null when
/// the user backs out.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  /// Opens the scanner and returns the scanned code.
  static Future<String?> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
  }

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final code = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (code == null) return;
    // The camera keeps reporting the same code; return only once.
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Kamera tidak bisa dipakai. Izinkan akses kamera di '
                  'pengaturan HP, atau ketik nama barangnya.',
                  textAlign: TextAlign.center,
                  style: AppText.body(16, color: AppColors.white),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: AppColors.white,
                      ),
                      tooltip: 'Tutup',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.x),
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Arahkan kamera ke barcode barang',
                    textAlign: TextAlign.center,
                    style: AppText.body(
                      16,
                      weight: FontWeight.w600,
                      color: AppColors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
