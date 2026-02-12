import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'providers/student_session_provider.dart';
import 'providers/drawing_provider.dart';
import 'providers/personal_drawing_provider.dart';
import 'screens/student_home_screen.dart';
import 'screens/material_detail_screen.dart';
import 'screens/drawing_screen.dart';
import 'services/deep_link_service.dart';
import 'models/student_session_model.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final DeepLinkService _deepLinkService = DeepLinkService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  /// Deep Link 초기화
  void _initDeepLinks() {
    // 1. 앱 시작 시 초기 링크 확인
    _handleInitialLink();

    // 2. 백그라운드에서 복귀 시 링크 감지
    _linkSubscription = _deepLinkService.uriLinkStream.listen(
          (Uri uri) {
        debugPrint('📱 Received Deep Link: $uri');
        _handleDeepLink(uri.toString());
      },
      onError: (err) {
        debugPrint('❌ Deep Link error: $err');
      },
    );
  }

  /// 앱 시작 시 초기 링크 처리
  Future<void> _handleInitialLink() async {
    try {
      final initialLink = await _deepLinkService.getInitialLink();
      if (initialLink != null) {
        // 앱이 완전히 로드된 후 처리
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleDeepLink(initialLink);
        });
      }
    } catch (e) {
      debugPrint('❌ Failed to handle initial link: $e');
    }
  }

  /// Deep Link 처리
  void _handleDeepLink(String uriString) {
    final params = _deepLinkService.parseMaterialLink(uriString);

    if (params == null) {
      debugPrint('⚠️ Invalid Deep Link format');
      return;
    }

    final sessionId = params['sessionId']!;
    final materialId = params['materialId']!;

    // Navigator로 화면 이동
    _navigatorKey.currentState?.pushNamed(
      '/material',
      arguments: {
        'sessionId': sessionId,
        'materialId': materialId,
      },
    );
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StudentSessionProvider()),
        ChangeNotifierProvider(create: (_) => DrawingProvider()),
        ChangeNotifierProvider(create: (_) => PersonalDrawingProvider()),
      ],
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: '하이브리드 교실 - 학생',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
          ),
        ),
        home: const StudentHomeScreen(),

        // Named Routes 정의
        routes: {
          '/home': (context) => const StudentHomeScreen(),
        },

        // Dynamic Routes (Deep Link용)
        onGenerateRoute: (settings) {
          // /material 라우트 처리
          if (settings.name == '/material') {
            final args = settings.arguments as Map<String, String>?;

            if (args == null) {
              return null;
            }

            final sessionId = args['sessionId']!;
            final materialId = args['materialId']!;

            return MaterialPageRoute(
              builder: (context) => _MaterialDetailLoader(
                sessionId: sessionId,
                materialId: materialId,
              ),
            );
          }

          return null;
        },
      ),
    );
  }
}

/// ===============================
/// Deep Link로 진입 시 자료 로드 후 MaterialDetailScreen 표시
/// ===============================
class _MaterialDetailLoader extends StatefulWidget {
  final String sessionId;
  final String materialId;

  const _MaterialDetailLoader({
    required this.sessionId,
    required this.materialId,
  });

  @override
  State<_MaterialDetailLoader> createState() => _MaterialDetailLoaderState();
}

class _MaterialDetailLoaderState extends State<_MaterialDetailLoader> {
  bool _isLoading = true;
  MaterialModel? _material;
  StudentSessionModel? _session;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMaterial();
  }

  Future<void> _loadMaterial() async {
    try {
      final provider = context.read<StudentSessionProvider>();

      // 세션 데이터가 없으면 로드
      if (provider.sessions.isEmpty) {
        await provider.loadMySessions();
      }

      // 세션 찾기
      _session = provider.getSessionById(widget.sessionId);

      if (_session == null) {
        setState(() {
          _errorMessage = '세션을 찾을 수 없습니다';
          _isLoading = false;
        });
        return;
      }

      // 자료 찾기
      _material = _session!.materials.firstWhere(
            (m) => m.id == widget.materialId,
        orElse: () => throw Exception('자료를 찾을 수 없습니다'),
      );

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '자료를 불러올 수 없습니다: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('자료 로딩 중...')),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('오류')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('돌아가기'),
              ),
            ],
          ),
        ),
      );
    }

    return MaterialDetailScreen(
      material: _material!,
      sessionTitle: _session!.title,
      teacherName: _session!.teacherName,
    );
  }
}