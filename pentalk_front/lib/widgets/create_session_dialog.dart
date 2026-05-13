import 'package:flutter/material.dart';

class CreateSessionDialog extends StatefulWidget {
  final Future<void> Function(
    String? materialId, {
    required String title,
    int? maxParticipants,
    String? password,
  })
  onCreateSession;

  const CreateSessionDialog({Key? key, required this.onCreateSession})
    : super(key: key);

  @override
  State<CreateSessionDialog> createState() => _CreateSessionDialogState();
}

class _CreateSessionDialogState extends State<CreateSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _materialIdController = TextEditingController();
  final _maxParticipantsController = TextEditingController(text: '30');
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _usePassword = false;

  @override
  void dispose() {
    _titleController.dispose();
    _materialIdController.dispose();
    _maxParticipantsController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleCreate() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        await widget.onCreateSession(
          _materialIdController.text.trim().isEmpty
              ? null
              : _materialIdController.text.trim(),
          title: _titleController.text.trim(),
          maxParticipants: int.tryParse(_maxParticipantsController.text.trim()),
          password: _usePassword && _passwordController.text.trim().isNotEmpty
              ? _passwordController.text.trim()
              : null,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '새 세션 생성',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '세션 제목',
                    hintText: '예: 1-2 방정식 수업',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.edit_note),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '세션 제목을 입력해주세요';
                    }
                    if (value.trim().length > 80) {
                      return '세션 제목은 80자 이하로 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _maxParticipantsController,
                  decoration: const InputDecoration(
                    labelText: '최대 인원',
                    hintText: '예: 30',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.people_outline),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    final number = int.tryParse(value?.trim() ?? '');
                    if (number == null || number <= 0) {
                      return '최대 인원을 1명 이상으로 입력해주세요';
                    }
                    if (number > 500) {
                      return '최대 인원은 500명 이하로 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('비밀번호 설정'),
                  value: _usePassword,
                  onChanged: _isLoading
                      ? null
                      : (value) {
                          setState(() {
                            _usePassword = value;
                            if (!value) _passwordController.clear();
                          });
                        },
                ),
                if (_usePassword) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: '비밀번호',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (!_usePassword) return null;
                      if (value == null || value.trim().isEmpty) {
                        return '비밀번호를 입력해주세요';
                      }
                      if (value.trim().length < 4) {
                        return '비밀번호는 4자 이상으로 입력해주세요';
                      }
                      return null;
                    },
                  ),
                ],
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
                      onPressed: _isLoading
                          ? null
                          : () {
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('생성'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
