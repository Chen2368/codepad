/// 版本号比较与更新清单解析（纯 Dart，便于单元测试）。
library;

/// 把 `0.8.0` / `1.2` / `v1.2.3` 解析成可比较的数字列表。
List<int> parseVersion(String text) {
  final String cleaned = text.trim().replaceFirst(RegExp('^[vV]'), '');
  final List<int> parts = <int>[];
  for (final String chunk in cleaned.split('.')) {
    final StringBuffer digits = StringBuffer();
    for (final int code in chunk.codeUnits) {
      if (code >= 48 && code <= 57) {
        digits.writeCharCode(code);
      } else {
        break; // 遇到 `-beta` 之类的后缀就停，比较时忽略
      }
    }
    parts.add(digits.isEmpty ? 0 : int.parse(digits.toString()));
  }
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts;
}

/// [candidate] 是否比 [current] 更新。
bool isNewerVersion(String candidate, String current) {
  final List<int> a = parseVersion(candidate);
  final List<int> b = parseVersion(current);
  for (int i = 0; i < 3; i++) {
    if (a[i] != b[i]) {
      return a[i] > b[i];
    }
  }
  return false;
}

/// 一份更新清单。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    this.notes = '',
  });

  final String version;

  /// 新版本 APK 的下载地址（也可以是发布页）。
  final String url;
  final String notes;

  /// 解析 `{"version": "0.9.0", "url": "https://…", "notes": "…"}`。
  ///
  /// 容忍多余字段；缺 version 或 url 时返回 null（当作无效清单）。
  static UpdateInfo? tryParse(Object? json) {
    if (json is! Map) {
      return null;
    }
    final Object? version = json['version'];
    final Object? url = json['url'];
    if (version is! String || version.trim().isEmpty) {
      return null;
    }
    if (url is! String || url.trim().isEmpty) {
      return null;
    }
    final Object? notes = json['notes'];
    return UpdateInfo(
      version: version.trim(),
      url: url.trim(),
      notes: notes is String ? notes : '',
    );
  }
}
