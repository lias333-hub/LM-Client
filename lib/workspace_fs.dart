part of 'main.dart';

// =====================================================================
//  طبقة الوصول للملفات: أدوات الملفات (read/write/edit/list/outline/search) تعمل على البيئة المختارة:
//  - بدون بيئة أو "هذا الهاتف": تخزين الهاتف مباشرة (مع PathGuard كما كان).
//  - بيئة SSH (سيرفر أو Termux): عبر SFTP، والبحث عبر grep/find على الطرف الآخر.
//  السبب: bash كان يعمل على السيرفر بينما أدوات الملفات تعدّل ملفات الهاتف، فينقسم عمل النموذج بين مكانين.
//  ملاحظة: لا نقاط حفظ (تراجع) للملفات البعيدة؛ التراجع هناك عبر git على السيرفر.
// =====================================================================

class FsStat {
  final bool exists;
  final bool isDir;
  final int size;
  final int mtimeMs;
  const FsStat(this.exists, this.isDir, this.size, this.mtimeMs);
  static const FsStat missing = FsStat(false, false, 0, 0);
}

class FsEntry {
  final String name;
  final bool isDir;
  final int size;
  const FsEntry(this.name, this.isDir, this.size);
}

abstract class FsBackend {
  bool get isRemote;

  /// اسم المكان كما يظهر للمستخدم في نوافذ الموافقة.
  String get label;

  /// مفتاح فريد لمسار داخل هذا النظام (للـ ReadLedger كي لا يختلط مسار الهاتف بمسار السيرفر).
  String ledgerKey(String path);
  Future<String> resolve(String raw, Agent ag, String convId);
  Future<FsStat> stat(String path);
  Future<List<FsEntry>> list(String path);
  Future<List<int>> read(String path);
  Future<void> write(String path, List<int> bytes);
  Future<void> append(String path, List<int> bytes);
  Future<void> ensureParent(String path);
}

FsBackend currentFs() {
  final WorkspaceConfig? w = currentWorkspace();
  if (w == null || w.isLocal) return const LocalFs();
  return RemoteFs(w);
}

// ---------------------------------------------------------------------
//  الهاتف (السلوك القديم نفسه)
// ---------------------------------------------------------------------
class LocalFs implements FsBackend {
  const LocalFs();

  @override
  bool get isRemote => false;

  @override
  String get label => 'الهاتف';

  @override
  String ledgerKey(String path) => path;

  @override
  Future<String> resolve(String raw, Agent ag, String convId) async => PathGuard.resolve(raw, ag);

  @override
  Future<FsStat> stat(String path) async {
    final FileSystemEntityType t = await FileSystemEntity.type(path);
    if (t == FileSystemEntityType.notFound) return FsStat.missing;
    if (t == FileSystemEntityType.directory) return const FsStat(true, true, 0, 0);
    final File f = File(path);
    int size = 0;
    int mt = 0;
    try {
      size = await f.length();
      mt = (await f.lastModified()).millisecondsSinceEpoch;
    } catch (_) {}
    return FsStat(true, false, size, mt);
  }

  @override
  Future<List<FsEntry>> list(String path) async {
    final List<FileSystemEntity> ents = await PhoneStorage.listFiles(path);
    final List<FsEntry> out = <FsEntry>[];
    for (final FileSystemEntity e in ents) {
      final String name = e.path.split('/').last;
      if (e is Directory) {
        out.add(FsEntry(name, true, 0));
      } else {
        int size = 0;
        try {
          size = (e as File).lengthSync();
        } catch (_) {}
        out.add(FsEntry(name, false, size));
      }
    }
    return out;
  }

  @override
  Future<List<int>> read(String path) => File(path).readAsBytes();

  @override
  Future<void> write(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> append(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes, mode: FileMode.append, flush: true);
  }

  @override
  Future<void> ensureParent(String path) async {
    await File(path).parent.create(recursive: true);
  }
}

// ---------------------------------------------------------------------
//  بيئة SSH عبر SFTP
// ---------------------------------------------------------------------
class RemoteFs implements FsBackend {
  final WorkspaceConfig w;
  RemoteFs(this.w);

  static final Map<String, String> _homes = <String, String>{};

  @override
  bool get isRemote => true;

  @override
  String get label => w.name;

  @override
  String ledgerKey(String path) => 'ssh:${w.id}:$path';

  Future<ssh.SftpClient> _sftp() async {
    try {
      final ssh.SSHClient c = await SshPool.get(w);
      return await c.sftp();
    } catch (e) {
      throw ToolError('Cannot open an SFTP session to workspace "${w.name}" (the server may not offer SFTP): $e');
    }
  }

  static String _statusMsg(ssh.SftpStatusError e) {
    if (e.code == ssh.SftpStatusCode.noSuchFile) return 'No such file or directory';
    if (e.code == ssh.SftpStatusCode.permissionDenied) return 'Permission denied';
    return 'SFTP error: ${e.message}';
  }

  Future<T> _with<T>(Future<T> Function(ssh.SftpClient s) body) async {
    final ssh.SftpClient s = await _sftp();
    try {
      return await body(s);
    } on ssh.SftpStatusError catch (e) {
      throw ToolError(_statusMsg(e));
    } finally {
      try {
        await s.close();
      } catch (_) {}
    }
  }

  Future<String> _home() async {
    final String? c = _homes[w.id];
    if (c != null) return c;
    String h = '/';
    try {
      h = await _with<String>((ssh.SftpClient s) => s.absolute('.'));
    } catch (_) {}
    _homes[w.id] = h;
    return h;
  }

  static String _normalize(String p) {
    final List<String> out = <String>[];
    for (final String seg in p.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (out.isNotEmpty) out.removeLast();
        continue;
      }
      out.add(seg);
    }
    return '/${out.join('/')}';
  }

  /// مفاتيح وبيانات اعتماد على السيرفر: لا تُقرأ ولا تُكتب بأدوات الملفات (bash يمرّ بموافقة المستخدم).
  static bool _denied(String p) {
    if (p.contains('/.ssh/') || p.endsWith('/.ssh') || p.contains('/.gnupg')) return true;
    if (p == '/etc/shadow' || p == '/etc/gshadow') return true;
    if (p.contains('/.aws/credentials') || p.endsWith('/.kube/config')) return true;
    return false;
  }

  @override
  Future<String> resolve(String raw, Agent ag, String convId) async {
    String p = raw.trim();
    if (p.isEmpty) p = '.';
    if (p == '~' || p.startsWith('~/')) {
      final String h = await _home();
      p = p == '~' ? h : '$h/${p.substring(2)}';
    } else if (!p.startsWith('/')) {
      String base = BashRuntime.cwdOf(convId, w).trim();
      if (base.isEmpty) {
        base = await _home();
      } else if (base == '~' || base.startsWith('~/')) {
        final String h = await _home();
        base = base == '~' ? h : '$h/${base.substring(2)}';
      } else if (!base.startsWith('/')) {
        final String h = await _home();
        base = '$h/$base';
      }
      p = '$base/$p';
    }
    final String n = _normalize(p);
    if (_denied(n)) throw ToolError('Access to $n is blocked: it holds keys or credentials. Ask the user to run the command themselves if it is really needed.');
    return n;
  }

  @override
  Future<FsStat> stat(String path) {
    return _with<FsStat>((ssh.SftpClient s) async {
      try {
        final ssh.SftpFileAttrs a = await s.stat(path);
        final int mt = (a.modifyTime ?? 0) * 1000;
        return FsStat(true, a.isDirectory, a.size ?? 0, mt);
      } on ssh.SftpStatusError catch (e) {
        if (e.code == ssh.SftpStatusCode.noSuchFile) return FsStat.missing;
        rethrow;
      }
    });
  }

  @override
  Future<List<FsEntry>> list(String path) {
    return _with<List<FsEntry>>((ssh.SftpClient s) async {
      final List<ssh.SftpName> names = await s.listdir(path);
      final List<FsEntry> out = <FsEntry>[];
      for (final ssh.SftpName n in names) {
        if (n.filename == '.' || n.filename == '..') continue;
        bool isDir = n.attr.isDirectory;
        if (n.attr.isSymbolicLink) {
          try {
            isDir = (await s.stat('$path/${n.filename}')).isDirectory;
          } catch (_) {}
        }
        out.add(FsEntry(n.filename, isDir, n.attr.size ?? 0));
      }
      out.sort((FsEntry a, FsEntry b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return out;
    });
  }

  @override
  Future<List<int>> read(String path) {
    return _with<List<int>>((ssh.SftpClient s) async {
      final ssh.SftpFile f = await s.open(path);
      try {
        return await f.readBytes();
      } finally {
        await f.close();
      }
    });
  }

  @override
  Future<void> write(String path, List<int> bytes) {
    return _with<void>((ssh.SftpClient s) async {
      final ssh.SftpFile f = await s.open(path, mode: ssh.SftpFileOpenMode.create | ssh.SftpFileOpenMode.write | ssh.SftpFileOpenMode.truncate);
      try {
        await f.writeBytes(Uint8List.fromList(bytes));
      } finally {
        await f.close();
      }
    });
  }

  @override
  Future<void> append(String path, List<int> bytes) async {
    final List<int> old = await read(path);
    await write(path, <int>[...old, ...bytes]);
  }

  @override
  Future<void> ensureParent(String path) {
    final int i = path.lastIndexOf('/');
    if (i <= 0) return Future<void>.value();
    final String dir = path.substring(0, i);
    return _with<void>((ssh.SftpClient s) async {
      Future<bool> exists(String d) async {
        try {
          await s.stat(d);
          return true;
        } on ssh.SftpStatusError catch (e) {
          if (e.code == ssh.SftpStatusCode.noSuchFile) return false;
          rethrow;
        }
      }

      if (await exists(dir)) return;
      String cur = '';
      for (final String part in dir.split('/')) {
        if (part.isEmpty) continue;
        cur = '$cur/$part';
        if (!await exists(cur)) await s.mkdir(cur);
      }
    });
  }
}

// ---------------------------------------------------------------------
//  بحث الملفات على بيئة بعيدة: grep / find على الطرف الآخر (لا نسحب الملفات عبر الشبكة)
// ---------------------------------------------------------------------
List<String> _expandBraces(String g) {
  final RegExpMatch? x = RegExp(r'^(.*)\{([^{}]*)\}(.*)$').firstMatch(g);
  if (x == null) return <String>[g];
  final String pre = x.group(1) ?? '';
  final String post = x.group(3) ?? '';
  final List<String> out = <String>[];
  for (final String alt in (x.group(2) ?? '').split(',')) {
    out.addAll(_expandBraces('$pre$alt$post'));
  }
  return out;
}

Future<ToolOutcome> _remoteSearchFiles(WorkspaceConfig w, String root, bool isDir, String pat, String glob, bool ignoreCase, int max) async {
  final List<String> globs = glob.isEmpty ? <String>[] : _expandBraces(glob);
  final String cwd;
  final String target;
  if (isDir) {
    cwd = root;
    target = '.';
  } else {
    final int i = root.lastIndexOf('/');
    cwd = i <= 0 ? '/' : root.substring(0, i);
    target = SshExec.sq(root.substring(i + 1));
  }
  final StringBuffer c = StringBuffer();
  if (pat.isNotEmpty) {
    c.writeln('M=-E; echo | grep -E -e ${SshExec.sq(pat)} >/dev/null 2>&1; [ \$? -eq 2 ] && M=-F');
    c.write('grep -rIHn \$M ${ignoreCase ? '-i ' : ''}-e ${SshExec.sq(pat)}');
    for (final String g in globs) {
      c.write(' --include=${SshExec.sq(g)}');
    }
    for (final String d in _kSkipDirs) {
      c.write(' --exclude-dir=${SshExec.sq(d)}');
    }
    c.write(' $target 2>/dev/null | cut -c1-320 | head -n ${max + 1}');
  } else {
    c.write('find $target \\( ');
    c.write(_kSkipDirs.map((String d) => '-name ${SshExec.sq(d)}').join(' -o '));
    c.write(' \\) -prune -o -type f \\( ');
    c.write(globs.map((String g) => '-iname ${SshExec.sq(g)}').join(' -o '));
    c.write(' \\) -print 2>/dev/null | head -n ${max + 1}');
  }
  final ExecResult r = await SshExec.run(w, c.toString(), cwd: cwd, timeoutMs: 40000);
  final List<String> rows = <String>[];
  for (String line in r.output.split('\n')) {
    line = line.trimRight();
    if (line.isEmpty) continue;
    if (line.startsWith('./')) line = line.substring(2);
    rows.add(line);
  }
  final bool stopped = rows.length > max;
  final List<String> shown = stopped ? rows.sublist(0, max) : rows;
  if (shown.isEmpty) {
    final String why = r.timedOut ? ' (timed out)' : '';
    return ToolOutcome('No matches under $root$why.', false);
  }
  String head;
  if (pat.isEmpty) {
    head = 'Found ${shown.length} file(s)';
  } else {
    final Set<String> files = <String>{};
    for (final String l in shown) {
      final int k = l.indexOf(':');
      files.add(k > 0 ? l.substring(0, k) : l);
    }
    head = 'Found ${shown.length} match(es) in ${files.length} file(s)';
  }
  final String tail = (stopped || r.timedOut || r.truncated) ? '\n…[stopped at a result/time limit — narrow the path, glob or pattern]' : '';
  return ToolOutcome('$head (paths relative to $root; searched on workspace "${w.name}")\n${shown.join('\n')}$tail', false);
}
