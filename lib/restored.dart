part of 'main.dart';

// =====================================================================
//  ميزات أصلية كانت مستبدلة بقوالب فارغة في compat.dart: تراجع تعديلات الملفات (Checkpoints)،
//  فاحص الطلب («ما يراه النموذج بالحرف»)، والبحث النصي في كل المحادثات. استُعيدت من v2.3.0 كما هي.
// =====================================================================

dynamic redactJson(dynamic v, [String key = '']) {
  if (v is Map) {
    final out = <String, dynamic>{};
    v.forEach((k, val) {
      out[k.toString()] = redactJson(val, k.toString());
    });
    return out;
  }
  if (v is List) return v.map((e) => redactJson(e, key)).toList();
  if (v is String && v.length > 400 && (key == 'data' || key == 'file_data' || v.startsWith('data:'))) {
    return '<${v.length} chars base64>';
  }
  return v;
}

String maskKey(String v) => v.length <= 10 ? '••••' : '${v.substring(0, 6)}••••${v.substring(v.length - 3)}';

String describeRequest(ChatSession session) {
  final c = session.lastCall;
  if (c == null) return 'لم يُرسل أي طلب في هذه المحادثة بعد.';
  final b = StringBuffer();
  b.writeln('POST ${c.url}');
  c.headers.forEach((k, v) {
    final low = k.toLowerCase();
    final masked = (low.contains('key') || low == 'authorization') ? maskKey(v) : v;
    b.writeln('$k: $masked');
  });
  b.writeln();
  b.writeln(const JsonEncoder.withIndent('  ').convert(redactJson(c.body)));
  return b.toString();
}

/// قائمة تعديلات الملفات التي أجراها النموذج في هذه المحادثة، مع زر تراجع لكل تعديل.
class CheckpointsSheet extends StatefulWidget {
  final String convId;
  const CheckpointsSheet({super.key, required this.convId});
  @override
  State<CheckpointsSheet> createState() => _CheckpointsSheetState();
}

class _CheckpointsSheetState extends State<CheckpointsSheet> {
  List<Checkpoint>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await CheckpointStore.list(widget.convId);
    if (mounted) setState(() => _items = l.reversed.toList());
  }

  Future<void> _undo(Checkpoint c) async {
    final changed = await CheckpointStore.changedSince(c);
    final name = c.path.split('/').last;
    final what = c.existed ? 'سيُستعاد "$name" كما كان قبل التعديل.' : 'سيُحذف "$name" (أنشأه النموذج).';
    final warn = changed ? '\n\nتنبيه: الملف تغيّر بعد هذا التعديل، وسيضيع ما تغيّر.' : '';
    if (!mounted) return;
    final ok = await confirmDialog(context, 'التراجع عن تعديل', '$what$warn', ok: 'تراجع');
    if (!ok) return;
    String msg;
    try {
      msg = await CheckpointStore.undo(c);
    } catch (e) {
      msg = 'تعذّر التراجع: $e';
    }
    toast(msg);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final items = _items;
    Widget body;
    if (items == null) {
      body = Center(child: CircularProgressIndicator(strokeWidth: 2, color: p.accent));
    } else if (items.isEmpty) {
      body = Center(child: Text('لا توجد تعديلات ملفات بعد', style: TextStyle(color: p.muted)));
    } else {
      body = ListView.builder(
        itemCount: items.length,
        itemBuilder: (c, i) {
          final it = items[i];
          final parts = it.path.split('/');
          final dir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '';
          return ListTile(
            leading: Icon(it.existed ? Icons.edit_outlined : Icons.add_circle_outline, color: p.muted, size: 22),
            title: Text(parts.last, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15)),
            subtitle: Text('${toolLabel(it.tool)} · ${fmtClock(it.time)}${dir.isEmpty ? '' : ' · $dir'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
            trailing: it.undone
                ? Text('تم التراجع', style: TextStyle(color: p.muted, fontSize: 12.5))
                : TextButton(onPressed: () => _undo(it), child: Text('تراجع', style: TextStyle(color: p.accent))),
          );
        },
      );
    }
    return FractionallySizedBox(
      heightFactor: 0.7,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('تعديلات الملفات في هذه المحادثة', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: body),
      ]),
    );
  }
}

void showInspector(BuildContext context, ChatSession session) {
  final text = describeRequest(session);
  int inTok = 0;
  int outTok = 0;
  bool exact = false;
  int cacheTok = 0;
  for (final m in session.messages.reversed) {
    if (m.role == 'assistant' && (m.inTok > 0 || m.outTok > 0)) {
      inTok = m.inTok;
      outTok = m.outTok;
      cacheTok = m.cacheTok;
      exact = m.tokExact;
      break;
    }
  }
  int excluded = 0;
  int est = 0;
  for (final m in session.messages) {
    if (m.excluded) {
      excluded++;
    } else {
      est += estimateTokens(m.content);
    }
  }
  showSheet<void>(context, (c) {
    final p = pal(c);
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(children: [
            Expanded(child: Text('ما يراه النموذج بالحرف', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600))),
            IconButton(
              tooltip: 'نسخ',
              icon: Icon(Icons.copy_rounded, size: 20, color: p.muted),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                toast('تم النسخ');
              },
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '${session.messages.length} رسالة${excluded > 0 ? ' ($excluded مستبعدة)' : ''} · ${exact ? '' : '~'}$inTok دخل${cacheTok > 0 ? ' (⚡$cacheTok من الكاش)' : ''} / ${exact ? '' : '~'}$outTok خرج · تقدير النصوص ~$est${session.ctxDropped > 0 ? ' · ${session.ctxDropped} رسالة قديمة خارج السياق' : ''}',
            style: TextStyle(color: p.muted, fontSize: 12.5),
          ),
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(text, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.45, color: p.text)),
            ),
          ),
        ),
      ]),
    );
  });
}

/// بحث نصي في محتوى كل المحادثات المحفوظة. يعيد {id: مقتطف}.
Future<Map<String, String>> searchChats(String q) async {
  final out = <String, String>{};
  final needle = q.trim().toLowerCase();
  if (needle.isEmpty) return out;
  final convs = appContainer.read(convListProvider);
  int n = 0;
  for (final c in convs) {
    n++;
    if (n % 8 == 0) await Future<void>.delayed(Duration.zero);
    final raw = await LocalStorage.load('chats', c.id);
    if (raw == null) continue;
    try {
      for (final e in asList(jsonDecode(raw))) {
        final t = asStr(asMap(e)['content']);
        final low = t.toLowerCase();
        final i = low.indexOf(needle);
        if (i < 0) continue;
        final st = clampInt(i - 40, 0, t.length);
        final en = clampInt(i + needle.length + 70, 0, t.length);
        out[c.id] = '…${t.substring(st, en).replaceAll('\n', ' ')}…';
        break;
      }
    } catch (_) {}
  }
  return out;
}
