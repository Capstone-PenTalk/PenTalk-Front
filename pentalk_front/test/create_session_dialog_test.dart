import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pentalk_front/widgets/create_session_dialog.dart';

void main() {
  testWidgets('CreateSessionDialog submits session options', (tester) async {
    String? submittedMaterialId;
    String? submittedTitle;
    int? submittedMaxParticipants;
    String? submittedPassword;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateSessionDialog(
            onCreateSession:
                (
                  materialId, {
                  required title,
                  maxParticipants,
                  password,
                }) async {
                  submittedMaterialId = materialId;
                  submittedTitle = title;
                  submittedMaxParticipants = maxParticipants;
                  submittedPassword = password;
                },
          ),
        ),
      ),
    );

    await tester.enterText(find.bySemanticsLabel('세션 제목'), '방정식 수업');
    await tester.enterText(find.bySemanticsLabel('최대 인원'), '24');
    await tester.tap(find.text('비밀번호 설정'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('비밀번호'), '1234');
    await tester.enterText(find.bySemanticsLabel('자료 ID (선택)'), 'material-1');

    await tester.ensureVisible(find.text('생성'));
    await tester.tap(find.text('생성'));
    await tester.pumpAndSettle();

    expect(submittedMaterialId, 'material-1');
    expect(submittedTitle, '방정식 수업');
    expect(submittedMaxParticipants, 24);
    expect(submittedPassword, '1234');
  });
}
