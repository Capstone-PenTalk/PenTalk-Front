
import 'package:flutter/material.dart';
import '../models/session_model.dart';
import 'package:intl/intl.dart';

class FileListItem extends StatelessWidget {
  final FileModel file;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const FileListItem({
    Key? key,
    required this.file,
    required this.onTap,
    this.onDelete,
  }) : super(key: key);

  IconData _getFileIcon() {
    switch (file.type) {
      case SessionFileType.pdf:
        return Icons.picture_as_pdf;
      case SessionFileType.image:
        return Icons.image;
      case SessionFileType.video:
        return Icons.video_file;
      case SessionFileType.document:
        return Icons.description;
      case SessionFileType.other:
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor() {
    switch (file.type) {
      case SessionFileType.pdf:
        return Colors.red;
      case SessionFileType.image:
        return Colors.blue;
      case SessionFileType.video:
        return Colors.purple;
      case SessionFileType.document:
        return Colors.green;
      case SessionFileType.other:
      default:
        return Colors.grey;
    }
  }


  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 1,
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _getFileIconColor().withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getFileIcon(),
            color: _getFileIconColor(),
            size: 28,
          ),
        ),
        title: Text(
          file.name,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              file.formattedSize,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            Text(
              _formatDate(file.uploadedAt),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        trailing: onDelete != null
            ? PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') {
              _confirmDelete(context);
            } else if (value == 'download') {
              onTap();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'download',
              child: Row(
                children: [
                  Icon(Icons.download, size: 20),
                  SizedBox(width: 8),
                  Text('다운로드'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('삭제', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        )
            : null,
        onTap: onTap,
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('파일 삭제'),
          content: Text('정말로 "${file.name}" 파일을 삭제하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                onDelete?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );
  }
}