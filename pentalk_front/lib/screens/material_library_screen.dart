import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/student_session_model.dart';
import '../providers/session_provider.dart';
import '../providers/student_session_provider.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'material_detail_screen.dart';

/// ===============================
/// 자료 보관함
/// 내가 속한 모든 클래스의 자료를 모아서 보여줌
/// ===============================
class MaterialLibraryScreen extends StatefulWidget {
  final bool isTeacher;

  const MaterialLibraryScreen({Key? key, required this.isTeacher})
    : super(key: key);

  @override
  State<MaterialLibraryScreen> createState() => _MaterialLibraryScreenState();
}

class _MaterialLibraryScreenState extends State<MaterialLibraryScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<MaterialUploadResponse> _materials = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMaterials());
  }

  Future<void> _loadMaterials() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final classIds = widget.isTeacher
          ? context
                .read<SessionProvider>()
                .sessions
                .map((s) => s.classId)
                .whereType<String>()
                .toSet()
          : context
                .read<StudentSessionProvider>()
                .sessions
                .map((s) => s.classId)
                .whereType<String>()
                .toSet();

      debugPrint(
        '📚 Material library: role=${widget.isTeacher ? "teacher" : "student"}, '
        'classIds=$classIds',
      );
      if (!widget.isTeacher) {
        final rawSessions = context.read<StudentSessionProvider>().sessions;
        debugPrint(
          '📚 StudentSessionProvider.sessions: '
          '${rawSessions.map((s) => "(id=${s.id}, classId=${s.classId})").toList()}',
        );
      }

      final collected = <MaterialUploadResponse>[];
      for (final classId in classIds) {
        try {
          final items = await ApiService.getMaterials(classId: classId);
          collected.addAll(items);
        } catch (e) {
          debugPrint('⚠️ 자료 조회 실패 (classId=$classId): $e');
        }
      }

      collected.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() {
        _materials = collected;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '자료를 불러오지 못했습니다';
        _isLoading = false;
      });
    }
  }

  List<MaterialUploadResponse> get _filtered {
    if (_query.trim().isEmpty) return _materials;
    final q = _query.trim().toLowerCase();
    return _materials.where((m) => m.name.toLowerCase().contains(q)).toList();
  }

  void _openMaterial(MaterialUploadResponse item) {
    final material = MaterialModel(
      id: item.id,
      title: item.name,
      fileName: item.name,
      url: item.url,
      sizeInBytes: 0,
      uploadedAt: DateTime.tryParse(item.createdAt) ?? DateTime.now(),
      type: FileMaterialType.fromString(item.type),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MaterialDetailScreen(
          material: material,
          sessionTitle: item.name,
          teacherName: '',
          classId: item.classId,
          isTeacher: widget.isTeacher,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.folder_outlined,
                color: AppColors.primary,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              '자료 보관함',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: '자료 검색',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  prefixIcon: Icon(
                    Icons.search,
                    color: AppColors.textSecondary,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 56,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(_errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadMaterials,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.folder_open,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            const Text(
              '보관된 자료가 없습니다',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _MaterialRow(
        item: items[index],
        onTap: () => _openMaterial(items[index]),
      ),
    );
  }
}

class _MaterialRow extends StatelessWidget {
  final MaterialUploadResponse item;
  final VoidCallback onTap;

  const _MaterialRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final createdAt = DateTime.tryParse(item.createdAt);
    final dateLabel = createdAt != null
        ? DateFormat('yyyy.MM.dd').format(createdAt)
        : '';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF87171), Color(0xFFEF4444)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'PDF',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 9.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.download,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
