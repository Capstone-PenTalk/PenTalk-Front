import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/drawing_provider.dart';
import 'providers/personal_drawing_provider.dart';
import 'providers/participants_provider.dart';
import 'screens/drawing_screen.dart';
import 'services/auth_service.dart';

/// ===============================
/// 세션 종료 UI 테스트용 main.dart
/// ===============================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 테스트용 토큰 저장
  await AuthService.saveUserInfo(
    token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJ0ZWFjaGVyX3Rlc3QiLCJyb2xlIjoidGVhY2hlciIsImlhdCI6MTc3MjYwMzk5MCwiZXhwIjoxNzczMjA4NzkwfQ.4_MvcZTSvmfNBeBHqr_jWcWGwH-lfklzhbUVFLMYRAk',
    userId: 'teacher_test',
    role: 'teacher',
  );

  runApp(const SessionEndTestApp());
}

class SessionEndTestApp extends StatelessWidget {
  const SessionEndTestApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DrawingProvider()),
        ChangeNotifierProvider(create: (_) => PersonalDrawingProvider()),
        ChangeNotifierProvider(create: (_) => ParticipantsProvider()),
      ],
      child: MaterialApp(
        title: '세션 종료 UI 테스트',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: const DrawingScreen(
          materialTitle: '🧪 세션 종료 UI 테스트',
          isTeacher: true,
        ),
      ),
    );
  }
}