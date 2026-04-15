import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_session_provider.dart';
import '../providers/material_provider.dart';
import '../providers/drawing_provider.dart';
import '../widgets/breadcrumb_navigation.dart';
import '../models/student_session_model.dart';
import '../services/api_service.dart';
import 'material_detail_screen.dart';

class MaterialListScreen extends StatefulWidget {
  final String sessionId;
  final String? classId; // 자료 목록 조회에 필요

  const MaterialListScreen({
    Key? key,
    required this.sessionId,
    this.classId,
  }) : super(key: key);

  @override
  State<MaterialListScreen> createState() => _MaterialListScreenState();
}

class _MaterialListScreenState extends State<MaterialListScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMaterials();
      _setupMaterialUploadListener();
    });
  }

  /// ===============================
  /// 자료 목록 로드 (REST API)
  /// classId 없으면 session의 더미 materials 사용
  /// ===============================
  Future<void> _loadMaterials() async {
    final classId = widget.classId;
    final materialProvider = context.read<MaterialProvider>();

    if (classId == null) {
      // classId 없으면 StudentSessionProvider의 기존 materials 사용
      final sessionProvider = context.read<StudentSessionProvider>();
      final session = sessionProvider.getSessionById(widget.sessionId);
      if (session != null) {
        materialProvider.setMaterials(session.materials);
      }
      return;
    }

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
          sizeInBytes: 0,
          uploadedAt: DateTime.parse(m.createdAt),
          type: FileMaterialType.pdf,
        )).toList(),
      );
    } catch (e) {
      debugPrint("Failed to load materials: " + e.toString());
      if (mounted) {
        // 실패 시 기존 session materials로 fallback
        final sessionProvider = context.read<StudentSessionProvider>();
        final session = sessionProvider.getSessionById(widget.sessionId);
        if (session != null) {
          materialProvider.setMaterials(session.materials);
        }
      }
    } finally {
      if (mounted) materialProvider.setLoading(false);
    }
  }

  /// ===============================
  /// material:uploaded 소켓 리스너 설정
  /// 수업 중 교사가 자료 업로드 시 실시간 반영
  /// ===============================
  void _setupMaterialUploadListener() {
    try {
      final drawingProvider = context.read<DrawingProvider>();
      final materialProvider = context.read<MaterialProvider>();

      drawingProvider.socketService.onMaterialUploaded = (data) {
        debugPrint("material:uploaded received");
        try {
          final material = MaterialModel(
            id: data["id"] as String,
            title: data["name"] as String,
            fileName: data["name"] as String,
            url: data["url"] as String,
            sizeInBytes: 0,
            uploadedAt: DateTime.parse(data["createdAt"] as String),
            type: FileMaterialType.pdf,
          );
          materialProvider.addMaterial(material);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("새 자료가 추가됐습니다: " + material.title),
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: "확인",
                  onPressed: () {},
                ),
              ),
            );
          }
        } catch (e) {
          debugPrint("Failed to parse material:uploaded: " + e.toString());
        }
      };
    } catch (e) {
      // DrawingProvider 없는 경우 (수업 외 화면) 무시
      debugPrint("No DrawingProvider for material socket: " + e.toString());
    }
  }

  @override
  void dispose() {
    // 리스너 정리
    try {
      final drawingProvider = context.read<DrawingProvider>();
      drawingProvider.socketService.onMaterialUploaded = null;
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<StudentSessionProvider>(
          builder: (context, provider, child) {
            final session = provider.getSessionById(widget.sessionId);
            return Text(session?.title ?? "자료 목록");
          },
        ),
        actions: [
          // 새로고침 버튼
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMaterials,
            tooltip: "새로고침",
          ),
        ],
      ),
      body: Consumer2<StudentSessionProvider, MaterialProvider>(
        builder: (context, sessionProvider, materialProvider, child) {
          final session = sessionProvider.getSessionById(widget.sessionId);

          if (session == null) {
            return const Center(child: Text("세션을 찾을 수 없습니다"));
          }

          return Column(
            children: [
              BreadcrumbNavigation(
                paths: [
                  "서예영 님의 공간",
                  session.subject,
                  session.title + " (" + session.teacherName + ")",
                ],
                onTap: (index) {
                  if (index == 0 || index == 1) Navigator.pop(context);
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
                      Icon(Icons.folder_open, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        "아직 업로드된 자료가 없습니다",
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "교사가 자료를 업로드하면 여기에 표시됩니다",
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: materialProvider.materials.length,
                  itemBuilder: (context, index) {
                    final material = materialProvider.materials[index];
                    return _MaterialCard(
                      material: material,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MaterialDetailScreen(
                              material: material,
                              sessionTitle: session.title,
                              teacherName: session.teacherName,
                              sessionId: widget.sessionId,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final MaterialModel material;
  final VoidCallback onTap;

  const _MaterialCard({required this.material, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 32),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      material.fileName,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}