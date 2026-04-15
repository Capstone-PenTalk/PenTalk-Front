import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/participant_model.dart';
import '../providers/participants_provider.dart';

/// ===============================
/// 참여자 목록 바텀시트
/// ===============================
class ParticipantsBottomSheet extends StatelessWidget {
  const ParticipantsBottomSheet({Key? key}) : super(key: key);

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ParticipantsBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 핸들
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 헤더
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: StreamBuilder<List<Participant>>(
              stream: context.read<ParticipantsProvider>().participantsStream,
              builder: (context, snapshot) {
                final provider = context.watch<ParticipantsProvider>();

                return Row(
                  children: [
                    const Icon(Icons.people, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      '참여자',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${provider.totalCount}명',
                        style: TextStyle(
                          color: Colors.blue[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          const Divider(height: 1),

          // 참여자 목록
          Expanded(
            child: StreamBuilder<List<Participant>>(
              stream: context.read<ParticipantsProvider>().participantsStream,
              initialData: context.read<ParticipantsProvider>().participants,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          '참여자가 없습니다',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  );
                }

                final participants = snapshot.data!;
                final teachers = participants.where((p) => p.isTeacher).toList();
                final students = participants.where((p) => p.isStudent).toList();

                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    // 교사 섹션
                    if (teachers.isNotEmpty) ...[
                      _SectionHeader(
                        title: '교사',
                        count: teachers.length,
                        icon: Icons.school,
                        color: Colors.blue,
                      ),
                      ...teachers.map((p) => _ParticipantTile(participant: p)),
                      const SizedBox(height: 16),
                    ],

                    // 학생 섹션
                    if (students.isNotEmpty) ...[
                      _SectionHeader(
                        title: '학생',
                        count: students.length,
                        icon: Icons.person,
                        color: Colors.green,
                      ),
                      ...students.map((p) => _ParticipantTile(participant: p)),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// 섹션 헤더
/// ===============================
class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

/// ===============================
/// 참여자 타일
/// ===============================
class _ParticipantTile extends StatelessWidget {
  final Participant participant;

  const _ParticipantTile({required this.participant});

  @override
  Widget build(BuildContext context) {
    final isTeacher = participant.isTeacher;
    final color = isTeacher ? Colors.blue : Colors.green;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.1),
        child: Icon(
          isTeacher ? Icons.school : Icons.person,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        participant.userId,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isTeacher ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Text(
          isTeacher ? '교사' : '학생',
          style: TextStyle(
            fontSize: 12,
            color: color[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}