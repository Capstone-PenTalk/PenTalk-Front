import 'package:flutter/material.dart';

/// ===============================
/// 입장 불가 팝업
/// 인증 실패 시 표시
/// ===============================
class AccessDeniedDialog {
  /// 인증 실패 팝업 (로그인 필요)
  static Future<void> showLoginRequired(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.lock, color: Colors.red),
            SizedBox(width: 12),
            Text('로그인 필요'),
          ],
        ),
        content: const Text(
          '수업에 참여하려면 먼저 로그인해주세요.',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // 팝업 닫기
              Navigator.pushReplacementNamed(context, '/login'); // 로그인 화면으로
            },
            child: const Text(
              '로그인하기',
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

  /// 권한 없음 팝업 (role 불일치)
  static Future<void> showPermissionDenied(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.block, color: Colors.orange),
            SizedBox(width: 12),
            Text('권한 없음'),
          ],
        ),
        content: const Text(
          '이 기능에 접근할 권한이 없습니다.\n교사 계정으로 로그인해주세요.',
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

  /// 세션 접근 불가 (classId 불일치 등)
  static Future<void> showSessionAccessDenied(
      BuildContext context, {
        String? reason,
      }) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 12),
            Text('입장 불가'),
          ],
        ),
        content: Text(
          reason ?? '이 세션에 접근할 수 없습니다.\n권한을 확인해주세요.',
          style: const TextStyle(fontSize: 15),
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

  /// 네트워크 오류
  static Future<void> showNetworkError(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.wifi_off, color: Colors.grey),
            SizedBox(width: 12),
            Text('네트워크 오류'),
          ],
        ),
        content: const Text(
          '서버에 연결할 수 없습니다.\n네트워크 연결을 확인해주세요.',
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

  /// 토큰 만료
  static Future<void> showTokenExpired(BuildContext context) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: const [
            Icon(Icons.timer_off, color: Colors.orange),
            SizedBox(width: 12),
            Text('세션 만료'),
          ],
        ),
        content: const Text(
          '로그인 세션이 만료되었습니다.\n다시 로그인해주세요.',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: const Text(
              '다시 로그인',
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
}