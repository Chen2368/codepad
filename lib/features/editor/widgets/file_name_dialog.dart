import 'package:flutter/material.dart';

/// 通用「输入文件名 / 相对路径」对话框，返回 null 表示取消。
Future<String?> showFileNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String confirmLabel = '确定',
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => _FileNameDialog(
      title: title,
      initial: initial,
      hint: hint,
      confirmLabel: confirmLabel,
    ),
  );
}

/// 用 StatefulWidget 管理控制器生命周期：
/// 不能在 `showDialog` 返回后立刻 dispose 控制器——此时关闭动画还在跑，
/// TextField 仍会监听它，会抛 `A TextEditingController was used after being disposed`。
class _FileNameDialog extends StatefulWidget {
  const _FileNameDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
    this.hint,
  });

  final String title;
  final String initial;
  final String confirmLabel;
  final String? hint;

  @override
  State<_FileNameDialog> createState() => _FileNameDialogState();
}

class _FileNameDialogState extends State<_FileNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = '不能为空');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: '文件名 / 相对路径',
            hintText: widget.hint,
            errorText: _error,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
