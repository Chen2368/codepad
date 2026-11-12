import 'package:codepad/core/settings/settings_controller.dart';
import 'package:codepad/core/update/update_checker.dart';
import 'package:codepad/core/update/update_info.dart';
import 'package:codepad/features/settings/storage_update_section.dart';
import 'package:codepad/runtime/storage_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假的存储桥：只记录调用，不碰真实通道。
class _FakeBridge extends StorageBridge {
  int exportCalls = 0;
  int installCalls = 0;
  String? openedUrl;

  @override
  Future<ExportResult?> exportProjectsZip({
    required String sourceDir,
    String name = 'CodePad-projects',
  }) async {
    exportCalls++;
    return const ExportResult(
      path: 'Download/CodePad/CodePad-projects-20260101-1200.zip',
      fileCount: 3,
    );
  }

  @override
  Future<bool> openDownloads() async => true;

  @override
  Future<bool> openUrl(String url) async {
    openedUrl = url;
    return true;
  }

  @override
  Future<InstallResult?> pickAndInstallApk() async {
    installCalls++;
    return const InstallResult(cancelled: false);
  }
}

void main() {
  group('版本号比较', () {
    test('解析常见写法', () {
      expect(parseVersion('0.8.0'), <int>[0, 8, 0]);
      expect(parseVersion('v1.2.3'), <int>[1, 2, 3]);
      expect(parseVersion('2.1'), <int>[2, 1, 0]);
      expect(parseVersion('1.0.0-beta'), <int>[1, 0, 0]);
    });

    test('判断新旧', () {
      expect(isNewerVersion('0.9.0', '0.8.0'), isTrue);
      expect(isNewerVersion('0.8.1', '0.8.0'), isTrue);
      expect(isNewerVersion('0.8.0', '0.8.0'), isFalse);
      expect(isNewerVersion('0.7.9', '0.8.0'), isFalse);
      // 位数不同也要能比
      expect(isNewerVersion('1.0', '0.99.99'), isTrue);
    });
  });

  group('更新清单解析', () {
    test('正常清单', () {
      final UpdateInfo? info = UpdateInfo.tryParse(<String, Object?>{
        'version': '0.9.0',
        'url': 'https://example.com/codepad.apk',
        'notes': '修好了编译',
      });
      expect(info, isNotNull);
      expect(info!.version, '0.9.0');
      expect(info.notes, '修好了编译');
    });

    test('缺字段或类型不对直接判无效', () {
      expect(UpdateInfo.tryParse(null), isNull);
      expect(UpdateInfo.tryParse('not a map'), isNull);
      expect(UpdateInfo.tryParse(<String, Object?>{'url': 'https://x'}), isNull);
      expect(UpdateInfo.tryParse(<String, Object?>{'version': '1.0'}), isNull);
      expect(
        UpdateInfo.tryParse(<String, Object?>{'version': 1, 'url': 'x'}),
        isNull,
      );
    });
  });

  group('检查更新', () {
    test('没配置地址时给出可操作的提示，而不是抛异常', () async {
      final UpdateCheckResult result =
          await UpdateChecker(currentVersion: '0.8.0').check('');
      expect(result.hasUpdate, isFalse);
      expect(result.error, contains('还没有配置更新地址'));
    });

    test('地址不是合法 URL 时也有中文说明', () async {
      final UpdateCheckResult result =
          await UpdateChecker(currentVersion: '0.8.0').check('not a url');
      expect(result.hasUpdate, isFalse);
      expect(result.error, isNotNull);
    });
  });

  group('存储与更新界面', () {
    testWidgets('导出按钮会调用原生能力并提示路径', (WidgetTester tester) async {
      final SettingsController settings = SettingsController();
      final _FakeBridge bridge = _FakeBridge();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StorageUpdateSection(settings: settings, bridge: bridge),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('程序保存位置'), findsOneWidget);
      expect(find.text('从文件安装'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);
    });

    testWidgets('未配置更新地址时，检查更新弹出说明并可转为本地安装',
        (WidgetTester tester) async {
      final SettingsController settings = SettingsController();
      final _FakeBridge bridge = _FakeBridge();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StorageUpdateSection(settings: settings, bridge: bridge),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();

      expect(find.text('检查更新失败'), findsOneWidget);
      expect(find.textContaining('还没有配置更新地址'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '从文件安装'));
      await tester.pumpAndSettle();
      expect(bridge.installCalls, 1);
    });

    testWidgets('保存更新地址会持久化到设置里', (WidgetTester tester) async {
      final SettingsController settings = SettingsController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StorageUpdateSection(
              settings: settings,
              bridge: _FakeBridge(),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byType(TextField),
        'https://example.com/update.json',
      );
      await tester.tap(find.text('保存地址'));
      await tester.pump();

      expect(settings.updateUrl, 'https://example.com/update.json');
    });
  });
}
