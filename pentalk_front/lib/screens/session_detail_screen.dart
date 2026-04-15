import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../providers/material_provider.dart';
import '../widgets/breadcrumb_navigation.dart';
import '../widgets/file_list_item.dart';
import '../services/file_service.dart';
import '../services/api_service.dart';
import '../models/student_session_model.dart';
import 'drawing_screen.dart'; // 👈 추가

class SessionDetailScreen extends StatefulWidget {
  final String sessionId;
  final String? classId; // 자료 업로드에 필요

  const SessionDetailScreen({
    Key? key,
    required this.sessionId,
    this.classId,
  }) : super(key: key);

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final FileService _fileService = FileService();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMaterials();
    });
  }
  // ⭐ 추가: 판서 화면으로 넘어가는 핵심 함수
  void _navigateToDrawing(BuildContext context, {required MaterialModel material}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DrawingScreen(
          materialTitle: material.title,
          backgroundUrl: material.url, // PDF 경로
          isTeacher: true,             // 교사 모드 켜기
          sessionId: widget.sessionId,
          roomId: 'room_${widget.sessionId}', // 임시 방 ID 세팅
          userId: '선생님',             // 임시 교사 이름
          serverUrl: 'pentalk-server-production.up.railway.app',
        ),
      ),
    );
  }

  /// ===============================
  /// 자료 목록 로드
  /// ===============================
  Future<void> _loadMaterials() async {
    final classId = widget.classId;
    if (classId == null) return;

    final materialProvider = context.read<MaterialProvider>();
    materialProvider.setLoading(true);

    try {
      final materials = await ApiService.getMaterials(classId: classId);
      if (!mounted) return;

      materialProvider.setMaterials(
        materials.map((m) => MaterialModel(
          id: m.id,
          title: m.name,
          fileName: m.name,
          url: m.url,
          sizeInBytes: 0, // 서버 응답에 size 없음
          uploadedAt: DateTime.parse(m.createdAt),
          type: FileMaterialType.pdf,
        )).toList(),
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
    final classId = widget.classId;
    if (classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('클래스 정보가 없어 업로드할 수 없습니다'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // 파일 선택 (PDF만)
      final file = await _fileService.pickFile();
      if (file == null) return;

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

      final fileName = file.path.split('/').last;

      // TODO: 서버 연결 후 실제 API 호출로 교체
      // 현재는 오프라인 더미 모드 (서버 연결 시 useOfflineDummy = false)
      const bool useOfflineDummy = true;

      if (!useOfflineDummy) {
        // 실제 API 업로드 (서버 연결 시 사용)
        final uploaded = await ApiService.uploadMaterial(
          classId: classId,
          filePath: file.path,
          fileName: fileName,
        );
        if (!mounted) return;

        // 👉 수정: 생성된 자료를 newMaterial 변수에 먼저 담습니다.
        final newMaterial = MaterialModel(
          id: uploaded.id,
          title: uploaded.name,
          fileName: uploaded.name,
          url: uploaded.url,
          sizeInBytes: fileSize,
          uploadedAt: DateTime.parse(uploaded.createdAt),
          type: FileMaterialType.pdf,
        );

        context.read<MaterialProvider>().addMaterial(newMaterial);

        // ⭐ 핵심 추가: Provider에 저장 후, 이 자료를 들고 판서 화면으로 바로 이동!
        _navigateToDrawing(context, material: newMaterial);

      } else {
        // 오프라인 더미: 로컬에만 추가
        if (!mounted) return;

        // 👉 수정: 생성된 더미 자료를 newMaterial 변수에 먼저 담습니다.
        final newMaterial = MaterialModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: fileName,
          fileName: fileName,
          url: file.path,
          sizeInBytes: fileSize,
          uploadedAt: DateTime.now(),
          type: FileMaterialType.pdf,
        );

        context.read<MaterialProvider>().addMaterial(newMaterial);

        // ⭐ 핵심 추가: Provider에 저장 후, 이 자료를 들고 판서 화면으로 바로 이동!
        _navigateToDrawing(context, material: newMaterial);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('자료가 업로드됐습니다'),
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
        SnackBar(
          content: Text('업로드 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _handleFileDelete(String fileId) async {
    try {
      context.read<MaterialProvider>().removeMaterial(fileId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('자료가 삭제됐습니다')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('삭제 실패: $e'),
            backgroundColor: Colors.red,
          ),
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
            return Text(session?.title ?? '세션');
          },
        ),
        actions: [
          if (_isUploading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20, height: 20,
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

          if (session == null) {
            return const Center(child: Text('세션을 찾을 수 없습니다'));
          }

          return Column(
            children: [
              BreadcrumbNavigation(
                paths: ['서예영 님의 공간', session.title],
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
                      Icon(Icons.upload_file, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('아직 업로드된 자료가 없습니다',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      Text('하단의 + 버튼을 눌러 자료를 업로드하세요',
                          style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: materialProvider.materials.length,
                  itemBuilder: (context, index) {
                    final material = materialProvider.materials[index];
                    return _MaterialListItem(
                      material: material,
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
        icon: const Icon(Icons.upload_file),
        label: const Text('자료 업로드'),
      ),
    );
  }
}

/// ===============================
/// 자료 목록 아이템
/// ===============================
class _MaterialListItem extends StatelessWidget {
  final MaterialModel material;
  final VoidCallback onDelete;

  const _MaterialListItem({
    required this.material,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
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
        content: Text('"\${material.title}" 자료를 삭제하시겠습니까?'),
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