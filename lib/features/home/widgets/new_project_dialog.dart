import 'package:flutter/material.dart';

import '../../../data/models/program_language.dart';

/// 新建工程对话框的返回值。
class NewProjectInput {
  const NewProjectInput({required this.name, required this.language});

  final String name;
  final ProgramLanguage language;
}

/// 新建工程对话框：输入名称 + 选择语言。
class NewProjectDialog extends StatefulWidget {
  const NewProjectDialog({super.key});

  @override
  State<NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<NewProjectDialog> {
  final TextEditingController _nameController =
      TextEditingController(text: '未命名工程');
  ProgramLanguage _language = ProgramLanguage.cpp;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(NewProjectInput(name: name, language: _language));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建工程'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: '工程名称'),
            ),
            const SizedBox(height: 20),
            Text(
              '语言',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ProgramLanguage>(
              showSelectedIcon: false,
              segments: <ButtonSegment<ProgramLanguage>>[
                for (final ProgramLanguage language in ProgramLanguage.values)
                  ButtonSegment<ProgramLanguage>(
                    value: language,
                    label: Text(language.label),
                  ),
              ],
              selected: <ProgramLanguage>{_language},
              onSelectionChanged: (Set<ProgramLanguage> selection) {
                setState(() => _language = selection.first);
              },
            ),
            const SizedBox(height: 12),
            Text(
              '将自动创建 ${_language.defaultFileName}，并写入 Hello World 模板。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}
