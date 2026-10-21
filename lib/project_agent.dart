part of 'main.dart';

// ---------------------------------------------------------------------
//  Project-scoped coding agent runtime
//  Safe, Claude Code-inspired helpers for repo work inside Android sandbox.
// ---------------------------------------------------------------------

class ProjectCommandResult {
  final bool ok;
  final int exitCode;
  final String stdout;
  final String stderr;
  final String command;

  const ProjectCommandResult({
    required this.ok,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.command,
  });

  String get summary => stdout.trim().isNotEmpty ? stdout.trim() : stderr.trim();
}

class ProjectExecutor {
  static const List<String> allowedBinaryNames = <String>[
    'ls',
    'pwd',
    'find',
    'grep',
    'rg',
    'git',
    'python',
    'python3',
    'node',
    'npm',
    'yarn',
    'pnpm',
    'dart',
    'flutter',
    'bash',
    'sh',
    'cat',
    'head',
    'tail',
    'sed',
    'awk',
    'cut',
    'jq',
    'mkdir',
    'cp',
    'mv',
    'touch',
    'echo',
    'printf',
    'stat',
    'uname',
    'test',
  ];

  static const List<String> bannedPatterns = <String>[
    'rm -rf /',
    'rm -rf /tmp',
    'chmod 777',
    'sudo ',
    '/system',
    '/proc',
    '/dev',
    'reset --hard',
    'git clean -fd',
    'git checkout -- .',
    'dd if=',
    'mkfs',
    'fdisk',
    'mount ',
    'umount ',
    'su ',
    'pkill ',
    'kill -9',
    'curl http://localhost',
    'curl https://localhost',
    'ssh ',
    'scp ',
  ];

  static String normalizeRoot(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '/';
    var r = s.replaceAll('\\', '/');
    while (r.endsWith('/')) {
      if (r == '/') break;
      r = r.substring(0, r.length - 1);
    }
    if (!r.startsWith('/')) r = '/$r';
    return r;
  }

  static String normalizePath(String root, String raw) {
    final base = normalizeRoot(root);
    final p = raw.trim();
    if (p.isEmpty) return base;
    String n = p.replaceAll('\\', '/');
    if (!n.startsWith('/')) n = '$base/$n';
    final parts = <String>[];
    for (final part in n.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    return '/${parts.join('/')}';
  }

  static bool isInsideRoot(String root, String path) {
    final r = normalizeRoot(root);
    final p = normalizePath(root, path);
    return p == r || p.startsWith('$r/');
  }

  static Future<List<String>> listDir(String root, {String path = '.'}) async {
    final target = normalizePath(root, path);
    final dir = Directory(target);
    if (!await dir.exists()) return <String>[];
    final out = <String>[];
    await for (final entity in dir.list(followLinks: false, recursive: false)) {
      out.add(entity.path.replaceFirst(target, '.').replaceFirst(RegExp(r'^\./'), ''));
    }
    out.sort();
    return out;
  }

  static Future<String> readFileRange(String root, String relativePath, {int offset = 1, int limit = 200}) async {
    final fullPath = normalizePath(root, relativePath);
    final file = File(fullPath);
    if (!await file.exists()) throw ToolError('File not found: $relativePath');
    if (!isInsideRoot(root, fullPath)) throw ToolError('Path is outside the project root');
    final lines = await file.readAsLines();
    final start = offset <= 0 ? 0 : offset - 1;
    final end = start + limit;
    final chunk = lines.sublist(start < lines.length ? start : lines.length, end <= lines.length ? end : lines.length);
    if (chunk.isEmpty) return '';
    final out = <String>[];
    for (int i = 0; i < chunk.length; i++) {
      final lineNo = start + i + 1;
      out.add('${lineNo.toString().padLeft(4, ' ')} | ${chunk[i]}');
    }
    return out.join('\n');
  }

  static Future<List<String>> searchFiles(String root, String query, {String glob = '*', bool ignoreCase = true}) async {
    final q = query.trim();
    final matches = <String>[];
    if (q.isEmpty) return matches;
    final rootDir = Directory(root);
    if (!await rootDir.exists()) return matches;
    final entries = await rootDir.list(followLinks: false, recursive: true).toList();
    final lower = ignoreCase ? q.toLowerCase() : q;
    for (final entity in entries) {
      if (entity is! File) continue;
      final relative = entity.path.substring(root.length).replaceAll('\\', '/');
      if (glob != '*' && !globMatches(relative, glob)) continue;
      try {
        final text = await entity.readAsString(encoding: utf8, flush: false);
        final hay = ignoreCase ? text.toLowerCase() : text;
        if (hay.contains(lower)) {
          matches.add(relative);
        }
      } catch (_) {}
    }
    return matches;
  }

  static bool globMatches(String path, String pattern) {
    final normalized = pattern.replaceAll('\\', '/');
    final regex = RegExp(normalized.replaceAll('.', '\\.').replaceAll('*', '.*').replaceAll('?', '.'));
    return regex.hasMatch(path);
  }

  static String _binaryFromCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return '';
    final match = RegExp(r'^\s*([A-Za-z0-9_./+-]+)').firstMatch(trimmed);
    return match == null ? '' : match.group(1)!;
  }

  static bool _isDangerous(String command) {
    final low = command.toLowerCase();
    for (final bad in bannedPatterns) {
      if (low.contains(bad.toLowerCase())) return true;
    }
    return false;
  }

  static Future<ProjectCommandResult> runSafeCommand(String root, String command, {Duration timeout = const Duration(seconds: 20)}) async {
    final safeRoot = normalizeRoot(root);
    final c = command.trim();
    if (c.isEmpty) {
      return const ProjectCommandResult(ok: false, exitCode: 1, stdout: '', stderr: 'Empty command', command: '');
    }
    final binary = _binaryFromCommand(c);
    if (binary.isEmpty || !allowedBinaryNames.contains(binary)) {
      return ProjectCommandResult(ok: false, exitCode: 1, stdout: '', stderr: 'Command not allowed: $binary', command: c);
    }
    if (_isDangerous(c)) {
      return ProjectCommandResult(ok: false, exitCode: 1, stdout: '', stderr: 'Dangerous command blocked', command: c);
    }

    final proc = await Process.start('sh', <String>['-lc', c], workingDirectory: safeRoot);
    final stdout = StringBuffer();
    final stderr = StringBuffer();

    proc.stdout.transform(utf8.decoder).listen((chunk) => stdout.write(chunk));
    proc.stderr.transform(utf8.decoder).listen((chunk) => stderr.write(chunk));

    final exitCode = await proc.exitCode.timeout(timeout, onTimeout: () => -1);
    final ok = exitCode == 0;
    return ProjectCommandResult(
      ok: ok,
      exitCode: exitCode,
      stdout: stdout.toString(),
      stderr: stderr.toString(),
      command: c,
    );
  }

  static Future<ProjectCommandResult> gitStatus(String root) async {
    return runSafeCommand(root, 'git status --short --branch');
  }

  static Future<ProjectCommandResult> gitDiff(String root, {String? path}) async {
    final suffix = path == null || path.trim().isEmpty ? '' : ' -- ${path.trim()}';
    return runSafeCommand(root, 'git diff --no-color$suffix');
  }
}

class WorkspaceState {
  final String root;
  final String lastResult;
  final bool busy;

  const WorkspaceState({this.root = '', this.lastResult = '', this.busy = false});

  WorkspaceState copyWith({String? root, String? lastResult, bool? busy}) {
    return WorkspaceState(
      root: root ?? this.root,
      lastResult: lastResult ?? this.lastResult,
      busy: busy ?? this.busy,
    );
  }
}

class ProjectWorkspaceScreen extends ConsumerStatefulWidget {
  const ProjectWorkspaceScreen({super.key});

  @override
  ConsumerState<ProjectWorkspaceScreen> createState() => _ProjectWorkspaceScreenState();
}

class _ProjectWorkspaceScreenState extends ConsumerState<ProjectWorkspaceScreen> {
  final TextEditingController _rootController = TextEditingController();
  final TextEditingController _commandController = TextEditingController(text: 'pwd\n&& git status --short --branch');
  final TextEditingController _searchController = TextEditingController(text: 'TODO');

  String _result = 'قد تم تجهيز مساحة العمل. اختر مجلد مشروعك.';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final settings = appContainer.read(settingsProvider).m;
    final root = asStr(settings['workspaceRoot']);
    _rootController.text = root.isNotEmpty ? root : '/storage/emulated/0';
  }

  @override
  void dispose() {
    _rootController.dispose();
    _commandController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _saveRoot() async {
    final root = _rootController.text.trim();
    if (root.isEmpty) return;
    appContainer.read(settingsProvider.notifier).set('workspaceRoot', root);
    setState(() => _result = 'تم حفظ مسار المشروع: $root');
  }

  Future<void> _listRoot() async {
    setState(() => _busy = true);
    try {
      final root = _rootController.text.trim();
      await _saveRoot();
      final items = await ProjectExecutor.listDir(root, path: '.');
      setState(() => _result = items.isEmpty ? 'المجلد فارغ.' : items.join('\n'));
    } catch (e) {
      setState(() => _result = 'خطأ: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _gitStatus() async {
    setState(() => _busy = true);
    try {
      final root = _rootController.text.trim();
      await _saveRoot();
      final res = await ProjectExecutor.gitStatus(root);
      setState(() => _result = res.summary.isEmpty ? 'لا يوجد خروج.' : res.summary);
    } catch (e) {
      setState(() => _result = 'خطأ: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      final root = _rootController.text.trim();
      await _saveRoot();
      final hits = await ProjectExecutor.searchFiles(root, _searchController.text.trim(), glob: '*');
      setState(() => _result = hits.isEmpty ? 'لا توجد نتائج.' : hits.join('\n'));
    } catch (e) {
      setState(() => _result = 'خطأ: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _runCommand() async {
    setState(() => _busy = true);
    try {
      final root = _rootController.text.trim();
      await _saveRoot();
      final res = await ProjectExecutor.runSafeCommand(root, _commandController.text.trim());
      setState(() => _result = res.summary.isEmpty ? 'Exit ${res.exitCode}\n${res.stderr}' : res.summary);
    } catch (e) {
      setState(() => _result = 'خطأ: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Project Workspace')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('مساحة المشروع', style: TextStyle(color: p.text, fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: _rootController,
                decoration: fieldDeco(context, hint: '/storage/emulated/0/...'),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(child: FilledButton.icon(onPressed: _saveRoot, icon: const Icon(Icons.folder_open), label: const Text('حفظ المسار'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(onPressed: _listRoot, icon: const Icon(Icons.list), label: const Text('قائمة'))),
                ],
              ),
              const SizedBox(height: 18),
              Text('أوامر المشروع الآمنة', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _commandController,
                minLines: 3,
                maxLines: 6,
                decoration: fieldDeco(context, hint: 'pwd\n&& git status --short --branch'),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(child: FilledButton.icon(onPressed: _runCommand, icon: const Icon(Icons.play_arrow_rounded), label: const Text('تشغيل'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.tonalIcon(onPressed: _gitStatus, icon: const Icon(Icons.sync_rounded), label: const Text('Git Status'))),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _searchController,
                decoration: fieldDeco(context, hint: 'أدخل كلمة/نمط للبحث', prefixIcon: const Icon(Icons.search)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonal(onPressed: _search, child: const Text('بحث في المشروع')),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.surfaceHi,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border),
                ),
                child: _busy
                    ? Row(
                        children: <Widget>[
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 12),
                          Text('جارٍ التنفيذ...', style: TextStyle(color: p.text, fontSize: 13)),
                        ],
                      )
                    : SelectableText(
                        _result,
                        style: TextStyle(color: p.text, fontSize: 12.5, height: 1.55, fontFamily: 'monospace'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Helper to expose the workspace quickly from other screens.
// ---------------------------------------------------------------------
Future<void> openProjectWorkspace(BuildContext context) async {
  if (!context.mounted) return;
  await Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => const ProjectWorkspaceScreen()),
  );
}

String workspaceRootFromSettings() {
  final settings = appContainer.read(settingsProvider).m;
  final root = asStr(settings['workspaceRoot']);
  return root.trim().isNotEmpty ? root.trim() : '/storage/emulated/0';
}
