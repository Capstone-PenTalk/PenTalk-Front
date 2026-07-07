import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/drawing_provider.dart';
import '../utils/pen_style_constants.dart';
import '../theme/app_colors.dart';

/// ===============================
/// 굵기 선택 바 (AppBar용)
/// 굿노트 스타일
/// ===============================
class WidthSelectorBar extends StatelessWidget {
  const WidthSelectorBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<DrawingProvider>(
      builder: (context, provider, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 굵기 아이콘 (인디케이터)
            const Icon(
              Icons.line_weight,
              size: 18,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),

            // 굵기 버튼들
            ...List.generate(
              PenStyleConstants.widthPresets.length,
                  (index) {
                final width = PenStyleConstants.widthPresets[index];
                final name = PenStyleConstants.widthNames[index];
                final isSelected = provider.currentWidth == width;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () {
                      provider.setWidth(width);
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withOpacity(0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 선 미리보기
                          Container(
                            width: 30,
                            height: width.clamp(2.0, 12.0),  // 표시용 높이 제한 (2~12)
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(width / 2),
                            ),
                          ),
                          const SizedBox(height: 2),
                          // 굵기 텍스트
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 9,
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.grey[600],
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
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