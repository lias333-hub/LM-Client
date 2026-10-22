part of 'main.dart';

/// Compact runtime state for project-aware agentic work.
/// This uses a smaller, explicit task model so the app can stay within
/// a tight token budget without sending the entire transcript every round.
enum TaskRuntimePhase {
  intake,
  scope,
  inspect,
  plan,
  patch,
  verify,
  finalize,
  blocked,
}

class RuntimeBudget {
  final int tokenCap;
  final int readCap;
  final int writeCap;
  final int verifyCap;
  final int toolCap;

  int tokensUsed = 0;
  int readsUsed = 0;
  int writesUsed = 0;
  int verifyRuns = 0;
  int toolCalls = 0;

  RuntimeBudget({
    required this.tokenCap,
    required this.readCap,
    required this.writeCap,
    required this.verifyCap,
    required this.toolCap,
  });

  bool get isExhausted =>
      tokensUsed >= tokenCap ||
      readsUsed >= readCap ||
      writesUsed >= writeCap ||
      verifyRuns >= verifyCap ||
      toolCalls >= toolCap;

  void recordTokens(int count) {
    if (count <= 0) return;
    tokensUsed += count;
  }

  void recordRead() => readsUsed++;
  void recordWrite() => writesUsed++;
  void recordVerify() => verifyRuns++;
  void recordToolCall() => toolCalls++;

  String get summary =>
      'tokens=$tokensUsed/$tokenCap | reads=$readsUsed/$readCap | writes=$writesUsed/$writeCap | verify=$verifyRuns/$verifyCap';
}

class RuntimeTaskState {
  final String id;
  final String title;
  final String objective;
  final String rootPath;
  final TaskRuntimePhase phase;
  final RuntimeBudget budget;
  final List<String> relevantFiles;
  final List<String> decisions;
  final List<String> verificationNotes;
  final List<String> errors;

  const RuntimeTaskState({
    required this.id,
    required this.title,
    required this.objective,
    required this.rootPath,
    required this.phase,
    required this.budget,
    required this.relevantFiles,
    required this.decisions,
    required this.verificationNotes,
    required this.errors,
  });

  RuntimeTaskState copyWith({
    String? id,
    String? title,
    String? objective,
    String? rootPath,
    TaskRuntimePhase? phase,
    RuntimeBudget? budget,
    List<String>? relevantFiles,
    List<String>? decisions,
    List<String>? verificationNotes,
    List<String>? errors,
  }) {
    return RuntimeTaskState(
      id: id ?? this.id,
      title: title ?? this.title,
      objective: objective ?? this.objective,
      rootPath: rootPath ?? this.rootPath,
      phase: phase ?? this.phase,
      budget: budget ?? this.budget,
      relevantFiles: relevantFiles ?? this.relevantFiles,
      decisions: decisions ?? this.decisions,
      verificationNotes: verificationNotes ?? this.verificationNotes,
      errors: errors ?? this.errors,
    );
  }

  String buildCompactPrompt() {
    final lines = <String>[
      'Task: $title',
      'Objective: $objective',
      'Root: $rootPath',
      'Phase: ${phase.name}',
      'Budget: ${budget.summary}',
      'RelevantFiles: ${relevantFiles.isEmpty ? 'none' : relevantFiles.join(', ')}',
      'RecentDecisions: ${decisions.isEmpty ? 'none' : decisions.takeLast(3).join(' | ')}',
      'Verification: ${verificationNotes.isEmpty ? 'not started' : verificationNotes.takeLast(2).join(' | ')}',
      'Errors: ${errors.isEmpty ? 'none' : errors.takeLast(2).join(' | ')}',
    ];
    return lines.join('\n');
  }
}

class CompactTaskSnapshot {
  final String taskTitle;
  final String objective;
  final String rootPath;
  final String phase;
  final String budgetSummary;
  final List<String> relevantFiles;
  final List<String> decisions;
  final List<String> verificationNotes;
  final List<String> activeErrors;

  const CompactTaskSnapshot({
    required this.taskTitle,
    required this.objective,
    required this.rootPath,
    required this.phase,
    required this.budgetSummary,
    required this.relevantFiles,
    required this.decisions,
    required this.verificationNotes,
    required this.activeErrors,
  });

  String buildPrompt() {
    return [
      'Project Task: $taskTitle',
      'Objective: $objective',
      'Root: $rootPath',
      'Phase: $phase',
      'Budget: $budgetSummary',
      'Files: ${relevantFiles.isEmpty ? 'not selected yet' : relevantFiles.join(', ')}',
      'Decisions: ${decisions.isEmpty ? 'none' : decisions.takeLast(3).join(' | ')}',
      'Verification: ${verificationNotes.isEmpty ? 'not started' : verificationNotes.takeLast(2).join(' | ')}',
      'Errors: ${activeErrors.isEmpty ? 'none' : activeErrors.takeLast(2).join(' | ')}',
    ].join('\n');
  }
}

class RuntimeContextManager {
  static CompactTaskSnapshot buildSnapshot(RuntimeTaskState task) {
    return CompactTaskSnapshot(
      taskTitle: task.title,
      objective: task.objective,
      rootPath: task.rootPath,
      phase: task.phase.name,
      budgetSummary: task.budget.summary,
      relevantFiles: task.relevantFiles,
      decisions: task.decisions,
      verificationNotes: task.verificationNotes,
      activeErrors: task.errors,
    );
  }

  static String compactHistory({
    required RuntimeTaskState task,
    required List<String> recentMessages,
    int keepLast = 3,
  }) {
    final snapshot = buildSnapshot(task);
    final recent = recentMessages.length > keepLast ? recentMessages.takeLast(keepLast).toList() : recentMessages;

    return [
      snapshot.buildPrompt(),
      '',
      'Recent Messages:',
      ...recent,
    ].join('\n');
  }
}

class RuntimeTaskHarness {
  static RuntimeTaskState createTask({
    required String title,
    required String objective,
    required String rootPath,
  }) {
    return RuntimeTaskState(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      objective: objective,
      rootPath: rootPath,
      phase: TaskRuntimePhase.intake,
      budget: RuntimeBudget(
        tokenCap: 12000,
        readCap: 18,
        writeCap: 8,
        verifyCap: 6,
        toolCap: 60,
      ),
      relevantFiles: const <String>[],
      decisions: const <String>[],
      verificationNotes: const <String>[],
      errors: const <String>[],
    );
  }

  static TaskRuntimePhase decideNextPhase(RuntimeTaskState task) {
    if (task.errors.isNotEmpty) return TaskRuntimePhase.verify;
    if (task.relevantFiles.isEmpty) return TaskRuntimePhase.scope;
    if (task.verificationNotes.isNotEmpty) return TaskRuntimePhase.verify;
    if (task.decisions.length >= 2) return TaskRuntimePhase.patch;
    return TaskRuntimePhase.inspect;
  }

  static bool shouldStop(RuntimeTaskState task) => task.budget.isExhausted;
}
