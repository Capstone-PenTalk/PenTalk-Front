
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/student_session_provider.dart';
import '../widgets/material_card.dart';
import '../widgets/breadcrumb_navigation.dart';
import 'material_detail_screen.dart';

class MaterialListScreen extends StatelessWidget {
  final String sessionId;

  const MaterialListScreen({
    Key? key,
    required this.sessionId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<StudentSessionProvider>(
          builder: (context, provider, child) {
            final session = provider.getSessionById(sessionId);
            return Text(session?.title ?? '자료 목록');
          },
        ),
      ),
      body: Consumer<StudentSessionProvider>(
        builder: (context, provider, child) {
          final session = provider.getSessionById(sessionId);

          if (session == null) {
            return const Center(
              child: Text('세션을 찾을 수 없습니다'),
            );
          }

          return Column(
            children: [
              // Breadcrumb
              BreadcrumbNavigation(
                paths: [
                  '서예영 님의 공간',
                  session.subject,
                  '${session.title} (${session.teacherName})',
                ],
                onTap: (index) {
                  if (index == 0 || index == 1) {
                    Navigator.pop(context);
                  }
                },
              ),

              // 자료 목록
              Expanded(
                child: session.materials.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.folder_open,
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
                        '교사가 자료를 업로드하면 여기에 표시됩니다',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: session.materials.length,
                  itemBuilder: (context, index) {
                    final material = session.materials[index];
                    return MaterialCard(
                      material: material,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MaterialDetailScreen(
                              material: material,
                              sessionTitle: session.title,
                              teacherName: session.teacherName,
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