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

class RuntimeTaskState {
  final dynamic budget;
  final dynamic phase;

  const RuntimeTaskState({this.budget, this.phase});
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

class RuntimeTaskHarness {
  static WorkflowTask createTask({
    required String title,
    required String objective,
    String rootPath = '/',
    int tokenBudget = 70000,
  }) {
    return WorkflowHarness.createTask(
      title: title,
      objective: objective,
      rootPath: rootPath,
      tokenBudget: tokenBudget,
    );
  }

  static WorkflowDecision decideNextPhase(WorkflowTask task, {int extraReads = 0, int extraWrites = 0}) {
    return WorkflowHarness.decideNextPhase(task, extraReads: extraReads, extraWrites: extraWrites);
  }
}

class RuntimeContextManager {
  static List<String> compactHistory(dynamic history, {int limit = 256}) {
    if (history == null) return const <String>[];
    if (history is Iterable) {
      final items = history.map((item) => item.toString()).toList();
      if (limit > 0 && items.length > limit) return items.sublist(items.length - limit);
      return items;
    }
    return <String>[history.toString()];
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

Future<void> showAgentPicker(BuildContext context) async {}

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

BoxDecoration cardDeco(BuildContext context, {bool selected = false}) {
  final p = pal(context);
  return BoxDecoration(
    color: selected ? p.surfaceHi : p.surface,
    borderRadius: BorderRadius.circular(18),
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

class AgentsScreen extends StatelessWidget {
  const AgentsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Agents')));
}

class PhoneFilesScreen extends StatelessWidget {
  const PhoneFilesScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Phone Files')));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Settings')));
}

Future<void> pickAttachments({bool images = false}) async {}

Future<void> pickAttachmentsWrapper({bool images = false}) async => pickAttachments(images: images);

class _ChatPageState {}

class _ComposerState {}
