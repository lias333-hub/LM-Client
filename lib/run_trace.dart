part of 'main.dart';

// =====================================================================
//  سجل التشغيل (Harness H1): تسجيل محلي دائم لكل طلب وكل أداة في كل تشغيل، يُصدَّر بضغطة واحدة للتشخيص.
//
//  لماذا: لا يمكن تحسين المحرّك بالتخمين. نحتاج أرقاماً حقيقية من مهمة حقيقية: كم طلباً، كم بايتاً، كم توكنز،
//  أين تأخّر النموذج، أي أداة فشلت وبأي وسائط، متى أعاد المحرّك المحاولة أو أصلح الطلب أو لخّص السياق.
//
//  القواعد:
//   - التسجيل محلي فقط (LMClient/traces/<conv>.jsonl) ولا يُرسل لأي جهة. سطر JSON لكل حدث، يُلحق فوراً فيبقى ما
//     سُجّل حتى لو انهار التطبيق.
//   - كل نص يمرّ على Redactor قبل الكتابة (وعند التصدير مرة ثانية): المفاتيح والرموز تُحجب في كل المستويات.
//   - التسجيل يخزّن المحتوى بسقوف (نتيجة أداة 12K حرف، جسم الطلب الأول والفاشل فقط)؛ مستوى التصدير يفلتر التصدير
//     فقط (أرقام فقط / قياسي / كامل).
//   - سقف 3 MB لكل محادثة (يُحذف الأقدم) و20 MB للمجموع (تُحذف أقدم المحادثات).
//   - لا يرمي أي خطأ أبداً: فشل التسجيل لا يجوز أن يُفسد التشغيل.
// =====================================================================
const String kTraceNumbers = 'numbers';
const String kTraceStandard = 'standard';
const String kTraceFull = 'full';

String traceLevelLabel(String l) => l == kTraceNumbers ? 'أرقام فقط' : (l == kTraceFull ? 'كامل' : 'قياسي');

String traceLevelHelp(String l) {
  if (l == kTraceNumbers) return 'أحجام وأزمنة واستهلاك توكنز وأخطاء وأسماء الأدوات فقط. لا نصوص ولا محتوى ملفات ولا وسائط أدوات.';
  if (l == kTraceFull) return 'كل ما سُجّل: نتائج الأدوات ووسائطها والتفكير وردود النموذج ونص الطلب الأول والفاشل. قد يحوي محتوى ملفاتك وكلامك.';
  return 'يضيف وسائط الأدوات ونتائجها مقصوصة وأوائل الردود. بلا نص التفكير ولا نص الطلب الكامل.';
}

class TraceInfo {
  final int records;
  final int runs;
  final int bytes;
  const TraceInfo(this.records, this.runs, this.bytes);
}

class _TraceFileStat {
  final File file;
  final int size;
  final DateTime mod;
  const _TraceFileStat(this.file, this.size, this.mod);
}

dynamic _traceWalk(dynamic v, String Function(String) f) {
  if (v is String) return f(v);
  if (v is Map) {
    final Map<String, dynamic> o = <String, dynamic>{};
    v.forEach((dynamic k, dynamic x) {
      o['$k'] = _traceWalk(x, f);
    });
    return o;
  }
  if (v is List) return <dynamic>[for (final dynamic x in v) _traceWalk(x, f)];
  return v;
}

String _traceClip(String s, int max, {int tail = 0}) {
  if (s.length <= max) return s;
  final int t = tail < max ? tail : 0;
  final int head = max - t;
  return '${s.substring(0, head)}…[+${s.length - max} chars]…${t > 0 ? s.substring(s.length - t) : ''}';
}

/// بصمة قصيرة ثابتة (FNV-1a) لنص كبير مثل الـ system prompt: تكفي لمعرفة هل تغيّر بين طلبين.
String traceHash(String s) {
  int h = 0x811c9dc5;
  for (int i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

class RunTrace {
  /// السقوف قابلة للتغيير من كود الاختبار فقط.
  static int fileCap = 3 * 1024 * 1024;
  static int totalCap = 20 * 1024 * 1024;
  static const int _recCap = 240000;
  static const int _bodyCap = 120000;
  static const int _exportChars = 2000000;

  /// مفاتيح تحمل محتوى (نصوص المستخدم والملفات والنموذج): يفلترها التصدير بحسب المستوى.
  static const Set<String> _contentKeys = <String>{'args', 'raw', 'result', 'text', 'think', 'body', 'system', 'user', 'errBody', 'ttl'};
  static const Map<String, int> _caps = <String, int>{
    'result': 12000,
    'text': 8000,
    'think': 4000,
    'user': 4000,
    'errBody': 2000,
    'system': 24000,
    'raw': 6000,
    'ttl': 300,
    'err': 1000,
    'args': 6000,
  };

  static final Map<String, Future<void>> _chains = <String, Future<void>>{};
  static final List<Map<String, dynamic>> _approvals = <Map<String, dynamic>>[];
  static int _seq = 0;

  static bool _enabled() {
    try {
      return appContainer.read(settingsProvider).traceOn;
    } catch (_) {
      return false;
    }
  }

  static String newRunId() {
    _seq++;
    return 'r${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${_seq.toRadixString(36)}';
  }

  // ---- موافقات المستخدم: تُجمَّع ثم تُلحق ببطاقة الأداة التي طلبتها ----------
  static void noteApproval(String how, bool ok, int ms, String title) {
    try {
      _approvals.add(<String, dynamic>{'how': how, 'ok': ok, 'ms': ms, 'ttl': title});
      if (_approvals.length > 20) _approvals.removeAt(0);
    } catch (_) {}
  }

  static List<Map<String, dynamic>> takeApprovals() {
    final List<Map<String, dynamic>> r = List<Map<String, dynamic>>.from(_approvals);
    _approvals.clear();
    return r;
  }

  // ---- الكتابة --------------------------------------------------------------
  static String _red(String s, List<String> known) {
    final String t = s.length > 300000 ? s.substring(0, 300000) : s;
    return Redactor.clean(t, heuristics: true, known: known).text;
  }

  static Future<void> _enqueue(String conv, Future<void> Function() job) {
    final Future<void> prev = _chains[conv] ?? Future<void>.value();
    final Future<void> next = prev.then((_) => job()).catchError((Object e) {
      debugPrint('trace job failed: $e');
    });
    _chains[conv] = next;
    return next;
  }

  static Future<File> _file(String conv) async {
    final Directory d = await LocalStorage.folder('traces');
    return File('${d.path}/${safeFileName(conv)}.jsonl');
  }

  static dynamic _bodyFor(dynamic body, List<String> known) {
    final dynamic red = _traceWalk(body, (String s) => _red(s, known));
    dynamic w = _traceWalk(red, (String s) => _traceClip(s, 3000, tail: 600));
    if (jsonEncode(w).length <= _bodyCap) return w;
    w = _traceWalk(red, (String s) => _traceClip(s, 400, tail: 100));
    final int n = jsonEncode(w).length;
    if (n <= _bodyCap) return w;
    return <String, dynamic>{'omitted_bytes': n};
  }

  /// يسجّل حدثاً. متزامن وآمن: لا يرمي أبداً.
  static void log(String conv, String run, String ev, Map<String, dynamic> data, {bool sub = false}) {
    try {
      if (!_enabled()) return;
      final List<String> known = Redactor.knownSecrets();
      final Map<String, dynamic> rec = <String, dynamic>{'t': DateTime.now().millisecondsSinceEpoch, 'ev': ev, 'run': run};
      if (sub) rec['sub'] = 1;
      for (final MapEntry<String, dynamic> e in data.entries) {
        final dynamic v = e.value;
        if (v == null) continue;
        if (e.key == 'body') {
          rec['body'] = _bodyFor(v, known);
          continue;
        }
        final int cap = _caps[e.key] ?? 0;
        if (cap == 0) {
          rec[e.key] = _traceWalk(v, (String s) => _red(s, known));
        } else {
          rec[e.key] = _traceWalk(v, (String s) => _traceClip(_red(s, known), cap, tail: cap ~/ 4));
        }
      }
      String line = jsonEncode(rec);
      if (line.length > _recCap && rec.containsKey('body')) {
        rec['body'] = <String, dynamic>{'omitted_bytes': line.length};
        line = jsonEncode(rec);
      }
      if (line.length > _recCap) line = jsonEncode(<String, dynamic>{'t': rec['t'], 'ev': ev, 'run': run, 'oversize': line.length});
      final String ln = line;
      unawaited(_enqueue(conv, () async {
        final File f = await _file(conv);
        await f.writeAsString('$ln\n', mode: FileMode.append, flush: true);
      }));
    } catch (e) {
      debugPrint('trace log failed: $e');
    }
  }

  static Future<void> flush(String conv) async {
    try {
      await (_chains[conv] ?? Future<void>.value());
    } catch (_) {}
  }

  // ---- صيانة وحذف -------------------------------------------------------------
  static Future<void> _trim(File f, int keep) async {
    final Uint8List b = await f.readAsBytes();
    if (b.length <= keep) return;
    int st = b.length - keep;
    while (st < b.length && b[st] != 10) {
      st++;
    }
    st++;
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(st >= b.length ? <int>[] : b.sublist(st), flush: true);
    await tmp.rename(f.path);
  }

  static Future<void> _prune(String keep) async {
    final Directory d = await LocalStorage.folder('traces');
    final List<_TraceFileStat> files = <_TraceFileStat>[];
    int total = 0;
    await for (final FileSystemEntity e in d.list()) {
      if (e is! File || !e.path.endsWith('.jsonl')) continue;
      final FileStat st = await e.stat();
      files.add(_TraceFileStat(e, st.size, st.modified));
      total += st.size;
    }
    if (total <= totalCap) return;
    files.sort((_TraceFileStat a, _TraceFileStat b) => a.mod.compareTo(b.mod));
    final String keepName = '${safeFileName(keep)}.jsonl';
    for (final _TraceFileStat t in files) {
      if (total <= totalCap) break;
      if (t.file.path.endsWith('/$keepName')) continue;
      try {
        await t.file.delete();
        total -= t.size;
      } catch (_) {}
    }
  }

  /// يُستدعى عند بدء كل تشغيل: يقصّ ملف هذه المحادثة إن تجاوز سقفه، ثم يطبّق سقف المجموع.
  static Future<void> maintain(String conv) {
    return _enqueue(conv, () async {
      final File f = await _file(conv);
      if (await f.exists() && await f.length() > fileCap) await _trim(f, fileCap ~/ 2);
      await _prune(conv);
    });
  }

  static Future<void> purge(String conv) {
    return _enqueue(conv, () async {
      final File f = await _file(conv);
      if (await f.exists()) await f.delete();
    });
  }

  static Future<int> clearAll() async {
    int n = 0;
    try {
      final Directory d = await LocalStorage.folder('traces');
      await for (final FileSystemEntity e in d.list()) {
        if (e is File) {
          try {
            await e.delete();
            n++;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return n;
  }

  // ---- القراءة ------------------------------------------------------------------
  static Future<List<Map<String, dynamic>>> load(String conv) async {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    try {
      await flush(conv);
      final File f = await _file(conv);
      if (!await f.exists()) return out;
      final String raw = utf8.decode(await f.readAsBytes(), allowMalformed: true);
      for (final String line in const LineSplitter().convert(raw)) {
        if (line.trim().isEmpty) continue;
        try {
          final dynamic j = jsonDecode(line);
          if (j is Map) out.add(asMap(j));
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  static Future<TraceInfo> info(String conv) async {
    final List<Map<String, dynamic>> recs = await load(conv);
    final Set<String> runs = <String>{};
    for (final Map<String, dynamic> r in recs) {
      final String x = '${r['run'] ?? ''}';
      if (x.isNotEmpty && r['sub'] != 1) runs.add(x);
    }
    int bytes = 0;
    try {
      final File f = await _file(conv);
      if (await f.exists()) bytes = await f.length();
    } catch (_) {}
    return TraceInfo(recs.length, runs.length, bytes);
  }

  // ---- التصدير ------------------------------------------------------------------
  static Map<String, dynamic> _filter(Map<String, dynamic> r, String level, List<String> known) {
    final Map<String, dynamic> o = <String, dynamic>{};
    r.forEach((String k, dynamic v) {
      if (_contentKeys.contains(k)) {
        if (level == kTraceNumbers) return;
        if (level == kTraceStandard) {
          if (k == 'think' || k == 'body' || k == 'system') return;
          final int max = k == 'result' ? 700 : (k == 'ttl' ? 120 : (k == 'errBody' ? 500 : 300));
          o[k] = _traceWalk(v, (String s) => _traceClip(s, max, tail: k == 'result' ? 200 : 0));
          return;
        }
      }
      o[k] = v;
    });
    final dynamic err = o['err'];
    if (level == kTraceNumbers && err is String) o['err'] = _traceClip(err, 200);
    return asMap(_traceWalk(o, (String s) => _red(s, known)));
  }

  static String _sec(num ms) => '${(ms / 1000).toStringAsFixed(1)}s';

  static String _runSummary(String run, List<Map<String, dynamic>> rs, bool omitted) {
    final StringBuffer b = StringBuffer();
    Map<String, dynamic>? start;
    Map<String, dynamic>? end;
    for (final Map<String, dynamic> r in rs) {
      if (r['ev'] == 'run_start') start = r;
      if (r['ev'] == 'run_end') end = r;
    }
    final int t0 = (start?['t'] is num) ? (start!['t'] as num).toInt() : ((rs.first['t'] is num) ? (rs.first['t'] as num).toInt() : 0);
    final bool isSub = rs.any((Map<String, dynamic> r) => r['sub'] == 1);
    final String when = t0 == 0 ? '?' : '${fmtDate(DateTime.fromMillisecondsSinceEpoch(t0))} ${fmtClock(DateTime.fromMillisecondsSinceEpoch(t0))}';
    b.writeln('run ${run.isEmpty ? '(outside a run)' : run}${isSub ? ' [sub-agent]' : ''} · $when · ${start?['model'] ?? '?'} (${start?['provider'] ?? '?'}) · msgs at start ${start?['msgs'] ?? '?'}');
    if (omitted) {
      b.writeln('  (details omitted: export size cap; older run)');
      return b.toString();
    }
    if (start == null) b.writeln('  (run_start missing: the start of this run was trimmed by the size cap)');
    if (end == null) {
      b.writeln('  end: NO run_end record (app was killed, crashed, or the run is still going)');
    } else {
      b.writeln('  end: ${end['reason']} · ${end['rounds']} rounds · ${end['reqs']} responses · ${end['ms'] is num ? _sec(end['ms'] as num) : '?'}'
          ' · in ${fmtNum((end['in'] as num?)?.toInt() ?? 0)} (cache ${fmtNum((end['cache'] as num?)?.toInt() ?? 0)}) · out ${fmtNum((end['out'] as num?)?.toInt() ?? 0)}'
          ' · think ${fmtNum((end['thinkTok'] as num?)?.toInt() ?? 0)} · no-usage ${end['noUsage'] ?? 0}${(end['err'] is String && (end['err'] as String).isNotEmpty) ? ' · err: ${_traceClip(end['err'] as String, 160)}' : ''}');
    }
    for (final Map<String, dynamic> r in rs) {
      final String ev = '${r['ev']}';
      final String rel = (r['t'] is num && t0 > 0) ? '+${_sec((r['t'] as num) - t0)}' : '';
      if (ev == 'run_start' || ev == 'run_end') continue;
      if (ev == 'request') {
        b.writeln('  $rel #${r['n']} → ${r['msgs']} msgs · ${fmtBytes((r['bytes'] as num?)?.toInt() ?? 0)} · ${r['tools']} tools · attempt ${r['attempt']}${(r['healed'] is List && (r['healed'] as List).isNotEmpty) ? ' · healed ${r['healed']}' : ''}');
      } else if (ev == 'response') {
        final List<dynamic> calls = r['calls'] is List ? r['calls'] as List<dynamic> : <dynamic>[];
        final String names = calls.map((dynamic c) => c is Map ? '${c['name']}${c['bad'] == true ? '(BAD-JSON)' : ''}' : '?').join(', ');
        b.writeln('  $rel #${r['n']} ← ${r['ok']} ${r['ms'] is num ? _sec(r['ms'] as num) : '?'} (first-event ${r['ttfe'] is num && (r['ttfe'] as num) >= 0 ? _sec(r['ttfe'] as num) : '—'}, first-token ${r['ttft'] is num && (r['ttft'] as num) >= 0 ? _sec(r['ttft'] as num) : '—'})'
            ' · in ${r['in']} cache ${r['cache']} out ${r['out']} think ${r['thinkTok']}${r['exact'] == true ? '' : ' (estimated)'} · stop ${r['stop']}${calls.isEmpty ? '' : ' · calls: $names'}${(r['err'] is String && (r['err'] as String).isNotEmpty) ? ' · err: ${_traceClip(r['err'] as String, 120)}' : ''}');
      } else if (ev == 'req_error') {
        b.writeln('  $rel #${r['n']} ✗ status ${r['status']} → ${r['action']} · ${_traceClip('${r['err'] ?? ''}', 140)}');
      } else if (ev == 'tool') {
        b.writeln('  $rel tool ${r['name']} ${r['ms'] is num ? _sec(r['ms'] as num) : ''} ${r['isErr'] == true ? 'ERROR' : 'ok'} · args ${r['argLen'] ?? '?'} chars · result ${r['resLen'] ?? '?'} chars${(r['approvals'] is List && (r['approvals'] as List).isNotEmpty) ? ' · approvals ${(r['approvals'] as List).map((dynamic a) => a is Map ? '${a['how']}:${a['ok'] == true ? 'yes' : 'no'}' : '?').join(',')}' : ''}${r['skipped'] != null ? ' · skipped ${r['skipped']}' : ''}');
      } else {
        final Map<String, dynamic> d = <String, dynamic>{};
        r.forEach((String k, dynamic v) {
          if (k != 't' && k != 'ev' && k != 'run' && k != 'sub' && !_contentKeys.contains(k)) d[k] = v;
        });
        b.writeln('  $rel $ev ${_traceClip(jsonEncode(d), 180)}');
      }
    }
    return b.toString();
  }

  /// نص التصدير الكامل: ترويسة وملخّص بشري لكل تشغيل، ثم سطور JSON مفلترة بحسب [level].
  static Future<String> build(String conv, String title, String level) async {
    final List<Map<String, dynamic>> recs = await load(conv);
    final List<String> order = <String>[];
    final Map<String, List<Map<String, dynamic>>> by = <String, List<Map<String, dynamic>>>{};
    for (final Map<String, dynamic> r in recs) {
      final String run = '${r['run'] ?? ''}';
      final List<Map<String, dynamic>>? l = by[run];
      if (l == null) {
        by[run] = <Map<String, dynamic>>[r];
        order.add(run);
      } else {
        l.add(r);
      }
    }
    final List<String> known = Redactor.knownSecrets();
    final Map<String, List<String>> lines = <String, List<String>>{};
    for (final String run in order) {
      lines[run] = <String>[for (final Map<String, dynamic> r in by[run]!) jsonEncode(_filter(r, level, known))];
    }
    // الأحدث أولاً حتى سقف الحجم؛ الأحدث يُضمَّن دائماً.
    final Set<String> omitted = <String>{};
    int budget = _exportChars;
    bool first = true;
    for (final String run in order.reversed) {
      final int n = lines[run]!.fold<int>(0, (int a, String s) => a + s.length + 1);
      if (!first && n > budget) {
        omitted.add(run);
      } else {
        budget -= n;
      }
      first = false;
    }
    final StringBuffer o = StringBuffer();
    o.writeln('# LMClient run trace');
    o.writeln('# app: v$kAppVersion · build $kBuildId · exported ${DateTime.now().toIso8601String()}');
    o.writeln('# level: $level (${traceLevelLabel(level)}) · secrets are redacted at every level');
    if (level != kTraceNumbers && title.trim().isNotEmpty) o.writeln('# conversation: ${_traceClip(_red(title.trim(), known), 80)}');
    o.writeln('# runs in file: ${order.length}${omitted.isEmpty ? '' : ' (${omitted.length} older omitted by the size cap)'} · records: ${recs.length}');
    o.writeln('# format: a human summary first, then after the "---" line one JSON object per line (t = epoch ms, ev = event, run = run id; numbers are tokens/bytes/ms).');
    o.writeln('# a "run" = one user message and the whole tool loop that follows it.');
    o.writeln();
    for (final String run in order) {
      o.write(_runSummary(run, by[run]!, omitted.contains(run)));
    }
    o.writeln('---');
    for (final String run in order) {
      if (omitted.contains(run)) continue;
      for (final String l in lines[run]!) {
        o.writeln(l);
      }
    }
    return o.toString();
  }
}

// ---------------------------------------------------------------------
//  اختبار ذاتي (يُشغَّل من فحص المحاكي في الـ CI): تسجيل حقيقي عبر خادم وهمي، حجب الأسرار، مستويات التصدير، الأسقف.
// ---------------------------------------------------------------------
Future<void> runTraceSelfTest() async {
  int fails = 0;
  int total = 0;
  // ignore: avoid_print
  void out(String s) => print('LMPROBE|TRACE $s');
  void rec(String name, bool ok, String detail) {
    total++;
    if (!ok) fails++;
    final String d = detail.replaceAll('\n', ' ⏎ ');
    out('${ok ? 'OK  ' : 'FAIL'} $name${d.isEmpty ? '' : ' :: ${d.length > 240 ? d.substring(0, 240) : d}'}');
  }

  final _MockLlm mock = _MockLlm();
  final SettingsNotifier st = appContainer.read(settingsProvider.notifier);
  final int oldFileCap = RunTrace.fileCap;
  final int oldTotalCap = RunTrace.totalCap;
  try {
    await mock.start();
    st.set('traceOn', true);
    st.set('traceLevel', 'standard');
    st.set('tools', true);
    st.set('autoTitle', false);
    st.set('autoCompact', false);
    const String knownKey = 'trace-key-0123456789';
    const String secret = 'sk-TRACEsecret0123456789ABCDEFghijklmn';
    await appContainer.read(profilesProvider.notifier).upsert(
          ApiProfile(id: 'trace-mock', name: 'tracemock', kind: kAnthropic, baseUrl: 'http://127.0.0.1:${mock.port}', apiKey: knownKey, selectedModel: 'mock-model'),
          select: true,
        );

    // ---- 1) تشغيل حقيقي: أداة ثم رد نهائي
    mock.bodies.clear();
    mock.handler = (int n, String body) async {
      if (n == 1) return _MockReply(200, _sseOf(_anTool('tu1', 'current_time', '{"note":"$secret"}')));
      return _MockReply(200, _sseOf(_anText('TRACE-DONE')));
    };
    final String conv1 = newId();
    final ChatSession s1 = ChatSession(ConvMeta(id: conv1));
    await s1.send('what time? $secret $knownKey', <PendingAtt>[]).timeout(const Duration(seconds: 60));
    await RunTrace.flush(conv1);
    final List<Map<String, dynamic>> recs = await RunTrace.load(conv1);
    List<Map<String, dynamic>> evs(String e) => recs.where((Map<String, dynamic> r) => r['ev'] == e).toList();
    final List<Map<String, dynamic>> reqs = evs('request');
    final List<Map<String, dynamic>> resps = evs('response');
    final List<Map<String, dynamic>> tools = evs('tool');
    final List<Map<String, dynamic>> ends = evs('run_end');
    rec('records: start, 2 requests, 2 responses, 1 tool, end', evs('run_start').length == 1 && reqs.length == 2 && resps.length == 2 && tools.length == 1 && ends.length == 1,
        'start=${evs('run_start').length} req=${reqs.length} resp=${resps.length} tool=${tools.length} end=${ends.length}');
    rec('run_end: reason done, 2 responses', ends.isNotEmpty && ends.first['reason'] == 'done' && ends.first['reqs'] == 2, '${ends.isEmpty ? '' : ends.first}');
    rec('exact usage recorded', resps.length == 2 && resps[0]['in'] == 120 && resps[0]['out'] == 9 && resps[1]['out'] == 7 && resps[0]['exact'] == true, '${resps.isEmpty ? '' : resps.first}');
    rec('first request carries body + system, second only sizes', reqs.length == 2 && reqs[0]['body'] != null && reqs[0]['system'] != null && reqs[1]['body'] == null && ((reqs[1]['bytes'] as num?) ?? 0) > 0,
        'keys0=${reqs.isEmpty ? '' : reqs[0].keys.join(',')}');
    rec('tool record: name, args, result length, duration', tools.length == 1 && tools[0]['name'] == 'current_time' && ((tools[0]['resLen'] as num?) ?? 0) > 0 && tools[0]['ms'] is num && tools[0]['args'] is Map,
        '${tools.isEmpty ? '' : tools.first}');
    final File f1 = await RunTrace._file(conv1);
    final String raw1 = await f1.readAsString();
    rec('no secret reaches the disk (typed, tool args, saved key)', !raw1.contains(secret) && !raw1.contains(knownKey) && raw1.contains('[REDACTED'), 'len=${raw1.length}');
    final TraceInfo inf = await RunTrace.info(conv1);
    rec('info: one run', inf.runs == 1 && inf.records == recs.length && inf.bytes > 0, '${inf.runs}/${inf.records}/${inf.bytes}');

    // ---- 2) مستويات التصدير
    final String tNum = await RunTrace.build(conv1, 'My chat title', kTraceNumbers);
    final String tStd = await RunTrace.build(conv1, 'My chat title', kTraceStandard);
    final String tFull = await RunTrace.build(conv1, 'My chat title', kTraceFull);
    rec('export numbers: structure only, no content', tNum.contains('"ev":"tool"') && !tNum.contains('"args"') && !tNum.contains('"result"') && !tNum.contains('"body"') && !tNum.contains('"system"') && !tNum.contains('TRACE-DONE') && !tNum.contains('what time') && !tNum.contains('My chat title'),
        'len=${tNum.length}');
    rec('export standard: args/results/text, no body/system/thinking', tStd.contains('"args"') && tStd.contains('"result"') && tStd.contains('TRACE-DONE') && !tStd.contains('"body"') && !tStd.contains('"system"'), 'len=${tStd.length}');
    rec('export full: body + system included', tFull.contains('"body"') && tFull.contains('"system"') && tFull.contains('TRACE-DONE'), 'len=${tFull.length}');
    rec('every export level is redacted', !tNum.contains(secret) && !tStd.contains(secret) && !tFull.contains(secret) && !tFull.contains(knownKey), '');
    rec('summary header lists the run with usage', tStd.contains('# LMClient run trace') && tStd.contains('end: done') && tStd.contains('#1 →') && tStd.contains('#1 ←') && tStd.contains('tool current_time'), tStd.split('---').first.replaceAll('\n', ' ⏎ '));

    // ---- 3) أسطر تالفة لا تُسقط القراءة
    await f1.writeAsString('this is not json\n{"ev":"x"\n', mode: FileMode.append, flush: true);
    final List<Map<String, dynamic>> again = await RunTrace.load(conv1);
    rec('corrupt lines are skipped', again.length == recs.length, '${again.length} vs ${recs.length}');

    // ---- 4) طلب فاشل 400: يُسجَّل بجسم الطلب وسبب الفشل
    mock.bodies.clear();
    mock.handler = (int n, String body) async => const _MockReply(400, '{"error":{"message":"quota nonsense 12345"}}', sse: false);
    final String conv2 = newId();
    final ChatSession s2 = ChatSession(ConvMeta(id: conv2));
    await s2.send('hello', <PendingAtt>[]).timeout(const Duration(seconds: 60));
    await RunTrace.flush(conv2);
    final List<Map<String, dynamic>> r2 = await RunTrace.load(conv2);
    final List<Map<String, dynamic>> errs = r2.where((Map<String, dynamic> r) => r['ev'] == 'req_error').toList();
    final List<Map<String, dynamic>> end2 = r2.where((Map<String, dynamic> r) => r['ev'] == 'run_end').toList();
    rec('failed request: req_error with status, action fail and the request body', errs.isNotEmpty && errs.last['status'] == 400 && errs.last['action'] == 'fail' && errs.last['body'] != null, '${errs.isEmpty ? '' : errs.last.keys.join(',')}');
    rec('failed run ends with reason error', end2.isNotEmpty && end2.first['reason'] == 'error', '${end2.isEmpty ? '' : end2.first}');

    // ---- 5) سقف الملف الواحد: يُحذف الأقدم ويبقى الأحدث
    final String conv3 = newId();
    RunTrace.fileCap = 20000;
    for (int i = 0; i < 150; i++) {
      RunTrace.log(conv3, 'rr', 'tool', <String, dynamic>{'name': 'x', 'i': i, 'result': 'y' * 200});
    }
    await RunTrace.flush(conv3);
    await RunTrace.maintain(conv3);
    final File f3 = await RunTrace._file(conv3);
    final int size3 = await f3.length();
    final List<Map<String, dynamic>> r3 = await RunTrace.load(conv3);
    rec('per-conversation cap trims the oldest, keeps the newest', size3 <= 20000 && r3.isNotEmpty && r3.last['i'] == 149 && ((r3.first['i'] as num?) ?? 0) > 0, 'size=$size3 n=${r3.length} first=${r3.isEmpty ? '' : r3.first['i']}');
    RunTrace.fileCap = oldFileCap;

    // ---- 6) سقف المجموع: تُحذف أقدم المحادثات ولا تُحذف الحالية
    final List<String> cs = <String>[newId(), newId(), newId()];
    for (final String c in cs) {
      for (int i = 0; i < 60; i++) {
        RunTrace.log(c, 'rr', 'tool', <String, dynamic>{'name': 'x', 'i': i, 'result': 'z' * 100});
      }
      await RunTrace.flush(c);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    final int s1b = await (await RunTrace._file(cs[1])).length();
    final int s2b = await (await RunTrace._file(cs[2])).length();
    RunTrace.totalCap = s1b + s2b + 10;
    await RunTrace.maintain(cs[2]);
    final bool gone0 = !await (await RunTrace._file(cs[0])).exists();
    final bool keep1 = await (await RunTrace._file(cs[1])).exists();
    final bool keep2 = await (await RunTrace._file(cs[2])).exists();
    rec('total cap deletes the oldest conversation first, keeps the current one', gone0 && keep1 && keep2, 'gone0=$gone0 keep1=$keep1 keep2=$keep2');
    RunTrace.totalCap = oldTotalCap;

    // ---- 7) التعطيل من الإعدادات يوقف الكتابة
    st.set('traceOn', false);
    final String conv4 = newId();
    RunTrace.log(conv4, 'rr', 'tool', <String, dynamic>{'name': 'x'});
    await RunTrace.flush(conv4);
    final bool noFile = !await (await RunTrace._file(conv4)).exists();
    rec('traceOn=false writes nothing', noFile, '');
    st.set('traceOn', true);

    // ---- 8) الحذف
    await RunTrace.purge(cs[2]);
    rec('purge removes a conversation trace', !await (await RunTrace._file(cs[2])).exists(), '');
    final int cleared = await RunTrace.clearAll();
    rec('clearAll removes everything', cleared >= 1 && !await (await RunTrace._file(conv1)).exists(), 'cleared=$cleared');
  } catch (e) {
    rec('trace self-test exception', false, '$e');
  } finally {
    RunTrace.fileCap = oldFileCap;
    RunTrace.totalCap = oldTotalCap;
    st.set('traceOn', true);
    try {
      await mock.stop();
    } catch (_) {}
  }
  out('DONE fails=$fails total=$total');
}
