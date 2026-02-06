
import 'package:flutter/material.dart';
import '../models/student_session_model.dart';
import 'package:intl/intl.dart';

class MaterialCard extends StatelessWidget {
  final MaterialModel material;
  final VoidCallback onTap;

  const MaterialCard({
    Key? key,
    required this.material,
    required this.onTap,
  }) : super(key: key);

  IconData _getMaterialIcon() {
    switch (material.type) {
      case FileMaterialType.pdf:
        return Icons.picture_as_pdf;
      case FileMaterialType.image:
        return Icons.image;
      case FileMaterialType.video:
        return Icons.video_file;
      case FileMaterialType.document:
        return Icons.description;
      case FileMaterialType.other:
        return Icons.insert_drive_file;
    }
  }

  Color _getMaterialIconColor() {
    switch (material.type) {
      case FileMaterialType.pdf:
        return Colors.red;
      case FileMaterialType.image:
        return Colors.blue;
      case FileMaterialType.video:
        return Colors.purple;
      case FileMaterialType.document:
        return Colors.green;
      case FileMaterialType.other:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy.MM.dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 파일 아이콘
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _getMaterialIconColor().withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getMaterialIcon(),
                  color: _getMaterialIconColor(),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              // 파일 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      material.fileName,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          material.formattedSize,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(material.uploadedAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 화살표 아이콘
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }
}