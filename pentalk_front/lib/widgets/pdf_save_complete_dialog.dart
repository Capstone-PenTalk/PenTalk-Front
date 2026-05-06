import 'package:flutter/material.dart';
import '../services/pdf_export_service.dart';

/// ===============================
/// PDF 저장 완료 다이얼로그 (B안)
///
/// 예전 저장 완료 다이얼로그.
/// 현재는 로딩 다이얼로그만 사용하고, 저장 완료는 시스템 save dialog 이후 스낵바로 안내한다.
/// ===============================
class PdfSaveCompleteDialog extends StatelessWidget {
  final PdfSaveResult saveResult;

  const PdfSaveCompleteDialog({
    Key? key,
    required this.saveResult,
  }) : super(key: key);

  /// 다이얼로그 표시 (static helper)
  static Future<void> show(
      BuildContext context, {
        required PdfSaveResult saveResult,
      }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PdfSaveCompleteDialog(saveResult: saveResult),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 아이콘
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.green[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle,
              color: Colors.green[600],
              size: 40,
            ),
          ),
          const SizedBox(height: 16),

          // 제목
          const Text(
            'PDF 저장 완료',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // 파일 정보 카드
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 파일명
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.picture_as_pdf,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        saveResult.fileName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 파일 크기
                Row(
                  children: [
                    Icon(
                      Icons.data_usage,
                      color: Colors.grey[500],
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      saveResult.formattedSize,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),

      // 버튼 영역
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        // 닫기 (텍스트 버튼)
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '닫기',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
        const SizedBox(width: 8),

        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    );
  }
}

/// ===============================
/// PDF export 진행 중 로딩 다이얼로그
/// ===============================
class PdfExportLoadingDialog extends StatelessWidget {
  const PdfExportLoadingDialog({Key? key}) : super(key: key);

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PdfExportLoadingDialog(),
    );
  }

  static void dismiss(BuildContext context) {
    if (!context.mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              'PDF를 생성하는 중...',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 6),
            Text(
              '잠시만 기다려주세요',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
