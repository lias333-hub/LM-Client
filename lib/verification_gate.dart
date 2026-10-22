part of 'main.dart';

enum VerifyStatus {
  pending,
  pass,
  fail,
}

class VerificationResult {
  final VerifyStatus status;
  final String command;
  final String stdout;
  final String stderr;
  final int exitCode;

  const VerificationResult({
    required this.status,
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  bool get passed => status == VerifyStatus.pass;
  bool get failed => status == VerifyStatus.fail;
}

class VerificationGate {
  static VerificationResult pass(
    String command, {
    String stdout = '',
    int exitCode = 0,
  }) {
    return VerificationResult(
      status: VerifyStatus.pass,
      command: command,
      stdout: stdout,
      stderr: '',
      exitCode: exitCode,
    );
  }

  static VerificationResult fail(
    String command, {
    String stderr = '',
    int exitCode = 1,
  }) {
    return VerificationResult(
      status: VerifyStatus.fail,
      command: command,
      stdout: '',
      stderr: stderr,
      exitCode: exitCode,
    );
  }

  static bool shouldBlockCompletion(VerificationResult result) {
    return result.status == VerifyStatus.fail;
  }
}
