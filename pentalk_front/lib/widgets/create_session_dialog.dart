
import 'package:flutter/material.dart';

class CreateSessionDialog extends StatefulWidget {
  final Future<void> Function(String classId, String? materialId) onCreateSession;

  const CreateSessionDialog({
    Key? key,
    required this.onCreateSession,
  }) : super(key: key);

  @override
  State<CreateSessionDialog> createState() => _CreateSessionDialogState();
}

class _CreateSessionDialogState extends State<CreateSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _classIdController = TextEditingController();
  final _materialIdController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _classIdController.dispose();
    _materialIdController.dispose();
    super.dispose();
  }

  void _handleCreate() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        await widget.onCreateSession(
          _classIdController.text.trim(),
          _materialIdController.text.trim().isEmpty
              ? null
              : _materialIdController.text.trim(),
        );

        if (mounted) {
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('세션 생성 실패: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '새 세션 생성',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),

              // classId
              TextFormField(
                controller: _classIdController,
                decoration: const InputDecoration(
                  labelText: '클래스 ID',
                  hintText: '예: seed-class-01',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.class_),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '클래스 ID를 입력해주세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // materialId (선택)
              TextFormField(
                controller: _materialIdController,
                decoration: const InputDecoration(
                  labelText: '자료 ID (선택)',
                  hintText: '예: seed-material-01',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.picture_as_pdf),
                ),
              ),

              const SizedBox(height: 24),

              // 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleCreate,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                        : const Text('생성'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
