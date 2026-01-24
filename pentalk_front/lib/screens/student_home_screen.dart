
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_session_provider.dart';
import '../widgets/student_session_card.dart';
import 'material_list_screen.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({Key? key}) : super(key: key);

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;

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

  void _initializeTabController(List<String> subjects) {
    if (_tabController == null || _tabController!.length != subjects.length) {
      _tabController?.dispose();
      _tabController = TabController(
        length: subjects.length,
        vsync: this,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '서예영 님의 공간',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              // TODO: 프로필 화면으로 이동
            },
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
                color: Theme.of(context).colorScheme.surface,
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: Theme.of(context).primaryColor,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Theme.of(context).primaryColor,
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
                    child: CircularProgressIndicator(),
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
                          color: Colors.red,
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
                        Icon(
                          Icons.school_outlined,
                          size: 80,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '참여한 세션이 없습니다',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '교사가 공유한 QR 코드나 링크로 세션에 참여하세요',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
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
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: InkWell(
              onTap: () {
                // TODO: QR 스캔 또는 세션 코드 입력 화면
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('QR 코드 스캔 기능은 추후 구현 예정입니다'),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: Icon(
                  Icons.add,
                  size: 48,
                  color: Colors.grey[600],
                ),
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
                ),
              ),
            );
          },
        );
      },
    );
  }
}