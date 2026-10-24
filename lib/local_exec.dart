part of 'main.dart';

// =====================================================================
//  التنفيذ المحلي: sh النظام على الهاتف نفسه (بدون SSH وبدون أي تطبيق آخر)
//  - /system/bin/sh (mksh) + أدوات toybox فقط. لا git ولا python ولا node في أندرويد العادي.
//  - يعمل بصلاحيات التطبيق نفسه (يستطيع قراءة بياناته الخاصة): الموافقة على الأوامر هي الحماية الوحيدة.
//  - أندرويد 10+ يمنع تنفيذ ملفات كتبها التطبيق في مجلده (W^X): لا يمكن "تنزيل حزمة أوامر" وتشغيلها؛ شاشة اختبار التنفيذ تقيس ذلك فعلياً.
// =====================================================================

const String kLocalWorkspaceId = 'local';

class LocalExec {
  static const String shPath = '/system/bin/sh';
  static const int _kRawCap = 2000000;
  static const int _kShowCap = 30000;
  static String? _home;

  static const String _template = r'''exec 2>&1
@CD@
@CMD@
__lm_rc=$?
printf '\n%s\n' "@M@END $__lm_rc $(pwd)"
''';

  /// مجلد HOME خاص بالتطبيق (للسكربتات والسجلات المؤقتة). لا يرمي أبداً.
  static Future<String> home() async {
    final String? c = _home;
    if (c != null) return c;
    String path = Directory.systemTemp.path;
    try {
      final Directory base = await getApplicationSupportDirectory();
      final Directory h = Directory('${base.path}/lmhome');
      if (!await h.exists()) await h.create(recursive: true);
      final Directory t = Directory('${h.path}/tmp');
      if (!await t.exists()) await t.create(recursive: true);
      path = h.path;
    } catch (_) {}
    _home = path;
    return path;
  }

  static Map<String, String> _env(String h) => <String, String>{
        'HOME': h,
        'TMPDIR': '$h/tmp',
        'LANG': 'C.UTF-8',
        'TERM': 'dumb',
      };

  // ---- process tree ------------------------------------------------------
  static List<int> _descendants(int root) {
    final Map<int, List<int>> kids = <int, List<int>>{};
    try {
      for (final FileSystemEntity e in Directory('/proc').listSync(followLinks: false)) {
        final String name = e.path.substring(e.path.lastIndexOf('/') + 1);
        final int? pid = int.tryParse(name);
        if (pid == null) continue;
        try {
          final String s = utf8.decode(File('/proc/$pid/stat').readAsBytesSync(), allowMalformed: true);
          final int i = s.lastIndexOf(')');
          if (i < 0) continue;
          final List<String> rest = s.substring(i + 1).trim().split(' ');
          if (rest.length < 2) continue;
          final int? pp = int.tryParse(rest[1]);
          if (pp == null) continue;
          (kids[pp] ??= <int>[]).add(pid);
        } catch (_) {}
      }
    } catch (_) {}
    final List<int> out = <int>[];
    void walk(int p, int depth) {
      if (depth > 64) return;
      final List<int> ks = kids[p] ?? const <int>[];
      for (final int c in ks) {
        walk(c, depth + 1);
      }
      out.add(p);
    }

    walk(root, 0);
    return out;
  }

  static bool _alive(int pid) {
    try {
      final String s = utf8.decode(File('/proc/$pid/stat').readAsBytesSync(), allowMalformed: true);
      final int i = s.lastIndexOf(')');
      if (i < 0) return false;
      final String st = s.substring(i + 1).trim();
      if (st.isEmpty) return false;
      return st[0] != 'Z' && st[0] != 'X';
    } catch (_) {
      return false;
    }
  }

  /// يوقف العملية وكل أبنائها (الأبناء أولاً): TERM ثم KILL بعد قليل.
  static Future<void> killTree(int pid) async {
    final Set<int> all = <int>{..._descendants(pid)};
    for (final int p in all) {
      try {
        Process.killPid(p, ProcessSignal.sigterm);
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    all.addAll(_descendants(pid));
    for (final int p in all) {
      try {
        Process.killPid(p, ProcessSignal.sigkill);
      } catch (_) {}
    }
  }

  /// يعيد Process عند النجاح أو الخطأ نفسه (Object) عند الفشل.
  static Future<Object> _start(String script, String h) async {
    try {
      return await Process.start(shPath, <String>['-c', script], workingDirectory: h, environment: _env(h));
    } catch (e) {
      return e;
    }
  }

  // ---- foreground command -----------------------------------------------
  static Future<ExecResult> run(String command, {required String cwd, required int timeoutMs, BashCancel? cancel}) async {
    final String marker = '__LM${newId().replaceAll('-', '').substring(0, 10)}__';
    final String script = _template.replaceAll('@CD@', SshExec._cdLine(cwd)).replaceAll('@M@', marker).replaceAll('@CMD@', command);
    final String h = await home();

    final Object started = await _start(script, h);
    if (started is! Process) {
      return ExecResult(output: 'تعذّر تشغيل $shPath على هذا الجهاز: $started', exitCode: null, lost: true);
    }
    final Process proc = started;
    try {
      await proc.stdin.close();
    } catch (_) {}

    final StringBuffer raw = StringBuffer();
    int rawLen = 0;
    bool capped = false;
    String tail = '';
    void feed(String chunk) {
      if (rawLen < _kRawCap) {
        raw.write(chunk);
        rawLen += chunk.length;
      } else {
        capped = true;
      }
      final String t = tail + chunk;
      tail = t.length > 800 ? t.substring(t.length - 800) : t;
    }

    final Completer<void> outDone = Completer<void>();
    final Completer<void> errDone = Completer<void>();
    final StreamSubscription<String> s1 = const Utf8Decoder(allowMalformed: true).bind(proc.stdout).listen(
      feed,
      onError: (Object e) {
        if (!outDone.isCompleted) outDone.complete();
      },
      onDone: () {
        if (!outDone.isCompleted) outDone.complete();
      },
      cancelOnError: false,
    );
    final StreamSubscription<String> s2 = const Utf8Decoder(allowMalformed: true).bind(proc.stderr).listen(
      feed,
      onError: (Object e) {
        if (!errDone.isCompleted) errDone.complete();
      },
      onDone: () {
        if (!errDone.isCompleted) errDone.complete();
      },
      cancelOnError: false,
    );

    bool timedOut = false;
    Future<void> killNow() async {
      await killTree(proc.pid);
    }

    final Timer timer = Timer(Duration(milliseconds: timeoutMs), () {
      timedOut = true;
      killNow();
    });
    if (cancel != null) {
      cancel.onKill = killNow;
      if (cancel.cancelled) killNow();
    }

    int exit = -1;
    try {
      exit = await proc.exitCode;
    } catch (_) {}
    timer.cancel();
    // قد يبقى ابن في الخلفية ماسكاً الأنبوب: ننتظر قليلاً ثم نكمل.
    await Future.wait(<Future<void>>[outDone.future, errDone.future]).timeout(const Duration(milliseconds: 1500), onTimeout: () => <void>[]);
    try {
      await s1.cancel();
      await s2.cancel();
    } catch (_) {}

    String text = raw.toString();
    String? newCwd;
    int code = exit;
    final Match? em = RegExp(RegExp.escape(marker) + r'END (-?\d+) ([^\n]*)').firstMatch(tail);
    if (em != null) {
      code = int.tryParse(em.group(1) ?? '') ?? exit;
      final String c = (em.group(2) ?? '').trim();
      if (c.isNotEmpty) newCwd = c;
    }
    text = text.replaceAll(RegExp(r'\n?' + RegExp.escape(marker) + r'END [^\n]*\n?'), '');
    text = text.replaceFirst(RegExp(r'\n+$'), '');

    final bool trunc = capped || text.length > _kShowCap;
    return ExecResult(
      output: SshExec.capOutput(text, _kShowCap),
      exitCode: code,
      timedOut: timedOut,
      cancelled: cancel != null && cancel.cancelled,
      lost: false,
      cwd: newCwd,
      truncated: trunc,
    );
  }

  /// سكربت قصير (إدارة المهام الخلفية، الاختبار…). يعيد المخرجات كاملة.
  static Future<String> script(String body, {int timeoutMs = 20000}) async {
    final String h = await home();
    final Object started = await _start('exec 2>&1\n' + body, h);
    if (started is! Process) return 'تعذّر تشغيل $shPath: $started';
    final Process p = started;
    try {
      await p.stdin.close();
    } catch (_) {}
    final StringBuffer b = StringBuffer();
    final Future<void> f1 = const Utf8Decoder(allowMalformed: true).bind(p.stdout).forEach((String s) {
      b.write(s);
    });
    final Future<void> f2 = const Utf8Decoder(allowMalformed: true).bind(p.stderr).forEach((String s) {
      b.write(s);
    });
    final Timer t = Timer(Duration(milliseconds: timeoutMs), () {
      killTree(p.pid);
    });
    try {
      await p.exitCode;
      await Future.wait(<Future<void>>[f1, f2]).timeout(const Duration(milliseconds: 1500), onTimeout: () => <void>[]);
    } catch (_) {
    } finally {
      t.cancel();
    }
    return b.toString();
  }

  // ---- background jobs ---------------------------------------------------
  static Future<BashJob> startJob(WorkspaceConfig w, String command, String cwd) async {
    final String id = 'j${newId().replaceAll('-', '').substring(0, 6)}';
    final String h = await home();
    final Directory jd = Directory('$h/.lmclient/jobs');
    if (!await jd.exists()) await jd.create(recursive: true);
    final String inner = SshExec._cdLine(cwd) + '\n' + command + '\n' + r'__lm_rc=$?' + '\necho\n' + r'echo "__LM_EXIT__$__lm_rc"' + '\n';
    await File('${jd.path}/$id.sh').writeAsString(inner);
    final String body = r'''J="$HOME/.lmclient/jobs/@ID@"
if command -v nohup >/dev/null 2>&1; then
  nohup sh "$J.sh" > "$J.log" 2>&1 < /dev/null &
else
  sh "$J.sh" > "$J.log" 2>&1 < /dev/null &
fi
echo $! > "$J.pid"
echo "PID $!"
'''
        .replaceAll('@ID@', id);
    final String out = await script(body);
    final Match? m = RegExp(r'PID (\d+)').firstMatch(out);
    if (m == null) throw ToolError('Could not start the background job: ${SshExec.capOutput(out.trim(), 400)}');
    final BashJob job = BashJob(id: id, wsId: w.id, command: command, pid: m.group(1) ?? '');
    BashRuntime.jobs[id] = job;
    return job;
  }

  /// نفس صيغة SshExec.readJob: "__STATE__ running|done SIZE\n<الجديد>" أو "__NOJOB__".
  static Future<String> readJob(BashJob job) async {
    final String h = await home();
    final File log = File('$h/.lmclient/jobs/${job.id}.log');
    if (!await log.exists()) return '__NOJOB__';
    final int size = await log.length();
    bool running = false;
    try {
      final String ps = (await File('$h/.lmclient/jobs/${job.id}.pid').readAsString()).trim();
      final int? pid = int.tryParse(ps);
      if (pid != null) running = _alive(pid);
    } catch (_) {}
    String body = '';
    if (size > job.offset) {
      final RandomAccessFile raf = await log.open();
      try {
        await raf.setPosition(job.offset);
        final Uint8List bytes = await raf.read(size - job.offset);
        body = utf8.decode(bytes, allowMalformed: true);
      } finally {
        await raf.close();
      }
    }
    return '__STATE__ ${running ? 'running' : 'done'} $size\n$body';
  }

  static Future<bool> killJob(BashJob job) async {
    final String h = await home();
    try {
      final String ps = (await File('$h/.lmclient/jobs/${job.id}.pid').readAsString()).trim();
      final int? pid = int.tryParse(ps);
      if (pid == null) return false;
      await killTree(pid);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ملخص سريع للأدوات المتاحة (يُستعمل في اختبار الاتصال).
  static Future<String> probeText() {
    return script(r'''echo "user: $(id -un 2>/dev/null || whoami)"
echo "dir: $(pwd)"
for t in sh toybox git python3 node; do
  if command -v $t >/dev/null 2>&1; then echo "$t: yes"; else echo "$t: no"; fi
done
''', timeoutMs: 15000);
  }

  /// هل يلمس الأمر مجلدات التطبيق الخاصة (مفاتيح API وبياناته)؟ تنبيه للمستخدم وليس حدّاً أمنياً.
  static final RegExp _privRe = RegExp('(^|[\\s\'"=:(])/data/(data|user|user_de)/');
  static bool touchesPrivate(String cmd) {
    if (_privRe.hasMatch(cmd)) return true;
    for (final String d in PathGuard._denied) {
      if (d.isNotEmpty && cmd.contains(d)) return true;
    }
    return false;
  }
}
