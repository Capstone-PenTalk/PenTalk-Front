import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../providers/material_provider.dart';
import '../services/auth_service.dart';
import '../widgets/session_card.dart';
import '../widgets/create_session_dialog.dart';
import 'session_detail_screen.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionProvider>().loadSessions();
      _loadUserName();
    });
  }

  Future<void> _loadUserName() async {
    final userId = await AuthService.getUserId();
    if (mounted && userId != null) {
      setState(() => _userName = userId);
    }
  }

  void _showCreateSessionDialog() {
    showDialog(
      context: context,
      builder: (context) => CreateSessionDialog(
        onCreateSession: (title, maxParticipants, password) async {
          await context.read<SessionProvider>().createSession(
            title: title,
            maxParticipants: maxParticipants,
            password: password,
          );
        },
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AuthService.logout();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '$_userName 님의 수업',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _showCreateSessionDialog,
            tooltip: '새 세션 만들기',
          ),
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: _handleLogout,
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: Consumer<SessionProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.sessions.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(provider.errorMessage!,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: provider.loadSessions,
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
                  Icon(Icons.folder_open, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('아직 생성된 세션이 없습니다',
                      style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  Text('우측 상단 + 버튼을 눌러 새 세션을 생성하세요',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500])),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showCreateSessionDialog,
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
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: _showCreateSessionDialog,
                    borderRadius: BorderRadius.circular(12),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 48, color: Colors.grey[600]),
                          const SizedBox(height: 8),
                          Text('새 세션',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[600])),
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
                          backgroundColor: Colors.red,
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
