import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import '../services/pdf_file_service.dart';

/// ===============================
/// PDF 저장 완료 다이얼로그 (B안)
///
/// 저장 완료 후 표시:
///   - 파일명 / 저장 위치 / 용량
///   - [열기] → 기기 PDF 앱
///   - [공유] → share_plus 시트
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

                // 저장 위치
                Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      color: Colors.grey[500],
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        saveResult.displayPath,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

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

        // 열기 버튼
        OutlinedButton.icon(
          onPressed: () => _handleOpen(context),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('열기'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 공유 버튼
        ElevatedButton.icon(
          onPressed: () => _handleShare(context),
          icon: const Icon(Icons.share, size: 18),
          label: const Text('공유'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleOpen(BuildContext context) async {
    final result = await PdfFileService.open(saveResult.filePath);

    if (!context.mounted) return;

    // PDF 앱이 없는 경우 안내
    if (result.type == ResultType.noAppToOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF를 열 수 있는 앱이 없습니다. 공유를 통해 저장해주세요.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleShare(BuildContext context) async {
    // 태블릿에서 공유 시트 위치를 버튼 근처에 표시하기 위해
    // RenderBox로 현재 위젯 위치를 계산
    final box = context.findRenderObject() as RenderBox?;
    final shareOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    await PdfFileService.share(
      filePath: saveResult.filePath,
      fileName: saveResult.fileName,
      sharePositionOrigin: shareOrigin,
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
    if (context.mounted) Navigator.of(context).pop();
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