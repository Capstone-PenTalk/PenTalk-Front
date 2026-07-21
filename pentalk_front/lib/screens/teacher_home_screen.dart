import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../providers/material_provider.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../widgets/session_card.dart';
import '../widgets/create_session_dialog.dart';
import '../theme/app_colors.dart';
import 'session_detail_screen.dart';
import 'material_library_screen.dart';
import 'login_screen.dart';

/// ===============================
/// 교사 홈 화면
/// 세션 목록 + 자료 관리
/// ===============================
class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({Key? key}) : super(key: key);

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  String _userName = '선생님';
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionProvider>().loadSessions();
      _loadUserName();
    });
  }

  Future<void> _loadUserName() async {
    final displayName = await AuthService.getDisplayName();
    final userId = await AuthService.getUserId();
    final resolvedName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : userId;
    if (mounted && resolvedName != null) {
      setState(() => _userName = resolvedName);
    }
  }

  void _showCreateSessionDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateSessionDialog(
        onCreateSession:
            (materialId, {required title, maxParticipants, password}) async {
              await context.read<SessionProvider>().createSession(
                materialId: materialId,
                title: title,
                maxParticipants: maxParticipants,
                password: password,
              );
            },
      ),
    );
  }

  void _openLocalPdfWorkspace() {
    context.read<MaterialProvider>().clear();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SessionDetailScreen(
          sessionId: 'local-pdf-workspace',
          localOnly: true,
          titleOverride: '로컬 PDF 테스트',
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _tabIndex,
        children: [_buildHomeTab(), const MaterialLibraryScreen(isTeacher: true)],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primaryLight,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: AppColors.textSecondary),
            selectedIcon: Icon(Icons.home, color: AppColors.primary),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined, color: AppColors.textSecondary),
            selectedIcon: Icon(Icons.folder, color: AppColors.primary),
            label: '자료실',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '$_userName 님의 수업',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (AppConfig.allowLocalPdfWorkspace)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _openLocalPdfWorkspace,
              tooltip: '로컬 PDF 테스트',
            ),
          IconButton(
            icon: const Icon(
              Icons.add_circle_outline,
              color: AppColors.primary,
            ),
            onPressed: _showCreateSessionDialog,
            tooltip: '새 세션 만들기',
          ),
          IconButton(
            icon: const Icon(Icons.account_circle, color: AppColors.primary),
            onPressed: _handleLogout,
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: Consumer<SessionProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.sessions.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          if (provider.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: AppColors.danger,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    provider.errorMessage!,
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: provider.loadSessions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            );
          }

          if (provider.sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.folder_open,
                    size: 80,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '아직 생성된 세션이 없습니다',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '우측 상단 + 버튼을 눌러 새 세션을 생성하세요',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showCreateSessionDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('새 세션 만들기'),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: provider.sessions.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Card(
                  color: AppColors.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  child: InkWell(
                    onTap: _showCreateSessionDialog,
                    borderRadius: BorderRadius.circular(12),
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 48, color: AppColors.primary),
                          SizedBox(height: 8),
                          Text(
                            '새 세션',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final session = provider.sessions[index - 1];
              return SessionCard(
                session: session,
                onTap: () {
                  //  세션 상세 페이지로 이동
                  context.read<MaterialProvider>().clear();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SessionDetailScreen(
                        sessionId: session.id,
                        classId: session.classId,
                        password: session.password,
                      ),
                    ),
                  );
                },
                onDelete: () async {
                  try {
                    await provider.deleteSession(session.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('세션이 삭제됐습니다')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('삭제 실패: $e'),
                          backgroundColor: AppColors.danger,
                        ),
                      );
                    }
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
