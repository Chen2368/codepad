/// 一次运行的执行状态。
enum RunStatus {
  idle,
  running,
  success,
  failed,
  cancelled,
}

extension RunStatusX on RunStatus {
  /// 是否已经结束（可再次点击运行）。
  bool get isFinished =>
      this == RunStatus.success ||
      this == RunStatus.failed ||
      this == RunStatus.cancelled;

  String get label {
    switch (this) {
      case RunStatus.idle:
        return '空闲';
      case RunStatus.running:
        return '运行中';
      case RunStatus.success:
        return '运行成功';
      case RunStatus.failed:
        return '运行失败';
      case RunStatus.cancelled:
        return '已取消';
    }
  }
}

/// 一次运行的结果。
class RunResult {
  const RunResult({
    required this.status,
    this.command = '',
    this.stdoutText = '',
    this.stderrText = '',
    this.exitCode,
    this.duration = Duration.zero,
  });

  final RunStatus status;

  /// 实际执行（或将要执行）的命令行，用于控制台回显。
  final String command;

  final String stdoutText;
  final String stderrText;

  /// 退出码；未执行完成时为 null。
  final int? exitCode;

  final Duration duration;

  bool get isSuccess => status == RunStatus.success;

  RunResult copyWith({
    RunStatus? status,
    String? command,
    String? stdoutText,
    String? stderrText,
    int? exitCode,
    Duration? duration,
  }) {
    return RunResult(
      status: status ?? this.status,
      command: command ?? this.command,
      stdoutText: stdoutText ?? this.stdoutText,
      stderrText: stderrText ?? this.stderrText,
      exitCode: exitCode ?? this.exitCode,
      duration: duration ?? this.duration,
    );
  }

  @override
  String toString() =>
      'RunResult($status, exitCode=$exitCode, ${duration.inMilliseconds}ms)';
}
