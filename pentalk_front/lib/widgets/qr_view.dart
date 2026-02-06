import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrView extends StatelessWidget {
  final String url;

  const QrView({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: url,
      size: 220,
      backgroundColor: Colors.white,
    );
  }
}
