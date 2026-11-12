/// 设置的持久化存储抽象。
///
/// 拆成抽象层的原因：`shared_preferences` 是平台插件，在 `flutter test`
/// 环境里没有注册，直接调用会抛异常；单元测试改用 [InMemorySettingsStore]。
abstract class SettingsStore {
  Future<Map<String, Object?>> readAll();

  Future<void> write(Map<String, Object?> values);
}

/// 内存实现：仅用于测试与插件不可用时的兜底。
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, Object?>? initial])
      : _values = <String, Object?>{...?initial};

  final Map<String, Object?> _values;

  @override
  Future<Map<String, Object?>> readAll() async => Map<String, Object?>.from(_values);

  @override
  Future<void> write(Map<String, Object?> values) async {
    _values.addAll(values);
  }
}
