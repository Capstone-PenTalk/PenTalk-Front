import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'native_drawing.dart';
import 'providers/drawing_provider.dart';
import 'providers/student_session_provider.dart';
import 'providers/session_provider.dart';
import 'providers/poll_provider.dart';
import 'providers/personal_drawing_provider.dart';
import 'providers/participants_provider.dart';
import 'providers/material_provider.dart';
import 'screens/join_session_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NativeDrawingBridge.init().catchError((error, stackTrace) {
    debugPrint('NativeDrawingBridge.init failed: $error');
    if (stackTrace is StackTrace) {
      debugPrintStack(stackTrace: stackTrace);
    }
  });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StudentSessionProvider()),
        ChangeNotifierProvider(create: (_) => SessionProvider()),
        ChangeNotifierProvider(create: (_) => DrawingProvider()),
        ChangeNotifierProvider(create: (_) => PersonalDrawingProvider()),
        ChangeNotifierProvider(create: (_) => ParticipantsProvider()),
        ChangeNotifierProvider(create: (_) => PollProvider()),
        ChangeNotifierProvider(create: (_) => MaterialProvider()),
      ],
      child: MaterialApp(
        title: '하이브리드 교실',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
        ),

        onGenerateInitialRoutes: (initialRoute) {
          final joinSessionId = _parseJoinSessionId(initialRoute);
          if (joinSessionId != null) {
            return [
              MaterialPageRoute(
                settings: RouteSettings(name: initialRoute),
                builder: (_) => JoinSessionScreen(sessionId: joinSessionId),
              ),
            ];
          }
          return [
            MaterialPageRoute(
              settings: const RouteSettings(name: '/'),
              builder: (_) => const SplashScreen(),
            ),
          ];
        },
        onGenerateRoute: (settings) {
          final joinSessionId = _parseJoinSessionId(settings.name);
          if (joinSessionId != null) {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => JoinSessionScreen(sessionId: joinSessionId),
            );
          }
          if (settings.name == '/') {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const SplashScreen(),
            );
          }
          return null;
        },
      ),
    );
  }

  String? _parseJoinSessionId(String? routeName) {
    if (routeName == null || routeName.trim().isEmpty) return null;
    final uri = Uri.tryParse(routeName);
    final segments = uri?.pathSegments ?? const <String>[];
    if (segments.length == 2 && segments[0] == 'join') {
      final sessionId = segments[1].trim();
      return sessionId.isEmpty ? null : sessionId;
    }
    return null;
  }
}
