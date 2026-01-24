
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../widgets/breadcrumb_navigation.dart';
import '../widgets/file_list_item.dart';
import '../services/file_service.dart';

class SessionDetailScreen extends StatefulWidget {
  final String sessionId;

  const SessionDetailScreen({
    Key? key,
    required this.sessionId,
  }) : super(key: key);

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  final FileService _fileService = FileService();
  bool _isUploading = false;

  void _handleFileUpload() async {
    try {
      final file = await _fileService.pickFile();
      if (file == null) return;

      // 파일 크기 검증
      final fileSize = await file.length();
      if (!_fileService.isValidFileSize(fileSize)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('파일 크기가 너무 큽니다 (최대 50MB)'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      setState(() {
        _isUploading = true;
      });

      // 파일 업로드
      final uploadedFile = await _fileService.uploadFile(file, widget.sessionId);

      // Provider에 파일 추가
      if (mounted) {
        await context.read<SessionProvider>().addFileToSession(
          widget.sessionId,
          uploadedFile,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('파일이 업로드되었습니다'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('파일 업로드 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _handleFileDownload(String fileUrl, String fileName) async {
    try {
      // TODO: 실제 다운로드 구현
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$fileName 다운로드 시작'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('다운로드 실패: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleFileDelete(String fileId) async {
    try {
      await context.read<SessionProvider>().deleteFileFromSession(
        widget.sessionId,
        fileId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('파일이 삭제되었습니다'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('파일 삭제 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<SessionProvider>(
          builder: (context, provider, child) {
            final session = provider.getSessionById(widget.sessionId);
            return Text(session?.title ?? '세션');
          },
        ),
        actions: [
          if (_isUploading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Consumer<SessionProvider>(
        builder: (context, provider, child) {
          final session = provider.getSessionById(widget.sessionId);

          if (session == null) {
            return const Center(
              child: Text('세션을 찾을 수 없습니다'),
            );
          }

          return Column(
            children: [
              // Breadcrumb 경로 표시
              BreadcrumbNavigation(
                paths: ['서예영 님의 공간', session.title],
                onTap: (index) {
                  if (index == 0) {
                    Navigator.pop(context);
                  }
                },
              ),

              // 파일 목록
              Expanded(
                child: session.files.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.upload_file,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '아직 업로드된 파일이 없습니다',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '하단의 + 버튼을 눌러 파일을 업로드하세요',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                )
                    : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: session.files.length,
                  itemBuilder: (context, index) {
                    final file = session.files[index];
                    return FileListItem(
                      file: file,
                      onTap: () {
                        _handleFileDownload(file.url, file.name);
                      },
                      onDelete: () {
                        _handleFileDelete(file.id);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _handleFileUpload,
        icon: const Icon(Icons.upload_file),
        label: const Text('파일 업로드'),
      ),
    );
  }
}