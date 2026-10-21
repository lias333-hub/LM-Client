part of 'main.dart';

/// A small, production-oriented workflow harness for coding tasks.
/// It keeps task state, budgeting, phase transitions, and verification
/// requirements in one place instead of spreading them across ad-hoc chat logic.

class WorkflowPhase {
  static const String intake = 'intake';
  static const String scope = 'scope';
  static const String inspect = 'inspect';
  static const String plan = 'plan';
  static const String patch = 'patch';
  static const String verify = 'verify';
  static const String summarize = 'summarize';
  static const String blocked = 'blocked';

  static const List<String> ordered = <String>[
    intake,
    scope,
    inspect,
    plan,
    patch,
    verify,
    summarize,
  ];
}

class TaskBudget {
  final int maxTurns;
  final int maxReadOps;
  final int maxWriteOps;
  final int maxVerifyRuns;
  final int maxTokens;

  const TaskBudget({
    this.maxTurns = 18,
    this.maxReadOps = 8,
    this.maxWriteOps = 4,
    this.maxVerifyRuns = 3,
    this.maxTokens = 70000,
  });
}

class WorkflowTask {
  final String id;
  final String title;
  final String objective;
  final String rootPath;
  final String currentPhase;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int turnsUsed;
  final int readsUsed;
  final int writesUsed;
  final int verifyRuns;
  final int tokensUsed;
  final int tokensBudget;
  final bool blocked;
  final List<String> tags;
  final List<String> notes;
  final List<String> decisions;

  const WorkflowTask({
    required this.id,
    required this.title,
    required this.objective,
    required this.rootPath,
    this.currentPhase = WorkflowPhase.intake,
    required this.createdAt,
    required this.updatedAt,
    this.turnsUsed = 0,
    this.readsUsed = 0,
    this.writesUsed = 0,
    this.verifyRuns = 0,
    this.tokensUsed = 0,
    this.tokensBudget = 70000,
    this.blocked = false,
    this.tags = const <String>[],
    this.notes = const <String>[],
    this.decisions = const <String>[],
  });

  WorkflowTask copyWith({
    String? id,
    String? title,
    String? objective,
    String? rootPath,
    String? currentPhase,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? turnsUsed,
    int? readsUsed,
    int? writesUsed,
    int? verifyRuns,
    int? tokensUsed,
    int? tokensBudget,
    bool? blocked,
    List<String>? tags,
    List<String>? notes,
    List<String>? decisions,
  }) {
    return WorkflowTask(
      id: id ?? this.id,
      title: title ?? this.title,
      objective: objective ?? this.objective,
      rootPath: rootPath ?? this.rootPath,
      currentPhase: currentPhase ?? this.currentPhase,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      turnsUsed: turnsUsed ?? this.turnsUsed,
      readsUsed: readsUsed ?? this.readsUsed,
      writesUsed: writesUsed ?? this.writesUsed,
      verifyRuns: verifyRuns ?? this.verifyRuns,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      tokensBudget: tokensBudget ?? this.tokensBudget,
      blocked: blocked ?? this.blocked,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      decisions: decisions ?? this.decisions,
    );
  }
}

class WorkflowRuntime {
  final TaskBudget budget;
  final WorkflowTask task;

  const WorkflowRuntime({
    required this.budget,
    required this.task,
  });

  bool get isAtTurnLimit => task.turnsUsed >= budget.maxTurns;
  bool get isAtReadLimit => task.readsUsed >= budget.maxReadOps;
  bool get isAtWriteLimit => task.writesUsed >= budget.maxWriteOps;
  bool get isAtVerifyLimit => task.verifyRuns >= budget.maxVerifyRuns;
  bool get isAtTokenLimit => task.tokensUsed >= task.tokensBudget;

  WorkflowRuntime nextPhase(String nextPhase) {
    final now = DateTime.now();
    final updated = task.copyWith(
      currentPhase: nextPhase,
      updatedAt: now,
    );
    return WorkflowRuntime(budget: budget, task: updated);
  }

  WorkflowRuntime recordTurn({int tokenDelta = 0}) {
    final now = DateTime.now();
    final updated = task.copyWith(
      turnsUsed: task.turnsUsed + 1,
      tokensUsed: task.tokensUsed + tokenDelta,
      updatedAt: now,
    );
    return WorkflowRuntime(budget: budget, task: updated);
  }

  WorkflowRuntime recordRead({int tokenDelta = 0}) {
    final now = DateTime.now();
    final updated = task.copyWith(
      readsUsed: task.readsUsed + 1,
      tokensUsed: task.tokensUsed + tokenDelta,
      updatedAt: now,
    );
    return WorkflowRuntime(budget: budget, task: updated);
  }

  WorkflowRuntime recordWrite({int tokenDelta = 0}) {
    final now = DateTime.now();
    final updated = task.copyWith(
      writesUsed: task.writesUsed + 1,
      tokensUsed: task.tokensUsed + tokenDelta,
      updatedAt: now,
    );
    return WorkflowRuntime(budget: budget, task: updated);
  }

  WorkflowRuntime recordVerify({int tokenDelta = 0}) {
    final now = DateTime.now();
    final updated = task.copyWith(
      verifyRuns: task.verifyRuns + 1,
      tokensUsed: task.tokensUsed + tokenDelta,
      updatedAt: now,
    );
    return WorkflowRuntime(budget: budget, task: updated);
  }

  WorkflowRuntime addNote(String note) {
    final now = DateTime.now();
    final notes = <String>[...task.notes, note];
    final updated = task.copyWith(
      notes: notes,
      updatedAt: now,
    );
    return WorkflowRuntime(budget: budget, task: updated);
  }

  WorkflowRuntime addDecision(String decision) {
    final now = DateTime.now();
    final decisions = <String>[...task.decisions, decision];
    final updated = task.copyWith(
      decisions: decisions,
      updatedAt: now,
    );
    return WorkflowRuntime(budget: budget, task: updated);
  }

  WorkflowRuntime block(String reason) {
    final now = DateTime.now();
    final updated = task.copyWith(
      blocked: true,
      currentPhase: WorkflowPhase.blocked,
      updatedAt: now,
      notes: <String>[...task.notes, reason],
    );
    return WorkflowRuntime(budget: budget, task: updated);
  }
}

class ProjectAtlas {
  final String root;
  final String projectType;
  final List<String> keyFiles;
  final List<String> sourceDirs;
  final List<String> buildFiles;
  final List<String> testFiles;
  final List<String> ignorePatterns;
  final List<String> allowedRoots;

  const ProjectAtlas({
    required this.root,
    this.projectType = 'generic',
    this.keyFiles = const <String>[],
    this.sourceDirs = const <String>[],
    this.buildFiles = const <String>[],
    this.testFiles = const <String>[],
    this.ignorePatterns = const <String>[],
    this.allowedRoots = const <String>[],
  });
}

class WorkflowDecision {
  final String phase;
  final String reason;
  final List<String> remainingSteps;

  const WorkflowDecision({
    required this.phase,
    required this.reason,
    this.remainingSteps = const <String>[],
  });
}

class WorkflowHarness {
  static const int defaultTokenBudget = 70000;

  static WorkflowTask createTask({
    required String title,
    required String objective,
    String rootPath = '/',
    int tokenBudget = defaultTokenBudget,
  }) {
    final now = DateTime.now();
    return WorkflowTask(
      id: const Uuid().v4(),
      title: title,
      objective: objective,
      rootPath: rootPath,
      createdAt: now,
      updatedAt: now,
      tokensBudget: tokenBudget,
    );
  }

  static WorkflowDecision decideNextPhase(WorkflowTask task, {int extraReads = 0, int extraWrites = 0}) {
    final phase = task.currentPhase;

    if (task.blocked) {
      return const WorkflowDecision(
        phase: WorkflowPhase.blocked,
        reason: 'The task is blocked and needs user input or additional constraints.',
        remainingSteps: <String>['clarify blocker', 'adjust scope', 'resume'],
      );
    }

    if (task.tokensUsed >= task.tokensBudget) {
      return const WorkflowDecision(
        phase: WorkflowPhase.summarize,
        reason: 'The task reached its budget threshold. Compact and summarize remaining work.',
        remainingSteps: <String>['summarize progress', 'restate blockers', 'request continuation if needed'],
      );
    }

    if (task.readsUsed + extraReads >= 8) {
      return const WorkflowDecision(
        phase: WorkflowPhase.plan,
        reason: 'Enough information has been gathered to form a precise plan.',
        remainingSteps: <String>['confirm root cause', 'prepare patch', 'verify'],
      );
    }

    if (task.writesUsed + extraWrites >= 4) {
      return const WorkflowDecision(
        phase: WorkflowPhase.verify,
        reason: 'The fix has been applied; verification is required before completion.',
        remainingSteps: <String>['run targeted validation', 'report result', 'summarize'],
      );
    }

    switch (phase) {
      case WorkflowPhase.intake:
        return const WorkflowDecision(
          phase: WorkflowPhase.scope,
          reason: 'Task is accepted and the project scope needs to be narrowed.',
          remainingSteps: <String>['identify project root', 'detect project type', 'narrow files'],
        );
      case WorkflowPhase.scope:
        return const WorkflowDecision(
          phase: WorkflowPhase.inspect,
          reason: 'The project is scoped; inspect the minimal relevant files.',
          remainingSteps: <String>['inspect likely entry points', 'check build/test flow', 'read only relevant ranges'],
        );
      case WorkflowPhase.inspect:
        return const WorkflowDecision(
          phase: WorkflowPhase.plan,
          reason: 'The issue is understood well enough to plan exact changes.',
          remainingSteps: <String>['define fix plan', 'confirm risk', 'prepare patch'],
        );
      case WorkflowPhase.plan:
        return const WorkflowDecision(
          phase: WorkflowPhase.patch,
          reason: 'The fix plan is ready; patch the exact files and ranges.',
          remainingSteps: <String>['apply patch', 'keep changes minimal', 'record decisions'],
        );
      case WorkflowPhase.patch:
        return const WorkflowDecision(
          phase: WorkflowPhase.verify,
          reason: 'Patch is in place; validate the intended behavior with minimal checks.',
          remainingSteps: <String>['run targeted verification', 'review diffs', 'summarize outcomes'],
        );
      case WorkflowPhase.verify:
        return const WorkflowDecision(
          phase: WorkflowPhase.summarize,
          reason: 'The change has been validated or the result is documented with remaining risks.',
          remainingSteps: <String>['report status', 'note verification evidence', 'list next steps'],
        );
      case WorkflowPhase.summarize:
        return const WorkflowDecision(
          phase: WorkflowPhase.summarize,
          reason: 'The task has reached a stable completion state.',
          remainingSteps: <String>['final answer', 'state evidence', 'close task'],
        );
      default:
        return const WorkflowDecision(
          phase: WorkflowPhase.blocked,
          reason: 'Unexpected phase, task should be re-evaluated.',
          remainingSteps: <String>['restate objective', 're-check scope', 'reset to intake'],
        );
    }
  }

  static ProjectAtlas detectProjectAtlas(String rootPath) {
    final normalized = rootPath.trim().isEmpty ? '/' : rootPath;
    final lower = normalized.toLowerCase();

    final isAndroid = lower.contains('android') || lower.contains('app/') || lower.contains('flutter');
    final isWeb = lower.contains('web') || lower.contains('frontend');
    final isSdk = lower.contains('sdk') || lower.contains('library');

    String type = 'generic';
    if (isAndroid) type = 'android';
    else if (isWeb) type = 'web';
    else if (isSdk) type = 'sdk';

    final buildFiles = <String>[];
    if (isAndroid) {
      buildFiles.add('android/build.gradle');
      buildFiles.add('android/app/build.gradle');
      buildFiles.add('pubspec.yaml');
    }
    if (type == 'web') {
      buildFiles.add('package.json');
      buildFiles.add('vite.config.*');
    }
    if (type == 'sdk') {
      buildFiles.add('pubspec.yaml');
      buildFiles.add('README.md');
    }

    final sourceDirs = <String>[];
    if (isAndroid || type == 'sdk') {
      sourceDirs.add('lib');
      sourceDirs.add('test');
    }
    if (type == 'web') {
      sourceDirs.add('src');
      sourceDirs.add('app');
    }

    return ProjectAtlas(
      root: normalized,
      projectType: type,
      buildFiles: buildFiles,
      sourceDirs: sourceDirs,
      testFiles: <String>['test', 'tests', 'integration_test'],
      ignorePatterns: <String>['.git', 'build', '.dart_tool', '.idea', 'node_modules', '.venv', 'Pods'],
      allowedRoots: <String>[normalized],
    );
  }
}
