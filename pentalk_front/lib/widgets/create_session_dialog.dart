
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CreateSessionDialog extends StatefulWidget {
  final Function(String title, int maxParticipants, String? password) onCreateSession;

  const CreateSessionDialog({
    Key? key,
    required this.onCreateSession,
  }) : super(key: key);

  @override
  State<CreateSessionDialog> createState() => _CreateSessionDialogState();
}

class _CreateSessionDialogState extends State<CreateSessionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _maxParticipantsController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordEnabled = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _titleController.dispose();
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
          _titleController.text.trim(),
          int.parse(_maxParticipantsController.text.trim()),
          _isPasswordEnabled ? _passwordController.text.trim() : null,
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

              // 세션 제목
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '세션 제목',
                  hintText: '예: 1-2',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '세션 제목을 입력해주세요';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 제한 인원
              TextFormField(
                controller: _maxParticipantsController,
                decoration: const InputDecoration(
                  labelText: '제한 인원',
                  hintText: '예: 30',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.people),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '제한 인원을 입력해주세요';
                  }
                  final number = int.tryParse(value.trim());
                  if (number == null || number <= 0) {
                    return '올바른 인원 수를 입력해주세요';
                  }
                  if (number > 100) {
                    return '최대 100명까지 설정 가능합니다';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // 비밀번호 설정 체크박스
              Row(
                children: [
                  Checkbox(
                    value: _isPasswordEnabled,
                    onChanged: (value) {
                      setState(() {
                        _isPasswordEnabled = value ?? false;
                        if (!_isPasswordEnabled) {
                          _passwordController.clear();
                        }
                      });
                    },
                  ),
                  const Text('비밀번호 설정'),
                ],
              ),

              // 비밀번호 입력
              if (_isPasswordEnabled) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: '비밀번호',
                    hintText: '4자리 이상',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (_isPasswordEnabled) {
                      if (value == null || value.trim().isEmpty) {
                        return '비밀번호를 입력해주세요';
                      }
                      if (value.trim().length < 4) {
                        return '비밀번호는 4자리 이상이어야 합니다';
                      }
                    }
                    return null;
                  },
                ),
              ],

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