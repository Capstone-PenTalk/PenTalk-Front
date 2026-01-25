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

class DrawingHomePage extends StatelessWidget {
  const DrawingHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Native Drawing'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<BrushConfig>(
          valueListenable: NativeDrawingBridge.currentBrush,
          builder: (context, brush, child) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current tool: ${brush.tool}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Text('Brush size: ${brush.size.toStringAsFixed(1)}'),
                Text('Eraser size: ${brush.eraserSize.toStringAsFixed(1)}'),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      NativeDrawingBridge.open(brush);
                    },
                    child: const Text('Open Drawing'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
