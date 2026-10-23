part of 'main.dart';

// =====================================================================
//  Workspace: بيئة تنفيذ حقيقية (Termux على الهاتف أو أي خادم SSH)
//  - اتصال SSH واحد مُعاد الاستخدام لكل بيئة (dartssh2)
//  - أداة bash مع موافقة على كل أمر، مهلة، إيقاف، وأوامر خلفية تعيش على الخادم
//  - ملاحظة أمنية: قائمة "الأوامر الخطرة" تنبيه للمستخدم وليست حدّاً أمنياً؛ الحدّ الأمني الحقيقي هو الموافقة.
// =====================================================================

const String kToolBash = 'bash';
const String kToolBashOut = 'bash_output';
const String kToolKillShell = 'kill_shell';

// ---------------------------------------------------------------------
//  Config + store
// ---------------------------------------------------------------------
class WorkspaceConfig {
  final String id;
  final String name;
  final String host;
  final int port;
  final String user;
  final String keyPem;
  final String password;
  final String startDir;
  final String hostFp;
  final bool isTermux;
  const WorkspaceConfig({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.user,
    this.keyPem = '',
    this.password = '',
    this.startDir = '',
    this.hostFp = '',
    this.isTermux = false,
  });

  /// بيئة "هذا الهاتف": sh النظام عبر Process، بدون SSH. غير مخزّنة في القائمة (مدمجة دائماً).
  factory WorkspaceConfig.local() => const WorkspaceConfig(
        id: kLocalWorkspaceId,
        name: 'هذا الهاتف',
        host: 'local',
        user: 'app',
        startDir: PhoneStorage.root,
      );

  bool get isLocal => id == kLocalWorkspaceId;
  bool get hasKey => keyPem.trim().isNotEmpty;
  String get address => isLocal ? 'local · /system/bin/sh' : '$user@$host:$port';

  WorkspaceConfig copyWith({
    String? name,
    String? host,
    int? port,
    String? user,
    String? keyPem,
    String? password,
    String? startDir,
    String? hostFp,
    bool? isTermux,
  }) =>
      WorkspaceConfig(
        id: id,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        user: user ?? this.user,
        keyPem: keyPem ?? this.keyPem,
        password: password ?? this.password,
        startDir: startDir ?? this.startDir,
        hostFp: hostFp ?? this.hostFp,
        isTermux: isTermux ?? this.isTermux,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'user': user,
        'keyPem': keyPem,
        'password': password,
        'startDir': startDir,
        'hostFp': hostFp,
        'isTermux': isTermux,
      };

  factory WorkspaceConfig.fromJson(Map<String, dynamic> j) {
    final dynamic p = j['port'];
    final int port = p is num ? p.toInt() : (int.tryParse(asStr(p)) ?? 22);
    return WorkspaceConfig(
      id: asStr(j['id'], newId()),
      name: asStr(j['name']),
      host: asStr(j['host']),
      port: port,
      user: asStr(j['user']),
      keyPem: asStr(j['keyPem']),
      password: asStr(j['password']),
      startDir: asStr(j['startDir']),
      hostFp: asStr(j['hostFp']),
      isTermux: j['isTermux'] == true,
    );
  }
}

class WorkspacesNotifier extends JsonListNotifier<WorkspaceConfig> {
  @override
  String get folderName => 'workspaces';
  @override
  String get fileName => 'list';
  @override
  WorkspaceConfig decode(Map<String, dynamic> j) => WorkspaceConfig.fromJson(j);
  @override
  Map<String, dynamic> encode(WorkspaceConfig t) => t.toJson();
  @override
  String idOf(WorkspaceConfig t) => t.id;
}

final workspacesProvider = NotifierProvider<WorkspacesNotifier, List<WorkspaceConfig>>(WorkspacesNotifier.new);

class SelectedWorkspaceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  Future<void> load() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      state = p.getString('selected_workspace');
    } catch (_) {}
  }

  Future<void> choose(String? id) async {
    state = id;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      if (id == null) {
        await p.remove('selected_workspace');
      } else {
        await p.setString('selected_workspace', id);
      }
    } catch (_) {}
  }
}

final selectedWorkspaceProvider = NotifierProvider<SelectedWorkspaceNotifier, String?>(SelectedWorkspaceNotifier.new);

WorkspaceConfig? currentWorkspace() {
  final String? id = appContainer.read(selectedWorkspaceProvider);
  if (id == null) return null;
  if (id == kLocalWorkspaceId) return WorkspaceConfig.local();
  return appContainer.read(workspacesProvider.notifier).byId(id);
}

// ---------------------------------------------------------------------
//  Keys
// ---------------------------------------------------------------------
class GeneratedKey {
  final String pem;
  final String publicLine;
  const GeneratedKey(this.pem, this.publicLine);
}

class SshKeys {
  /// مفتاح ed25519 جديد بصيغة OpenSSH. يبقى الخاص داخل التطبيق، والعام يُلصق في authorized_keys.
  static GeneratedKey generate(String comment) {
    final nacl.SigningKey sk = nacl.SigningKey.generate();
    final Uint8List priv = Uint8List.fromList(sk.asTypedList);
    final Uint8List pub = Uint8List.fromList(sk.verifyKey.asTypedList);
    final ssh.OpenSSHEd25519KeyPair kp = ssh.OpenSSHEd25519KeyPair(pub, priv, comment);
    return GeneratedKey(kp.toPem(), 'ssh-ed25519 ${base64.encode(kp.toPublicKey().encode())} $comment');
  }

  /// السطر العام لمفتاح خاص محفوظ (للعرض مجدداً). يعيد '' عند الفشل.
  static String publicLineOf(String pem, String comment) {
    try {
      final List<ssh.SSHKeyPair> pairs = ssh.SSHKeyPair.fromPem(pem);
      if (pairs.isEmpty) return '';
      final ssh.SSHKeyPair k = pairs.first;
      return '${k.name} ${base64.encode(k.toPublicKey().encode())} $comment';
    } catch (_) {
      return '';
    }
  }
}

String sshErrorText(Object e) {
  if (e is ssh.SSHAuthFailError) {
    return 'رُفض تسجيل الدخول: المفتاح أو كلمة المرور غير مقبولة. في Termux تأكد أن المفتاح العام أُضيف إلى ~/.ssh/authorized_keys وأن اسم المستخدم صحيح (الأمر whoami).';
  }
  if (e is ssh.SSHHostkeyError) {
    return 'بصمة الخادم تغيّرت عن المحفوظة، فرفضت الاتصال. إن كنت تثق بالتغيير (إعادة تثبيت مثلاً) احذف هذه البيئة وأضفها من جديد.';
  }
  if (e is TimeoutException) {
    return 'انتهت مهلة الاتصال. تأكد من العنوان والمنفذ ومن أن الجهاز يعمل ومتصل بنفس الشبكة.';
  }
  if (e is SocketException) {
    final String m = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();
    if (m.contains('refused')) return 'رُفض الاتصال: لا يوجد خادم SSH يستمع على هذا المنفذ. في Termux شغّل الأمر sshd أولاً.';
    if (m.contains('lookup') || m.contains('resolve') || m.contains('host')) return 'تعذّر العثور على العنوان. راجع اسم المضيف.';
    return 'تعذّر الاتصال: ${e.message}';
  }
  if (e is ssh.SSHError) return 'خطأ SSH: $e';
  return '$e';
}

// ---------------------------------------------------------------------
//  Connection pool
// ---------------------------------------------------------------------
class SshPool {
  static final Map<String, ssh.SSHClient> _clients = <String, ssh.SSHClient>{};
  static final Map<String, Future<ssh.SSHClient>> _connecting = <String, Future<ssh.SSHClient>>{};

  static Future<ssh.SSHClient> get(WorkspaceConfig w) async {
    final ssh.SSHClient? existing = _clients[w.id];
    if (existing != null && !existing.isClosed) return existing;
    _clients.remove(w.id);
    final Future<ssh.SSHClient>? pending = _connecting[w.id];
    if (pending != null) return pending;
    final Future<ssh.SSHClient> f = open(w, onFingerprint: (String fp) {
      final WorkspaceConfig? latest = appContainer.read(workspacesProvider.notifier).byId(w.id);
      if (latest != null && latest.hostFp.isEmpty) {
        appContainer.read(workspacesProvider.notifier).upsert(latest.copyWith(hostFp: fp));
      }
    });
    _connecting[w.id] = f;
    try {
      final ssh.SSHClient c = await f;
      _clients[w.id] = c;
      return c;
    } finally {
      _connecting.remove(w.id);
    }
  }

  static void drop(String id) {
    final ssh.SSHClient? c = _clients.remove(id);
    if (c != null) {
      try {
        c.close();
      } catch (_) {}
    }
  }

  /// يفتح اتصالاً جديداً (غير مُشارَك). يستدعي onFingerprint عند أول ثقة بالبصمة.
  static Future<ssh.SSHClient> open(WorkspaceConfig w, {void Function(String fp)? onFingerprint}) async {
    final ssh.SSHSocket sock = await ssh.SSHSocket.connect(w.host, w.port, timeout: const Duration(seconds: 12));
    List<ssh.SSHKeyPair>? ids;
    if (w.hasKey) {
      try {
        ids = ssh.SSHKeyPair.fromPem(w.keyPem);
      } catch (_) {
        await sock.close();
        throw 'تعذّر قراءة المفتاح الخاص المحفوظ لهذه البيئة. أنشئ مفتاحاً جديداً.';
      }
    }
    final ssh.SSHPasswordRequestHandler? pw = w.password.isEmpty ? null : () => w.password;
    final ssh.SSHClient client = ssh.SSHClient(
      sock,
      username: w.user,
      identities: ids,
      onPasswordRequest: pw,
      onVerifyHostKey: (String type, Uint8List fingerprint) => _verifyHost(w, utf8.decode(fingerprint, allowMalformed: true), onFingerprint),
      keepAliveInterval: const Duration(seconds: 15),
    );
    try {
      await client.authenticated.timeout(const Duration(seconds: 25));
    } catch (e) {
      try {
        client.close();
      } catch (_) {}
      rethrow;
    }
    return client;
  }

  static Future<bool> _verifyHost(WorkspaceConfig w, String fp, void Function(String fp)? onFingerprint) async {
    if (w.hostFp.isNotEmpty) return w.hostFp == fp;
    final bool local = w.isTermux || w.host == 'localhost' || w.host.startsWith('127.');
    if (local) {
      if (onFingerprint != null) onFingerprint(fp);
      return true;
    }
    final bool ok = await askConfirm(
      'خادم جديد',
      'هذه أول مرة تتصل بـ ${w.host}.\nبصمة الخادم:\n$fp\n\nقارنها ببصمة خادمك (الأمر ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub عليه) ثم تابع إن تطابقتا.',
      ok: 'ثقة ومتابعة',
      cancel: 'إلغاء',
    );
    if (ok && onFingerprint != null) onFingerprint(fp);
    return ok;
  }
}

// ---------------------------------------------------------------------
//  Execution
// ---------------------------------------------------------------------
class BashCancel {
  bool cancelled = false;
  Future<void> Function()? onKill;
  Future<void> cancel() async {
    cancelled = true;
    final Future<void> Function()? k = onKill;
    if (k != null) await k();
  }
}

class ExecResult {
  final String output;
  final int? exitCode;
  final bool timedOut;
  final bool cancelled;
  final bool lost;
  final String? cwd;
  final bool truncated;
  const ExecResult({
    required this.output,
    this.exitCode,
    this.timedOut = false,
    this.cancelled = false,
    this.lost = false,
    this.cwd,
    this.truncated = false,
  });
}

class BashJob {
  final String id;
  final String wsId;
  final String command;
  int offset;
  String pid;
  BashJob({required this.id, required this.wsId, required this.command, this.offset = 0, this.pid = ''});
}

class BashRuntime {
  static final Set<BashCancel> active = <BashCancel>{};
  static final Map<String, String> _cwd = <String, String>{};
  static final Map<String, Set<String>> _allowed = <String, Set<String>>{};
  static final Map<String, BashJob> jobs = <String, BashJob>{};

  static String cwdOf(String convId, WorkspaceConfig w) => _cwd['$convId|${w.id}'] ?? w.startDir;
  static void setCwd(String convId, WorkspaceConfig w, String cwd) => _cwd['$convId|${w.id}'] = cwd;

  static bool isAllowed(String convId, String prefix) => (_allowed[convId] ?? const <String>{}).contains(prefix);
  static void allow(String convId, String prefix) => (_allowed[convId] ??= <String>{}).add(prefix);

  static void forget(String convId) {
    _allowed.remove(convId);
    _cwd.removeWhere((String k, String v) => k.startsWith('$convId|'));
  }

  static Future<void> cancelAll() async {
    for (final BashCancel c in List<BashCancel>.from(active)) {
      try {
        await c.cancel();
      } catch (_) {}
    }
  }
}

class SshExec {
  static const int _kRawCap = 2000000;
  static const int _kShowCap = 30000;

  static const String _template = r'''exec 2>&1
@CD@
printf '%s\n' "@M@PID $$"
@CMD@
__lm_rc=$?
printf '\n%s\n' "@M@END $__lm_rc $(pwd)"
''';

  /// kill شجرة العمليات عبر /proc (لا يحتاج procps: يعمل على Termux والخوادم).
  static const String _ktFn = r'''kt() { local d p pp rest; for d in /proc/[0-9]*; do p=${d#/proc/}; { read -r _ _ _ pp rest < "$d/stat"; } 2>/dev/null || continue; [ "$pp" = "$1" ] && kt "$p"; done; kill -"$2" "$1" 2>/dev/null; }
''';

  static String sq(String s) => "'" + s.replaceAll("'", "'\\''") + "'";

  static String _cdLine(String cwd) {
    final String c = cwd.trim();
    if (c.isEmpty || c == '~') return r'cd "$HOME"';
    if (c.startsWith('~/')) return r'cd "$HOME"/' + sq(c.substring(2)) + r' 2>/dev/null || cd "$HOME"';
    return 'cd -- ' + sq(c) + r' 2>/dev/null || cd "$HOME"';
  }

  /// السكربت يُمرَّر base64 كي لا نقع في مشاكل الاقتباس، ويبقى stdin حراً (يُغلق فيرى الأمر EOF بدل أن ينتظر).
  static String _asBashC(String script) {
    final String b64 = base64.encode(utf8.encode(script));
    return r'bash -c "$(printf %s ' + sq(b64) + r' | base64 -d)"';
  }

  static String? _parsePid(String text, String marker) {
    final Match? m = RegExp(RegExp.escape(marker) + r'PID (\d+)').firstMatch(text);
    return m == null ? null : m.group(1);
  }

  static String capOutput(String s, int max) {
    if (s.length <= max) return s;
    final int head = (max * 0.4).floor();
    final int tail = max - head;
    final int cut = s.length - head - tail;
    return s.substring(0, head) + '\n[… حُذف $cut حرفاً من الوسط …]\n' + s.substring(s.length - tail);
  }

  static Future<ExecResult> run(WorkspaceConfig w, String command, {required String cwd, required int timeoutMs, BashCancel? cancel}) async {
    if (w.isLocal) return LocalExec.run(command, cwd: cwd, timeoutMs: timeoutMs, cancel: cancel);
    final String marker = '__LM${newId().replaceAll('-', '').substring(0, 10)}__';
    final String script = _template.replaceAll('@CD@', _cdLine(cwd)).replaceAll('@M@', marker).replaceAll('@CMD@', command);

    ssh.SSHClient client;
    try {
      client = await SshPool.get(w);
    } catch (e) {
      return ExecResult(output: 'تعذّر الاتصال بالبيئة "${w.name}": ${sshErrorText(e)}', exitCode: null, lost: true);
    }
    ssh.SSHSession sess;
    try {
      sess = await client.execute(_asBashC(script));
    } catch (e) {
      SshPool.drop(w.id);
      return ExecResult(output: 'تعذّر بدء الأمر: ${sshErrorText(e)}', exitCode: null, lost: true);
    }
    try {
      await sess.stdin.close();
    } catch (_) {}

    final StringBuffer raw = StringBuffer();
    int rawLen = 0;
    bool capped = false;
    String tail = '';
    final Completer<void> outDone = Completer<void>();
    final StreamSubscription<String> sub = const Utf8Decoder(allowMalformed: true).bind(sess.stdout).listen(
      (String chunk) {
        if (rawLen < _kRawCap) {
          raw.write(chunk);
          rawLen += chunk.length;
        } else {
          capped = true;
        }
        final String t = tail + chunk;
        tail = t.length > 800 ? t.substring(t.length - 800) : t;
      },
      onError: (Object e) {
        if (!outDone.isCompleted) outDone.complete();
      },
      onDone: () {
        if (!outDone.isCompleted) outDone.complete();
      },
      cancelOnError: false,
    );

    bool timedOut = false;
    Timer? hard;
    Future<void> killNow() async {
      hard ??= Timer(const Duration(seconds: 12), () {
        try {
          sess.close();
        } catch (_) {}
        if (!outDone.isCompleted) outDone.complete();
      });
      try {
        sess.kill(ssh.SSHSignal.TERM);
      } catch (_) {}
      final String? p = _parsePid(raw.toString(), marker);
      if (p != null) await killTree(w, p);
    }

    final Timer timer = Timer(Duration(milliseconds: timeoutMs), () {
      timedOut = true;
      killNow();
    });
    if (cancel != null) {
      cancel.onKill = killNow;
      if (cancel.cancelled) killNow();
    }

    await outDone.future;
    timer.cancel();
    final Timer? h = hard;
    if (h != null) h.cancel();
    int? code;
    try {
      code = await sess.waitForExit(timeout: const Duration(seconds: 3));
    } catch (_) {}
    try {
      await sub.cancel();
    } catch (_) {}
    try {
      sess.close();
    } catch (_) {}

    String text = raw.toString();
    String? newCwd;
    final Match? em = RegExp(RegExp.escape(marker) + r'END (-?\d+) ([^\n]*)').firstMatch(tail);
    bool ended = false;
    if (em != null) {
      ended = true;
      code = int.tryParse(em.group(1) ?? '');
      final String c = (em.group(2) ?? '').trim();
      if (c.isNotEmpty) newCwd = c;
    }
    text = text.replaceAll(RegExp(r'\n?' + RegExp.escape(marker) + r'END [^\n]*\n?'), '');
    text = text.replaceFirst(RegExp(RegExp.escape(marker) + r'PID \d+\n?'), '');
    text = text.replaceFirst(RegExp(r'\n+$'), '');

    final bool lost = !ended && !timedOut && !(cancel != null && cancel.cancelled) && code == null;
    if (lost) SshPool.drop(w.id);
    final bool trunc = capped || text.length > _kShowCap;
    return ExecResult(
      output: capOutput(text, _kShowCap),
      exitCode: code,
      timedOut: timedOut,
      cancelled: cancel != null && cancel.cancelled,
      lost: lost,
      cwd: newCwd,
      truncated: trunc,
    );
  }

  /// سكربت قصير (إدارة المهام الخلفية، الاختبار…). يعيد المخرجات كاملة.
  static Future<String> script(WorkspaceConfig w, String body, {int timeoutMs = 20000, ssh.SSHClient? useClient}) async {
    final ssh.SSHClient client = useClient ?? await SshPool.get(w);
    final ssh.SSHSession sess = await client.execute(_asBashC('exec 2>&1\n' + body));
    try {
      await sess.stdin.close();
    } catch (_) {}
    final StringBuffer b = StringBuffer();
    final Future<void> r = const Utf8Decoder(allowMalformed: true).bind(sess.stdout).forEach((String s) {
      b.write(s);
    });
    await r.timeout(Duration(milliseconds: timeoutMs), onTimeout: () {
      try {
        sess.close();
      } catch (_) {}
    });
    return b.toString();
  }

  static Future<void> killTree(WorkspaceConfig w, String pid) async {
    if (!RegExp(r'^\d+$').hasMatch(pid)) return;
    try {
      await script(w, _ktFn + 'kt $pid TERM\nsleep 1\nkt $pid KILL\n', timeoutMs: 8000);
    } catch (_) {}
  }

  // ---- background jobs (تعيش على الخادم حتى لو انقطع الاتصال) ------------
  static Future<BashJob> startJob(WorkspaceConfig w, String command, String cwd) async {
    if (w.isLocal) return LocalExec.startJob(w, command, cwd);
    final String id = 'j${newId().replaceAll('-', '').substring(0, 6)}';
    final String inner = _cdLine(cwd) + '\n' + command + '\n' + r'__lm_rc=$?' + '\necho\n' + r'echo "__LM_EXIT__$__lm_rc"' + '\n';
    final String b64 = base64.encode(utf8.encode(inner));
    final String body = r'''mkdir -p "$HOME/.lmclient/jobs"
J="$HOME/.lmclient/jobs/@ID@"
nohup bash -c "$(printf %s '@B64@' | base64 -d)" > "$J.log" 2>&1 < /dev/null &
echo $! > "$J.pid"
echo "PID $!"
'''
        .replaceAll('@ID@', id)
        .replaceAll('@B64@', b64);
    final String out = await script(w, body);
    final Match? m = RegExp(r'PID (\d+)').firstMatch(out);
    if (m == null) throw ToolError('Could not start the background job: ${capOutput(out.trim(), 400)}');
    final BashJob job = BashJob(id: id, wsId: w.id, command: command, pid: m.group(1) ?? '');
    BashRuntime.jobs[id] = job;
    return job;
  }

  static Future<String> readJob(WorkspaceConfig w, BashJob job) async {
    if (w.isLocal) return LocalExec.readJob(job);
    final String body = r'''J="$HOME/.lmclient/jobs/@ID@"
if [ ! -f "$J.log" ]; then echo "__NOJOB__"; exit 0; fi
size=$(wc -c < "$J.log" | tr -d ' ')
P=$(cat "$J.pid" 2>/dev/null)
if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then echo "__STATE__ running $size"; else echo "__STATE__ done $size"; fi
head -c "$size" "$J.log" | tail -c +@OFF@
'''
        .replaceAll('@ID@', job.id)
        .replaceAll('@OFF@', '${job.offset + 1}');
    return script(w, body);
  }

  static Future<bool> killJob(WorkspaceConfig w, BashJob job) async {
    if (w.isLocal) return LocalExec.killJob(job);
    final String body = _ktFn +
        r'''J="$HOME/.lmclient/jobs/@ID@"
P=$(cat "$J.pid" 2>/dev/null)
[ -z "$P" ] && { echo "__NOJOB__"; exit 0; }
kt "$P" TERM
sleep 1
kt "$P" KILL
echo "__KILLED__"
'''
            .replaceAll('@ID@', job.id);
    final String out = await script(w, body, timeoutMs: 12000);
    return out.contains('__KILLED__');
  }

  /// اختبار اتصال لصفحة الإعداد: اتصال جديد، ثم يعرف الأدوات المتاحة.
  static Future<String> probe(WorkspaceConfig w, {void Function(String fp)? onFingerprint}) async {
    if (w.isLocal) return LocalExec.probeText();
    final ssh.SSHClient c = await SshPool.open(w, onFingerprint: onFingerprint);
    try {
      return await script(
          w,
          r'''echo "user: $(whoami)"
echo "dir: $(pwd)"
for t in bash git python3 node; do
  if command -v $t >/dev/null 2>&1; then echo "$t: yes"; else echo "$t: no"; fi
done
''',
          timeoutMs: 15000,
          useClient: c);
    } finally {
      try {
        await c.close();
      } catch (_) {}
    }
  }
}

// ---------------------------------------------------------------------
//  Approval policy
// ---------------------------------------------------------------------
class BashPolicy {
  static final RegExp _compound = RegExp(r'[;&|<>`\n]|\$\(|\$\{');

  static const Set<String> _single = <String>{
    'ls', 'cat', 'head', 'tail', 'grep', 'rg', 'wc', 'sort', 'diff', 'tree', 'stat', 'file', 'du', 'df', 'which', 'pwd', 'date', 'whoami', 'uname', 'pytest', 'ruff', 'black', 'prettier', 'eslint', 'tsc',
  };
  static const Set<String> _double = <String>{
    'git', 'npm', 'pnpm', 'yarn', 'pip', 'pip3', 'cargo', 'flutter', 'dart', 'docker', 'make', 'go', 'gradle', 'mvn',
  };
  static const Set<String> _quiet = <String>{'pwd', 'ls', 'date', 'whoami', 'uname'};

  static final List<RegExp> _danger = <RegExp>[
    RegExp(r'\brm\s+(-[a-zA-Z]*[rR][a-zA-Z]*\s+|--recursive\s+)'),
    RegExp(r'\bsudo\b'),
    RegExp(r'\bsu\s'),
    RegExp(r'\bmkfs'),
    RegExp(r'\bdd\s+[^|;]*of='),
    RegExp(r'>\s*/dev/(sd|nvme|mmcblk)'),
    RegExp(r'\bchmod\s+-R\b'),
    RegExp(r'\bchown\s+-R\b'),
    RegExp(r'git\s+push\s+[^|;]*(--force|-f\b)'),
    RegExp(r'git\s+(reset\s+--hard|clean\s+-[a-z]*f)'),
    RegExp(r'(curl|wget)\s[^|;]*\|\s*(sudo\s+)?(ba|z)?sh\b'),
    RegExp(r':\(\)\s*\{'),
    RegExp(r'\b(shutdown|reboot|halt|poweroff)\b'),
    RegExp(r'\bkillall\b|\bpkill\b'),
  ];

  static bool isDangerous(String cmd) {
    for (final RegExp r in _danger) {
      if (r.hasMatch(cmd)) return true;
    }
    return false;
  }

  static bool isCompound(String cmd) => _compound.hasMatch(cmd);

  static List<String> tokens(String cmd) => cmd.trim().split(RegExp(r'\s+'));

  /// بادئة يمكن السماح بها لبقية المحادثة، أو null إن كان الأمر مركّباً أو غير مناسب.
  static String? prefixFor(String cmd) {
    final String c = cmd.trim();
    if (c.isEmpty || isCompound(c) || isDangerous(c)) return null;
    final List<String> t = tokens(c);
    final String first = t.first;
    if (_single.contains(first)) return first;
    if (_double.contains(first) && t.length >= 2 && RegExp(r'^[a-z][a-z0-9:_-]*$').hasMatch(t[1])) return '$first ${t[1]}';
    return null;
  }

  static bool isQuiet(String cmd) {
    final String c = cmd.trim();
    if (c.isEmpty || isCompound(c)) return false;
    final List<String> t = tokens(c);
    if (!_quiet.contains(t.first)) return false;
    for (final String a in t.skip(1)) {
      if (a.contains('/') || a.startsWith('~')) return false;
    }
    return true;
  }

  /// وسوم مختصرة تُعرض في شاشة الموافقة.
  static List<String> riskTags(String cmd, {bool local = false}) {
    final List<String> tags = <String>[];
    if (isDangerous(cmd)) tags.add('خطر');
    if (local && LocalExec.touchesPrivate(cmd)) tags.add('يلمس بيانات التطبيق الخاصة');
    if (RegExp(r'(^|[\s;&|])(rm|mv|cp|tee|touch|mkdir|sed\s+-i|truncate)\b|>|git\s+(commit|merge|rebase|checkout|apply)').hasMatch(cmd)) tags.add('قد يعدّل الملفات');
    if (RegExp(r'\b(curl|wget|ssh|scp|rsync|nc)\b|git\s+(push|pull|fetch|clone)|(pip3?|npm|pnpm|yarn|cargo|flutter)\s+(install|add|get|update)').hasMatch(cmd)) tags.add('يستخدم الشبكة');
    return tags;
  }
}

class BashDecision {
  final bool allow;
  final String command;
  final String prefix;
  final String reason;
  const BashDecision({required this.allow, required this.command, this.prefix = '', this.reason = ''});
}

Future<BashDecision> approveBash(WorkspaceConfig w, String cwd, String command, String description, String convId, AppSettings s) async {
  final bool danger = BashPolicy.isDangerous(command) || (w.isLocal && LocalExec.touchesPrivate(command));
  if (!danger) {
    if (BashPolicy.isQuiet(command)) return BashDecision(allow: true, command: command);
    if (s.bashApproval == 'auto') return BashDecision(allow: true, command: command);
    final String? pre = BashPolicy.prefixFor(command);
    if (pre != null && BashRuntime.isAllowed(convId, pre)) return BashDecision(allow: true, command: command);
  }
  final BuildContext? ctx = navKey.currentContext;
  if (ctx == null) return BashDecision(allow: false, command: command, reason: 'no UI available to ask the user');
  final BashDecision? d = await showModalBottomSheet<BashDecision>(
    context: ctx,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (BuildContext c) => BashApprovalSheet(ws: w, cwd: cwd, command: command, description: description),
  );
  final BashDecision r = d ?? BashDecision(allow: false, command: command);
  if (r.allow && r.prefix.isNotEmpty) BashRuntime.allow(convId, r.prefix);
  return r;
}

// ---------------------------------------------------------------------
//  Tools
// ---------------------------------------------------------------------
List<ToolDef> workspaceTools(WorkspaceConfig w) {
  return <ToolDef>[
    ToolDef(
      kToolBash,
      (w.isLocal
              ? 'Run a shell command on the user\'s phone itself: Android\'s built-in shell (/system/bin/sh, mksh, not bash) with toybox utilities (ls, cat, grep, sed, find, tar, ...). It is NOT a full Linux: git, python, node and make are normally not installed, so check with `command -v tool` before relying on one. Use it for file inspection, simple scripts and anything the stock Android toolbox can do.'
              : 'Run a shell command (bash) on the user\'s connected workspace: a real Linux shell reached over SSH. Use it for git, tests, builds, package managers, running programs and anything a terminal can do.') +
          ' The working directory persists between calls (so `cd` sticks); environment variables do not. Output is capped at about 30,000 characters (the middle is cut): pipe through head/tail/grep when you expect a lot. Prefer read_file/edit_file/search_files for reading and changing files. Every command needs the user\'s approval, so give a short `description` saying what it does and why. Do not start interactive programs (editors, prompts, REPLs): stdin is closed. For servers or other long-running processes set run_in_background=true and poll with bash_output.',
      _obj(<String, dynamic>{
        'command': _pStr('The command to run'),
        'description': _pStr('One short sentence: what the command does and why (shown to the user in the approval sheet)'),
        'timeout_ms': _pInt('Timeout in milliseconds (default 120000, max 600000); the process tree is killed when it expires'),
        'run_in_background': _pBool('Start the command detached and return a job id immediately (it keeps running on the workspace)'),
      }, <String>['command']),
    ),
    ToolDef(
      kToolBashOut,
      'Read the new output of a background job started with bash (run_in_background=true) since the last time you read it, and whether it is still running.',
      _obj(<String, dynamic>{'id': _pStr('Job id returned by bash')}, <String>['id']),
    ),
    ToolDef(
      kToolKillShell,
      'Stop a background job started with bash (the whole process tree).',
      _obj(<String, dynamic>{'id': _pStr('Job id returned by bash')}, <String>['id']),
    ),
  ];
}

String workspacePromptSection(WorkspaceConfig w) {
  final StringBuffer b = StringBuffer();
  b.writeln('## Workspace');
  if (w.isLocal) {
    b.writeln('You are working on the user\'s Android phone through the bash tool (workspace "${w.name}"): Android\'s own shell /system/bin/sh (mksh, not bash: no arrays, [[ ]] or process substitution) with toybox utilities, running with the app\'s permissions in the phone\'s shared storage. git, python, node, make and curl are normally NOT installed: check with `command -v` first, and when something is missing use read_file/edit_file/search_files or tell the user what is missing instead of trying to install it.');
  } else {
    b.writeln('You are working on a real computer through the bash tool: workspace "${w.name}" (${w.user}@${w.host}${w.isTermux ? ", Termux on the user's own phone" : ""}).');
  }
  if (w.startDir.trim().isNotEmpty) b.writeln('Starting directory: ${w.startDir.trim()}.');
  b.writeln('Every bash command is shown to the user for approval, so keep commands focused and explain them briefly. When a command is denied, do not retry the same thing: ask the user or take another approach.');
  b.writeln('Tool results end with the exit code when it is not 0. The working directory persists between bash calls.');
  b.writeln('When you start work in a project folder you have not seen yet, first look at its root (ls) and its manifest (pubspec.yaml, package.json, pyproject.toml, Cargo.toml, go.mod, Makefile, README) to learn the project type and the right build/test commands; read CLAUDE.md or AGENTS.md there if present and follow it.');
  return b.toString().trimRight();
}

Future<ToolOutcome> _toolBash(Map<String, dynamic> a, AppSettings s, String convId) async {
  final WorkspaceConfig? w = currentWorkspace();
  if (w == null) throw const ToolError('No workspace is selected');
  String command = asStr(a['command']);
  if (command.trim().isEmpty) throw const ToolError('command is required');
  if (command.length > 60000) throw const ToolError('Command is too long (over 60,000 characters). Write the content to a file with write_file and run that instead.');
  final String desc = asStr(a['description']).trim();
  final dynamic to = a['timeout_ms'];
  final int timeoutMs = clampInt(to is num ? to.toInt() : 120000, 1000, 600000);
  final bool bg = a['run_in_background'] == true;
  final String cwd = BashRuntime.cwdOf(convId, w);

  final BashDecision d = await approveBash(w, cwd, command, desc, convId, s);
  if (!d.allow) {
    final String why = d.reason.trim();
    return ToolOutcome('The user denied this command.${why.isEmpty ? '' : ' Reason: $why'} Do not retry it as is: ask what they want instead.', true);
  }
  command = d.command;
  if (command.trim().isEmpty) throw const ToolError('command is empty');

  if (bg) {
    try {
      final BashJob job = await SshExec.startJob(w, command, cwd);
      return ToolOutcome('Started background job ${job.id} (pid ${job.pid}). Read its output with bash_output, stop it with kill_shell.', false);
    } catch (e) {
      if (e is ToolError) rethrow;
      return ToolOutcome('Could not start the job: ${sshErrorText(e)}', true);
    }
  }

  final BashCancel cancel = BashCancel();
  BashRuntime.active.add(cancel);
  ExecResult r;
  try {
    r = await SshExec.run(w, command, cwd: cwd, timeoutMs: timeoutMs, cancel: cancel);
  } finally {
    BashRuntime.active.remove(cancel);
  }
  final String? nc = r.cwd;
  bool cwdChanged = false;
  if (nc != null && nc != cwd && nc.isNotEmpty) {
    BashRuntime.setCwd(convId, w, nc);
    cwdChanged = true;
  }
  final StringBuffer b = StringBuffer();
  b.write(r.output.isEmpty ? '(no output)' : r.output);
  if (r.timedOut) {
    b.write('\n[timed out after ${(timeoutMs / 1000).round()}s: the process was killed. Use a larger timeout_ms or run_in_background]');
  } else if (r.cancelled) {
    b.write('\n[stopped by the user]');
  } else if (r.lost) {
    b.write('\n[the connection to the workspace was lost before the command finished; it may still be running]');
  } else if (r.exitCode != null && r.exitCode != 0) {
    b.write('\n[exit code: ${r.exitCode}]');
  }
  if (cwdChanged) b.write('\n[cwd: $nc]');
  final bool err = r.timedOut || r.cancelled || r.lost || (r.exitCode != null && r.exitCode != 0);
  return ToolOutcome(b.toString(), err);
}

Future<ToolOutcome> _toolBashOutput(Map<String, dynamic> a) async {
  final WorkspaceConfig? w = currentWorkspace();
  if (w == null) throw const ToolError('No workspace is selected');
  final String id = asStr(a['id']).trim();
  final BashJob? job = BashRuntime.jobs[id];
  if (job == null) throw ToolError('Unknown job: $id (jobs are forgotten when the app restarts; list ~/.lmclient/jobs with bash)');
  String out = '';
  try {
    out = await SshExec.readJob(w, job);
  } catch (e) {
    return ToolOutcome('Could not reach the workspace: ${sshErrorText(e)}', true);
  }
  if (out.contains('__NOJOB__')) return ToolOutcome('Job $id has no log on the workspace.', true);
  final Match? m = RegExp(r'__STATE__ (running|done) (\d+)').firstMatch(out);
  if (m == null) return ToolOutcome(SshExec.capOutput(out, 4000), true);
  final bool running = m.group(1) == 'running';
  final int size = int.tryParse(m.group(2) ?? '') ?? job.offset;
  String body = out.substring(m.end);
  if (body.startsWith('\n')) body = body.substring(1);
  job.offset = size;
  String status = running ? 'running' : 'finished';
  final Match? ex = RegExp(r'__LM_EXIT__(-?\d+)').firstMatch(body);
  if (ex != null) {
    status = 'finished, exit code ${ex.group(1)}';
    body = body.replaceAll(RegExp(r'\n?__LM_EXIT__-?\d+\n?'), '');
  }
  body = SshExec.capOutput(body.trimRight(), 30000);
  return ToolOutcome('[job $id: $status]\n${body.isEmpty ? '(no new output)' : body}', false);
}

Future<ToolOutcome> _toolKillShell(Map<String, dynamic> a) async {
  final WorkspaceConfig? w = currentWorkspace();
  if (w == null) throw const ToolError('No workspace is selected');
  final String id = asStr(a['id']).trim();
  final BashJob? job = BashRuntime.jobs[id];
  if (job == null) throw ToolError('Unknown job: $id');
  bool ok = false;
  try {
    ok = await SshExec.killJob(w, job);
  } catch (e) {
    return ToolOutcome('Could not reach the workspace: ${sshErrorText(e)}', true);
  }
  return ToolOutcome(ok ? 'Stopped job $id.' : 'Could not stop job $id (it may have already finished).', !ok);
}
