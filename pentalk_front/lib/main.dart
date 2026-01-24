
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/student_session_provider.dart';
import 'providers/drawing_provider.dart';
import 'screens/student_home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StudentSessionProvider()),
        ChangeNotifierProvider(create: (_) => DrawingProvider()),
      ],
      child: MaterialApp(
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
      ),
    );
  }
}
