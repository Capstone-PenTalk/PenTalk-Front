import 'package:flutter/material.dart';
import 'native_drawing.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NativeDrawingBridge.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PenTalk',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F172A)),
        useMaterial3: true,
      ),
      home: const DrawingHomePage(),
    );
  }
}

class DrawingHomePage extends StatefulWidget {
  const DrawingHomePage({super.key});

  @override
  State<DrawingHomePage> createState() => _DrawingHomePageState();
}

class _DrawingHomePageState extends State<DrawingHomePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PenTalk'),
      ),
      body: Center(
        child: ValueListenableBuilder<BrushConfig>(
          valueListenable: NativeDrawingBridge.currentBrush,
          builder: (context, brush, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PenTalk',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    NativeDrawingBridge.open(brush);
                  },
                  child: const Text('Open Drawing'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
