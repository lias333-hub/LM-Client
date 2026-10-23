part of 'main.dart';

class ToolCategory {
  static const String workspace = 'workspace';
  static const String search = 'search';
  static const String shell = 'shell';
  static const String memory = 'memory';
  static const String project = 'project';
}

class ToolPermission {
  static const String workspace = 'workspace';
  static const String project = 'project';
  static const String network = 'network';
}

class ToolSpec {
  final String name;
  final String description;
  final String category;
  final String permission;
  final bool safeByDefault;
  final List<String> tags;

  const ToolSpec({
    required this.name,
    required this.description,
    required this.category,
    required this.permission,
    this.safeByDefault = true,
    this.tags = const <String>[],
  });
}

class ToolSecurityPolicy {
  final bool allowNetwork;
  final bool allowShell;
  final bool allowWrites;

  const ToolSecurityPolicy({
    this.allowNetwork = true,
    this.allowShell = true,
    this.allowWrites = true,
  });

  static const ToolSecurityPolicy defaultPolicy = ToolSecurityPolicy();

  bool allows(ToolSpec spec) {
    if (!allowNetwork && spec.permission == ToolPermission.network) return false;
    if (!allowShell && spec.category == ToolCategory.shell) return false;
    if (!allowWrites && spec.category == ToolCategory.workspace && !spec.safeByDefault) return false;
    return true;
  }
}

enum TaskRuntimePhase {
  intake,
  scope,
  inspect,
  plan,
  patch,
  verify,
  summarize,
  blocked,
}

/// Mutable per-task budget tracker (tokens / reads / tool calls).
class RuntimeBudget {
  final int tokenCap;
  final int readCap;
  final int toolCallCap;

  int tokensUsed = 0;
  int readsUsed = 0;
  int toolCalls = 0;

  RuntimeBudget({this.tokenCap = 70000, this.readCap = 8, this.toolCallCap = 40});

  void recordTokens(int n) => tokensUsed += n;
  void recordRead() => readsUsed += 1;
  void recordToolCall() => toolCalls += 1;

  bool get isExhausted => tokensUsed >= tokenCap || readsUsed >= readCap || toolCalls >= toolCallCap;
}

class RuntimeTaskState {
  final WorkflowTask workflow;
  final RuntimeBudget budget;
  final TaskRuntimePhase phase;

  const RuntimeTaskState({
    required this.workflow,
    required this.budget,
    this.phase = TaskRuntimePhase.intake,
  });
}

class RuntimeTaskHarness {
  static RuntimeTaskState createTask({
    required String title,
    required String objective,
    String rootPath = '/',
    int tokenBudget = 70000,
  }) {
    final wf = WorkflowHarness.createTask(
      title: title,
      objective: objective,
      rootPath: rootPath,
      tokenBudget: tokenBudget,
    );
    return RuntimeTaskState(workflow: wf, budget: RuntimeBudget(tokenCap: tokenBudget));
  }

  static TaskRuntimePhase decideNextPhase(RuntimeTaskState task, {int extraReads = 0, int extraWrites = 0}) {
    final d = WorkflowHarness.decideNextPhase(task.workflow, extraReads: extraReads, extraWrites: extraWrites);
    for (final p in TaskRuntimePhase.values) {
      if (p.name == d.phase) return p;
    }
    return TaskRuntimePhase.blocked;
  }
}

class RuntimeContextManager {
  /// Keeps only the most recent [limit] messages.
  static List<String> compactHistory({
    required RuntimeTaskState task,
    required List<String> recentMessages,
    int limit = 24,
  }) {
    if (limit > 0 && recentMessages.length > limit) {
      return recentMessages.sublist(recentMessages.length - limit);
    }
    return List<String>.of(recentMessages);
  }
}

class CheckpointsSheet extends StatelessWidget {
  final String convId;
  const CheckpointsSheet({super.key, required this.convId});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Checkpoints for $convId', style: TextStyle(color: pal(context).text)),
      ),
    );
  }
}

Future<void> showInspector(BuildContext context, dynamic session) async {}

Future<void> showModelPicker(BuildContext context, [Object? profile]) async {}


Future<void> exportConversation(BuildContext context, dynamic session) async {}

Future<void> showExportSheet(BuildContext context, String title, String content) async {}

String dateGroup(DateTime value, DateTime now) {
  final diff = now.difference(value);
  if (diff.inDays == 0) return 'اليوم';
  if (diff.inDays == 1) return 'أمس';
  if (diff.inDays < 7) return 'هذا الأسبوع';
  if (diff.inDays < 30) return 'هذا الشهر';
  return 'أقدم';
}

class _DrawerRow {
  final String? header;
  final ConvMeta? conv;

  const _DrawerRow._({this.header, this.conv});

  static _DrawerRow h(String header) => _DrawerRow._(header: header);
  static _DrawerRow c(ConvMeta conv) => _DrawerRow._(conv: conv);
}

class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const EmptyHint({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 34, color: p.muted),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: p.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class SegPicker<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T value;
  final ValueChanged<T> onChanged;

  const SegPicker({
    super.key,
    required this.values,
    required this.labels,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List<Widget>.generate(values.length, (index) {
        final selected = values[index] == value;
        return ChoiceChip(
          label: Text(labels[index]),
          selected: selected,
          onSelected: (_) => onChanged(values[index]),
          backgroundColor: p.surfaceHi,
          selectedColor: p.accent.withAlpha(30),
          labelStyle: TextStyle(color: selected ? p.text : p.muted),
          side: BorderSide(color: selected ? p.accent : p.border),
        );
      }),
    );
  }
}

BoxDecoration cardDeco(Pal p, {bool selected = false}) {
  return BoxDecoration(
    color: selected ? p.surfaceHi : p.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: selected ? p.accent : p.border),
  );
}

Future<Map<String, String>> searchChats(String query) async => <String, String>{};

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Projects')));
}

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Library')));
}

class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Memory')));
}


class PhoneFilesScreen extends StatelessWidget {
  const PhoneFilesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Phone Files')));
}

Future<List<PendingAtt>> pickAttachments({bool images = false}) async {
  final out = <PendingAtt>[];
  try {
    if (images) {
      final files = await ImagePicker().pickMultiImage();
      for (final x in files) {
        final bytes = await x.readAsBytes();
        out.add(PendingAtt(id: newId(), name: x.name, mime: mimeFromName(x.name), size: bytes.length, bytes: bytes));
      }
    } else {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: FileType.any);
      if (res == null) return out;
      for (final f in res.files) {
        Uint8List? b = f.bytes;
        if (b == null && f.path != null) b = await File(f.path!).readAsBytes();
        if (b == null) continue;
        out.add(PendingAtt(id: newId(), name: f.name, mime: mimeFromName(f.name), size: b.length, bytes: b));
      }
    }
  } catch (e) {
    toast('تعذر اختيار الملف: $e');
  }
  return out;
}
