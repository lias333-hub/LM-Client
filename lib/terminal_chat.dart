part of 'main.dart';

// ---------------------------------------------------------------------
// وضع الواجهة: محادثة عادية أو Terminal (على نفس الجلسة والأدوات).
// المفتاح الظاهر في الشاشة الأولى: UiModeSwitch. القيمة في الإعداد uiMode.
// ---------------------------------------------------------------------

// ---- موافقة داخل السجل (وضع Terminal) ----
class ApprovalRequest {
  final String title;
  final String body;
  final String ok;
  final String cancel;
  final Completer<bool> done = Completer<bool>();
  ApprovalRequest(this.title, this.body, this.ok, this.cancel);
}

final ValueNotifier<ApprovalRequest?> inlineApproval = ValueNotifier<ApprovalRequest?>(null);
int inlineApprovalHosts = 0;
final Set<String> alwaysAllowed = <String>{};

Future<bool> requestInlineApproval(String title, String body, String ok, String cancel) async {
  while (inlineApproval.value != null) {
    await inlineApproval.value!.done.future;
  }
  final r = ApprovalRequest(title, body, ok, cancel);
  inlineApproval.value = r;
  final res = await r.done.future;
  if (identical(inlineApproval.value, r)) inlineApproval.value = null;
  return res;
}

class _Cmd {
  final String name;
  final String desc;
  final bool arg;
  const _Cmd(this.name, this.desc, {this.arg = false});
}

const List<_Cmd> _kCmds = <_Cmd>[
  _Cmd('/new', 'محادثة جديدة'),
  _Cmd('/model', 'اختيار المزوّد والموديل'),
  _Cmd('/agent', 'اختيار Agent'),
  _Cmd('/think', 'مستوى التفكير: off low mid high', arg: true),
  _Cmd('/compact', 'تلخيص السياق الآن'),
  _Cmd('/retry', 'إعادة توليد آخر رد'),
  _Cmd('/copy', 'نسخ آخر رد'),
  _Cmd('/cd', 'تحديد مجلد المشروع', arg: true),
  _Cmd('/env', 'اختيار بيئة التنفيذ (هذا الهاتف / SSH)'),
  _Cmd('/terminal', 'فتح شاشة الطرفية'),
  _Cmd('/chat', 'العودة لوضع المحادثة'),
];

class UiModeSwitch extends ConsumerWidget {
  final EdgeInsetsGeometry margin;
  const UiModeSwitch({super.key, this.margin = const EdgeInsets.fromLTRB(14, 6, 14, 2)});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final mode = ref.watch(settingsProvider).uiMode;
    Widget cell(int v, IconData icon, String label) {
      final on = mode == v;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => ref.read(settingsProvider.notifier).set('uiMode', v),
          child: Container(
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? p.surfaceHi : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: on ? p.accent : Colors.transparent),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(icon, size: 16, color: on ? p.accent : p.muted),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: on ? p.text : p.muted, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
    }

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(11), border: Border.all(color: p.border)),
      child: Row(children: <Widget>[
        cell(0, Icons.chat_bubble_outline, 'محادثة'),
        const SizedBox(width: 3),
        cell(1, Icons.terminal, 'Terminal'),
      ]),
    );
  }
}

/// شريط علوي واحد: مفتاح (محادثة | Terminal) + مجلد المشروع إن وُجد.
class ChatTopStrip extends ConsumerWidget {
  const ChatTopStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final raw = asStr(ref.watch(settingsProvider).m['workspaceRoot']).trim();
    String? name;
    if (raw.isNotEmpty) {
      final parts = raw.split('/').where((e) => e.isNotEmpty).toList();
      name = parts.isEmpty ? raw : parts.last;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      child: Row(children: <Widget>[
        const Expanded(child: UiModeSwitch(margin: EdgeInsets.zero)),
        if (name != null) ...<Widget>[
          const SizedBox(width: Sp.sm),
          InkWell(
            borderRadius: BorderRadius.circular(Rd.control),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PhoneFilesScreen())),
            child: Container(
              height: 42,
              constraints: const BoxConstraints(maxWidth: 120),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(Rd.control), border: Border.all(color: p.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Icon(Icons.folder_open, size: 16, color: p.accent),
                const SizedBox(width: 6),
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5, fontFamily: 'monospace'))),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class _ShellRun {
  final int anchor;
  final TerminalEntry entry;
  _ShellRun(this.anchor, this.entry);
}

class TerminalChatView extends ConsumerStatefulWidget {
  final ChatSession session;
  const TerminalChatView({super.key, required this.session});

  @override
  ConsumerState<TerminalChatView> createState() => _TerminalChatViewState();
}

class _TerminalChatViewState extends ConsumerState<TerminalChatView> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _focus = FocusNode();
  final Set<String> _open = <String>{};
  final List<_ShellRun> _runs = <_ShellRun>[];
  bool _stick = true;
  int _sig = 0;

  @override
  void initState() {
    super.initState();
    inlineApprovalHosts++;
    inlineApproval.addListener(_onApproval);
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _onApproval() {
    _stick = true;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant TerminalChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) _runs.clear();
  }

  @override
  void dispose() {
    inlineApproval.removeListener(_onApproval);
    inlineApprovalHosts--;
    final pending = inlineApproval.value;
    if (pending != null && !pending.done.isCompleted) {
      inlineApproval.value = null;
      askConfirmDialog(pending.title, pending.body, ok: pending.ok, cancel: pending.cancel).then((v) {
        if (!pending.done.isCompleted) pending.done.complete(v);
      });
    }
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  TextStyle _mono(Pal p, {Color? color, double size = 13.5, FontWeight? w}) {
    return TextStyle(fontFamily: 'monospace', fontSize: size, color: color ?? p.text, height: 1.45, fontWeight: w);
  }

  int _signature(ChatSession s) {
    var h = s.messages.length;
    if (s.messages.isNotEmpty) {
      final m = s.messages.last;
      h = h * 31 + m.content.length;
      for (final t in m.toolCalls) {
        h = h * 31 + (t.result?.length ?? 0) + t.status.length;
      }
    }
    for (final r in _runs) {
      h = h * 31 + (r.entry.result == null ? 1 : 2);
    }
    if (inlineApproval.value != null) h += 7;
    return h * 2 + (s.generating ? 1 : 0);
  }

  void _maybeScroll(ChatSession s) {
    final sig = _signature(s);
    if (sig == _sig) return;
    _sig = sig;
    if (!_stick) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical) _stick = n.metrics.pixels >= n.metrics.maxScrollExtent - 80;
    return false;
  }

  Future<void> _attach() async {
    final list = await pickAttachments();
    for (final a in list) {
      ref.read(pendingProvider.notifier).add(a);
    }
  }

  void _slash(String cmd) {
    final parts = cmd.trim().split(RegExp(r'\s+'));
    var c = parts.first.toLowerCase();
    final arg = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final m = _kCmds.where((e) => e.name.startsWith(c)).toList();
    if (m.length == 1) c = m.first.name;
    final s = widget.session;
    switch (c) {
      case '/new':
        hub.newChat();
        break;
      case '/model':
        showModelPicker(context);
        break;
      case '/agent':
        showAgentPicker(context);
        break;
      case '/think':
        _think(arg);
        break;
      case '/compact':
        toast('جارٍ تلخيص السياق…');
        s.compactNow();
        break;
      case '/retry':
        s.regenerate();
        break;
      case '/copy':
        _copyLast();
        break;
      case '/cd':
        _cd(arg);
        break;
      case '/env':
        showWorkspacePicker(context);
        break;
      case '/terminal':
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TerminalScreen()));
        break;
      case '/chat':
        ref.read(settingsProvider.notifier).set('uiMode', 0);
        break;
      default:
        toast('الأوامر: ${_kCmds.map((e) => e.name).join('  ')}');
    }
  }

  void _think(String a) {
    const lv = <String, int>{'off': 0, 'low': 1, 'mid': 2, 'medium': 2, 'high': 3};
    final v = lv[a.toLowerCase()];
    if (v == null) {
      toast('الاستخدام: /think off|low|mid|high');
      return;
    }
    ref.read(settingsProvider.notifier).set('thinkLevel', v);
    toast('مستوى التفكير: ${a.toLowerCase()}');
  }

  void _cd(String a) {
    if (a.isEmpty) {
      toast('الاستخدام: /cd المسار');
      return;
    }
    ref.read(settingsProvider.notifier).set('workspaceRoot', a);
    final WorkspaceConfig? w = currentWorkspace();
    if (w != null) BashRuntime.setCwd(widget.session.meta.id, w, a);
    toast('مجلد المشروع: $a');
  }

  void _copyLast() {
    final msgs = widget.session.messages;
    for (var i = msgs.length - 1; i >= 0; i--) {
      final m = msgs[i];
      if (m.role != 'user' && m.content.trim().isNotEmpty) {
        Clipboard.setData(ClipboardData(text: m.content));
        toast('تم نسخ آخر رد');
        return;
      }
    }
    toast('لا يوجد رد لنسخه');
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    final pend = ref.read(pendingProvider);
    if (text.isEmpty && pend.isEmpty) return;
    final s = widget.session;
    if (text.startsWith('!') && pend.isEmpty) {
      final cmd = text.substring(1).trim();
      _ctrl.clear();
      if (cmd.isEmpty) return;
      _stick = true;
      final entry = TerminalEntry(cmd, false);
      setState(() => _runs.add(_ShellRun(s.messages.length, entry)));
      ShellResult? r = await runUserCommandInWorkspace(cmd, s.meta.id);
      if (r == null) {
        if (await TermuxBridge.isInstalled()) {
          r = await TermuxBridge.run(cmd);
        } else {
          r = const ShellResult(ok: false, error: 'لا توجد بيئة تنفيذ. اكتب /env واختر «هذا الهاتف» (أو أضف بيئة SSH)');
        }
      }
      entry.result = r;
      if (mounted) setState(() {});
      return;
    }
    if (text.startsWith('/') && pend.isEmpty) {
      _ctrl.clear();
      _slash(text);
      return;
    }
    _ctrl.clear();
    ref.read(pendingProvider.notifier).clear();
    _stick = true;
    if (s.generating && s.enqueue(text, pend)) return;
    await s.send(text, pend);
  }

  String _argSummary(ToolCall t) {
    for (final k in const <String>['command', 'path', 'url', 'query', 'pattern', 'name']) {
      final v = t.args[k];
      if (v != null && '$v'.trim().isNotEmpty) return clip('$v'.replaceAll('\n', ' '), 70);
    }
    if (t.args.isEmpty) return '';
    return clip(jsonEncode(t.args), 70);
  }

  Widget _block(Pal p, String prefix, String text, Color prefixColor, {Color? textColor}) {
    final dir = detectDir(text) ?? Directionality.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Directionality(
        textDirection: dir,
        child: Text.rich(TextSpan(children: <InlineSpan>[
          TextSpan(text: prefix, style: _mono(p, color: prefixColor, w: FontWeight.w700)),
          TextSpan(text: text, style: _mono(p, color: textColor)),
        ])),
      ),
    );
  }

  Widget _assistantText(Pal p, String text) {
    final parts = text.split('```');
    final kids = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      final seg = parts[i];
      if (i.isOdd) {
        final nl = seg.indexOf('\n');
        final code = nl >= 0 ? seg.substring(nl + 1) : seg;
        kids.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(code.trimRight(), style: _mono(p, color: p.codeText, size: 12.5)),
          ),
        ));
      } else if (seg.trim().isNotEmpty) {
        final dir = detectDir(seg) ?? Directionality.of(context);
        kids.add(Directionality(
          textDirection: dir,
          child: Text.rich(TextSpan(children: <InlineSpan>[
            if (i == 0) TextSpan(text: '● ', style: _mono(p, color: p.accent)),
            TextSpan(text: seg.trim(), style: _mono(p)),
          ])),
        ));
      }
    }
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids));
  }

  Widget _tool(Pal p, ToolCall t) {
    final open = _open.contains(t.id);
    final failed = t.status == 'error' || t.isError;
    final color = failed ? p.danger : (t.status == 'done' ? p.success : p.muted);
    final res = (t.result ?? '').trimRight();
    final lines = res.isEmpty ? <String>[] : res.split('\n');
    final shown = (open ? lines : lines.take(4).toList()).map((l) => clip(l, 220)).toList();
    final running = t.status == 'running' || t.status == 'pending';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => setState(() {
          if (!_open.remove(t.id)) _open.add(t.id);
        }),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text.rich(TextSpan(children: <InlineSpan>[
              TextSpan(text: '● ', style: _mono(p, color: color)),
              TextSpan(text: t.name, style: _mono(p, w: FontWeight.w700)),
              TextSpan(text: '(${_argSummary(t)})', style: _mono(p, color: p.muted)),
            ])),
            if (running) Text('  ⎿ …', style: _mono(p, color: p.muted)),
            if (shown.isNotEmpty) Text('  ⎿ ${shown.join('\n    ')}', style: _mono(p, color: failed ? p.danger : p.muted, size: 12.5)),
            if (!open && lines.length > 4) Text('    … +${lines.length - 4} lines (اضغط للتوسيع)', style: _mono(p, color: p.muted, size: 11.5)),
          ]),
        ),
      ),
    );
  }

  List<Widget> _messageWidgets(Pal p, ChatMessage m) {
    final w = <Widget>[];
    if (m.role == 'user') {
      if (m.summary) {
        w.add(_block(p, '✻ ', 'ملخّص سياق سابق', p.muted, textColor: p.muted));
        return w;
      }
      w.add(_block(p, '> ', m.content, p.accent));
      for (final a in m.attachments) {
        w.add(Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('  [${a.name}]', style: _mono(p, color: p.muted, size: 12))));
      }
      return w;
    }
    if (m.thinkMs > 0 || m.thinking.isNotEmpty) {
      final secs = m.thinkMs > 0 ? ' · ${(m.thinkMs / 1000).toStringAsFixed(1)}s' : '';
      w.add(Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('✻ thinking$secs', style: _mono(p, color: p.muted, size: 12))));
    }
    if (m.content.trim().isNotEmpty) w.add(_assistantText(p, m.content));
    for (final t in m.toolCalls) {
      w.add(_tool(p, t));
    }
    if (m.error != null && m.error!.isNotEmpty) w.add(_block(p, '✗ ', m.error!, p.danger, textColor: p.danger));
    return w;
  }

  Widget _approvalCard(Pal p, ApprovalRequest r) {
    final dangerous = r.title.contains('خطير');
    void answer(bool v, {bool always = false}) {
      if (always) alwaysAllowed.add('${r.title}|${r.body}');
      inlineApproval.value = null;
      if (!r.done.isCompleted) r.done.complete(v);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: dangerous ? p.danger : p.accent)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text(r.title, style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
            child: Text(clip(r.body, 600), style: _mono(p, size: 12.5)),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: <Widget>[
          Expanded(
            child: FilledButton(
              onPressed: () => answer(true),
              style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent, minimumSize: const Size.fromHeight(44)),
              child: Text(r.ok),
            ),
          ),
          if (!dangerous) ...<Widget>[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => answer(true, always: true),
                style: OutlinedButton.styleFrom(foregroundColor: p.text, side: BorderSide(color: p.border), minimumSize: const Size.fromHeight(44)),
                child: const Text('دائماً'),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => answer(false),
              style: OutlinedButton.styleFrom(foregroundColor: p.danger, side: BorderSide(color: p.border), minimumSize: const Size.fromHeight(44)),
              child: Text(r.cancel),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _statusLine(Pal p, ChatSession s, String? agentName) {
    final st = ref.watch(settingsProvider);
    final model = ref.watch(profilesProvider).selected?.selectedModel ?? '';
    var used = 0;
    for (final m in s.messages) {
      if (m.excluded) continue;
      used += estimateTokens(m.content);
      for (final t in m.toolCalls) {
        used += estimateTokens(t.result ?? '');
      }
    }
    final budget = st.contextBudget > 0 ? st.contextBudget : 60000;
    final pct = (used * 100 / budget).clamp(0, 100).round();
    final hot = pct >= 80;
    final tx = _mono(p, color: p.muted, size: 11.5);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
        child: Row(children: <Widget>[
          Flexible(child: Text('agent: ${agentName ?? 'none'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: tx)),
          const SizedBox(width: 10),
          if (model.isNotEmpty) Flexible(child: Text(model, maxLines: 1, overflow: TextOverflow.ellipsis, style: tx)),
          const SizedBox(width: 10),
          Text('ctx $pct%', style: tx.copyWith(color: hot ? p.danger : p.muted)),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(value: pct / 100, minHeight: 4, backgroundColor: p.border, color: hot ? p.danger : p.accent),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _palette(Pal p) {
    final t = _ctrl.text;
    if (!t.startsWith('/') || t.contains(' ')) return const SizedBox.shrink();
    final items = _kCmds.where((e) => e.name.startsWith(t.toLowerCase())).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        for (var i = 0; i < items.length; i++)
          InkWell(
            onTap: () {
              if (items[i].arg) {
                _ctrl.text = '${items[i].name} ';
                _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
                _focus.requestFocus();
              } else {
                _ctrl.clear();
                _slash(items[i].name);
              }
            },
            child: Container(
              height: 48,
              color: i == 0 ? p.surfaceHi : null,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: <Widget>[
                SizedBox(
                  width: 92,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(items[i].name, style: _mono(p, color: p.accent, size: 14, w: FontWeight.w700)),
                  ),
                ),
                Expanded(child: Text(items[i].desc, style: TextStyle(color: p.muted, fontSize: 14))),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _shellRow(Pal p, TerminalEntry e) {
    final mono = _mono(p, size: 12.5);
    final r = e.result;
    final spans = <InlineSpan>[
      TextSpan(text: r'$ ', style: mono.copyWith(color: p.accent, fontWeight: FontWeight.w700)),
      TextSpan(text: e.command, style: mono.copyWith(fontWeight: FontWeight.w600)),
      const TextSpan(text: '\n'),
    ];
    if (r == null) {
      spans.add(TextSpan(text: '…', style: mono.copyWith(color: p.muted)));
    } else if (!r.ok) {
      spans.add(TextSpan(text: _shellHint(r.error), style: mono.copyWith(color: p.danger)));
    } else {
      final out = r.stdout.trimRight();
      final err = r.stderr.trimRight();
      if (out.isNotEmpty) spans.add(TextSpan(text: '$out\n', style: mono));
      if (err.isNotEmpty) spans.add(TextSpan(text: '$err\n', style: mono.copyWith(color: p.danger)));
      if (r.exitCode != 0) spans.add(TextSpan(text: 'exit ${r.exitCode}', style: mono.copyWith(color: p.muted, fontSize: 11)));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: Text.rich(TextSpan(children: spans)),
        ),
      ),
    );
  }

  Widget _header(Pal p, String? agentName, String raw) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('✻ $kAppName', style: _mono(p, color: p.accent, size: 16, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('agent: ${agentName ?? 'none  (/agent)'}', style: _mono(p, color: p.muted, size: 12.5)),
          Text('cwd:   ${raw.isEmpty ? '-' : raw}', style: _mono(p, color: p.muted, size: 12.5)),
          const SizedBox(height: 6),
          Text('اكتب رسالة للنموذج، أو !أمر لتنفيذه في Termux. الأوامر: /new /agent /terminal /chat', textDirection: TextDirection.rtl, style: _mono(p, color: p.muted, size: 12)),
        ]),
      ),
    );
  }

  Widget _working(Pal p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: <Widget>[
        SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.6, color: p.accent)),
        const SizedBox(width: 10),
        Text('working…', style: _mono(p, color: p.muted, size: 12.5)),
      ]),
    );
  }

  Widget _prompt(Pal p, ChatSession s) {
    final pend = ref.watch(pendingProvider);
    final empty = _ctrl.text.trim().isEmpty;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (pend.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('[${pend.map((e) => e.name).join(', ')}]', style: _mono(p, color: p.muted, size: 12)),
              ),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Text('>', style: _mono(p, color: p.accent, size: 16, w: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                minLines: 1,
                maxLines: 6,
                scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                style: _mono(p, size: 14),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'رسالة، أو !أمر',
                  hintStyle: _mono(p, color: p.muted, size: 14),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            IconButton(icon: Icon(Icons.attach_file, color: p.muted, size: 20), onPressed: _attach),
            IconButton(
              icon: Icon(s.generating && empty ? Icons.stop_circle_outlined : Icons.arrow_upward, color: p.accent),
              onPressed: () {
                if (s.generating && empty) {
                  s.stop();
                } else {
                  _submit();
                }
              },
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final s = widget.session;
    if (!s.loaded) {
      return Center(child: CircularProgressIndicator(strokeWidth: 2, color: p.accent));
    }
    _maybeScroll(s);
    final agents = ref.watch(agentsProvider);
    final sel = ref.watch(selectedAgentProvider);
    String? agentName;
    for (final a in agents) {
      if (a.id == sel) agentName = a.name;
    }
    final root = asStr(ref.watch(settingsProvider).m['workspaceRoot']).trim();
    final msgs = s.messages;
    final rows = <Widget Function()>[];
    if (msgs.isEmpty) rows.add(() => _header(p, agentName, root));
    for (final r in _runs) {
      if (r.anchor == 0) rows.add(() => _shellRow(p, r.entry));
    }
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      rows.add(() {
        final col = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _messageWidgets(p, m));
        return m.excluded ? Opacity(opacity: 0.5, child: col) : col;
      });
      for (final r in _runs) {
        if (r.anchor == i + 1) rows.add(() => _shellRow(p, r.entry));
      }
    }
    final req = inlineApproval.value;
    if (req != null) rows.add(() => _approvalCard(p, req));
    rows.add(() => s.generating ? _working(p) : const SizedBox(height: 4));
    return Column(children: <Widget>[
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              itemCount: rows.length,
              itemBuilder: (c, i) => rows[i](),
            ),
          ),
        ),
      ),
      _palette(p),
      _statusLine(p, s, agentName),
      _prompt(p, s),
    ]);
  }
}
