import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gotit/app/services.dart';
import 'package:gotit/app/theme/gotit_colors.dart';
import 'package:gotit/core/link/pairing.dart';
import 'package:gotit/features/pairing/view/pair_code_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scans the QR code the PC shows, then pairs at once.
class ScanPage extends StatefulWidget {
  const ScanPage({required this.services, super.key});

  final AppServices services;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  DateTime _lastHint = DateTime(2000);

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final invite = PairInvite.parse(code.rawValue ?? '');
      if (invite == null) continue;
      _done = true;
      unawaited(_scanner.stop());
      final attempt = widget.services.phoneLink!.pairWithInvite(invite);
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                PairCodePage(attempt: attempt, pcName: invite.pcName),
          ),
        ),
      );
      return;
    }
    // Some other QR code: say so, but not on every frame.
    final now = DateTime.now();
    if (now.difference(_lastHint) > const Duration(seconds: 3)) {
      _lastHint = now;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("That's not a Gotit code")));
    }
  }

  @override
  void dispose() {
    unawaited(_scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GotitColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR code')),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _scanner,
              onDetect: _onDetect,
              errorBuilder: (context, error) => ColoredBox(
                color: colors.bg,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      error.errorCode == MobileScannerErrorCode.permissionDenied
                          ? 'Camera access is off. Turn it on for Gotit in Settings.'
                          : "The camera couldn't start.",
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: colors.muted),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The frame to aim with.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.accent, width: 2.5),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.bg.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    'Point at the code on your PC',
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
