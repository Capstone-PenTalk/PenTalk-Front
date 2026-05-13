import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pentalk_front/config/app_config.dart';
import 'package:pentalk_front/services/api_service.dart';
import 'package:pentalk_front/services/deep_link_service.dart';
import 'package:pentalk_front/widgets/qr_view.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  test('default server URL points at the configured backend', () {
    expect(AppConfig.apiBaseUrl, 'http://3.36.74.3:3000');
    expect(
      AppConfig.resolveSocketUrl(isTeacher: true),
      'http://3.36.74.3:3000',
    );
    expect(
      AppConfig.resolveSocketUrl(isTeacher: false),
      'http://3.36.74.3:3000',
    );
  });

  test('join web link uses the configured backend by default', () {
    expect(
      DeepLinkService().generateJoinWebLink('session-123'),
      'http://3.36.74.3:3000/join/session-123',
    );
    expect(
      DeepLinkService().generateJoinWebLink(
        'session-123',
        classId: 'seed-class-01',
        materialId: 'material-456',
      ),
      'http://3.36.74.3:3000/join/session-123?classId=seed-class-01&materialId=material-456',
    );
  });

  test('join link parser supports web, app, and server query links', () {
    final service = DeepLinkService();

    expect(
      service.parseJoinSessionId('http://3.36.74.3:3000/join/session-123'),
      'session-123',
    );
    expect(
      service.parseJoinSessionId('pentalk://join/session-123'),
      'session-123',
    );
    expect(
      service.parseJoinSessionId('*/?sessionId=session-123&role=student'),
      'session-123',
    );
    expect(
      service.parseJoinClassId(
        'http://3.36.74.3:3000/join/session-123?classId=seed-class-01&materialId=material-456',
      ),
      'seed-class-01',
    );
    expect(
      service.parseJoinMaterialId(
        'http://3.36.74.3:3000/join/session-123?classId=seed-class-01&materialId=material-456',
      ),
      'material-456',
    );
  });

  test('join response parses material payload from JOIN_SUCCESS', () {
    final response = SessionJoinResponse.fromJson({
      'roomId': 'session-123',
      'classId': 'class-123',
      'materialId': 'material-456',
      'material': {
        'id': 'material-456',
        'name': '5월 수학 자료.pdf',
        'type': 'PDF',
        'downloadUrl': 'https://example.com/pdfs/teacher1/uuid.pdf',
      },
      'user': {'userId': 'student1', 'role': 'student'},
    }, fallbackSessionId: 'fallback-session');

    expect(response.sessionId, 'session-123');
    expect(response.classId, 'class-123');
    expect(response.materialId, 'material-456');
    expect(response.material?.id, 'material-456');
    expect(response.material?.name, '5월 수학 자료.pdf');
    expect(response.material?.type, 'PDF');
    expect(
      response.material?.url,
      'https://example.com/pdfs/teacher1/uuid.pdf',
    );
  });

  test('join response parses wrapped JOIN_SUCCESS payload', () {
    final response = SessionJoinResponse.fromJson({
      'event': 'JOIN_SUCCESS',
      'data': {
        'roomId': 'session-123',
        'classId': 'class-123',
        'material': {
          'id': 'material-456',
          'name': '5월 수학 자료.pdf',
          'type': 'PDF',
          'url': 'pdfs/teacher1/uuid.pdf',
        },
      },
    }, fallbackSessionId: 'fallback-session');

    expect(response.sessionId, 'session-123');
    expect(response.classId, 'class-123');
    expect(response.materialId, 'material-456');
    expect(response.material?.url, 'pdfs/teacher1/uuid.pdf');
  });

  testWidgets('QrView renders a QR image with the provided URL', (
    tester,
  ) async {
    const url = 'http://3.36.74.3:3000/join/session-123';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: QrView(url: url)),
      ),
    );

    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.size, 220);
    expect(qr.backgroundColor, Colors.white);
  });
}
