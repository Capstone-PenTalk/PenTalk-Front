import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_session_provider.dart';
import '../services/auth_service.dart';
import '../widgets/student_session_card.dart';
import '../theme/app_colors.dart';
import 'material_list_screen.dart';
import 'material_library_screen.dart';
import 'login_screen.dart';
import 'qr_scan_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({Key? key}) : super(key: key);

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StudentSessionProvider>().loadMySessions();
    });
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _handleSwitchRole() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _initializeTabController(List<String> subjects) {
    if (_tabController == null || _tabController!.length != subjects.length) {
      _tabController?.dispose();
      _tabController = TabController(length: subjects.length, vsync: this);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildHomeTab(),
          const MaterialLibraryScreen(isTeacher: false),
        ],
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
        title: const Text(
          '서예영 님의 공간',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle, color: AppColors.primary),
            onPressed: _handleSwitchRole,
            tooltip: '역할 변경',
          ),
        ],
      ),
      body: Column(
        children: [
          // 탭바를 body 안으로 이동
          Consumer<StudentSessionProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading || provider.subjects.isEmpty) {
                return const SizedBox.shrink();
              }

              _initializeTabController(provider.subjects);

              return Container(
                color: AppColors.surface,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primary,
                  labelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.normal,
                  ),
                  tabs: provider.subjects
                      .map((subject) => Tab(text: subject))
                      .toList(),
                ),
              );
            },
          ),
          // 나머지 body 내용
          Expanded(
            child: Consumer<StudentSessionProvider>(
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
                          onPressed: () {
                            provider.loadMySessions();
                          },
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
                          Icons.school_outlined,
                          size: 80,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '참여한 세션이 없습니다',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '교사가 공유한 QR 코드나 링크로 세션에 참여하세요',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return TabBarView(
                  controller: _tabController,
                  children: provider.subjects.map((subject) {
                    final sessions = provider.getSessionsBySubject(subject);
                    return _buildSessionGrid(sessions, subject);
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionGrid(List<dynamic> sessions, String subject) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: sessions.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // + 버튼 카드 (세션 추가용)
          return Card(
            color: AppColors.surface,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QrScanScreen()),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: const Center(
                child: Icon(Icons.add, size: 48, color: AppColors.primary),
              ),
            ),
          );
        }

        final session = sessions[index - 1];
        return StudentSessionCard(
          session: session,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MaterialListScreen(
                  sessionId: session.id,
                  classId: session.classId,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
