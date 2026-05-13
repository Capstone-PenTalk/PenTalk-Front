import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../providers/material_provider.dart';
import '../config/app_config.dart';
import '../widgets/breadcrumb_navigation.dart';
import '../services/file_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/local_material_service.dart';
import '../models/student_session_model.dart';
import 'drawing_screen.dart'; // 👈 추가
import '../widgets/quiz_editor_widget.dart';

class SessionDetailScreen extends StatefulWidget {
  final String sessionId;
  final String? classId; // 자료 업로드에 필요
  final bool localOnly;
  final String? titleOverride;

  const SessionDetailScreen({
    Key? key,
    required this.sessionId,
    this.classId,
    this.localOnly = false,
    this.titleOverride,
  }) : super(key: key);

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final FileService _fileService = FileService();
  final LocalMaterialService _localMaterialService = LocalMaterialService();
  bool _isUploading = false;
  String? _realtimeSessionId;

  bool get _canUseRemoteMaterials =>
      !widget.localOnly &&
      !AppConfig.preferLocalPdfImport &&
      !AppConfig.shouldAvoidLoopbackServerOnDevice &&
      widget.classId != null &&
      widget.classId!.isNotEmpty;

  String? get _effectiveSessionId =>
      _realtimeSessionId ??
      (_looksLikeRealtimeSessionId(widget.sessionId)
          ? widget.sessionId.trim()
          : null);

  String get _screenTitle => widget.titleOverride ?? '세션';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMaterials();
    });
  }

  // ⭐ 추가: 판서 화면으로 넘어가는 핵심 함수
  Future<void> _navigateToDrawing(
    BuildContext context, {
    required MaterialModel material,
    required bool connectRealtime,
  }) async {
    final userId = await AuthService.getUserId() ?? 'teacher';
    final resolvedBackgroundUrl = await _resolveMaterialBackgroundUrl(material);
    String? realtimeSessionId = connectRealtime ? _effectiveSessionId : null;
    if (connectRealtime && realtimeSessionId == null) {
      realtimeSessionId = await _createRealtimeSessionForMaterial(material);
      if (realtimeSessionId == null) return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          materialTitle: material.title,
          backgroundUrl: resolvedBackgroundUrl,
          isPdfDocument: material.type == FileMaterialType.pdf,
          isTeacher: true, // 교사 모드 켜기
          sessionId: realtimeSessionId,
          roomId: realtimeSessionId,
          userId: realtimeSessionId != null ? userId : null,
          serverUrl: realtimeSessionId != null
              ? AppConfig.resolveSocketUrl(isTeacher: true)
              : null,
          classId: realtimeSessionId != null ? widget.classId : null,
          materialId: material.id,
        ),
      ),
    );
  }

  Future<String> _resolveMaterialBackgroundUrl(MaterialModel material) async {
    final isRemotePdf =
        _canUseRemoteMaterials &&
        material.type == FileMaterialType.pdf &&
        !material.id.startsWith('local_');

    if (!isRemotePdf) return material.url;

    return ApiService.getMaterialDownloadUrl(materialId: material.id);
  }

  Future<String?> _createRealtimeSessionForMaterial(
    MaterialModel material,
  ) async {
    if (!_canUseRemoteMaterials) return null;

    final classId = widget.classId;
    if (classId == null || classId.isEmpty) return null;

    try {
      final response = await ApiService.createSession(
        classId: classId,
        materialId: material.id,
      );
      if (!response.success || response.data == null) {
        throw Exception(response.message ?? '실시간 세션 생성에 실패했습니다.');
      }

      final createdSessionId = response.data!.sessionId.trim();
      if (createdSessionId.isEmpty) {
        throw Exception('서버가 비어 있는 sessionId를 반환했습니다.');
      }

      debugPrint(
        '✅ Realtime session created for material: '
        'classId=$classId materialId=${material.id} serverSessionId=$createdSessionId',
      );
      if (mounted) {
        setState(() {
          _realtimeSessionId = createdSessionId;
        });
      }
      return createdSessionId;
    } catch (e) {
      debugPrint('❌ Failed to create realtime session for material: $e');
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('실시간 세션 생성 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }

  bool _looksLikeRealtimeSessionId(String value) {
    if (value.isEmpty) return false;
    if (value == 'local-pdf-workspace') return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  /// ===============================
  /// 자료 목록 로드
  /// ===============================
  Future<void> _loadMaterials() async {
    final materialProvider = context.read<MaterialProvider>();
    if (!_canUseRemoteMaterials) {
      materialProvider.setMaterials(const []);
      materialProvider.setLoading(false);
      materialProvider.setError(null);
      return;
    }

    final classId = (widget.classId != null && widget.classId!.isNotEmpty)
        ? widget.classId
        : (kIsWeb ? Uri.base.queryParameters['classId'] : null);
    if (classId == null) return;

    materialProvider.setLoading(true);

    try {
      final materials = await ApiService.getMaterials(classId: classId);
      if (!mounted) return;

      materialProvider.setMaterials(
        materials
            .map(
              (m) => MaterialModel(
                id: m.id,
                title: m.name,
                fileName: m.name,
                url: m.url,
                sizeInBytes: 0, // 서버 응답에 size 없음
                uploadedAt: DateTime.tryParse(m.createdAt) ?? DateTime.now(),
                type: FileMaterialType.pdf,
              ),
            )
            .toList(),
      );
    } catch (e) {
      debugPrint('❌ Failed to load materials: $e');
      if (mounted) materialProvider.setError('자료 목록 로드 실패');
    } finally {
      if (mounted) materialProvider.setLoading(false);
    }
  }

  /// ===============================
  /// 파일 업로드
  /// ===============================
  Future<void> _handleFileUpload() async {
    try {
      // 파일 선택 (PDF만)
      final file = await _fileService.pickFile();
      if (file == null) return;

      debugPrint(
        '📄 PDF import requested: '
        'apiBaseUrl=${AppConfig.apiBaseUrl}, '
        'loopbackBlocked=${AppConfig.shouldAvoidLoopbackServerOnDevice}, '
        'remoteEnabled=$_canUseRemoteMaterials',
      );

      // 파일 크기 검증
      final fileSize = await file.length();
      if (!_fileService.isValidFileSize(fileSize)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('파일 크기가 너무 큽니다 (최대 50MB)'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() => _isUploading = true);

      final material = await _createMaterialForTesting(filePath: file.path);
      if (!mounted) return;

      context.read<MaterialProvider>().addMaterial(material);
      await _navigateToDrawing(
        context,
        material: material,
        connectRealtime: _shouldConnectRealtimeForMaterial(material),
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _shouldConnectRealtimeForMaterial(material)
                ? '자료가 업로드됐습니다'
                : '서버 연결 없이 로컬 PDF 작업공간이 열렸습니다',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } on MaterialUploadException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('업로드 실패: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<MaterialModel> _uploadMaterialToServer({
    required String filePath,
  }) async {
    final classId = widget.classId;
    if (classId == null || classId.isEmpty) {
      throw Exception('클래스 정보가 없어 서버 업로드를 진행할 수 없습니다.');
    }

    final file = await _localMaterialService.importPdf(File(filePath));
    final uploaded = await ApiService.uploadMaterial(
      classId: classId,
      sessionId: _effectiveSessionId ?? widget.sessionId,
      filePath: file.url,
      fileName: file.fileName,
    );

    return MaterialModel(
      id: uploaded.id,
      title: uploaded.name,
      fileName: uploaded.name,
      url: uploaded.url,
      sizeInBytes: file.sizeInBytes,
      uploadedAt: DateTime.tryParse(uploaded.createdAt) ?? DateTime.now(),
      type: FileMaterialType.pdf,
    );
  }

  Future<MaterialModel> _createMaterialForTesting({
    required String filePath,
  }) async {
    if (!_canUseRemoteMaterials) {
      return _importMaterialLocally(filePath: filePath);
    }

    try {
      return await _uploadMaterialToServer(filePath: filePath);
    } catch (e) {
      debugPrint(
        '⚠️ Remote upload unavailable, falling back to local import. '
        'baseUrl=${AppConfig.apiBaseUrl}, error=$e',
      );
      return _importMaterialLocally(filePath: filePath);
    }
  }

  bool _shouldConnectRealtimeForMaterial(MaterialModel material) {
    return _canUseRemoteMaterials && !material.id.startsWith('local_');
  }

  Future<MaterialModel> _importMaterialLocally({
    required String filePath,
  }) async {
    return _localMaterialService.importPdf(File(filePath));
  }

  Future<void> _handleFileDelete(String fileId) async {
    try {
      context.read<MaterialProvider>().removeMaterial(fileId);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('자료가 삭제됐습니다')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<SessionProvider>(
          builder: (context, provider, child) {
            final session = provider.getSessionById(widget.sessionId);
            return Text(session?.title ?? _screenTitle);
          },
        ),
        actions: [
          if (_isUploading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Consumer2<SessionProvider, MaterialProvider>(
        builder: (context, sessionProvider, materialProvider, child) {
          final session = sessionProvider.getSessionById(widget.sessionId);

          if (session == null && !widget.localOnly) {
            return const Center(child: Text('세션을 찾을 수 없습니다'));
          }

          final sessionTitle = session?.title ?? _screenTitle;

          return Column(
            children: [
              BreadcrumbNavigation(
                paths: ['서예영 님의 공간', sessionTitle],
                onTap: (index) {
                  if (index == 0) Navigator.pop(context);
                },
              ),
              Expanded(
                child: materialProvider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : materialProvider.materials.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.upload_file,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '아직 업로드된 자료가 없습니다',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _canUseRemoteMaterials
                                  ? '하단의 + 버튼을 눌러 자료를 업로드하세요'
                                  : '하단의 + 버튼을 눌러 로컬 PDF를 열어보세요',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                            if (AppConfig
                                .shouldAvoidLoopbackServerOnDevice) ...[
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Text(
                                  '현재 서버 주소가 localhost/127.0.0.1 계열이라 실기기에서는 서버 업로드를 건너뛰고 로컬 PDF 테스트 모드로 동작합니다.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[800],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount:
                            materialProvider.materials.length +
                            (widget.sessionId == 'local-pdf-workspace' ? 0 : 3),
                        itemBuilder: (context, index) {
                          if (index >= materialProvider.materials.length) {
                            final footerIndex =
                                index - materialProvider.materials.length;
                            if (footerIndex == 0) {
                              return const SizedBox(height: 16);
                            }
                            if (footerIndex == 1) {
                              return const Divider(thickness: 1);
                            }
                            return QuizEditorWidget(
                              sessionId: widget.sessionId,
                            );
                          }
                          final material = materialProvider.materials[index];
                          return _MaterialListItem(
                            material: material,
                            onOpen: () => _navigateToDrawing(
                              context,
                              material: material,
                              connectRealtime: _canUseRemoteMaterials,
                            ),
                            onDelete: () => _handleFileDelete(material.id),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _handleFileUpload,
        icon: Icon(
          _canUseRemoteMaterials ? Icons.upload_file : Icons.picture_as_pdf,
        ),
        label: Text(_canUseRemoteMaterials ? '자료 업로드' : '로컬 PDF 열기'),
      ),
    );
  }
}

/// ===============================
/// 자료 목록 아이템
/// ===============================
class _MaterialListItem extends StatelessWidget {
  final MaterialModel material;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _MaterialListItem({
    required this.material,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onOpen,
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 28),
        ),
        title: Text(
          material.title,
          style: const TextStyle(fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          material.formattedSize,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _confirmDelete(context),
          tooltip: '삭제',
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('자료 삭제'),
        content: Text('"${material.title}" 자료를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
}
