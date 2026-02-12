import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/student_session_model.dart';
import '../services/deep_link_service.dart';
import 'package:intl/intl.dart';
import 'drawing_screen.dart';

class MaterialDetailScreen extends StatefulWidget {
  final MaterialModel material;
  final String sessionTitle;
  final String teacherName;
  final String? sessionId; // Deep Link용 (선택)
  final bool isTeacher; // 교사 여부 (선택)

  const MaterialDetailScreen({
    Key? key,
    required this.material,
    required this.sessionTitle,
    required this.teacherName,
    this.sessionId,
    this.isTeacher = false,
  }) : super(key: key);

  @override
  State<MaterialDetailScreen> createState() => _MaterialDetailScreenState();
}

class _MaterialDetailScreenState extends State<MaterialDetailScreen> {
  final DeepLinkService _deepLinkService = DeepLinkService();

  IconData _getMaterialIcon() {
    switch (widget.material.type) {
      case FileMaterialType.pdf:
        return Icons.picture_as_pdf;
      case FileMaterialType.image:
        return Icons.image;
      case FileMaterialType.video:
        return Icons.video_file;
      case FileMaterialType.document:
        return Icons.description;
      case FileMaterialType.other:
        return Icons.insert_drive_file;
    }
  }

  Color _getMaterialIconColor() {
    switch (widget.material.type) {
      case FileMaterialType.pdf:
        return Colors.red;
      case FileMaterialType.image:
        return Colors.blue;
      case FileMaterialType.video:
        return Colors.purple;
      case FileMaterialType.document:
        return Colors.green;
      case FileMaterialType.other:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy년 MM월 dd일 HH:mm').format(date);
  }

  void _handleDownload(BuildContext context) {
    // TODO: 실제 다운로드 구현
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.material.fileName} 다운로드 시작'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handlePreview(BuildContext context) {
    // TODO: 실제 미리보기 구현
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('미리보기 기능은 추후 구현 예정입니다'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handleStartDrawing(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          materialTitle: widget.material.title,
          backgroundUrl: widget.material.url,
          isTeacher: widget.isTeacher,
          serverUrl: null, // 서버 연결은 나중에
          roomId: null,
          userId: null,
        ),
      ),
    );
  }

  /// QR 코드 공유 (교사 전용)
  void _showQrCodeDialog() {
    if (widget.sessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('세션 ID가 없습니다')),
      );
      return;
    }

    // Deep Link 생성
    final deepLink = _deepLinkService.generateMaterialLink(
      widget.sessionId!,
      widget.material.id,
    );

    showDialog(
      context: context,
      builder: (context) => _QrCodeDialog(
        deepLink: deepLink,
        materialTitle: widget.material.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('자료 상세'),
        actions: [
          // 교사 전용: QR 공유 버튼
          if (widget.isTeacher && widget.sessionId != null)
            IconButton(
              icon: const Icon(Icons.qr_code_2),
              onPressed: _showQrCodeDialog,
              tooltip: 'QR 코드 공유',
            ),
          // 다운로드 버튼
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _handleDownload(context),
            tooltip: '다운로드',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 파일 아이콘 및 타입
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: _getMaterialIconColor().withOpacity(0.1),
              ),
              child: Column(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getMaterialIcon(),
                      size: 64,
                      color: _getMaterialIconColor(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.material.type.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      color: _getMaterialIconColor(),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),

            // 자료 정보
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 제목
                  const Text(
                    '제목',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.material.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 파일 정보 카드
                  Card(
                    elevation: 0,
                    color: Colors.grey[100],
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildInfoRow(
                            Icons.insert_drive_file_outlined,
                            '파일명',
                            widget.material.fileName,
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            Icons.storage_outlined,
                            '파일 크기',
                            widget.material.formattedSize,
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            Icons.calendar_today_outlined,
                            '업로드 날짜',
                            _formatDate(widget.material.uploadedAt),
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            Icons.school_outlined,
                            '세션',
                            '${widget.sessionTitle} (${widget.teacherName})',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 설명
                  if (widget.material.description != null &&
                      widget.material.description!.isNotEmpty) ...[
                    const Text(
                      '설명',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.material.description!,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 액션 버튼들
                  Column(
                    children: [
                      // 판서 시작 버튼
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _handleStartDrawing(context),
                          icon: const Icon(Icons.edit),
                          label: Text(widget.isTeacher ? '판서 시작' : '내 필기 시작'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _handlePreview(context),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('미리보기'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _handleDownload(context),
                              icon: const Icon(Icons.download),
                              label: const Text('다운로드'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ===============================
/// QR 코드 다이얼로그
/// ===============================
class _QrCodeDialog extends StatelessWidget {
  final String deepLink;
  final String materialTitle;

  const _QrCodeDialog({
    required this.deepLink,
    required this.materialTitle,
  });

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: deepLink));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('링크가 복사되었습니다')),
    );
  }

  void _shareLink() {
    Share.share(
      deepLink,
      subject: '자료 공유: $materialTitle',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 제목
            Row(
              children: [
                const Icon(Icons.qr_code_2, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'QR 코드 공유',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              materialTitle,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),

            // QR 코드
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: QrImageView(
                data: deepLink,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),

            // 링크 텍스트
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                deepLink,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            // 액션 버튼들
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyLink(context),
                    icon: const Icon(Icons.copy),
                    label: const Text('링크 복사'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _shareLink,
                    icon: const Icon(Icons.share),
                    label: const Text('공유'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}