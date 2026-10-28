part of 'main.dart';

// =====================================================================
//  شاشة "اختبار التنفيذ": تقيس على الجهاز نفسه ما يستطيع التطبيق تشغيله فعلاً
//  (بدل التخمين): هل sh يعمل، أي أدوات موجودة، هل يُسمح بتنفيذ ملفات من مجلد التطبيق (W^X)،
//  هل المهلة والإيقاف والمهام الخلفية تعمل. وفيها طرفية سطر أوامر بسيطة للتجربة.
// =====================================================================

class _R {
  final int state; // 1 نجاح، 2 تنبيه/قيد معروف، 3 فشل
  final String detail;
  const _R(this.state, this.detail);
}

class _Check {
  final String title;
  int state = 0; // 0 لم يبدأ، 1 نجاح، 2 تنبيه، 3 فشل، 4 قيد التنفيذ
  String detail = '';
  _Check(this.title);
}

class ExecProbeScreen extends StatefulWidget {
  /// autoRun: يشغّل كل الفحوص فور الفتح ويطبع التقرير في logcat بالبادئة LMPROBE| (يستعمله CI على المحاكي).
  final bool autoRun;

  /// إعداد اختبار SSH الذاتي (يمرّره CI عبر مسار البدء): host=127.0.0.1 عبر adb reverse.
  final Map<String, dynamic>? sshCfg;

  /// فرع المستودع الذي يُجرَّب عليه استيراد المهارات من GitHub (يمرّره CI؛ فارغ = لا اختبار شبكة).
  final String ghBranch;
  const ExecProbeScreen({super.key, this.autoRun = false, this.sshCfg, this.ghBranch = ''});
  @override
  State<ExecProbeScreen> createState() => _ExecProbeScreenState();
}

class _ExecProbeScreenState extends State<ExecProbeScreen> {
  static const List<String> _kTools = <String>[
    'sh', 'toybox', 'ls', 'cat', 'cp', 'mv', 'rm', 'mkdir', 'touch', 'chmod', 'ln', 'head', 'tail', 'wc', 'sort', 'uniq', 'cut', 'tr', 'sed', 'awk', 'grep', 'find', 'xargs', 'tar', 'gzip', 'unzip', 'zip', 'diff', 'patch', 'du', 'df', 'stat', 'date', 'env', 'printf', 'base64', 'sha256sum', 'md5sum', 'nohup', 'kill', 'ps', 'sleep', 'curl', 'wget', 'ssh', 'git', 'python3', 'python', 'node', 'npm', 'make', 'gcc', 'busybox',
  ];

  final List<_Check> _checks = <_Check>[
    _Check('تشغيل sh'),
    _Check('الأدوات المتاحة'),
    _Check('الملفات والتخزين'),
    _Check('تنفيذ ملفات من مجلد التطبيق (W^X)'),
    _Check('المهلة والإيقاف'),
    _Check('المهام الخلفية'),
    _Check('المجلد الحالي ورمز الخروج'),
  ];
  bool _running = false;
  bool _done = false;

  final TextEditingController _cmd = TextEditingController();
  final ScrollController _logScroll = ScrollController();
  final StringBuffer _log = StringBuffer();
  String _cwd = PhoneStorage.root;
  bool _busy = false;
  BashCancel? _cancel;

  @override
  void initState() {
    super.initState();
    if (widget.autoRun) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoRun());
    }
  }

  Future<void> _autoRun() async {
    try {
      await _runAll();
      final StringBuffer out = StringBuffer();
      out.writeln('LMClient autoprobe · v$kAppVersion');
      out.writeln('os: ${Platform.operatingSystemVersion}');
      out.writeln(_report());
      for (final String line in out.toString().split('\n')) {
        // ignore: avoid_print
        print('LMPROBE|$line');
      }
      await runSecretsSelfTest();
      await runEngineSelfTest();
      await runAgentE2E();
      await runPlanningSelfTest();
      await runSkillsSelfTest(ghBranch: widget.ghBranch);
      final Map<String, dynamic>? cfg = widget.sshCfg;
      if (cfg != null) await runSshSelfTest(cfg);
    } catch (e) {
      // ignore: avoid_print
      print('LMPROBE|autoprobe exception: $e');
    }
    // ignore: avoid_print
    print('LMPROBE|DONE');
  }

  @override
  void dispose() {
    _cmd.dispose();
    _logScroll.dispose();
    final BashCancel? c = _cancel;
    if (c != null) c.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- tests
  Future<_R> _tShell() async {
    final ExecResult r = await LocalExec.run(
        'echo ok; id -un 2>/dev/null; uname -m; getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.product.cpu.abi; getprop ro.product.model',
        cwd: PhoneStorage.root,
        timeoutMs: 15000);
    final String o = r.output.trim();
    if (r.lost) return _R(3, o);
    if (!o.startsWith('ok')) return _R(3, 'مخرجات غير متوقعة (exit ${r.exitCode}):\n$o');
    final List<String> ls = o.split('\n').map((String e) => e.trim()).toList();
    if (ls.length >= 7) {
      return _R(1, 'المستخدم: ${ls[1]}\nالمعمارية: ${ls[2]} · ABI: ${ls[5]}\nأندرويد ${ls[3]} (SDK ${ls[4]}) · ${ls[6]}');
    }
    return _R(1, ls.skip(1).join(' · '));
  }

  Future<_R> _tTools() async {
    final String body = r'''for t in @T@; do if command -v $t >/dev/null 2>&1; then echo "$t=1"; else echo "$t=0"; fi; done
echo "TBV=$(toybox --version 2>&1 | head -n 1)"
echo "TBN=$(toybox 2>/dev/null | wc -w)"
'''
        .replaceAll('@T@', _kTools.join(' '));
    final ExecResult r = await LocalExec.run(body, cwd: PhoneStorage.root, timeoutMs: 30000);
    final List<String> have = <String>[];
    final List<String> miss = <String>[];
    String tbv = '';
    String tbn = '';
    for (final String line in r.output.split('\n')) {
      final String l = line.trim();
      if (l.startsWith('TBV=')) {
        tbv = l.substring(4);
      } else if (l.startsWith('TBN=')) {
        tbn = l.substring(4).trim();
      } else if (l.endsWith('=1')) {
        have.add(l.substring(0, l.length - 2));
      } else if (l.endsWith('=0')) {
        miss.add(l.substring(0, l.length - 2));
      }
    }
    if (have.isEmpty) return _R(3, 'لم يُعثر على أي أداة:\n${r.output}');
    final StringBuffer d = StringBuffer();
    d.writeln('متوفر (${have.length}): ${have.join(' ')}');
    d.writeln('غير متوفر (${miss.length}): ${miss.join(' ')}');
    if (tbv.isNotEmpty) d.writeln('toybox: $tbv${tbn.isEmpty ? '' : ' · $tbn أمراً'}');
    final bool dev = have.contains('git') || have.contains('python3') || have.contains('node');
    const List<String> core = <String>['ls', 'cat', 'grep', 'sed', 'find'];
    for (final String c in core) {
      if (!have.contains(c)) return _R(3, d.toString().trimRight());
    }
    if (!dev) d.writeln('git/python/node غير موجودة، كما هو متوقع في أندرويد العادي.');
    return _R(dev ? 1 : 2, d.toString().trimRight());
  }

  Future<_R> _tFiles() async {
    final ExecResult r = await LocalExec.run(
        r'''echo hi > "$HOME/probe.txt" && cat "$HOME/probe.txt" && echo HOME_OK
echo "--- /storage/emulated/0"
ls /storage/emulated/0 2>&1 | head -n 6
echo "--- write test"
echo x > /storage/emulated/0/.lm_probe 2>&1 && echo SHARED_WRITE_OK && rm -f /storage/emulated/0/.lm_probe
''',
        cwd: PhoneStorage.root,
        timeoutMs: 20000);
    final String o = r.output;
    final bool homeOk = o.contains('HOME_OK');
    final bool listDenied = RegExp('denied|Cannot open|No such|not permitted', caseSensitive: false).hasMatch(o.split('--- write test').first);
    final bool writeOk = o.contains('SHARED_WRITE_OK');
    final String summary = 'مجلد HOME الخاص: ${homeOk ? 'يعمل' : 'لا يعمل'}\nقراءة التخزين المشترك: ${listDenied ? 'مرفوضة' : 'تعمل'}\nكتابة التخزين المشترك: ${writeOk ? 'تعمل' : 'لا تعمل'}';
    if (!homeOk) return _R(3, '$summary\n\n$o');
    if (listDenied || !writeOk) return _R(2, '$summary\nامنح التطبيق "الوصول لكل الملفات" من إعدادات أندرويد.\n\n$o');
    return _R(1, summary);
  }

  Future<_R> _tExec() async {
    final String h = await LocalExec.home();
    final StringBuffer d = StringBuffer();
    bool direct = false;
    bool elf = false;
    bool viaSh = false;
    final File script = File('$h/probe_exec.sh');
    final File copy = File('$h/sh_copy');
    try {
      await script.writeAsString('#!/system/bin/sh\necho SCRIPT_EXEC_OK\n');
      try {
        await Process.run('/system/bin/chmod', <String>['755', script.path]);
      } catch (_) {}
      try {
        final ProcessResult a = await Process.run('/system/bin/sh', <String>[script.path]);
        viaSh = '${a.stdout}'.contains('SCRIPT_EXEC_OK');
      } catch (_) {}
      d.writeln('تشغيل السكربت عبر sh (sh ملف): ${viaSh ? 'يعمل' : 'لا يعمل'}');
      try {
        final ProcessResult b = await Process.run(script.path, <String>[]);
        direct = '${b.stdout}'.contains('SCRIPT_EXEC_OK');
        d.writeln('تنفيذ السكربت مباشرة (shebang): ${direct ? 'مسموح' : 'مرفوض (exit ${b.exitCode})'}');
      } catch (e) {
        d.writeln('تنفيذ السكربت مباشرة (shebang): مرفوض ($e)');
      }
      try {
        await File('/system/bin/sh').copy(copy.path);
        try {
          await Process.run('/system/bin/chmod', <String>['755', copy.path]);
        } catch (_) {}
        final ProcessResult c = await Process.run(copy.path, <String>['-c', 'echo ELF_EXEC_OK']);
        elf = '${c.stdout}'.contains('ELF_EXEC_OK');
        d.writeln('تنفيذ ملف ثنائي منسوخ إلى مجلد التطبيق: ${elf ? 'مسموح' : 'مرفوض (exit ${c.exitCode})'}');
      } catch (e) {
        d.writeln('تنفيذ ملف ثنائي منسوخ إلى مجلد التطبيق: مرفوض ($e)');
      }
    } catch (e) {
      d.writeln('تعذّر تجهيز الاختبار: $e');
    }
    try {
      if (await script.exists()) await script.delete();
      if (await copy.exists()) await copy.delete();
    } catch (_) {}
    if (elf) {
      d.writeln('\nالنتيجة: هذا الجهاز/البناء يسمح بتنفيذ ملفات ثنائية من مجلد التطبيق، فتنزيل حزمة أدوات (git/python…) ممكن من حيث المبدأ.');
      return _R(1, d.toString().trimRight());
    }
    d.writeln('\nالنتيجة: تنفيذ الملفات الثنائية من مجلد التطبيق ممنوع (قيد W^X في أندرويد 10+ للتطبيقات التي تستهدف SDK 29 فأعلى). لا يمكن تنزيل git/python/node وتشغيلها؛ البدائل: sh+toybox النظام، أو ملفات تنفيذية مضمّنة داخل الـAPK، أو SSH.');
    return _R(2, d.toString().trimRight());
  }

  Future<_R> _tTimeout() async {
    final Stopwatch sw = Stopwatch()..start();
    final ExecResult r = await LocalExec.run('sleep 30', cwd: PhoneStorage.root, timeoutMs: 1500);
    sw.stop();
    final int ms = sw.elapsedMilliseconds;
    if (r.timedOut && ms < 8000) return _R(1, 'أُوقف أمر sleep 30 بعد ${(ms / 1000).toStringAsFixed(1)} ثانية (المهلة 1.5).');
    return _R(3, 'لم يُوقف الأمر كما يجب: timedOut=${r.timedOut} بعد $ms مللي ثانية.\n${r.output}');
  }

  Future<_R> _tJobs() async {
    final BashJob job = await LocalExec.startJob(WorkspaceConfig.local(), 'echo started; sleep 1; echo bg_done', PhoneStorage.root);
    await Future<void>.delayed(const Duration(milliseconds: 2800));
    final String out = await LocalExec.readJob(job);
    BashRuntime.jobs.remove(job.id);
    final bool ok = out.contains('bg_done') && out.contains('__STATE__ done');
    if (ok) return _R(1, 'المهمة ${job.id} اكتملت وقُرئ ناتجها.');
    return _R(3, 'ناتج غير متوقع:\n${SshExec.capOutput(out, 600)}');
  }

  Future<_R> _tCwd() async {
    final ExecResult r = await LocalExec.run('cd /storage/emulated/0/Download 2>/dev/null || cd /storage/emulated/0; pwd; false', cwd: PhoneStorage.root, timeoutMs: 10000);
    final String? c = r.cwd;
    final bool ok = r.exitCode == 1 && c != null && c.startsWith('/storage/emulated/0');
    if (ok) return _R(1, 'exit=1 ✓ · cwd=$c ✓');
    return _R(3, 'exit=${r.exitCode} · cwd=$c\n${r.output}');
  }

  Future<void> _runAll() async {
    if (_running) return;
    setState(() {
      _running = true;
      _done = false;
      for (final _Check c in _checks) {
        c.state = 0;
        c.detail = '';
      }
    });
    final List<Future<_R> Function()> tests = <Future<_R> Function()>[_tShell, _tTools, _tFiles, _tExec, _tTimeout, _tJobs, _tCwd];
    for (int i = 0; i < tests.length; i++) {
      if (!mounted) return;
      setState(() => _checks[i].state = 4);
      _R res;
      try {
        res = await tests[i]().timeout(const Duration(seconds: 60));
      } catch (e) {
        res = _R(3, 'استثناء: $e');
      }
      if (!mounted) return;
      setState(() {
        _checks[i].state = res.state;
        _checks[i].detail = res.detail;
      });
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _done = true;
    });
  }

  String _report() {
    final StringBuffer b = StringBuffer();
    b.writeln('LMClient · اختبار التنفيذ · v$kAppVersion');
    for (final _Check c in _checks) {
      final String tag = c.state == 1 ? 'OK' : (c.state == 2 ? 'NOTE' : (c.state == 3 ? 'FAIL' : '--'));
      b.writeln('\n[$tag] ${c.title}');
      if (c.detail.isNotEmpty) b.writeln(c.detail);
    }
    return b.toString().trimRight();
  }

  // ------------------------------------------------------------- terminal
  void _append(String s) {
    _log.writeln(s);
    if (_log.length > 60000) {
      final String t = _log.toString();
      _log.clear();
      _log.write(t.substring(t.length - 40000));
    }
  }

  Future<void> _exec() async {
    final String cmd = _cmd.text.trim();
    if (cmd.isEmpty || _busy) return;
    _cmd.clear();
    final BashCancel cancel = BashCancel();
    setState(() {
      _busy = true;
      _cancel = cancel;
      _append('\$ $cmd');
    });
    ExecResult r;
    try {
      r = await LocalExec.run(cmd, cwd: _cwd, timeoutMs: 60000, cancel: cancel);
    } catch (e) {
      r = ExecResult(output: 'خطأ: $e', exitCode: null, lost: true);
    }
    if (!mounted) return;
    final String? nc = r.cwd;
    setState(() {
      if (nc != null && nc.isNotEmpty) _cwd = nc;
      if (r.output.isNotEmpty) _append(r.output);
      if (r.timedOut) {
        _append('[انتهت المهلة (60 ثانية) وأُوقف الأمر]');
      } else if (r.cancelled) {
        _append('[أوقفته أنت]');
      } else if (r.exitCode != null && r.exitCode != 0) {
        _append('[exit ${r.exitCode}]');
      }
      _busy = false;
      _cancel = null;
    });
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  // ------------------------------------------------------------------ UI
  Widget _icon(Pal p, int state) {
    switch (state) {
      case 1:
        return Icon(Icons.check_circle, color: p.success, size: 22);
      case 2:
        return Icon(Icons.info_outline, color: p.accent, size: 22);
      case 3:
        return Icon(Icons.cancel, color: p.danger, size: 22);
      case 4:
        return SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: p.accent));
      default:
        return Icon(Icons.radio_button_unchecked, color: p.muted, size: 22);
    }
  }

  Widget _checkCard(Pal p, _Check c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.state == 3 ? p.danger : p.border)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Padding(padding: const EdgeInsets.only(top: 1), child: _icon(p, c.state)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(c.title, style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w600)),
            if (c.detail.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              SelectableText(c.detail, style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.55)),
            ],
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    final String logText = _log.toString();
    return Scaffold(
      appBar: AppBar(title: const Text('اختبار التنفيذ')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 30),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(12)),
            child: Text(
              'يقيس ما يستطيع هذا التطبيق تشغيله فعلاً على جهازك، بدل التخمين. الأوامر تعمل بصلاحيات التطبيق نفسه (sh النظام)، وتكتب ملفات صغيرة مؤقتة في مجلد التطبيق وتحذفها.',
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: _running ? null : _runAll,
                icon: const Icon(Icons.play_arrow),
                label: Text(_done ? 'أعد الفحص' : 'ابدأ الفحص'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _done
                  ? () async {
                      await Clipboard.setData(ClipboardData(text: _report()));
                      toast('تم نسخ التقرير');
                    }
                  : null,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('نسخ التقرير'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ]),
          const SizedBox(height: 12),
          ..._checks.map((_Check c) => _checkCard(p, c)),
          const SectionLabel('طرفية بسيطة'),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('اكتب أمراً وسيُنفَّذ مباشرة (بدون موافقة لأنك أنت من يكتبه). سطر أوامر فقط: لا برامج تفاعلية كالمحررات.', style: TextStyle(color: p.muted, fontSize: 12, height: 1.5)),
          ),
          Container(
            height: 240,
            decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SingleChildScrollView(
                controller: _logScroll,
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    logText.isEmpty ? '# $_cwd' : logText,
                    style: TextStyle(color: logText.isEmpty ? p.muted : p.codeText, fontSize: 12.5, height: 1.45, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _cmd,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (String _) => _exec(),
                  style: TextStyle(color: p.text, fontSize: 14, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: '\$ ls -la',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (_busy)
                IconButton.filledTonal(
                  onPressed: () {
                    final BashCancel? c = _cancel;
                    if (c != null) c.cancel();
                  },
                  icon: const Icon(Icons.stop),
                  tooltip: 'إيقاف',
                )
              else
                IconButton.filled(onPressed: _exec, icon: const Icon(Icons.send, size: 18), tooltip: 'تنفيذ'),
              IconButton(
                onPressed: () => setState(() {
                  _log.clear();
                }),
                icon: Icon(Icons.delete_outline, color: p.muted),
                tooltip: 'مسح',
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// تطبيق مصغّر يفتح شاشة الاختبار مباشرة (مسار البدء `/probe` من adb). لا يمس بيانات المستخدم.
class AutoProbeApp extends StatelessWidget {
  /// المسار كما وصل من adb: `/probe` أو `/probe?ssh=<base64url(json)>`.
  final String route;
  const AutoProbeApp({super.key, this.route = '/probe'});

  Map<String, dynamic>? _sshCfg() {
    try {
      final String? b = Uri.parse(route).queryParameters['ssh'];
      if (b == null || b.isEmpty) return null;
      return asMap(jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(b)))));
    } catch (e) {
      // ignore: avoid_print
      print('LMPROBE|bad ssh config in route: $e');
      return null;
    }
  }

  String _ghBranch() {
    try {
      return Uri.parse(route).queryParameters['gh'] ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      theme: buildTheme(Brightness.dark),
      home: ExecProbeScreen(autoRun: true, sshCfg: _sshCfg(), ghBranch: _ghBranch()),
    );
  }
}

// ---------------------------------------------------------------------
//  اختبار SSH ذاتي (CI فقط): يمرّ على نفس دوال الأدوات التي يستعملها النموذج، على sshd حقيقي.
//  أهم ما يثبته: الملف الذي تكتبه write_file هو الذي يراه bash على السيرفر.
// ---------------------------------------------------------------------
Future<void> runSshSelfTest(Map<String, dynamic> cfg) async {
  int fails = 0;
  int total = 0;
  // ignore: avoid_print
  void out(String s) => print('LMPROBE|SSH $s');
  void rec(String name, bool ok, String detail) {
    total++;
    if (!ok) fails++;
    final String d = detail.replaceAll('\n', ' ⏎ ');
    out('${ok ? 'OK  ' : 'FAIL'} $name${d.isEmpty ? '' : ' :: ${d.length > 260 ? d.substring(0, 260) : d}'}');
  }

  final String dir = asStr(cfg['dir'], '/tmp/lmci');
  final WorkspaceConfig w = WorkspaceConfig(
    id: 'ci-ssh',
    name: 'ci-server',
    host: '127.0.0.1',
    port: toInt(cfg['port']) ?? 2222,
    user: asStr(cfg['user']),
    keyPem: asStr(cfg['key']),
    startDir: dir,
  );
  try {
    await appContainer.read(workspacesProvider.notifier).upsert(w);
    await appContainer.read(selectedWorkspaceProvider.notifier).choose(w.id);
    appContainer.read(settingsProvider.notifier).set('confirm', false);
    appContainer.read(settingsProvider.notifier).set('bashApproval', 'auto');
  } catch (e) {
    rec('setup', false, '$e');
    out('DONE fails=$fails total=$total');
    return;
  }
  final AppSettings s = appContainer.read(settingsProvider);
  const Agent ag = Agent(id: 'ci', name: 'ci', canRead: true, canWrite: true, canExecute: true, canShell: true);
  const String cv = 'ci-conv';

  Future<String> step(String name, Future<ToolOutcome> Function() f, bool Function(String t) check, {bool expectError = false}) async {
    String text = '';
    try {
      final ToolOutcome o = await f().timeout(const Duration(seconds: 60));
      text = o.text;
      if (o.error && !expectError) {
        rec(name, false, 'tool error: $text');
        return text;
      }
    } catch (e) {
      text = '$e';
      if (!expectError) {
        rec(name, false, 'exception: $text');
        return text;
      }
    }
    rec(name, check(text), text);
    return text;
  }

  Future<ToolOutcome> bash(String cmd, {bool bg = false, int? timeoutMs}) =>
      _toolBash(<String, dynamic>{'command': cmd, 'description': 'ci', 'run_in_background': bg, if (timeoutMs != null) 'timeout_ms': timeoutMs}, s, cv);

  await step('bash echo/pwd/id', () => bash('echo hello-ssh; pwd; id -un'), (String t) => t.contains('hello-ssh') && t.contains(dir));
  await step('write_file new (relative path)', () => _toolWriteFile(<String, dynamic>{'path': 'proj/hello.txt', 'content': 'line1\nline2\nline3\n'}, ag, s, cv), (String t) => t.contains('Wrote'));
  await step('bash sees the file write_file wrote', () => bash('cat proj/hello.txt'), (String t) => t.contains('line2'));
  await step('read_file', () => _toolReadFile(<String, dynamic>{'path': 'proj/hello.txt'}, ag, s, cv), (String t) => t.contains('2\tline2'));
  await step('edit_file', () => _toolEditFile(<String, dynamic>{'path': 'proj/hello.txt', 'old_string': 'line2', 'new_string': 'LINE-TWO'}, ag, s, cv), (String t) => t.contains('Edited'));
  await step('bash sees the edit', () => bash('cat proj/hello.txt'), (String t) => t.contains('LINE-TWO') && !t.contains('line2'));
  await step('list_directory', () => _toolListDir(<String, dynamic>{'path': 'proj'}, ag, cv), (String t) => t.contains('f hello.txt'));
  await step('search_files pattern+glob', () => _toolSearchFiles(<String, dynamic>{'path': '.', 'pattern': 'LINE-TWO', 'glob': '*.txt'}, ag, s, cv), (String t) => t.contains('proj/hello.txt:2'));
  await step('search_files glob only', () => _toolSearchFiles(<String, dynamic>{'path': '.', 'glob': '*.txt'}, ag, s, cv), (String t) => t.contains('proj/hello.txt'));
  await step('outline_file', () => _toolOutline(<String, dynamic>{'path': 'proj/hello.txt'}, ag, s, cv), (String t) => t.contains('3 lines'));
  await bash("printf 'x\\nx\\nx\\n' > proj/other.txt");
  await step('write_file overwrite guard (unread file)', () => _toolWriteFile(<String, dynamic>{'path': 'proj/other.txt', 'content': 'y'}, ag, s, cv), (String t) => t.contains('not read all'), expectError: true);
  await step('write_file append', () => _toolWriteFile(<String, dynamic>{'path': 'proj/hello.txt', 'content': 'tail-line\n', 'append': true}, ag, s, cv), (String t) => t.contains('Appended'));
  await step('bash sees the append', () => bash('tail -n 1 proj/hello.txt'), (String t) => t.contains('tail-line'));
  await step('write_file creates parent dirs', () => _toolWriteFile(<String, dynamic>{'path': 'deep/a/b/c.txt', 'content': 'deep'}, ag, s, cv), (String t) => t.contains('Wrote'));
  await step('bash sees deep file', () => bash('test -f deep/a/b/c.txt && echo found-deep'), (String t) => t.contains('found-deep'));
  await step('blocked key path', () => _toolReadFile(<String, dynamic>{'path': '~/.ssh/id_ed25519'}, ag, s, cv), (String t) => t.contains('blocked'), expectError: true);
  await step('read_file on missing file', () => _toolReadFile(<String, dynamic>{'path': 'nope/missing.txt'}, ag, s, cv), (String t) => t.contains('not found'), expectError: true);
  await step('timeout kills the command', () => bash('sleep 30', timeoutMs: 1500), (String t) => t.contains('timed out'), expectError: true);
  await step('non-zero exit code reported', () => bash('exit 3'), (String t) => t.contains('exit code: 3'), expectError: true);
  await step('cd persists across calls', () async {
    await bash('cd proj');
    return bash('pwd');
  }, (String t) => t.trim().endsWith('/proj'));
  await step('relative path follows the new cwd', () => _toolReadFile(<String, dynamic>{'path': 'hello.txt'}, ag, s, cv), (String t) => t.contains('LINE-TWO'));

  // مهمة خلفية: تبدأ، ثم نقرأ ناتجها حتى تنتهي.
  String jobId = '';
  final String started = await step('background job starts', () => bash('echo job-start; sleep 2; echo job-end', bg: true), (String t) => RegExp(r'job (j\w+)').hasMatch(t));
  final Match? jm = RegExp(r'job (j\w+)').firstMatch(started);
  if (jm != null) jobId = jm.group(1) ?? '';
  if (jobId.isNotEmpty) {
    // bash_output يعيد الجديد فقط في كل نداء، فنجمع النواتج.
    final StringBuffer acc = StringBuffer();
    for (int i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        acc.writeln((await _toolBashOutput(<String, dynamic>{'id': jobId})).text);
      } catch (e) {
        acc.writeln('$e');
      }
      if (acc.toString().contains('job-end')) break;
    }
    final String last = acc.toString();
    rec('background job output (incremental)', last.contains('job-start') && last.contains('job-end'), last);
  }

  // Skills على بيئة SSH: اكتشاف .claude/skills (مجلد العمل الحالي + مجلد البدء) وتحميلها عبر use_skill.
  await step(
    'create workspace skills',
    () => bash(
        "mkdir -p .claude/skills/ci-proj && printf '%s\\n' '---' 'name: ci-proj' 'description: project skill from cwd' '---' 'PROJ-BODY' > .claude/skills/ci-proj/SKILL.md && "
        "mkdir -p $dir/.claude/skills/ci-start && printf '%s\\n' '---' 'name: ci-start' 'description: skill from start dir' '---' 'START-BODY' > $dir/.claude/skills/ci-start/SKILL.md && "
        "echo 'NOTE-OK' > $dir/.claude/skills/ci-start/notes.md && echo skills-made"),
    (String t) => t.contains('skills-made'),
  );
  await step('use_skill lists workspace skills', () => _toolUseSkill(<String, dynamic>{}, cv), (String t) => t.contains('ci-proj') && t.contains('ci-start'));
  await step('use_skill loads cwd skill', () => _toolUseSkill(<String, dynamic>{'name': 'ci-proj'}, cv), (String t) => t.contains('PROJ-BODY') && t.contains('Skill folder:'));
  await step('use_skill loads start-dir skill', () => _toolUseSkill(<String, dynamic>{'name': 'ci-start'}, cv), (String t) => t.contains('START-BODY') && t.contains('notes.md'));
  await step('use_skill reads a workspace skill file', () => _toolUseSkill(<String, dynamic>{'name': 'ci-start', 'file': 'notes.md'}, cv), (String t) => t.contains('NOTE-OK'));
  await step('use_skill rejects path traversal', () => _toolUseSkill(<String, dynamic>{'name': 'ci-start', 'file': '../../etc/passwd'}, cv), (String t) => t.contains('relative path'), expectError: true);
  await step('runTool dispatches use_skill on ssh', () => runTool(ToolCall(id: 'sk1', name: kToolUseSkill, args: <String, dynamic>{'name': 'ci-proj'}), ag, s, convId: cv), (String t) => t.contains('PROJ-BODY'));
  out('DONE fails=$fails total=$total');
}
