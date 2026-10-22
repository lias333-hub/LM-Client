part of 'main.dart';

class RuntimeDecision {
  final bool stop;
  final bool requiresApproval;
  final bool requiresVerification;
  final String reason;

  const RuntimeDecision({
    required this.stop,
    required this.requiresApproval,
    required this.requiresVerification,
    required this.reason,
  });
}

class RuntimeGuard {
  static RuntimeDecision evaluate(
    RuntimeTaskState task, {
    required VerificationResult? verificationResult,
    required String toolName,
    bool wrote = false,
    bool shell = false,
  }) {
    final budgetStop = task.budget.isExhausted;
    final approvalNeeded = ToolPolicy.requiresApproval(toolName) || shell || wrote;
    final verifyRequired = task.phase == TaskRuntimePhase.verify || shell || wrote;

    if (budgetStop) {
      return const RuntimeDecision(
        stop: true,
        requiresApproval: false,
        requiresVerification: false,
        reason: 'Task budget exhausted.',
      );
    }

    if (verificationResult != null && verificationResult.failed) {
      return RuntimeDecision(
        stop: true,
        requiresApproval: false,
        requiresVerification: true,
        reason: 'Verification failed: ${verificationResult.stderr}',
      );
    }

    if (approvalNeeded) {
      return RuntimeDecision(
        stop: false,
        requiresApproval: true,
        requiresVerification: verifyRequired,
        reason: 'Dangerous or write-producing action requires approval.',
      );
    }

    return RuntimeDecision(
      stop: false,
      requiresApproval: false,
      requiresVerification: verifyRequired,
      reason: 'Task can continue safely.',
    );
  }

  static bool canClose(RuntimeTaskState task, VerificationResult? verificationResult) {
    if (task.budget.isExhausted) return false;
    if (verificationResult == null) return false;
    return verificationResult.passed;
  }
}

class ProjectExecutionDecision {
  final bool allowed;
  final String reason;

  const ProjectExecutionDecision({
    required this.allowed,
    required this.reason,
  });
}

class ProjectToolGuard {
  static ProjectExecutionDecision validate({
    required String projectType,
    required String root,
    required String toolName,
    required String targetPath,
    required String command,
    bool allowWrite = false,
  }) {
    final spec = ToolRegistry.byName(toolName);
    if (spec == null) {
      return const ProjectExecutionDecision(
        allowed: false,
        reason: 'Unknown tool.',
      );
    }

    if (!ToolPolicy.isAllowedForProject(projectType, toolName)) {
      return ProjectExecutionDecision(
        allowed: false,
        reason: 'Tool "$toolName" is not allowed for project type "$projectType".',
      );
    }

    if (ToolPolicy.requiresApproval(toolName)) {
      return ProjectExecutionDecision(
        allowed: allowWrite,
        reason: allowWrite
            ? 'Write operation approved.'
            : 'Write operation requires explicit user approval.',
      );
    }

    if (ToolPolicy.isDangerousCommand(command)) {
      return const ProjectExecutionDecision(
        allowed: false,
        reason: 'Dangerous command pattern blocked.',
      );
    }

    if (!ToolPolicy.isAllowedRoot(root, targetPath)) {
      return const ProjectExecutionDecision(
        allowed: false,
        reason: 'Target path is outside project root.',
      );
    }

    return const ProjectExecutionDecision(
      allowed: true,
      reason: 'Allowed.',
    );
  }
}
