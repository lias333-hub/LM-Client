part of 'main.dart';

// =====================================================================
//  واجهة الملخّص الحيّ (v2.13.0):
//  - لوحة «الملخّص»: جدول زمني للخطوات كما في تطبيق Claude (أيقونة + عنوان + سطر خافت، وجمل السرد بينها).
//  - جدول الاستهلاك الفعلي (دخل، منه كاش، خرج، منه تفكير) بأرقام المزوّد حرفياً، و«—» لما لم يُبلَّغ عنه.
//  - سطر العمل الحيّ في Terminal، وساعة التشغيل في وضع الدردشة.
//  الأرقام والخطوات كلها من دوال summary.dart النقية (المختبَرة في CI).
// =====================================================================

Future<void> showSummarySheet(BuildContext context, ChatSession session, {String? msgId}) {
  return showSheet<void>(context, (BuildContext c) => SummarySheet(session: session, msgId: msgId));
}

String _prettyArgs(ToolCall c) {
  try {
    return clip(const JsonEncoder.withIndent('  ').convert(c.args), 3000);
  } catch (_) {
    return c.args.toString();
  }
}

// ---- جدول الاستهلاك ----------------------------------------------------
class UsageRow {
  final String label;
  final RunUsage usage;
  const UsageRow(this.label, this.usage);
}

class UsageTable extends StatelessWidget {
  final List<UsageRow> rows;
  final String caption;
  final List<String> notes;
  const UsageTable({super.key, required this.rows, this.caption = '', this.notes = const <String>[]});

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    final TextStyle headStyle = TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600);
    final TextStyle labelStyle = TextStyle(color: p.muted, fontSize: 12.5);
    final TextStyle strong = TextStyle(color: p.text, fontSize: 12.5, fontFamily: 'monospace', fontWeight: FontWeight.w600);
    final TextStyle dim = TextStyle(color: p.muted, fontSize: 12.5, fontFamily: 'monospace');
    Widget head(String t) => Expanded(child: Text(t, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: headStyle));
    Widget cell(String t, TextStyle st) => Expanded(child: Text(t, textAlign: TextAlign.right, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis, style: st));
    final List<Widget> kids = <Widget>[
      Row(children: <Widget>[const SizedBox(width: 74), head('دخل'), head('منه كاش'), head('خرج'), head('منه تفكير')]),
      Divider(height: 12, color: p.border),
    ];
    for (final UsageRow r in rows) {
      final RunUsage u = r.usage;
      kids.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: <Widget>[
          SizedBox(width: 74, child: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: labelStyle)),
          cell(u.input > 0 ? fmtNum(u.input) : '—', strong),
          cell(u.input > 0 ? fmtNum(u.cached) : '—', dim),
          cell(u.output > 0 ? fmtNum(u.output) : '—', strong),
          cell(u.thinking > 0 ? fmtNum(u.thinking) : '—', dim),
        ]),
      ));
    }
    if (caption.isNotEmpty) {
      kids.add(Padding(padding: const EdgeInsets.only(top: 6), child: Text(caption, style: TextStyle(color: p.muted, fontSize: 11.5))));
    }
    for (final String n in notes) {
      kids.add(Padding(padding: const EdgeInsets.only(top: 4), child: Text(n, style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.4))));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(Rd.card), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids),
    );
  }
}

/// «الجولة 8 · 4:21» تتحرك كل ثانية (وإلا بدا الانتظار عالقاً بين حدثين).
class RunClock extends StatefulWidget {
  final ChatSession session;
  final TextStyle style;
  const RunClock({super.key, required this.session, required this.style});
  @override
  State<RunClock> createState() => _RunClockState();
}

class _RunClockState extends State<RunClock> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ChatSession s = widget.session;
    final DateTime? st = s.runStart;
    final int r = s.runRounds;
    final List<String> parts = <String>[
      if (r > 0) 'الجولة $r',
      if (st != null) fmtElapsed(DateTime.now().difference(st)),
    ];
    return Text(parts.join(' · '), style: widget.style);
  }
}

// ---- لوحة الملخّص -----------------------------------------------------------
class SummarySheet extends StatefulWidget {
  final ChatSession session;
  /// رسالة من التشغيل المطلوب (null = التشغيل الأخير).
  final String? msgId;
  const SummarySheet({super.key, required this.session, this.msgId});
  @override
  State<SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<SummarySheet> {
  Timer? _t;
  final ScrollController _sc = ScrollController();
  bool _stick = true;
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (mounted && widget.session.generating) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _sc.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical) _stick = n.metrics.pixels >= n.metrics.maxScrollExtent - 60;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    return ListenableBuilder(
      listenable: widget.session,
      builder: (BuildContext c, Widget? child) {
        final ChatSession s = widget.session;
        final List<ChatMessage> msgs = s.messages;
        int idx = -1;
        final String? id = widget.msgId;
        if (id != null) idx = msgs.indexWhere((ChatMessage m) => m.id == id);
        final int? at = idx >= 0 ? idx : null;
        final RunSpan sp = runSpanAt(msgs, at);
        final bool live = s.generating && sp.end == msgs.length;
        final List<RunStep> steps = buildRunSteps(msgs, live: live, at: at);
        final RunUsage total = runUsageAt(msgs, at);
        String title = 'الملخّص';
        String sub = '';
        if (live) {
          final DateTime? st = s.runStart;
          final List<String> bits = <String>[
            if (s.runRounds > 0) 'الجولة ${s.runRounds}',
            if (st != null) fmtElapsed(DateTime.now().difference(st)),
          ];
          sub = bits.join(' · ');
        } else {
          final String h = runSummaryHeader(steps);
          if (h.isNotEmpty) title = h;
        }
        if (live && steps.length != _seen && _stick) {
          WidgetsBinding.instance.addPostFrameCallback((Duration _) {
            if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
          });
        }
        _seen = steps.length;
        ChatMessage? lastA;
        for (int i = sp.end - 1; i >= sp.start; i--) {
          if (msgs[i].role == 'assistant' && !msgs[i].excluded) {
            lastA = msgs[i];
            break;
          }
        }
        final List<UsageRow> rows = <UsageRow>[];
        if (total.requests > 1 && lastA != null) rows.add(UsageRow('آخر طلب', usageOfMessages(<ChatMessage>[lastA])));
        rows.add(UsageRow(total.requests > 1 ? 'التشغيل كله' : 'هذا الطلب', total));
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 6, 8),
              child: Row(children: <Widget>[
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(title, style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w700)),
                    if (sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub, style: TextStyle(color: p.muted, fontSize: 12.5))),
                  ]),
                ),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: Icon(Icons.close, color: p.muted)),
              ]),
            ),
            Divider(height: 1, color: p.border),
            Expanded(
              child: steps.isEmpty
                  ? Center(child: Text(live ? 'لا خطوات بعد' : 'لا خطوات في هذا التشغيل', style: TextStyle(color: p.muted, fontSize: 14)))
                  : NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: ListView.builder(
                        controller: _sc,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        itemCount: steps.length,
                        itemBuilder: (BuildContext c2, int i) => _StepRow(key: ValueKey<int>(i), step: steps[i], last: i == steps.length - 1),
                      ),
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: UsageTable(rows: rows, caption: usageCaption(total), notes: usageNotes(total)),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _StepRow extends StatefulWidget {
  final RunStep step;
  final bool last;
  const _StepRow({super.key, required this.step, required this.last});
  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  bool _open = false;

  Widget _badge(Pal p, Widget inner) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(8)),
      child: Center(child: inner),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    final RunStep s = widget.step;
    final AppSettings cfg = appContainer.read(settingsProvider);
    Widget node;
    Widget content;
    if (s.note) {
      node = Container(width: 7, height: 7, decoration: BoxDecoration(color: p.muted, shape: BoxShape.circle));
      content = Padding(
        padding: const EdgeInsets.only(top: 3, bottom: 14),
        child: Text(
          s.title,
          style: TextStyle(
            color: p.text,
            fontSize: 14.5 * cfg.fontScale,
            height: 1.5,
            fontFamily: cfg.serif ? 'serif' : null,
            fontFamilyFallback: cfg.serif ? const <String>['Noto Serif', 'Georgia'] : null,
          ),
        ),
      );
    } else {
      if (s.running) {
        node = _badge(p, SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.8, color: p.accent)));
      } else if (s.failed) {
        node = _badge(p, Icon(Icons.warning_amber_rounded, size: 17, color: p.danger));
      } else {
        node = _badge(p, Icon(toolIcon(s.tool), size: 16, color: p.muted));
      }
      final List<Widget> kids = <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(s.title, style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35)),
        ),
      ];
      if (s.failed) {
        kids.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(s.error.isEmpty ? 'فشلت الخطوة' : 'فشلت · ${s.error}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.danger, fontSize: 12.5)),
        ));
      } else if (s.detail.isNotEmpty) {
        kids.add(Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(s.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12, fontFamily: 'monospace')),
          ),
        ));
      }
      final String? mi = s.minus;
      final String? pl = s.plus;
      final String? fl = s.file;
      if (s.edit && (mi != null || pl != null)) {
        kids.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                if (fl != null) Text(_baseName(fl), style: TextStyle(color: p.muted, fontSize: 11.5, fontFamily: 'monospace')),
                if (mi != null) Text(mi, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.danger, fontSize: 11.5, fontFamily: 'monospace')),
                if (pl != null) Text(pl, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.success, fontSize: 11.5, fontFamily: 'monospace')),
              ]),
            ),
          ),
        ));
      }
      final ToolCall? cl = s.call;
      if (_open && cl != null) {
        kids.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
              child: SelectableText(
                'args:\n${_prettyArgs(cl)}\n\nresult:\n${clip(cl.result ?? '(pending)', 3000)}',
                style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.45, color: p.text),
              ),
            ),
          ),
        ));
      }
      content = Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
      );
    }
    return InkWell(
      onTap: s.call == null ? null : () => setState(() => _open = !_open),
      child: Stack(children: <Widget>[
        if (!widget.last)
          Positioned.directional(
            textDirection: Directionality.of(context),
            start: 17,
            top: 28,
            bottom: 0,
            width: 1.5,
            child: ColoredBox(color: p.border),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          SizedBox(width: 36, height: 28, child: Center(child: node)),
          Expanded(child: content),
        ]),
      ]),
    );
  }
}

// ---- Terminal: سطر العمل الحيّ -------------------------------------------------
/// «Thinking… (14s · round 7 · 4:07)» وتحته «⎿ آخر خطوة ›»؛ الضغط يفتح لوحة الملخّص.
class TerminalWorkLine extends StatefulWidget {
  final ChatSession session;
  final VoidCallback onOpen;
  const TerminalWorkLine({super.key, required this.session, required this.onOpen});
  @override
  State<TerminalWorkLine> createState() => _TerminalWorkLineState();
}

class _TerminalWorkLineState extends State<TerminalWorkLine> {
  Timer? _t;
  String _key = '';
  DateTime _since = DateTime.now();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _verb(String st) {
    if (st == 'connecting') return 'Connecting…';
    if (st == 'thinking') return 'Thinking…';
    if (st == 'writing') return 'Writing…';
    if (st == 'compacting') return 'Compacting…';
    if (st.startsWith('retry:')) return 'Retrying…';
    if (st.startsWith('tool:')) return 'Running ${st.substring(5)}…';
    return 'Working…';
  }

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    final ChatSession s = widget.session;
    final String st = s.status;
    if (st != _key) {
      _key = st;
      _since = DateTime.now();
    }
    final DateTime now = DateTime.now();
    final DateTime? rs = s.runStart;
    final List<String> meta = <String>[
      '${now.difference(_since).inSeconds}s',
      if (s.runRounds > 0) 'round ${s.runRounds}',
      if (rs != null) fmtElapsed(now.difference(rs)),
    ];
    final String note = s.liveNote;
    final TextStyle mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.45, color: p.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: InkWell(
          onTap: widget.onOpen,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.6, color: p.accent)),
              const SizedBox(width: 10),
              Flexible(child: Text('${_verb(st)} (${meta.join(' · ')})', maxLines: 1, overflow: TextOverflow.ellipsis, style: mono)),
            ]),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 23, top: 2),
                child: Text('⎿ $note ›', maxLines: 2, overflow: TextOverflow.ellipsis, style: mono.copyWith(color: p.text)),
              ),
          ]),
        ),
      ),
    );
  }
}

// ---- معاينة CI: لوحة الملخّص ببيانات نموذجية (تلتقطها خطوة المحاكي) -----------------
ChatSession previewSummarySession() {
  final ChatSession s = ChatSession(ConvMeta(id: newId(), title: 'فحص بيئة العمل'));
  ToolCall tc(String name, Map<String, dynamic> args, String result, {bool err = false}) {
    return ToolCall(id: newId(), name: name, args: args, result: result, isError: err, status: err ? 'error' : 'done');
  }

  ChatMessage round(String note, List<ToolCall> calls, {int inTok = 0, int cache = 0, int out = 0, int think = 0}) {
    return ChatMessage(id: newId(), role: 'assistant', content: note, toolCalls: calls, inTok: inTok, cacheTok: cache, outTok: out, thinkTok: think, tokExact: true, model: 'deepseek-v4.1-flash');
  }

  s.messages.addAll(<ChatMessage>[
    ChatMessage(id: newId(), role: 'user', content: 'افحص بيئة العمل كاملة وحلّلها'),
    round('أفحص الأدوات المثبّتة على الهاتف.', <ToolCall>[
      tc('bash', <String, dynamic>{'command': 'ls ~/.claude/skills; which node python3 git curl', 'description': 'فحص الأدوات المثبّتة على الهاتف'}, 'node\npython3\ngit'),
    ], inTok: 22707, cache: 22528, out: 2682, think: 2400),
    round('أنتقل إلى إعداد الوسيط لأرى كيف تُمرَّر الطلبات.', <ToolCall>[
      tc('bash', <String, dynamic>{'command': 'grep -n port ~/.config/proxy/*.ts', 'description': 'البحث عن إعداد المنفذ'}, 'server.ts:12: const port = 8787'),
    ], inTok: 24100, cache: 23900, out: 910, think: 600),
    round('المنفذ 8787، أنظر الآن في خريطة المسارات نفسها.', <ToolCall>[
      tc('read_file', <String, dynamic>{'path': '~/.config/proxy/map.ts', 'description': 'قراءة خريطة المسارات في الوسيط'}, 'export const routes = []'),
      tc('fetch_url', <String, dynamic>{'url': 'https://docs.claude.com/en/docs/build-with-claude/extended-thinking'}, 'HTTP 404 Not Found', err: true),
    ], inTok: 25300, cache: 25100, out: 740, think: 410),
    round('أصحّح اختبار الاستهلاك ليشمل توكنز التفكير.', <ToolCall>[
      tc('edit_file', <String, dynamic>{
        'path': 'lib/engine_selftest.dart',
        'old_string': "expect(usageOf(a), 'in=22707 out=2682');",
        'new_string': "expect(usageOf(a), 'in=22707 out=2682 think=2400');",
      }, 'ok'),
      tc('bash', <String, dynamic>{'command': 'git diff --stat && git status -sb', 'description': 'تشغيل الاختبارات الذاتية'}, '1 file changed'),
    ], inTok: 26000, cache: 25800, out: 520, think: 300),
    ChatMessage(id: newId(), role: 'assistant', content: 'فحصتُ البيئة كاملة. Node وPython وgit مثبّتة، والوسيط يعمل على المنفذ 8787.', inTok: 26900, cacheTok: 26500, outTok: 380, thinkTok: 150, tokExact: true, model: 'deepseek-v4.1-flash'),
  ]);
  return s;
}
