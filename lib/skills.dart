part of 'main.dart';

// =====================================================================
//  Skills (مهارات): تعليمات جاهزة قابلة لإعادة الاستخدام، بنفس صيغة Claude Code (مجلد فيه SKILL.md).
//  - يرى النموذج في الـ system prompt الاسم + الوصف فقط، ويحمّل النص الكامل عند الحاجة بالأداة use_skill
//    (هكذا يبقى الـ prompt صغيراً والكاش ثابتاً مهما كثرت المهارات).
//  - المصادر: مكتوبة/ملصوقة يدوياً، مستوردة من GitHub (عام)، أو مجلد .claude/skills على بيئة SSH المختارة.
//  - الأمان: المهارة نص تعليمات فقط؛ لا تمنح أي صلاحية. كل أمر/كتابة يمرّ بموافقات الأدوات المعتادة.
// =====================================================================

const String kToolUseSkill = 'use_skill';
const int kSkillMaxBody = 100 * 1024;
const int kSkillMaxFile = 60 * 1024;
const int kSkillMaxTotal = 400 * 1024;
const int kSkillMaxFiles = 40;
const int kSkillPromptMax = 40;
const int kSkillResultMax = 60000;

class Skill {
  final String id;
  final String name;
  final String description;
  final String body;
  final Map<String, String> files;
  final bool enabled;
  final String source;
  final int addedAt;

  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.body,
    this.files = const <String, String>{},
    this.enabled = true,
    this.source = 'manual',
    this.addedAt = 0,
  });

  Skill copyWith({String? name, String? description, String? body, Map<String, String>? files, bool? enabled, String? source}) {
    return Skill(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      body: body ?? this.body,
      files: files ?? this.files,
      enabled: enabled ?? this.enabled,
      source: source ?? this.source,
      addedAt: addedAt,
    );
  }

  factory Skill.fromJson(Map<String, dynamic> j) {
    final Map<String, String> f = <String, String>{};
    asMap(j['files']).forEach((String k, dynamic v) {
      f[k] = asStr(v);
    });
    return Skill(
      id: asStr(j['id'], newId()),
      name: asStr(j['name']),
      description: asStr(j['description']),
      body: asStr(j['body']),
      files: f,
      enabled: j['enabled'] != false,
      source: asStr(j['source'], 'manual'),
      addedAt: toInt(j['addedAt']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'body': body,
        'files': files,
        'enabled': enabled,
        'source': source,
        'addedAt': addedAt,
      };
}

class SkillsNotifier extends JsonListNotifier<Skill> {
  @override
  String get folderName => 'skills';
  @override
  String get fileName => 'list';
  @override
  Skill decode(Map<String, dynamic> j) => Skill.fromJson(j);
  @override
  Map<String, dynamic> encode(Skill t) => t.toJson();
  @override
  String idOf(Skill t) => t.id;

  Skill? byName(String name) {
    for (final Skill s in state) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// تثبيت مهارة: إن وُجدت مهارة بالاسم نفسه تُستبدل (مع إبقاء معرّفها وحالة تفعيلها).
  Future<void> install(Skill sk) async {
    final Skill? old = byName(sk.name);
    if (old == null) {
      await upsert(sk);
      return;
    }
    await upsert(Skill(
      id: old.id,
      name: sk.name,
      description: sk.description,
      body: sk.body,
      files: sk.files,
      enabled: old.enabled,
      source: sk.source,
      addedAt: old.addedAt,
    ));
  }
}

final skillsProvider = NotifierProvider<SkillsNotifier, List<Skill>>(SkillsNotifier.new);

List<Skill> enabledSkills() {
  final List<Skill> l = appContainer.read(skillsProvider).where((Skill s) => s.enabled).toList();
  l.sort((Skill a, Skill b) => a.name.compareTo(b.name));
  return l;
}

// ---------------------------------------------------------------------
//  SKILL.md: frontmatter بسيط (name / description) + النص
// ---------------------------------------------------------------------
class ParsedSkill {
  final String name;
  final String description;
  final String body;
  const ParsedSkill(this.name, this.description, this.body);
}

String _unquote(String v) {
  if (v.length >= 2) {
    final String a = v[0];
    final String b = v[v.length - 1];
    if ((a == '"' && b == '"') || (a == "'" && b == "'")) return v.substring(1, v.length - 1);
  }
  return v;
}

String skillSlug(String raw) {
  String s = raw.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'\s+'), '-');
  s = s.replaceAll(RegExp(r'[^\p{L}\p{N}_\-]', unicode: true), '');
  s = s.replaceAll(RegExp(r'-{2,}'), '-');
  s = s.replaceAll(RegExp(r'^-+'), '').replaceAll(RegExp(r'-+$'), '');
  return s.length > 64 ? s.substring(0, 64) : s;
}

ParsedSkill parseSkillMd(String raw) {
  String text = raw.replaceAll('\r\n', '\n');
  if (text.startsWith('﻿')) text = text.substring(1);
  final Map<String, String> meta = <String, String>{};
  String body = text.trim();
  final List<String> lines = text.split('\n');
  if (lines.isNotEmpty && lines.first.trim() == '---') {
    int end = -1;
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        end = i;
        break;
      }
    }
    if (end > 0) {
      final RegExp kv = RegExp(r'^([A-Za-z0-9_\-]+):\s*(.*)$');
      String key = '';
      String style = '';
      final List<String> parts = <String>[];
      void flush() {
        if (key.isNotEmpty) {
          final String joined = style == '|' ? parts.join('\n') : parts.join(' ');
          meta[key.toLowerCase()] = _unquote(joined.trim());
        }
        key = '';
        style = '';
        parts.clear();
      }

      for (int i = 1; i < end; i++) {
        final String ln = lines[i];
        final bool indented = ln.startsWith(' ') || ln.startsWith('\t');
        final RegExpMatch? m = indented ? null : kv.firstMatch(ln);
        if (m != null) {
          flush();
          key = m.group(1) ?? '';
          String v = (m.group(2) ?? '').trim();
          if (v == '>' || v == '>-' || v == '>+') {
            style = '>';
            v = '';
          } else if (v == '|' || v == '|-' || v == '|+') {
            style = '|';
            v = '';
          }
          if (v.isNotEmpty) parts.add(v);
        } else if (key.isNotEmpty && ln.trim().isNotEmpty) {
          parts.add(ln.trim());
        }
      }
      flush();
      body = lines.sublist(end + 1).join('\n').trim();
    }
  }
  String desc = (meta['description'] ?? '').trim();
  if (desc.isEmpty) {
    for (final String l in body.split('\n')) {
      final String t = l.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      desc = clip(t, 200);
      break;
    }
  }
  return ParsedSkill((meta['name'] ?? '').trim(), desc, body);
}

// ---------------------------------------------------------------------
//  الـ system prompt + تعريف الأداة
// ---------------------------------------------------------------------
bool _skillsToolWanted(WorkspaceConfig? ws) {
  if (enabledSkills().isNotEmpty) return true;
  return ws != null && !ws.isLocal;
}

ToolDef? skillToolDef(WorkspaceConfig? ws) {
  if (!_skillsToolWanted(ws)) return null;
  return ToolDef(
    kToolUseSkill,
    'Load a skill: reusable expert instructions for a kind of task (installed by the user, or found in the workspace folder .claude/skills). '
    'Call it with a name to get the full instructions and the list of bundled files; call it with name and file to read one bundled file; '
    'call it with no name to list every available skill. Use it BEFORE starting a task that matches a skill description.',
    _obj(<String, dynamic>{
      'name': _pStr('Skill name (empty lists all skills)'),
      'file': _pStr('Optional: relative path of a bundled file to read'),
    }, <String>[]),
  );
}

String? skillsPromptSection(WorkspaceConfig? ws) {
  final List<Skill> l = enabledSkills();
  final bool remote = ws != null && !ws.isLocal;
  if (l.isEmpty && !remote) return null;
  final StringBuffer b = StringBuffer();
  b.write('Skills are reusable expert instructions. When the task matches a skill below, call $kToolUseSkill with its name BEFORE starting and follow it.');
  if (remote) b.write(' The workspace may also hold project skills in .claude/skills; call $kToolUseSkill with no name to list them.');
  if (l.isNotEmpty) {
    b.write('\nInstalled skills:');
    final List<Skill> shown = l.length > kSkillPromptMax ? l.sublist(0, kSkillPromptMax) : l;
    for (final Skill s in shown) {
      b.write('\n- ${s.name}: ${clip(s.description.replaceAll('\n', ' '), 200)}');
    }
    if (l.length > shown.length) b.write('\n(+${l.length - shown.length} more — list them with $kToolUseSkill and no name)');
  }
  return b.toString();
}

// ---------------------------------------------------------------------
//  تنفيذ الأداة
// ---------------------------------------------------------------------
Skill? _matchSkill(List<Skill> l, String q) {
  final String n = skillSlug(q);
  for (final Skill s in l) {
    if (s.name == q || s.name == n) return s;
  }
  if (n.isNotEmpty) {
    for (final Skill s in l) {
      if (s.name.contains(n)) return s;
    }
  }
  return null;
}

class _WsSkill {
  final String name;
  final String description;
  final String dir;
  final String origin; // project | user
  const _WsSkill(this.name, this.description, this.dir, this.origin);
}

_WsSkill? _matchWs(List<_WsSkill> l, String q) {
  final String n = skillSlug(q);
  for (final _WsSkill s in l) {
    if (s.name == n) return s;
  }
  if (n.isNotEmpty) {
    for (final _WsSkill s in l) {
      if (s.name.contains(n)) return s;
    }
  }
  return null;
}

Future<List<FsEntry>> _tryList(FsBackend fs, String p) async {
  try {
    return await fs.list(p);
  } catch (_) {
    return <FsEntry>[];
  }
}

Future<String?> _tryReadText(FsBackend fs, String path, int maxChars) async {
  try {
    final List<int> b = await fs.read(path);
    if (looksBinary(b)) return null;
    final String t = utf8.decode(b, allowMalformed: true);
    return t.length > maxChars ? t.substring(0, maxChars) : t;
  } catch (_) {
    return null;
  }
}

/// مهارات المشروع (<cwd>/.claude/skills) ومهارات المستخدم (~/.claude/skills) على بيئة SSH المختارة.
Future<List<_WsSkill>> _discoverWorkspaceSkills(String convId) async {
  final WorkspaceConfig? w = currentWorkspace();
  if (w == null || w.isLocal) return <_WsSkill>[];
  final FsBackend fs = currentFs();
  const Agent ag = Agent(id: 'skills', name: 'skills');
  final List<MapEntry<String, String>> roots = <MapEntry<String, String>>[];
  final Set<String> seen = <String>{};
  Future<void> addRoot(String rel, String origin) async {
    try {
      final String p = await fs.resolve(rel, ag, convId);
      if (seen.add(p)) roots.add(MapEntry<String, String>(p, origin));
    } catch (_) {}
  }

  await addRoot('.claude/skills', 'project');
  final String sd = w.startDir.trim();
  if (sd.startsWith('/') || sd.startsWith('~')) await addRoot('$sd/.claude/skills', 'project');
  await addRoot('~/.claude/skills', 'user');

  final List<_WsSkill> out = <_WsSkill>[];
  final Set<String> names = <String>{};
  for (final MapEntry<String, String> r in roots) {
    final List<FsEntry> ents = await _tryList(fs, r.key);
    int n = 0;
    for (final FsEntry e in ents) {
      if (!e.isDir || e.name.startsWith('.')) continue;
      n++;
      if (n > 50) break;
      final String dir = '${r.key}/${e.name}';
      final String? txt = await _tryReadText(fs, '$dir/SKILL.md', 12000);
      if (txt == null) continue;
      final ParsedSkill ps = parseSkillMd(txt);
      final String nm = skillSlug(ps.name.isEmpty ? e.name : ps.name);
      if (nm.isEmpty || !names.add(nm)) continue;
      out.add(_WsSkill(nm, ps.description, dir, r.value));
    }
  }
  return out;
}

String _skillResult(Skill s) {
  final StringBuffer b = StringBuffer('# Skill: ${s.name}\n');
  if (s.description.isNotEmpty) b.write('${s.description}\n');
  b.write('\n');
  String body = s.body;
  if (body.length > kSkillResultMax) body = '${body.substring(0, kSkillResultMax)}\n…[truncated]';
  b.write(body);
  if (s.files.isNotEmpty) {
    b.write('\n\n---\nBundled files (read one with $kToolUseSkill {"name": "${s.name}", "file": "<path>"}):\n');
    final List<String> keys = s.files.keys.toList()..sort();
    for (final String k in keys) {
      b.write('- $k (${s.files[k]?.length ?? 0} chars)\n');
    }
  }
  return b.toString().trimRight();
}

Future<ToolOutcome> _loadWorkspaceSkill(_WsSkill w, String file) async {
  final FsBackend fs = currentFs();
  if (file.isNotEmpty) {
    final String rel = file.startsWith('./') ? file.substring(2) : file;
    if (rel.startsWith('/') || rel.split('/').contains('..')) {
      return const ToolOutcome('file must be a relative path inside the skill folder', true);
    }
    final String? t = await _tryReadText(fs, '${w.dir}/$rel', kSkillResultMax);
    if (t == null) return ToolOutcome('Cannot read ${w.dir}/$rel (missing, unreadable or binary).', true);
    return ToolOutcome(t, false);
  }
  final String? raw = await _tryReadText(fs, '${w.dir}/SKILL.md', kSkillMaxBody);
  if (raw == null) return ToolOutcome('Cannot read ${w.dir}/SKILL.md', true);
  final ParsedSkill ps = parseSkillMd(raw);
  final StringBuffer b = StringBuffer('# Skill: ${w.name} (${w.origin == 'user' ? 'from the ~/.claude/skills folder of the workspace' : 'from this project'})\n');
  b.write('Skill folder: ${w.dir}\n\n');
  String body = ps.body;
  if (body.length > kSkillResultMax) body = '${body.substring(0, kSkillResultMax)}\n…[truncated]';
  b.write(body);
  final List<FsEntry> ents = await _tryList(fs, w.dir);
  final List<String> others = <String>[];
  for (final FsEntry e in ents) {
    if (e.name == 'SKILL.md') continue;
    others.add(e.isDir ? '${e.name}/' : e.name);
  }
  if (others.isNotEmpty) {
    b.write('\n\n---\nOther files in the skill folder: ${others.take(40).join(', ')}\n'
        'Read them with $kToolUseSkill {"name": "${w.name}", "file": "<relative path>"} or read_file; scripts can be run with bash.');
  }
  return ToolOutcome(b.toString(), false);
}

Future<ToolOutcome> _toolUseSkill(Map<String, dynamic> a, String convId) async {
  final String q = asStr(a['name']).trim();
  final String file = asStr(a['file']).trim();
  final List<Skill> local = enabledSkills();
  if (q.isEmpty) {
    final List<_WsSkill> ws = await _discoverWorkspaceSkills(convId);
    if (local.isEmpty && ws.isEmpty) return const ToolOutcome('No skills are installed or found in the workspace.', false);
    final StringBuffer b = StringBuffer('Available skills (call $kToolUseSkill with the name):\n');
    for (final Skill s in local) {
      b.write('- ${s.name}: ${clip(s.description.replaceAll('\n', ' '), 200)}\n');
    }
    for (final _WsSkill s in ws) {
      b.write('- ${s.name} [${s.origin == 'user' ? 'workspace ~/.claude/skills' : 'this project'}]: ${clip(s.description.replaceAll('\n', ' '), 200)}\n');
    }
    return ToolOutcome(b.toString().trimRight(), false);
  }
  final Skill? sk = _matchSkill(local, q);
  if (sk != null) {
    if (file.isEmpty) return ToolOutcome(_skillResult(sk), false);
    final String rel = file.startsWith('./') ? file.substring(2) : file;
    final String? c = sk.files[rel];
    if (c == null) {
      final List<String> keys = sk.files.keys.toList()..sort();
      return ToolOutcome('No such bundled file: $rel. Available: ${keys.isEmpty ? '(none)' : keys.join(', ')}', true);
    }
    return ToolOutcome(c.length > kSkillResultMax ? '${c.substring(0, kSkillResultMax)}\n…[truncated]' : c, false);
  }
  final List<_WsSkill> ws = await _discoverWorkspaceSkills(convId);
  final _WsSkill? hit = _matchWs(ws, q);
  if (hit == null) {
    return ToolOutcome('Skill not found: $q. Call $kToolUseSkill with no name to list the available skills.', true);
  }
  return await _loadWorkspaceSkill(hit, file);
}

// ---------------------------------------------------------------------
//  استيراد من GitHub (مستودعات عامة): شجرة المستودع بطلب واحد ثم تنزيل الملفات من raw
// ---------------------------------------------------------------------
class GhRef {
  final String owner;
  final String repo;
  final List<String> rest;
  final bool hasBranch;
  const GhRef(this.owner, this.repo, this.rest, this.hasBranch);
}

GhRef? parseGithubRef(String input) {
  String s = input.trim();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
  s = s.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
  final int q = s.indexOf(RegExp(r'[?#]'));
  if (q >= 0) s = s.substring(0, q);
  List<String> seg = s.split('/').where((String x) => x.isNotEmpty).toList();
  if (seg.isEmpty) return null;
  final RegExp ok = RegExp(r'^[A-Za-z0-9_.\-]+$');
  if (seg.first.toLowerCase() == 'raw.githubusercontent.com') {
    seg = seg.sublist(1);
    if (seg.length < 3) return null;
    return GhRef(seg[0], seg[1], seg.sublist(2), true);
  }
  if (seg.first.toLowerCase() == 'github.com') {
    seg = seg.sublist(1);
  } else if (seg.first.contains('.')) {
    return null;
  }
  if (seg.length < 2) return null;
  final String owner = seg[0];
  String repo = seg[1];
  if (repo.endsWith('.git')) repo = repo.substring(0, repo.length - 4);
  if (!ok.hasMatch(owner) || !ok.hasMatch(repo)) return null;
  final List<String> tail = seg.sublist(2);
  if (tail.length >= 2 && (tail[0] == 'tree' || tail[0] == 'blob')) return GhRef(owner, repo, tail.sublist(1), true);
  return GhRef(owner, repo, tail, false);
}

class GhBlob {
  final String path;
  final int size;
  const GhBlob(this.path, this.size);
}

class GhCandidate {
  final String dir;
  final String name;
  const GhCandidate(this.dir, this.name);
}

class GhDiscovery {
  final String owner;
  final String repo;
  final String ref;
  final List<GhBlob> blobs;
  final List<GhCandidate> candidates;
  final bool truncated;
  const GhDiscovery(this.owner, this.repo, this.ref, this.blobs, this.candidates, this.truncated);
}

class GhFetched {
  final Skill skill;
  final int skipped;
  const GhFetched(this.skill, this.skipped);
}

Future<dynamic> _ghGetJson(String url) async {
  final Response<dynamic> r = await httpClient.get<dynamic>(
    url,
    options: Options(
      responseType: ResponseType.json,
      validateStatus: (int? c) => true,
      receiveTimeout: const Duration(seconds: 30),
      headers: <String, dynamic>{'Accept': 'application/vnd.github+json', 'User-Agent': 'LMClient/$kAppVersion'},
    ),
  );
  final int code = r.statusCode ?? 0;
  if (code == 404) return null;
  if (code == 403 || code == 429) throw const ToolError('وصلتَ لحدّ طلبات GitHub (60 في الساعة بدون حساب). جرّب بعد قليل.');
  if (code >= 400) throw ToolError('GitHub: HTTP $code');
  return r.data;
}

String _encPath(String p) => p.split('/').map(Uri.encodeComponent).join('/');

Future<GhDiscovery> ghDiscover(String input) async {
  final GhRef? r = parseGithubRef(input);
  if (r == null) throw const ToolError('الرابط غير مفهوم. مثال: https://github.com/owner/repo أو owner/repo/مسار/المهارة');
  final List<List<String>> splits = <List<String>>[];
  if (!r.hasBranch) {
    splits.add(<String>['HEAD', r.rest.join('/')]);
  } else {
    final int maxK = math.min(4, r.rest.length);
    for (int k = 1; k <= maxK; k++) {
      splits.add(<String>[r.rest.sublist(0, k).join('/'), r.rest.sublist(k).join('/')]);
    }
  }
  for (final List<String> sp in splits) {
    final dynamic data = await _ghGetJson('https://api.github.com/repos/${r.owner}/${r.repo}/git/trees/${Uri.encodeComponent(sp[0])}?recursive=1');
    if (data == null) continue;
    final Map<String, dynamic> m = asMap(data);
    String path = sp[1];
    if (path == 'SKILL.md') {
      path = '';
    } else if (path.endsWith('/SKILL.md')) {
      path = path.substring(0, path.length - '/SKILL.md'.length);
    }
    final String prefix = path.isEmpty ? '' : '$path/';
    final List<GhBlob> blobs = <GhBlob>[];
    for (final dynamic e in asList(m['tree'])) {
      final Map<String, dynamic> t = asMap(e);
      if (asStr(t['type']) != 'blob') continue;
      final String p = asStr(t['path']);
      if (!p.startsWith(prefix)) continue;
      blobs.add(GhBlob(p, toInt(t['size']) ?? 0));
    }
    final List<String> dirs = <String>[];
    for (final GhBlob b in blobs) {
      if (b.path == 'SKILL.md') {
        dirs.add('');
      } else if (b.path.endsWith('/SKILL.md')) {
        dirs.add(b.path.substring(0, b.path.length - '/SKILL.md'.length));
      }
    }
    dirs.sort((String a, String b) => a.length.compareTo(b.length));
    final List<String> top = <String>[];
    for (final String d in dirs) {
      bool nested = false;
      for (final String o in top) {
        if (o.isEmpty || d.startsWith('$o/')) {
          nested = true;
          break;
        }
      }
      if (!nested) top.add(d);
    }
    if (top.isEmpty) throw const ToolError('لم أجد ملف SKILL.md في هذا المسار.');
    top.sort();
    final List<GhCandidate> cands = <GhCandidate>[];
    for (final String d in top.take(60)) {
      cands.add(GhCandidate(d, d.isEmpty ? r.repo : d.split('/').last));
    }
    return GhDiscovery(r.owner, r.repo, sp[0], blobs, cands, m['truncated'] == true);
  }
  throw const ToolError('لم أجد المستودع/الفرع/المسار (يدعم التطبيق المستودعات العامة فقط).');
}

const Set<String> _kBinaryExt = <String>{
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'ico', 'bmp', 'pdf', 'zip', 'gz', 'tgz', 'tar', 'ttf', 'otf', 'woff', 'woff2',
  'mp4', 'mov', 'mp3', 'wav', 'so', 'dll', 'exe', 'jar', 'bin', 'pyc', 'class', 'wasm', 'ogg', 'webm', 'psd', 'sketch',
};

Future<String?> _ghRaw(GhDiscovery d, String path, int maxBytes) async {
  final String url = 'https://raw.githubusercontent.com/${d.owner}/${d.repo}/${_encPath(d.ref)}/${_encPath(path)}';
  final Response<List<int>> r = await httpClient.get<List<int>>(
    url,
    options: Options(
      responseType: ResponseType.bytes,
      validateStatus: (int? c) => true,
      receiveTimeout: const Duration(seconds: 30),
      headers: <String, dynamic>{'User-Agent': 'LMClient/$kAppVersion'},
    ),
  );
  if ((r.statusCode ?? 0) >= 400) return null;
  final List<int> b = r.data ?? <int>[];
  if (b.length > maxBytes || looksBinary(b)) return null;
  return utf8.decode(b, allowMalformed: true);
}

Future<GhFetched> ghFetchSkill(GhDiscovery d, GhCandidate c) async {
  final String base = c.dir.isEmpty ? '' : '${c.dir}/';
  final Set<String> otherSkillDirs = <String>{};
  for (final GhCandidate o in d.candidates) {
    if (o.dir != c.dir && o.dir.isNotEmpty) otherSkillDirs.add('${o.dir}/');
  }
  GhBlob? main;
  final List<GhBlob> others = <GhBlob>[];
  for (final GhBlob b in d.blobs) {
    if (!b.path.startsWith(base)) continue;
    final String rel = b.path.substring(base.length);
    if (rel == 'SKILL.md') {
      main = b;
      continue;
    }
    if (rel.startsWith('.') || rel.contains('/.') || rel.startsWith('node_modules/')) continue;
    bool inOther = false;
    for (final String o in otherSkillDirs) {
      if (b.path.startsWith(o)) {
        inOther = true;
        break;
      }
    }
    if (inOther) continue;
    others.add(b);
  }
  if (main == null) throw const ToolError('SKILL.md غير موجود.');
  if (main.size > kSkillMaxBody) throw const ToolError('SKILL.md أكبر من الحد المسموح (100KB).');
  final String? raw = await _ghRaw(d, main.path, kSkillMaxBody);
  if (raw == null) throw const ToolError('تعذّر تنزيل SKILL.md.');
  final ParsedSkill ps = parseSkillMd(raw);
  String name = skillSlug(ps.name);
  if (name.isEmpty) name = skillSlug(c.name);
  if (name.isEmpty) throw const ToolError('تعذّر تحديد اسم المهارة.');
  others.sort((GhBlob a, GhBlob b) => a.path.compareTo(b.path));
  final Map<String, String> files = <String, String>{};
  int total = 0;
  int skipped = 0;
  for (final GhBlob b in others) {
    final String rel = b.path.substring(base.length);
    final String ext = rel.contains('.') ? rel.split('.').last.toLowerCase() : '';
    if (_kBinaryExt.contains(ext) || b.size > kSkillMaxFile || files.length >= kSkillMaxFiles || total + b.size > kSkillMaxTotal) {
      skipped++;
      continue;
    }
    final String? t = await _ghRaw(d, b.path, kSkillMaxFile);
    if (t == null) {
      skipped++;
      continue;
    }
    files[rel] = t;
    total += t.length;
  }
  final String src = 'github:${d.owner}/${d.repo}${c.dir.isEmpty ? '' : '/${c.dir}'}';
  return GhFetched(
    Skill(
      id: newId(),
      name: name,
      description: ps.description,
      body: ps.body,
      files: files,
      source: src,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    ),
    skipped,
  );
}

// ---------------------------------------------------------------------
//  الواجهة: شاشة المهارات + المحرر + مسارات الإضافة
// ---------------------------------------------------------------------
class SkillsScreen extends ConsumerWidget {
  const SkillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Pal p = pal(context);
    final List<Skill> list = <Skill>[...ref.watch(skillsProvider)];
    list.sort((Skill a, Skill b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(title: const Text('المهارات (Skills)')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addMenu(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('مهارة'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 110),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(12)),
            child: Text(
              'المهارة تعليمات جاهزة لنوع من المهام (مثل: مراجعة كود، كتابة اختبارات، إعداد تقرير). يرى النموذج اسمها ووصفها فقط، ويحمّل نصّها الكامل عند الحاجة، فلا تُثقل المحادثة. '
              'يمكنك استيراد مهارات بصيغة Claude Code (مجلد فيه SKILL.md) من GitHub، وإن كانت بيئة SSH المختارة تحوي مجلد .claude/skills فتُكتشف تلقائياً. '
              'المهارة نص فقط ولا تمنح أي صلاحية: كل أمر أو كتابة يمرّ بموافقاتك المعتادة. راجع محتوى أي مهارة تستوردها من مصدر لا تثق به.',
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.5),
            ),
          ),
          const SectionLabel('المهارات المثبّتة'),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyHint(icon: Icons.auto_awesome, text: 'لا توجد مهارات بعد.\nاستورد من GitHub أو الصق ملف SKILL.md أو اكتب مهارتك.'),
            ),
          ...list.map((Skill sk) => _skillCard(ref, p, sk)),
        ],
      ),
    );
  }

  Widget _skillCard(WidgetRef ref, Pal p, Skill sk) {
    final List<String> meta = <String>[];
    if (sk.source != 'manual') meta.add(sk.source);
    if (sk.files.isNotEmpty) meta.add('${sk.files.length} ملف مرفق');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sk.enabled ? p.accent.withAlpha(120) : p.border),
      ),
      child: ListTile(
        onTap: () => pushScreen(SkillEditor(existing: sk)),
        title: Directionality(
          textDirection: TextDirection.ltr,
          child: Text(sk.name, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '${clip(sk.description.replaceAll('\n', ' '), 150)}${meta.isEmpty ? '' : '\n${meta.join(' · ')}'}',
            style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
          ),
        ),
        isThreeLine: true,
        trailing: Switch(
          value: sk.enabled,
          onChanged: (bool v) => ref.read(skillsProvider.notifier).upsert(sk.copyWith(enabled: v)),
        ),
      ),
    );
  }

  Future<void> _addMenu(BuildContext context, WidgetRef ref) async {
    final String? v = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('استيراد من GitHub'),
            subtitle: const Text('رابط مجلد مهارة، أو مستودع فيه عدة مهارات'),
            onTap: () => Navigator.pop(c, 'gh'),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('لصق ملف SKILL.md'),
            subtitle: const Text('يُستخرج الاسم والوصف من رأس الملف'),
            onTap: () => Navigator.pop(c, 'paste'),
          ),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: const Text('كتابة مهارة جديدة'),
            onTap: () => Navigator.pop(c, 'new'),
          ),
        ]),
      ),
    );
    if (v == null || !context.mounted) return;
    if (v == 'gh') {
      await _importGithub(context, ref);
    } else if (v == 'paste') {
      final String? t = await askText(context, 'الصق محتوى SKILL.md', hint: '---\nname: my-skill\ndescription: متى تُستخدم…\n---\nالتعليمات…', multiline: true);
      if (t == null || t.trim().isEmpty) return;
      final ParsedSkill ps = parseSkillMd(t);
      pushScreen(SkillEditor(draft: Skill(id: newId(), name: skillSlug(ps.name), description: ps.description, body: ps.body, addedAt: DateTime.now().millisecondsSinceEpoch)));
    } else {
      pushScreen(const SkillEditor());
    }
  }

  Future<void> _importGithub(BuildContext context, WidgetRef ref) async {
    final String? url = await askText(context, 'استيراد من GitHub', hint: 'https://github.com/owner/repo/tree/main/skills/name');
    if (url == null || url.trim().isEmpty) return;
    toast('جارٍ البحث عن المهارات…');
    try {
      final GhDiscovery d = await ghDiscover(url.trim());
      List<GhCandidate> chosen = d.candidates;
      if (d.candidates.length > 1) {
        if (!context.mounted) return;
        chosen = await _pickCandidates(context, d);
      }
      if (chosen.isEmpty) return;
      int done = 0;
      for (final GhCandidate c in chosen) {
        final GhFetched f = await ghFetchSkill(d, c);
        final Skill sk = f.skill;
        final bool exists = ref.read(skillsProvider.notifier).byName(sk.name) != null;
        final String preview = 'الاسم: ${sk.name}\nالوصف: ${clip(sk.description, 220)}\n'
            'ملفات مرفقة: ${sk.files.length}${f.skipped > 0 ? ' (تخطّيتُ ${f.skipped}: ثنائية أو كبيرة)' : ''}\n'
            'المصدر: ${sk.source}${exists ? '\n⚠ توجد مهارة بالاسم نفسه وستُستبدل.' : ''}\n\n'
            '${clip(sk.body, 500)}\n\nراجع المحتوى كاملاً بعد التثبيت (يُفتح في المحرر).';
        final bool ok = await askConfirm('تثبيت المهارة؟', preview, ok: 'تثبيت', cancel: chosen.length > 1 ? 'تخطّي' : 'إلغاء');
        if (!ok) continue;
        await ref.read(skillsProvider.notifier).install(sk);
        done++;
      }
      if (done > 0) toast('ثُبّتت $done مهارة');
    } on ToolError catch (e) {
      toast(e.message);
    } catch (e) {
      toast('تعذّر الاستيراد: $e');
    }
  }

  Future<List<GhCandidate>> _pickCandidates(BuildContext context, GhDiscovery d) async {
    final Set<int> sel = <int>{};
    final List<int>? r = await showDialog<List<int>>(
      context: context,
      builder: (BuildContext c) => StatefulBuilder(
        builder: (BuildContext c, void Function(void Function()) set) => AlertDialog(
          title: Text('وجدتُ ${d.candidates.length} مهارة${d.truncated ? ' (القائمة قد تكون ناقصة)' : ''}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (int i = 0; i < d.candidates.length; i++)
                  CheckboxListTile(
                    dense: true,
                    value: sel.contains(i),
                    onChanged: (bool? v) => set(() {
                      if (v == true) {
                        sel.add(i);
                      } else {
                        sel.remove(i);
                      }
                    }),
                    title: Directionality(textDirection: TextDirection.ltr, child: Text(d.candidates[i].dir.isEmpty ? d.candidates[i].name : d.candidates[i].dir, style: const TextStyle(fontSize: 13))),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, sel.toList()..sort()), child: const Text('متابعة')),
          ],
        ),
      ),
    );
    if (r == null) return <GhCandidate>[];
    return r.map((int i) => d.candidates[i]).toList();
  }
}

class SkillEditor extends ConsumerStatefulWidget {
  final Skill? existing;
  final Skill? draft;
  const SkillEditor({super.key, this.existing, this.draft});

  @override
  ConsumerState<SkillEditor> createState() => _SkillEditorState();
}

class _SkillEditorState extends ConsumerState<SkillEditor> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _body;

  @override
  void initState() {
    super.initState();
    final Skill? s = widget.existing ?? widget.draft;
    _name = TextEditingController(text: s?.name ?? '');
    _desc = TextEditingController(text: s?.description ?? '');
    _body = TextEditingController(text: s?.body ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = skillSlug(_name.text);
    final String desc = _desc.text.trim();
    final String body = _body.text.trim();
    if (name.isEmpty) {
      toast('اسم المهارة مطلوب (حروف وأرقام وشرطات).');
      return;
    }
    if (desc.isEmpty) {
      toast('الوصف مطلوب: به يقرّر النموذج متى يستخدم المهارة.');
      return;
    }
    if (body.isEmpty) {
      toast('نص التعليمات فارغ.');
      return;
    }
    if (body.length > kSkillMaxBody) {
      toast('النص أكبر من الحد (100KB).');
      return;
    }
    final Skill? base = widget.existing ?? widget.draft;
    final String id = base?.id ?? newId();
    final Skill? clash = ref.read(skillsProvider.notifier).byName(name);
    if (clash != null && clash.id != id) {
      final bool ok = await askConfirm('استبدال مهارة؟', 'توجد مهارة بالاسم "$name" وستُستبدل.', ok: 'استبدال', cancel: 'إلغاء');
      if (!ok) return;
      await ref.read(skillsProvider.notifier).remove(clash.id);
    }
    await ref.read(skillsProvider.notifier).upsert(Skill(
          id: id,
          name: name,
          description: desc,
          body: body,
          files: base?.files ?? const <String, String>{},
          enabled: base?.enabled ?? true,
          source: base?.source ?? 'manual',
          addedAt: base?.addedAt ?? DateTime.now().millisecondsSinceEpoch,
        ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final Skill? s = widget.existing;
    if (s == null) return;
    final bool ok = await askConfirm('حذف المهارة؟', 'ستُحذف "${s.name}" من التطبيق.', ok: 'حذف', cancel: 'إلغاء');
    if (!ok) return;
    await ref.read(skillsProvider.notifier).remove(s.id);
    if (mounted) Navigator.pop(context);
  }

  Widget _field(Pal p, String label, TextEditingController c, {int minLines = 1, int? maxLines = 1, bool mono = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(label, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          minLines: minLines,
          maxLines: maxLines,
          autocorrect: false,
          style: TextStyle(color: p.text, fontSize: 14, fontFamily: mono ? 'monospace' : null),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: p.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    final Skill? ex = widget.existing;
    return Scaffold(
      appBar: AppBar(
        title: Text(ex == null ? 'مهارة جديدة' : 'تعديل المهارة'),
        actions: <Widget>[
          if (ex != null) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'حذف'),
          TextButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 40),
        children: <Widget>[
          _field(p, 'الاسم (حروف وأرقام وشرطات)', _name, mono: true, hint: 'code-review'),
          _field(p, 'الوصف: متى يستخدمها النموذج؟', _desc, minLines: 2, maxLines: 4, hint: 'استخدمها عند مراجعة تغييرات كود قبل الدمج…'),
          _field(p, 'التعليمات (Markdown)', _body, minLines: 12, maxLines: null, mono: true),
          if (ex != null && ex.files.isNotEmpty)
            Text('ملفات مرفقة (للقراءة فقط): ${(ex.files.keys.toList()..sort()).join('، ')}', style: TextStyle(color: p.muted, fontSize: 12, height: 1.5)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  اختبار ذاتي (يُشغَّل من فحص المحاكي في الـ CI): منطق نقي + أداة use_skill + (اختياري) استيراد حقيقي من GitHub
// ---------------------------------------------------------------------
Future<void> runSkillsSelfTest({String ghBranch = ''}) async {
  int fails = 0;
  int total = 0;
  // ignore: avoid_print
  void out(String s) => print('LMPROBE|SKILLS $s');
  void rec(String name, bool ok, String detail) {
    total++;
    if (!ok) fails++;
    final String d = detail.replaceAll('\n', ' ⏎ ');
    out('${ok ? 'OK  ' : 'FAIL'} $name${d.isEmpty ? '' : ' :: ${d.length > 220 ? d.substring(0, 220) : d}'}');
  }

  try {
    final ParsedSkill a = parseSkillMd('---\nname: My-Skill\ndescription: "Does X: and Y"\n---\n# Body\nhello');
    rec('parse quoted', a.name == 'My-Skill' && a.description == 'Does X: and Y' && a.body == '# Body\nhello', '${a.name}|${a.description}|${a.body}');
    final ParsedSkill b = parseSkillMd('---\nname: folded\ndescription: >\n  line one\n  line two\nversion: 1\n---\nBody');
    rec('parse folded', b.name == 'folded' && b.description == 'line one line two' && b.body == 'Body', '${b.name}|${b.description}|${b.body}');
    final ParsedSkill c = parseSkillMd('# Title\nFirst real line\nsecond');
    rec('parse no frontmatter', c.name.isEmpty && c.description == 'First real line' && c.body.startsWith('# Title'), '${c.name}|${c.description}');
    final ParsedSkill d = parseSkillMd('---\r\nname: crlf\r\ndescription: d\r\n---\r\nB');
    rec('parse crlf', d.name == 'crlf' && d.description == 'd' && d.body == 'B', '${d.name}|${d.description}|${d.body}');
    rec('slug', skillSlug('  Hello World_1! ') == 'hello-world_1' && skillSlug('مهارة جديدة') == 'مهارة-جديدة' && skillSlug('--a--b--') == 'a-b', '${skillSlug('  Hello World_1! ')}');
    final GhRef? g1 = parseGithubRef('https://github.com/o/r/tree/main/skills/x');
    final GhRef? g2 = parseGithubRef('o/r/skills/x');
    final GhRef? g3 = parseGithubRef('https://github.com/o/r.git');
    final GhRef? g4 = parseGithubRef('https://example.com/o/r');
    rec(
      'github refs',
      g1 != null && g1.hasBranch && g1.rest.join('/') == 'main/skills/x' && g2 != null && !g2.hasBranch && g2.rest.join('/') == 'skills/x' && g3 != null && g3.repo == 'r' && g4 == null,
      '',
    );
  } catch (e) {
    rec('pure tests', false, '$e');
  }

  try {
    final SkillsNotifier n = appContainer.read(skillsProvider.notifier);
    await n.upsert(const Skill(id: 'ci-skill', name: 'ci-skill', description: 'for tests', body: 'BODY-OK', files: <String, String>{'ref/a.md': 'A-OK'}));
    await n.upsert(const Skill(id: 'ci-off', name: 'ci-off', description: 'disabled', body: 'X', enabled: false));
    final AppSettings s = appContainer.read(settingsProvider);
    final List<ToolDef> tools = availableTools(s, null, hasLibrary: false, hasMemory: false);
    rec('tool exposed', tools.any((ToolDef t) => t.name == kToolUseSkill), '');
    final String sec = skillsPromptSection(null) ?? '';
    rec('prompt section', sec.contains('ci-skill') && !sec.contains('ci-off'), sec);
    final ToolOutcome o1 = await _toolUseSkill(<String, dynamic>{'name': 'ci-skill'}, 'ci');
    rec('load skill', !o1.error && o1.text.contains('BODY-OK') && o1.text.contains('ref/a.md'), o1.text);
    final ToolOutcome o2 = await _toolUseSkill(<String, dynamic>{'name': 'ci-skill', 'file': 'ref/a.md'}, 'ci');
    rec('load bundled file', !o2.error && o2.text == 'A-OK', o2.text);
    final ToolOutcome o3 = await _toolUseSkill(<String, dynamic>{'name': 'nope'}, 'ci');
    rec('unknown skill', o3.error, o3.text);
    final ToolOutcome o4 = await _toolUseSkill(<String, dynamic>{}, 'ci');
    rec('list skills', !o4.error && o4.text.contains('ci-skill') && !o4.text.contains('ci-off'), o4.text);
    final ToolOutcome o5 = await runTool(ToolCall(id: 't1', name: kToolUseSkill, args: <String, dynamic>{'name': 'ci-skill'}), null, s);
    rec('runTool dispatch', !o5.error && o5.text.contains('BODY-OK'), o5.text);
    await n.remove('ci-skill');
    await n.remove('ci-off');
  } catch (e) {
    rec('tool tests', false, '$e');
  }

  // استيراد حقيقي من GitHub (يعتمد على الشبكة: يُسجَّل لكنه لا يُحسب فشلاً)
  if (ghBranch.isNotEmpty) {
    try {
      final GhDiscovery d = await ghDiscover('https://github.com/lias333-hub/LM-Client/tree/$ghBranch/ci/skills');
      final bool found = d.candidates.any((GhCandidate c) => c.dir.endsWith('hello-ci'));
      out('${found ? 'OK  ' : 'FAIL'} NET discover :: ${d.candidates.map((GhCandidate c) => c.dir).join(',')} (ref=${d.ref}, blobs=${d.blobs.length})');
      if (found) {
        final GhCandidate c = d.candidates.firstWhere((GhCandidate c) => c.dir.endsWith('hello-ci'));
        final GhFetched f = await ghFetchSkill(d, c);
        final bool ok = f.skill.name == 'hello-ci' && f.skill.body.contains('HELLO-CI-BODY') && f.skill.files.containsKey('notes.md');
        out('${ok ? 'OK  ' : 'FAIL'} NET fetch :: ${f.skill.name} | ${clip(f.skill.description, 60)} | files=${f.skill.files.keys.join(',')}');
      }
    } catch (e) {
      out('FAIL NET import :: $e');
    }
  }
  out('DONE fails=$fails total=$total');
}
