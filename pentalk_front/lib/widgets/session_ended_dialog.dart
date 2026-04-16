import 'package:flutter/material.dart';

/// ===============================
/// 세션 종료 관련 다이얼로그
/// ===============================
class SessionEndedDialog {
  /// 교사용: 세션 종료 확인 팝업
  static Future<bool> showEndConfirmation(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.logout, color: Colors.orange),
            SizedBox(width: 12),
            Text('세션 종료'),
          ],
        ),
        content: const Text(
          '세션을 종료하시겠습니까?\n\n'
              '모든 학생이 수업에서 나가게 되며,\n'
              '판서 내용은 서버에 저장됩니다.',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text(
              '종료',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// 학생용: 세션 종료 알림 팝업
  static Future<void> showStudentNotification(
      BuildContext context, {
        required String message,
        required VoidCallback onConfirm,
      }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 12),
            Text('수업 종료'),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: const Text(
              '확인',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 세션 종료 중 로딩 팝업
  static Future<void> showEndingProgress(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('세션을 종료하는 중...'),
            ],
          ),
        ),
      ),
    );
  }

  /// SESSION_ENDED 에러 팝업 (종료된 세션 재입장 시도)
  static Future<void> showSessionAlreadyEnded(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.block, color: Colors.red),
            SizedBox(width: 12),
            Text('입장 불가'),
          ],
        ),
        content: const Text(
          '이미 종료된 세션입니다.\n입장할 수 없습니다.',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}