
import 'package:flutter/material.dart';

class BreadcrumbNavigation extends StatelessWidget {
  final List<String> paths;
  final Function(int) onTap;

  const BreadcrumbNavigation({
    Key? key,
    required this.paths,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.folder,
            size: 20,
            color: Colors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(
                  paths.length,
                      (index) {
                    final isLast = index == paths.length - 1;
                    return Row(
                      children: [
                        InkWell(
                          onTap: isLast ? null : () => onTap(index),
                          child: Text(
                            paths[index],
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                              color: isLast ? Colors.black87 : Colors.blue,
                            ),
                          ),
                        ),
                        if (!isLast) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}