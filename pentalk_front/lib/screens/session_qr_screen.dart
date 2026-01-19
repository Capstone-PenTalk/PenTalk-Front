import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/session_link_provider.dart';
import '../widgets/qr_view.dart';

class SessionQrScreen extends StatelessWidget {
  const SessionQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SessionLinkProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text("세션 접속")),
      body: Center(
        child: provider.isLoading
            ? const CircularProgressIndicator()
            : provider.error != null
            ? Text(provider.error!)
            : provider.sessionUrl == null
            ? ElevatedButton(
          onPressed: () {
            context
                .read<SessionLinkProvider>()
                .loadSessionLink();
          },
          child: const Text("세션 링크 불러오기"),
        )
            : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrView(url: provider.sessionUrl!),
            const SizedBox(height: 16),
            Text(provider.sessionUrl!),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                          text: provider.sessionUrl!),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("링크 복사됨")),
                    );
                  },
                  child: const Text("링크 복사"),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    Share.share(provider.sessionUrl!);
                  },
                  child: const Text("공유"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
