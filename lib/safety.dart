part of 'main.dart';

// ---------------------------------------------------------------------
// أمان وأدوات تشخيص: بحث المحادثات، نقاط الحفظ (تراجع عن تعديلات الأدوات)،
// وفحص ما يُرسل للنموذج فعلاً.
// ---------------------------------------------------------------------

Future<Map<String, String>> searchChats(String query) async {
  final q = query.trim().toLowerCase();
  final out = <String, String>{};
  if (q.length < 2) return out;
  final idx = appContainer.read(convListProvider);
  for (final cv in idx) {
    final raw = await LocalStorage.load('chats', cv.id);
    if (raw == null) continue;
    try {
      for (final e in asList(jsonDecode(raw))) {
        final text = asStr(asMap(e)['content']);
        final i = text.toLowerCase().indexOf(q);
        if (i < 0) continue;
        final a = i > 30 ? i - 30 : 0;
        final b = (i + q.length + 50) < text.length ? i + q.length + 50 : text.length;
        out[cv.id] = '${a > 0 ? '…' : ''}${text.substring(a, b).replaceAll('\n', ' ')}${b < text.length ? '…' : ''}';
        break;
      }
    } catch (_) {}
  }
  return out;
}

class CheckpointsSheet extends StatefulWidget {
  final String convId;
  const CheckpointsSheet({super.key, required this.convId});

  @override
  State<CheckpointsSheet> createState() => _CheckpointsSheetState();
}

class _CheckpointsSheetState extends State<CheckpointsSheet> {
  late Future<List<Checkpoint>> _f;

  @override
  void initState() {
    super.initState();
    _f = CheckpointStore.list(widget.convId);
  }

  void _reload() => setState(() => _f = CheckpointStore.list(widget.convId));

  Future<void> _undo(Checkpoint c) async {
    if (await CheckpointStore.changedSince(c)) {
      if (!mounted) return;
      final ok = await confirmDialog(context, 'الملف تغيّر بعد هذا التعديل', 'التراجع سيكتب فوق التغييرات الأحدث. متابعة؟', ok: 'تراجع');
      if (!ok) return;
    }
    final msg = await CheckpointStore.undo(c);
    toast(msg);
    _reload();
  }

  String _label(Checkpoint c) {
    if (c.tool == kToolEditFile) return 'تعديل';
    return c.existed ? 'استبدال' : 'إنشاء';
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(alignment: AlignmentDirectional.centerStart, child: Text('نقاط الحفظ', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600))),
          ),
          Flexible(
            child: FutureBuilder<List<Checkpoint>>(
              future: _f,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                }
                final list = (snap.data ?? <Checkpoint>[]).reversed.toList();
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text('لا توجد تعديلات ملفات في هذه المحادثة. تُسجَّل نسخة قبل كل تعديل ينفذه الـ Agent ليمكن التراجع عنه.', textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.6)),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (c, i) {
                    final cp = list[i];
                    final slash = cp.path.lastIndexOf('/');
                    final name = slash < 0 ? cp.path : cp.path.substring(slash + 1);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(children: <Widget>[
                        IconBadge(cp.existed ? Icons.edit_outlined : Icons.note_add_outlined),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                            Directionality(textDirection: TextDirection.ltr, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w600, fontFamily: 'monospace'))),
                            const SizedBox(height: 2),
                            Text('${_label(cp)} · ${fmtDate(cp.time)} ${two(cp.time.hour)}:${two(cp.time.minute)}${cp.undone ? ' · تم التراجع' : ''}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                          ]),
                        ),
                        TextButton(onPressed: cp.undone ? null : () => _undo(cp), child: const Text('تراجع')),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

Future<void> showInspector(BuildContext context, dynamic session) async {
  final c = appContainer;
  final s = c.read(settingsProvider);
  final profile = c.read(profilesProvider).selected;
  final meta = session.meta as ConvMeta;
  final agent = c.read(agentsProvider.notifier).byId(c.read(selectedAgentProvider));
  final project = c.read(projectsProvider.notifier).byId(meta.projectId);
  final mem = c.read(memoryProvider);
  final lib = c.read(libraryProvider);
  final tools = availableTools(s, agent, hasLibrary: lib.isNotEmpty, hasMemory: mem.isNotEmpty, workspace: currentWorkspace());
  final system = await buildSystemPrompt(s: s, project: project, agent: agent, memory: mem, library: lib, tools: tools);
  var hist = 0;
  var n = 0;
  for (final m in session.messages as List<ChatMessage>) {
    if (m.excluded) continue;
    n++;
    hist += estimateTokens(m.content);
    for (final t in m.toolCalls) {
      hist += estimateTokens(t.result ?? '');
    }
  }
  final sysTok = estimateTokens(system);
  if (!context.mounted) return;
  await showSheet<void>(context, (ctx) {
    final p = pal(ctx);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            SizedBox(width: 92, child: Text(k, style: TextStyle(color: p.muted, fontSize: 13))),
            Expanded(child: Text(v, style: TextStyle(color: p.text, fontSize: 13.5))),
          ]),
        );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const SheetHandle(),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('ما يُرسل للنموذج', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                row('المزوّد', profile == null ? '-' : '${profile.name} · ${profile.selectedModel}'),
                row('Agent', agent == null ? 'بدون' : agent.name),
                row('المشروع', project == null ? 'بدون' : project.name),
                row('الأدوات', tools.isEmpty ? 'لا شيء' : tools.map((t) => t.name).join('، ')),
                row('توكنز تقريبية', 'التعليمات $sysTok + السجل $hist ($n رسالة)'),
                const SizedBox(height: 10),
                Text('تعليمات النظام', style: TextStyle(color: p.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
                    child: SelectableText(clip(system, 12000), style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.5, color: p.codeText)),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  });
}
