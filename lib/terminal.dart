part of 'main.dart';

// ---------------------------------------------------------------------
// Terminal: تنفيذ الأوامر عبر Termux (RUN_COMMAND). يستخدمه النموذج (أداة
// run_shell) والمستخدم (شاشة Terminal) وكلاهما يظهر في نفس السجل.
// ---------------------------------------------------------------------
const String kToolShell = 'run_shell';

class ShellResult {
  final bool ok;
  final String stdout;
  final String stderr;
  final int exitCode;
  final String error;
  const ShellResult({required this.ok, this.stdout = '', this.stderr = '', this.exitCode = -1, this.error = ''});

  String toModelText() {
    if (!ok) return 'Shell error: ${_shellHint(error)}';
    final b = StringBuffer('exit code: $exitCode');
    final out = _tailText(stdout.trimRight(), 12000);
    final err = _tailText(stderr.trimRight(), 6000);
    if (out.isNotEmpty) b.write('\n--- stdout ---\n$out');
    if (err.isNotEmpty) b.write('\n--- stderr ---\n$err');
    if (out.isEmpty && err.isEmpty) b.write('\n(no output)');
    return b.toString();
  }
}

String _tailText(String s, int max) {
  if (s.length <= max) return s;
  return '…[truncated ${s.length - max} chars]\n${s.substring(s.length - max)}';
}

String _shellHint(String code) {
  switch (code) {
    case 'termux_not_installed':
      return 'Termux is not installed on this phone';
    case 'permission_denied':
      return 'the RUN_COMMAND permission for Termux is not granted';
    case 'timeout':
      return 'timed out. Either the command is slow/interactive, or allow-external-apps=true is not set in ~/.termux/termux.properties';
    default:
      return code;
  }
}

class TermuxBridge {
  static const MethodChannel _ch = MethodChannel('lmclient/termux');

  static Future<bool> isInstalled() async {
    try {
      return await _ch.invokeMethod<bool>('isInstalled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasPermission() async {
    try {
      return await _ch.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _ch.invokeMethod<bool>('requestPermission');
    } catch (_) {}
  }

  static Future<ShellResult> run(String command, {String? workdir, int timeoutMs = 60000}) async {
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('run', <String, dynamic>{
        'command': command,
        'workdir': workdir,
        'timeoutMs': timeoutMs,
      });
      if (r == null) return const ShellResult(ok: false, error: 'no response from the native bridge');
      if (r['ok'] != true) return ShellResult(ok: false, error: '${r['error'] ?? 'unknown error'}');
      final err = r['err'] is int ? r['err'] as int : 0;
      final msg = '${r['errmsg'] ?? ''}';
      if (err != 0 && msg.isNotEmpty) return ShellResult(ok: false, error: msg);
      return ShellResult(
        ok: true,
        stdout: '${r['stdout'] ?? ''}',
        stderr: '${r['stderr'] ?? ''}',
        exitCode: r['exitCode'] is int ? r['exitCode'] as int : -1,
      );
    } on MissingPluginException {
      return const ShellResult(ok: false, error: 'native bridge missing (rebuild the APK with android_overlay)');
    } catch (e) {
      return ShellResult(ok: false, error: '$e');
    }
  }
}

class TerminalEntry {
  final String command;
  final bool fromModel;
  ShellResult? result;
  TerminalEntry(this.command, this.fromModel);
}

final ValueNotifier<List<TerminalEntry>> terminalLog = ValueNotifier<List<TerminalEntry>>(<TerminalEntry>[]);

Future<ShellResult> runShellLogged(String command, {String? workdir, int timeoutMs = 60000, bool fromModel = false}) async {
  final e = TerminalEntry(command, fromModel);
  final l = <TerminalEntry>[...terminalLog.value, e];
  terminalLog.value = l.length > 200 ? l.sublist(l.length - 200) : l;
  final r = await TermuxBridge.run(command, workdir: workdir, timeoutMs: timeoutMs);
  e.result = r;
  terminalLog.value = List<TerminalEntry>.of(terminalLog.value);
  return r;
}

Future<ToolOutcome> _toolShell(Map<String, dynamic> a, Agent? agent, AppSettings s) async {
  final ag = _needAgent(agent, 'shell access');
  if (!ag.canShell) throw const ToolError('This agent has no shell permission');
  final cmd = asStr(a['command']).trim();
  if (cmd.isEmpty) throw const ToolError('command is required');
  final dangerous = ToolPolicy.isDangerousCommand(cmd);
  if (s.confirm || dangerous) {
    final ok = await askConfirm(dangerous ? 'أمر خطير: هل تسمح بتنفيذه؟' : 'الـ Agent يريد تنفيذ أمر في Termux', clip(cmd, 800), ok: 'تنفيذ');
    if (!ok) throw const ToolError('The user denied this action');
  }
  String? cwd = asStr(a['cwd']).trim();
  if (cwd.isEmpty) {
    final roots = ag.allowedPaths.where((e) => e.trim().isNotEmpty).toList();
    if (roots.isNotEmpty) {
      final r = roots.first.trim();
      cwd = r.startsWith('/') ? r : '${PhoneStorage.root}/$r';
    } else {
      cwd = null;
    }
  }
  final secs = (num.tryParse('${a['timeout_seconds'] ?? ''}') ?? 60).toInt().clamp(5, 300).toInt();
  final r = await runShellLogged(cmd, workdir: cwd, timeoutMs: secs * 1000, fromModel: true);
  return ToolOutcome(r.toModelText(), !r.ok || r.exitCode != 0);
}

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> with WidgetsBindingObserver {
  static const String _setupCmd = 'mkdir -p ~/.termux && echo "allow-external-apps=true" >> ~/.termux/termux.properties && termux-reload-settings';

  final TextEditingController _in = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _installed = false;
  bool _perm = false;
  bool _busy = false;
  bool _showSetup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _in.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final i = await TermuxBridge.isInstalled();
    final p = i ? await TermuxBridge.hasPermission() : false;
    if (!mounted) return;
    setState(() {
      _installed = i;
      _perm = p;
      if (!(i && p)) _showSetup = true;
    });
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _run(String cmd) async {
    final c = cmd.trim();
    if (c.isEmpty || _busy) return;
    _in.clear();
    setState(() => _busy = true);
    await runShellLogged(c);
    if (mounted) setState(() => _busy = false);
  }

  Widget _step(Pal p, bool ok, String t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: <Widget>[
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: ok ? p.success : p.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(t, style: TextStyle(color: p.text, fontSize: 13.5))),
      ]),
    );
  }

  Widget _setupCard(Pal p) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: cardDeco(p),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('ربط Termux', style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _step(p, _installed, 'تثبيت Termux (من F-Droid أو GitHub)'),
        _step(p, _perm, 'صلاحية تشغيل أوامر Termux'),
        if (_installed && !_perm)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () async {
                await TermuxBridge.requestPermission();
                await Future<void>.delayed(const Duration(seconds: 1));
                _check();
              },
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: const Text('طلب الصلاحية'),
            ),
          ),
        const SizedBox(height: 6),
        Text('داخل Termux نفّذ هذا الأمر مرة واحدة:', style: TextStyle(color: p.muted, fontSize: 12.5)),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(10)),
            child: SelectableText(_setupCmd, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: p.codeText)),
          ),
        ),
        Row(children: <Widget>[
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: _setupCmd));
              toast('تم نسخ الأمر');
            },
            icon: const Icon(Icons.copy, size: 17),
            label: const Text('نسخ الأمر'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : () => _run('echo ok && node -v && npm -v'),
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: const Text('اختبار الاتصال'),
          ),
        ]),
      ]),
    );
  }

  List<InlineSpan> _entrySpans(Pal p, TerminalEntry e, TextStyle mono) {
    final spans = <InlineSpan>[
      TextSpan(text: r'$ ', style: mono.copyWith(color: p.accent, fontWeight: FontWeight.w700)),
      TextSpan(text: e.command, style: mono.copyWith(fontWeight: FontWeight.w600)),
      if (e.fromModel) TextSpan(text: '   [agent]', style: mono.copyWith(color: p.muted, fontSize: 11)),
      const TextSpan(text: '\n'),
    ];
    final r = e.result;
    if (r == null) {
      spans.add(TextSpan(text: '…\n', style: mono.copyWith(color: p.muted)));
    } else if (!r.ok) {
      spans.add(TextSpan(text: '${_shellHint(r.error)}\n', style: mono.copyWith(color: p.danger)));
    } else {
      final out = r.stdout.trimRight();
      final err = r.stderr.trimRight();
      if (out.isNotEmpty) spans.add(TextSpan(text: '$out\n', style: mono));
      if (err.isNotEmpty) spans.add(TextSpan(text: '$err\n', style: mono.copyWith(color: p.danger)));
      if (r.exitCode != 0) spans.add(TextSpan(text: 'exit ${r.exitCode}\n', style: mono.copyWith(color: p.muted, fontSize: 11)));
    }
    spans.add(const TextSpan(text: '\n'));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: p.codeText, height: 1.35);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: p.text),
        title: Text('Terminal', style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w600)),
        actions: <Widget>[
          IconButton(tooltip: 'إعداد Termux', icon: const Icon(Icons.link), onPressed: () => setState(() => _showSetup = !_showSetup)),
          IconButton(tooltip: 'مسح السجل', icon: const Icon(Icons.delete_sweep_outlined), onPressed: () => terminalLog.value = <TerminalEntry>[]),
        ],
      ),
      body: Column(children: <Widget>[
        if (_showSetup) _setupCard(p),
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
              child: ValueListenableBuilder<List<TerminalEntry>>(
                valueListenable: terminalLog,
                builder: (ctx, list, _) {
                  _toBottom();
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('اكتب أمراً بالأسفل.\nالأوامر التي ينفذها الـ Agent تظهر هنا أيضاً.',
                            textAlign: TextAlign.center, textDirection: TextDirection.rtl, style: TextStyle(color: p.muted, fontSize: 13, height: 1.6)),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: list.length,
                    itemBuilder: (_, i) => SelectableText.rich(TextSpan(children: _entrySpans(p, list[i], mono))),
                  );
                },
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Directionality(
                textDirection: TextDirection.ltr,
                child: Wrap(spacing: 6, children: <Widget>[
                  for (final c in const <String>['pwd', 'ls', 'node -v', 'npm -v'])
                    ActionChip(
                      label: Text(c, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: p.text)),
                      backgroundColor: p.surface,
                      side: BorderSide(color: p.border),
                      onPressed: _busy ? null : () => _run(c),
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _in,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _run,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: p.text),
                      decoration: fieldDeco(context, hint: 'command', prefix: Padding(padding: const EdgeInsets.only(left: 12, right: 4), child: Text(r'$', style: TextStyle(fontFamily: 'monospace', color: p.accent, fontSize: 16)))),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent),
                    onPressed: _busy ? null : () => _run(_in.text),
                    icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_upward),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
