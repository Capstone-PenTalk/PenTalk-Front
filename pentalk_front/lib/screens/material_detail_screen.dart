
import 'package:flutter/material.dart';
import '../models/student_session_model.dart';
import 'package:intl/intl.dart';
import 'drawing_screen.dart';

class MaterialDetailScreen extends StatelessWidget {
  final MaterialModel material;
  final String sessionTitle;
  final String teacherName;
  static const String _demoSessionId =
      '58e29366-0563-47bd-8137-54500bf3d957';
  static const String _demoMaterialId = 'seed-material-01';

  static const String _teacherServerUrl =
      'http://192.168.219.143:3000/?role=teacher&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJ0ZWFjaGVyMSIsInJvbGUiOiJ0ZWFjaGVyIiwiaWF0IjoxNzczMTUxNDA2LCJleHAiOjE3NzM3NTYyMDZ9.JTsfuuL2K5C-OWURkvYM0PcPUVYvDzdzveqBu4w-8gA';
  static const String _studentServerUrl =
      'http://192.168.219.143:3000/?role=student&token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJzdHVkZW50MSIsInJvbGUiOiJzdHVkZW50IiwiaWF0IjoxNzczMTUxNDE2LCJleHAiOjE3NzM3NTYyMTZ9.xDtnlgluJbUM9vjPKSnyvc0P-RtpBKCrt3cMaIN9mGs';

  const MaterialDetailScreen({
    Key? key,
    required this.material,
    required this.sessionTitle,
    required this.teacherName,
  }) : super(key: key);

  IconData _getMaterialIcon() {
    switch (material.type) {
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
    switch (material.type) {
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
        content: Text('${material.fileName} 다운로드 시작'),
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
    _showRolePicker(context);
  }

  void _showRolePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.school),
                title: const Text('선생님으로 시작'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _startDrawingWithRole(context, isTeacher: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('학생으로 시작'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _startDrawingWithRole(context, isTeacher: false);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _startDrawingWithRole(BuildContext context, {required bool isTeacher}) {
    // Demo session/material are seeded on the backend and used for local testing.
    final serverUrl = _resolveServerUrl(isTeacher);
    const userId = 'user_124'; // 실제 사용자 ID로 변경

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          materialTitle: material.title,
          backgroundUrl: null,
          materialId: _demoMaterialId,
          isTeacher: isTeacher,
          serverUrl: serverUrl,
          roomId: _demoSessionId,
          userId: userId,
        ),
      ),
    );
  }

  String? _resolveServerUrl(bool isTeacher) {
    final url = isTeacher ? _teacherServerUrl : _studentServerUrl;
    if (url.isEmpty) {
      return null;
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('자료 상세'),
        actions: [
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
                    material.type.name.toUpperCase(),
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
                    material.title,
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
                            material.fileName,
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            Icons.storage_outlined,
                            '파일 크기',
                            material.formattedSize,
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            Icons.calendar_today_outlined,
                            '업로드 날짜',
                            _formatDate(material.uploadedAt),
                          ),
                          const Divider(height: 24),
                          _buildInfoRow(
                            Icons.school_outlined,
                            '세션',
                            '$sessionTitle ($teacherName)',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 설명
                  if (material.description != null &&
                      material.description!.isNotEmpty) ...[
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
                        material.description!,
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
                      // 판서 시작 버튼 (교사용)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _handleStartDrawing(context),
                          icon: const Icon(Icons.edit),
                          label: const Text('판서 시작'),
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
