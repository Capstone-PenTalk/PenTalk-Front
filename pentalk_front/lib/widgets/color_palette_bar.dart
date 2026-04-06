import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../utils/pen_style_constants.dart';

/// ===============================
/// 색상 팔레트 바 (AppBar용)
/// 굿노트 스타일
/// ===============================
class ColorPaletteBar extends StatelessWidget {
  const ColorPaletteBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, provider, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 색상 아이콘 (인디케이터)
            const Icon(Icons.palette, size: 18, color: Colors.grey),
            const SizedBox(width: 4),

            // 색상 버튼들
            ...List.generate(
              PenStyleConstants.colorPalette.length,
                  (index) {
                final color = PenStyleConstants.colorPalette[index];
                final isSelected = provider.currentColor.value == color.value;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () {
                      provider.setColor(color);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.grey[400]!,
                          width: isSelected ? 3 : 1,
                        ),
                        boxShadow: isSelected
                            ? [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          )
                        ]
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}