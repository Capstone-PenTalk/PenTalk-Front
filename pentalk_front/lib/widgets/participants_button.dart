import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/participant_model.dart';
import '../providers/participants_provider.dart';
import '../widgets/participants_bottom_sheet.dart';

/// ===============================
/// 참여자 버튼 (AppBar용)
/// ===============================
class ParticipantsButton extends StatelessWidget {
  const ParticipantsButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Participant>>(
      stream: context.read<ParticipantsProvider>().participantsStream,
      initialData: context.read<ParticipantsProvider>().participants,
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;

        return IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.people_outline),
              // 참여자 수 배지
              if (count > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Center(
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () {
            ParticipantsBottomSheet.show(context);
          },
          tooltip: '참여자 목록',
        );
      },
    );
  }
}