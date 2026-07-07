import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/student_session_model.dart';
import '../config/app_config.dart';
import '../services/deep_link_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/pdf_file_service.dart';
import '../theme/app_colors.dart';
import 'package:intl/intl.dart';
import 'drawing_screen.dart';

class MaterialDetailScreen extends StatefulWidget {
  final MaterialModel material;
  final String sessionTitle;
  final String teacherName;
  final String? sessionId;
  final String? joinUrl;
  final bool isTeacher;
  final String? classId;

  /// 복습 퀴즈 통과 여부 (null이면 퀴즈와 무관한 일반 자료 열람)
  /// true: 통과 · 필기 가능 배지 / false: 미통과 · 읽기 전용 배지 + 잠금
  final bool? quizPassed;

  static const String _demoClassId = String.fromEnvironment(
    'PENTALK_DEMO_CLASS_ID',
    defaultValue: 'seed-class-01',
  );
  static const String _demoMaterialId = String.fromEnvironment(
    'PENTALK_DEMO_MATERIAL_ID',
    defaultValue: 'seed-material-01',
  );
  static const String _demoTeacherId = String.fromEnvironment(
    'PENTALK_DEMO_TEACHER_ID',
    defaultValue: 'seed-teacher-01',
  );
  static const String _demoStudentId = String.fromEnvironment(
    'PENTALK_DEMO_STUDENT_ID',
    defaultValue: 'seed-student-01',
  );
  // QR 기능 전까지 학생은 여기에 교사가 생성한 sessionId(UUID)를 직접 넣고 입장(하드코딩)
  static const String _studentHardcodedSessionId = String.fromEnvironment(
    'PENTALK_STUDENT_SESSION_ID',
    defaultValue: '',
  );

  const MaterialDetailScreen({
    Key? key,
    required this.material,
    required this.sessionTitle,
    required this.teacherName,
    this.sessionId,
    this.joinUrl,
    this.isTeacher = false,
    this.classId,
    this.quizPassed,
  }) : super(key: key);

  @override
  State<MaterialDetailScreen> createState() => _MaterialDetailScreenState();
}

class _MaterialDetailScreenState extends State<MaterialDetailScreen> {
  final DeepLinkService _deepLinkService = DeepLinkService();
  bool _isDownloading = false;

  bool _looksLikeRealtimeSessionId(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{12}$',
    ).hasMatch(normalized);
  }

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
        return AppColors.danger;
      case FileMaterialType.image:
        return AppColors.primary;
      case FileMaterialType.video:
        return Colors.purple;
      case FileMaterialType.document:
        return AppColors.success;
      case FileMaterialType.other:
        return AppColors.textSecondary;
    }
  }

  bool get _isLocked => widget.quizPassed == false;

  String _formatDate(DateTime date) {
    return DateFormat('yyyy년 MM월 dd일 HH:mm').format(date);
  }

  Future<void> _handleDownload() async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    try {
      final bytes = await _loadMaterialBytes(widget.material);
      final suggestedFileName = _suggestedDownloadFileName(widget.material);
      final savedLocation = await PdfFileService.saveWithPicker(
        bytes: bytes,
        fileName: suggestedFileName,
        dialogTitle: '저장 위치를 선택하세요',
      );

      if (!mounted) return;

      if (savedLocation == null || savedLocation.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('저장이 취소되었습니다')));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$suggestedFileName 저장 완료'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('다운로드 실패: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<Uint8List> _loadMaterialBytes(MaterialModel material) async {
    final isRemoteMaterial =
        material.id.isNotEmpty && !material.id.startsWith('local_');

    if (isRemoteMaterial) {
      final downloadUrl = await ApiService.getMaterialDownloadUrl(
        materialId: material.id,
      );
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) {
        throw Exception('자료 다운로드 실패 [${response.statusCode}]');
      }
      return response.bodyBytes;
    }

    if (kIsWeb) {
      throw UnsupportedError('웹에서는 로컬 파일 다운로드를 지원하지 않습니다.');
    }

    final file = File(material.url);
    if (!await file.exists()) {
      throw Exception('로컬 파일을 찾을 수 없습니다.');
    }
    return file.readAsBytes();
  }

  String _suggestedDownloadFileName(MaterialModel material) {
    final candidates = [material.fileName, material.title, material.id];

    final baseName = candidates
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty && value != 'untitled');

    if (p.extension(baseName).isNotEmpty) {
      return baseName;
    }

    final extension = material.type.extension;
    return extension.isEmpty ? baseName : '$baseName.$extension';
  }

  void _handlePreview(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('미리보기 기능은 추후 구현 예정입니다')));
  }

  void _handleStartDrawing(BuildContext context) {
    _showRolePicker(context);
  }

  // 팀원 추가: 역할 선택 바텀시트
  void _showRolePicker(BuildContext context) {
    // 세션 ID가 있으면 역할이 이미 결정됨 (실제 수업 진입)
    if (widget.sessionId != null) {
      _startDrawingWithRole(context, isTeacher: widget.isTeacher);
      return;
    }

    // 데모 모드: 역할 선택
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
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
      ),
    );
  }

  Future<void> _startDrawingWithRole(
    BuildContext context, {
    required bool isTeacher,
  }) async {
    final serverUrl = _resolveServerUrl(isTeacher);
    if (serverUrl == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('서버 URL이 비어 있어요.')));
      return;
    }

    final userId =
        await AuthService.getUserId() ??
        (isTeacher
            ? MaterialDetailScreen._demoTeacherId
            : MaterialDetailScreen._demoStudentId);
    String? roomId = _looksLikeRealtimeSessionId(widget.sessionId)
        ? widget.sessionId!.trim()
        : null;

    if (!isTeacher && roomId == null) {
      final hardcodedRoomId = MaterialDetailScreen._studentHardcodedSessionId
          .trim();
      if (_looksLikeRealtimeSessionId(hardcodedRoomId)) {
        roomId = hardcodedRoomId;
      }
    }

    if (!isTeacher && roomId == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('학생용 하드코딩 sessionId를 먼저 입력해주세요.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (roomId == null &&
        widget.classId != null &&
        widget.classId!.trim().isNotEmpty) {
      final response = await ApiService.createSession(
        classId: widget.classId!.trim(),
        materialId: widget.material.id,
        maxParticipants: 30,
        password: '0000',
      );

      if (!response.success || response.data == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? '실시간 세션 생성에 실패했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      roomId = response.data!.sessionId.trim();
      debugPrint(
        'Student drawing session bootstrapped: '
        'classId=${widget.classId} materialId=${widget.material.id} roomId=$roomId',
      );
    }

    if (roomId == null || roomId.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('세션 ID가 없습니다.')));
      return;
    }

    final backgroundUrl = await _resolveMaterialBackgroundUrl(widget.material);

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          materialTitle: widget.material.title,
          backgroundUrl: backgroundUrl,
          isPdfDocument: widget.material.type == FileMaterialType.pdf,
          materialId: widget.material.id.isNotEmpty
              ? widget.material.id
              : MaterialDetailScreen._demoMaterialId,
          classId:
              widget.classId ??
              (kIsWeb ? Uri.base.queryParameters['classId'] : null) ??
              MaterialDetailScreen._demoClassId,
          isTeacher: isTeacher,
          serverUrl: serverUrl,
          roomId: roomId,
          userId: userId,
          sessionId: roomId,
        ),
      ),
    );
  }

  Future<String> _resolveMaterialBackgroundUrl(MaterialModel material) async {
    final isRemotePdf =
        material.type == FileMaterialType.pdf &&
        material.id.isNotEmpty &&
        !material.id.startsWith('local_');

    if (!isRemotePdf) return material.url;

    return ApiService.getMaterialDownloadUrl(materialId: material.id);
  }

  String? _resolveServerUrl(bool isTeacher) {
    final url = AppConfig.resolveSocketUrl(isTeacher: isTeacher);
    return url.isEmpty ? null : url;
  }

  // 내 코드: QR 코드 공유 (교사 전용)
  void _showQrCodeDialog() {
    if (widget.sessionId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('세션 ID가 없습니다')));
      return;
    }
    final joinUrl =
        widget.joinUrl ??
        _deepLinkService.generateJoinWebLink(
          widget.sessionId!,
          classId: widget.classId,
          materialId: widget.material.id,
        );
    final appDeepLink = _deepLinkService.generateJoinDeepLink(
      widget.sessionId!,
    );
    showDialog(
      context: context,
      builder: (context) => _QrCodeDialog(
        joinUrl: joinUrl,
        appDeepLink: appDeepLink,
        materialTitle: widget.material.title,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('자료 상세'),
        actions: [
          if (widget.isTeacher && widget.sessionId != null)
            IconButton(
              icon: const Icon(Icons.qr_code_2),
              onPressed: _showQrCodeDialog,
              tooltip: 'QR 코드 공유',
            ),
          if (_isDownloading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else if (!_isLocked)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _handleDownload,
              tooltip: '다운로드',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.quizPassed != null)
              Container(
                width: double.infinity,
                color: widget.quizPassed!
                    ? const Color(0xFFE7F5EA)
                    : AppColors.border,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.quizPassed! ? Icons.check_circle : Icons.lock_outline,
                      size: 16,
                      color: widget.quizPassed!
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.quizPassed! ? '통과 · 필기 가능' : '미통과 · 읽기 전용',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: widget.quizPassed!
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                    ),
                    if (_isLocked) ...[
                      const Spacer(),
                      const Text(
                        '복습 퀴즈를 통과하면 다시 필기할 수 있어요',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: _getMaterialIconColor().withOpacity(0.08),
              ),
              child: Column(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getMaterialIcon(),
                      size: 64,
                      color: _isLocked
                          ? AppColors.textSecondary
                          : _getMaterialIconColor(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.material.type.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      color: _isLocked
                          ? AppColors.textSecondary
                          : _getMaterialIconColor(),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '제목',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.material.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 0,
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppColors.border),
                    ),
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
                  if (widget.material.description != null &&
                      widget.material.description!.isNotEmpty) ...[
                    const Text(
                      '설명',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        widget.material.description!,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLocked
                              ? null
                              : () => _handleStartDrawing(context),
                          icon: const Icon(Icons.edit),
                          label: Text(widget.isTeacher ? '판서 시작' : '내 필기 시작'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
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
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLocked || _isDownloading
                                  ? null
                                  : _handleDownload,
                              icon: _isDownloading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Icon(Icons.download),
                              label: Text(_isDownloading ? '저장 중...' : '다운로드'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
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
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
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
/// QR 코드 다이얼로그 (내 코드 유지)
/// ===============================
class _QrCodeDialog extends StatelessWidget {
  final String joinUrl;
  final String appDeepLink;
  final String materialTitle;

  const _QrCodeDialog({
    required this.joinUrl,
    required this.appDeepLink,
    required this.materialTitle,
  });

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: joinUrl));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('링크가 복사되었습니다')));
  }

  void _shareLink() {
    Share.share(joinUrl, subject: '세션 공유: $materialTitle');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'QR 코드 공유',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            QrImageView(
              data: joinUrl,
              size: 200,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              materialTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              joinUrl,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              appDeepLink,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyLink(context),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('링크 복사'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _shareLink,
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('공유'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
