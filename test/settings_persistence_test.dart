import 'package:codepad/core/settings/settings_controller.dart';
import 'package:codepad/data/repositories/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('设置写入后能被新的控制器读回', () async {
    final InMemorySettingsStore store = InMemorySettingsStore();

    final SettingsController first = SettingsController(store: store);
    await first.load();
    first.setThemeMode(ThemeMode.light);
    first.setEditorFontSize(20);
    first.setShowLineNumbers(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final SettingsController second = SettingsController(store: store);
    await second.load();
    expect(second.themeMode, ThemeMode.light);
    expect(second.editorFontSize, 20);
    expect(second.showLineNumbers, isFalse);
  });

  test('非法 / 越界值回退到默认值', () async {
    final InMemorySettingsStore store = InMemorySettingsStore(<String, Object?>{
      SettingsController.keyThemeMode: 'not-a-mode',
      SettingsController.keyFontSize: '999',
    });

    final SettingsController controller = SettingsController(store: store);
    await controller.load();

    expect(controller.themeMode, ThemeMode.dark);
    // 字号被夹到上限 26
    expect(controller.editorFontSize, 26);
    expect(controller.showLineNumbers, isTrue);
  });

  test('字号写入时同样夹紧范围', () async {
    final SettingsController controller = SettingsController();
    controller.setEditorFontSize(2);
    expect(controller.editorFontSize, 10);
    controller.setEditorFontSize(100);
    expect(controller.editorFontSize, 26);
  });
}
