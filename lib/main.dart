// ============================================================
//  LMClient 2.0 — عميل API ذكي (Agentic) بنمط Claude Code
//  ملف واحد، بدون أي اعتماديات جديدة (نفس pubspec السابق)
// ============================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';

final AppState app = AppState();
final AgentRunner runner = AgentRunner();
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
const _uuid = Uuid();
String newId() => _uuid.v4();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await app.init();
  } catch (e) {
    debugPrint('init error: $e');
  }
  runApp(const LMClientApp());
}

// ============================================================
//  أدوات مساعدة (عربي / اتجاه النص / مسارات)
// ============================================================
bool isRtlChar(int c) =>
    (c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB1D && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF);
bool _isLatin(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0xC0 && c <= 0x24F);

/// اتجاه النص حسب الأغلبية (عربي/لاتيني) — يحل مشكلة اختلاط العربي بالإنجليزي
TextDirection dirOf(String s, {TextDirection fallback = TextDirection.ltr}) {
  int rtl = 0, ltr = 0, n = 0;
  for (final r in s.runes) {
    if (isRtlChar(r)) {
      rtl++;
    } else if (_isLatin(r)) {
      ltr++;
    } else {
      continue;
    }
    if (++n >= 150) break;
  }
  if (rtl == 0 && ltr == 0) return fallback;
  return rtl >= ltr ? TextDirection.rtl : TextDirection.ltr;
}

int estimateTokens(String t) {
  int ar = 0, other = 0;
  for (final r in t.runes) {
    if (isRtlChar(r)) {
      ar++;
    } else {
      other++;
    }
  }
  return (ar / 2.2 + other / 4).ceil();
}

String clip(String s, int max) {
  if (s.length <= max) return s;
  var cut = max;
  if (cut > 0 && s.codeUnitAt(cut - 1) >= 0xD800 && s.codeUnitAt(cut - 1) <= 0xDBFF) cut--;
  return '${s.substring(0, cut)}\n…[تم الاقتطاع: ${s.length - cut} حرف]';
}

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

String normPath(String p) {
  final abs = p.startsWith('/');
  final out = <String>[];
  for (final s in p.split('/')) {
    if (s.isEmpty || s == '.') continue;
    if (s == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(s);
  }
  return (abs ? '/' : '') + out.join('/');
}

T? firstWhereOrNull<T>(Iterable<T> it, bool Function(T) f) {
  for (final e in it) {
    if (f(e)) return e;
  }
  return null;
}

int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
String _str(dynamic v, String d) => v == null ? d : v.toString();
int _int(dynamic v, int d) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? d;
}

bool looksBinary(List<int> b) {
  final n = b.length < 4000 ? b.length : 4000;
  for (var i = 0; i < n; i++) {
    if (b[i] == 0) return true;
  }
  return false;
}

String mimeOf(String ext) {
  switch (ext) {
    case 'png': return 'image/png';
    case 'jpg':
    case 'jpeg': return 'image/jpeg';
    case 'gif': return 'image/gif';
    case 'webp': return 'image/webp';
    case 'pdf': return 'application/pdf';
    default: return 'application/octet-stream';
  }
}

// ============================================================
//  ألوان بنمط Claude
// ============================================================
class Pal {
  final bool dark;
  const Pal(this.dark);
  static Pal of(BuildContext c) => Pal(Theme.of(c).brightness == Brightness.dark);
  // === Fix5 Legendary — Starlight الكاملة (بدون كسر الأسماء القديمة) ===
  Color get bg => dark ? const Color(0xFF0F0F0F) : const Color(0xFFFDFCF8);
  Color get surface => dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  Color get bubble => dark ? const Color(0xFF2A2A28) : const Color(0xFFF2F0E8);
  Color get bubble2 => dark ? const Color(0xFF252520) : const Color(0xFFEDE9DC);
  Color get line => dark ? const Color(0xFF3A3A36) : const Color(0xFFE8E5DB);
  Color get lineSoft => dark ? const Color(0xFF2A2A28) : const Color(0xFFF0F0EC);
  Color get text => dark ? const Color(0xFFF5F3EF) : const Color(0xFF1A1A18);
  Color get sub => dark ? const Color(0xFF9E9B94) : const Color(0xFF7A7872);
  Color get accent => const Color(0xFFD97757);
  Color get accent2 => const Color(0xFFE8A87C);
  Color get accent3 => const Color(0xFFFFC88A);
  Color get code => dark ? const Color(0xFF1A1A18) : const Color(0xFFF6F4EE);
  Color get codeBorder => dark ? const Color(0xFF333330) : const Color(0xFFE8E5DB);
  Color get ok => const Color(0xFF4CAF7A);
  Color get okSoft => dark ? const Color(0xFF2E7D52) : const Color(0xFFE8F5ED);
  Color get warn => const Color(0xFFE8A838);
  Color get bad => const Color(0xFFE57373);
  Color get badSoft => dark ? const Color(0xFF7A3A3A) : const Color(0xFFFFE8E8);
  Color get accentSoft => dark ? const Color(0x33D97757) : const Color(0x1AD97757);
  Color get accentSoft2 => dark ? const Color(0x1AD97757) : const Color(0x0FD97757);
  Color get starGlow => dark ? const Color(0x22FFD700) : const Color(0x14D97757);
  Color get overlay => dark ? const Color(0x66000000) : const Color(0x33000000);
  Color get shadow => dark ? const Color(0x44000000) : const Color(0x14000000);
  Color get shadowSoft => dark ? const Color(0x22000000) : const Color(0x0D000000);
  Color get selection => accent.withOpacity(0.18);
  // شعارات أسطورية
  LinearGradient get starlightGradient => LinearGradient(
        colors: dark ? [const Color(0xFF1E1E1E), const Color(0xFF0F0F0F)] : [const Color(0xFFFFFFFF), const Color(0xFFFDFCF8)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter);
  LinearGradient get accentGradient => const LinearGradient(colors: [Color(0xFFD97757), Color(0xFFE8A87C)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  LinearGradient get codeGradient => LinearGradient(colors: dark ? [const Color(0xFF252520), const Color(0xFF1A1A18)] : [const Color(0xFFFFFDF5), const Color(0xFFF6F4EE)], begin: Alignment.topCenter, end: Alignment.bottomCenter);
  LinearGradient get bubbleGradient => LinearGradient(colors: [bubble, bubble2], begin: Alignment.topCenter, end: Alignment.bottomCenter);
  LinearGradient get shimmerGradient => LinearGradient(colors: dark ? [const Color(0xFF2A2A28), const Color(0xFF3A3A36), const Color(0xFF2A2A28)] : [const Color(0xFFF2F0E8), const Color(0xFFEDE9DC), const Color(0xFFF2F0E8)], begin: Alignment.centerLeft, end: Alignment.centerRight);
}

// ============================================================
//  النماذج (Models)
// ============================================================
class Attachment {
  final String name, mime, path;
  final int size;
  final String? text;
  Attachment({required this.name, required this.mime, required this.path, required this.size, this.text});
  bool get isImage => mime.startsWith('image/');
  Map<String, dynamic> toJson() => {'name': name, 'mime': mime, 'path': path, 'size': size, 'text': text};
  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
      name: '${j['name'] ?? ''}',
      mime: '${j['mime'] ?? 'application/octet-stream'}',
      path: '${j['path'] ?? ''}',
      size: j['size'] is int ? j['size'] as int : 0,
      text: j['text'] as String?);
  String? b64() {
    try {
      final f = File(path);
      // guard: لا تشفّر ملفات ضخمة في الذاكرة (يسبب OOM)
      try { if (f.lengthSync() > 10 * 1024 * 1024) return null; } catch (_) {}
      return base64Encode(f.readAsBytesSync());
    } catch (_) {
      return null;
    }
  }

  // Fix8: نسخة غير متزامنة — تُستدعى من مسارات الشبكة لتجنب تجميد الواجهة
  Future<String?> b64Async() async {
    try {
      final f = File(path);
      try { if (await f.length() > 10 * 1024 * 1024) return null; } catch (_) {}
      return base64Encode(await f.readAsBytes());
    } catch (_) {
      return null;
    }
  }
}

class ToolCall {
  final String id, name;
  final Map<String, dynamic> args;
  final String? error;
  ToolCall({required this.id, required this.name, required this.args, this.error});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'args': args, 'error': error};
  factory ToolCall.fromJson(Map<String, dynamic> j) => ToolCall(
      id: '${j['id']}',
      name: '${j['name']}',
      args: j['args'] is Map ? Map<String, dynamic>.from(j['args'] as Map) : <String, dynamic>{},
      error: j['error'] as String?);
}

/// role: user | assistant | tool | note
class Msg {
  final String id;
  final String role;
  String content;
  String reasoning;
  List<ToolCall> toolCalls;
  String? toolCallId;
  String? toolName;
  String status; // ok | error | denied | ''
  List<Attachment> files;
  DateTime time;
  bool excluded;
  bool auto;
  Msg({
    String? id,
    required this.role,
    this.content = '',
    this.reasoning = '',
    List<ToolCall>? toolCalls,
    this.toolCallId,
    this.toolName,
    this.status = '',
    List<Attachment>? files,
    DateTime? time,
    this.excluded = false,
    this.auto = false,
  })  : id = id ?? newId(),
        toolCalls = toolCalls ?? [],
        files = files ?? [],
        time = time ?? DateTime.now();

  String promptText() {
    final b = StringBuffer(content);
    for (final f in files) {
      if (f.text != null) {
        b.write('\n\n[File: ${f.name}]\n${f.text}');
      } else if (!f.isImage && f.mime != 'application/pdf') {
        b.write('\n\n[File: ${f.name} (${fmtSize(f.size)}) — binary, stored in library; not readable inline]');
      }
    }
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'reasoning': reasoning,
        'toolCalls': toolCalls.map((e) => e.toJson()).toList(),
        'toolCallId': toolCallId,
        'toolName': toolName,
        'status': status,
        'files': files.map((e) => e.toJson()).toList(),
        'time': time.toIso8601String(),
        'excluded': excluded,
        'auto': auto,
      };

  factory Msg.fromJson(Map<String, dynamic> j) {
    final files = <Attachment>[];
    if (j['files'] is List) {
      for (final f in j['files'] as List) {
        files.add(Attachment.fromJson(Map<String, dynamic>.from(f as Map)));
      }
    } else if (j['fileNames'] is List) {
      for (final n in j['fileNames'] as List) {
        files.add(Attachment(name: '$n', mime: 'text/plain', path: '', size: 0));
      }
    }
    final calls = <ToolCall>[];
    if (j['toolCalls'] is List) {
      for (final t in j['toolCalls'] as List) {
        calls.add(ToolCall.fromJson(Map<String, dynamic>.from(t as Map)));
      }
    }
    return Msg(
      id: j['id'] as String?,
      role: '${j['role'] ?? 'user'}',
      content: '${j['content'] ?? ''}',
      reasoning: '${j['reasoning'] ?? ''}',
      toolCalls: calls,
      toolCallId: j['toolCallId'] as String?,
      toolName: j['toolName'] as String?,
      status: '${j['status'] ?? ''}',
      files: files,
      time: DateTime.tryParse('${j['time'] ?? ''}'),
      excluded: j['excluded'] == true,
      auto: j['auto'] == true,
    );
  }
}

class Todo {
  String text;
  String status; // pending | in_progress | completed
  Todo(this.text, this.status);
  Map<String, dynamic> toJson() => {'text': text, 'status': status};
  factory Todo.fromJson(Map<String, dynamic> j) => Todo('${j['text'] ?? ''}', '${j['status'] ?? 'pending'}');
}

class Conversation {
  final String id;
  String title;
  String? projectId;
  DateTime updated;
  List<Msg> msgs = [];
  List<Todo> todos = [];
  bool loaded = false;
  Conversation({required this.id, this.title = 'محادثة جديدة', this.projectId, DateTime? updated})
      : updated = updated ?? DateTime.now();
  Map<String, dynamic> metaJson() =>
      {'id': id, 'title': title, 'projectId': projectId, 'updated': updated.toIso8601String()};
  factory Conversation.fromMeta(Map<String, dynamic> j) => Conversation(
      id: '${j['id']}',
      title: '${j['title'] ?? 'محادثة'}',
      projectId: j['projectId'] as String?,
      updated: DateTime.tryParse('${j['updated'] ?? ''}'));
}

class Project {
  final String id;
  String name, instructions, folder;
  String systemPrompt;
  Project({required this.id, required this.name, this.instructions = '', this.systemPrompt = '', String? folder})
      : folder = folder ?? 'p_${id.length > 6 ? id.substring(0, 6) : id}';
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'instructions': instructions, 'systemPrompt': systemPrompt, 'folder': folder};
  factory Project.fromJson(Map<String, dynamic> j) => Project(
      id: '${j['id']}',
      name: '${j['name'] ?? ''}',
      instructions: '${j['instructions'] ?? ''}',
      systemPrompt: '${j['systemPrompt'] ?? j['instructions'] ?? ''}',
      folder: j['folder'] as String?);
}

class MemoryPart {
  final String id;
  String title, content;
  bool pinned;
  MemoryPart({required this.id, required this.title, required this.content, this.pinned = false});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'content': content, 'pinned': pinned};
  factory MemoryPart.fromJson(Map<String, dynamic> j) => MemoryPart(
      id: '${j['id']}', title: '${j['title'] ?? ''}', content: '${j['content'] ?? ''}', pinned: j['pinned'] == true);
}

class LibItem {
  final String id, name, path, mime;
  final int size;
  final DateTime time;
  LibItem({required this.id, required this.name, required this.size, required this.time, this.path = '', this.mime = ''});
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'size': size, 'time': time.toIso8601String(), 'path': path, 'mime': mime};
  factory LibItem.fromJson(Map<String, dynamic> j) => LibItem(
      id: '${j['id']}',
      name: '${j['name'] ?? ''}',
      size: j['size'] is int ? j['size'] as int : 0,
      time: DateTime.tryParse('${j['time'] ?? ''}') ?? DateTime.now(),
      path: '${j['path'] ?? ''}',
      mime: '${j['mime'] ?? ''}');
}

/// Agent = مجموعة صلاحيات + تعليمات. المسارات الفارغة تعني: مجلد العمل فقط (وليس الكل)
class Agent {
  final String id;
  String name, systemPrompt, approval; // approval: ask | edits | auto
  List<String> allowedPaths, allowedApps;
  bool canRead, canWrite, canExecute, canNet;
  Agent({
    required this.id,
    required this.name,
    this.systemPrompt = '',
    List<String>? allowedPaths,
    List<String>? allowedApps,
    this.canRead = true,
    this.canWrite = true,
    this.canExecute = false,
    this.canNet = false,
    this.approval = 'ask',
  })  : allowedPaths = allowedPaths ?? [],
        allowedApps = allowedApps ?? [];
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'systemPrompt': systemPrompt,
        'allowedPaths': allowedPaths,
        'allowedApps': allowedApps,
        'canRead': canRead,
        'canWrite': canWrite,
        'canExecute': canExecute,
        'canNet': canNet,
        'approval': approval,
      };
  factory Agent.fromJson(Map<String, dynamic> j) => Agent(
        id: '${j['id']}',
        name: '${j['name'] ?? 'Agent'}',
        systemPrompt: '${j['systemPrompt'] ?? ''}',
        allowedPaths: List<String>.from((j['allowedPaths'] as List?) ?? []),
        allowedApps: List<String>.from((j['allowedApps'] as List?) ?? []),
        canRead: j['canRead'] != false,
        canWrite: j['canWrite'] == true,
        canExecute: j['canExecute'] == true,
        canNet: j['canNet'] == true,
        approval: '${j['approval'] ?? 'ask'}',
      );
}

class Workflow {
  final String id;
  String name, desc;
  List<String> steps;
  Workflow({required this.id, required this.name, this.desc = '', List<String>? steps}) : steps = steps ?? [];
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'desc': desc, 'steps': steps};
  factory Workflow.fromJson(Map<String, dynamic> j) => Workflow(
      id: '${j['id']}',
      name: '${j['name'] ?? ''}',
      desc: '${j['desc'] ?? ''}',
      steps: List<String>.from((j['steps'] as List?) ?? []));
  /// يوسّع القوالب: $ARGS, $ARG1..$ARGn, $PREV, $WORKSPACE, $PROJECT
  String expandStep(String raw, {required String args, required String prev, required String workspace, required String projectName}) {
    var s = raw;
    // تقسيم الوسائط
    final parts = args.trim().split(RegExp(r'\s+'));
    s = s.replaceAll('\$ARGS', args);
    s = s.replaceAll('\$ARG0', args);
    for (var i = 0; i < parts.length && i < 9; i++) {
      s = s.replaceAll('\$ARG${i + 1}', parts[i]);
    }
    s = s.replaceAll('\$PREV', prev);
    s = s.replaceAll('\$WORKSPACE', workspace);
    s = s.replaceAll('\$PROJECT', projectName);
    return s;
  }
}

/// بروفايل API — kind: openai (أي خدمة متوافقة مع OpenAI) | anthropic (Messages API الأصلي)
class ApiProfile {
  String id, name, kind, baseUrl, apiKey, model, chatPath, modelsPath, systemRole, extraBody;
  List<String> models;
  Map<String, String> headers;
  double? temperature;
  int? maxTokens;
  bool stream, tools;
  ApiProfile({
    required this.id,
    required this.name,
    this.kind = 'openai',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    List<String>? models,
    this.chatPath = '',
    this.modelsPath = '',
    this.systemRole = 'system',
    this.extraBody = '',
    Map<String, String>? headers,
    this.temperature,
    this.maxTokens,
    this.stream = true,
    this.tools = true,
  })  : models = models ?? [],
        headers = headers ?? {};
  String get chatEndpointPath => chatPath.isNotEmpty ? chatPath : (kind == 'anthropic' ? '/v1/messages' : '/v1/chat/completions');
  String get modelsEndpointPath => modelsPath.isNotEmpty ? modelsPath : '/v1/models';
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'models': models,
        'chatPath': chatPath,
        'modelsPath': modelsPath,
        'systemRole': systemRole,
        'extraBody': extraBody,
        'headers': headers,
        'temperature': temperature,
        'maxTokens': maxTokens,
        'stream': stream,
        'tools': tools,
      };
  factory ApiProfile.fromJson(Map<String, dynamic> j) => ApiProfile(
        id: '${j['id']}',
        name: '${j['name'] ?? 'API'}',
        kind: '${j['kind'] ?? 'openai'}',
        baseUrl: '${j['baseUrl'] ?? ''}',
        apiKey: '${j['apiKey'] ?? ''}',
        model: '${j['model'] ?? j['selectedModel'] ?? ''}',
        models: List<String>.from((j['models'] as List?) ?? []),
        chatPath: '${j['chatPath'] ?? ''}',
        modelsPath: '${j['modelsPath'] ?? ''}',
        systemRole: '${j['systemRole'] ?? 'system'}',
        extraBody: '${j['extraBody'] ?? ''}',
        headers: j['headers'] is Map
            ? (j['headers'] as Map).map((k, v) => MapEntry('$k', '$v'))
            : <String, String>{},
        temperature: (j['temperature'] as num?)?.toDouble(),
        maxTokens: j['maxTokens'] as int?,
        stream: j['stream'] != false,
        tools: j['tools'] != false,
      );
  ApiProfile copy() => ApiProfile.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
}

// ============================================================
//  التخزين المحلي (ذري: كتابة مؤقتة ثم rename لتفادي تلف الملفات)
// ============================================================
class LocalStorage {
  static Directory? _root;
  static Future<Directory> getDir() async {
    if (_root != null) return _root!;
    final d = await getApplicationDocumentsDirectory();
    final lm = Directory('${d.path}/LMClient');
    if (!await lm.exists()) await lm.create(recursive: true);
    _root = lm;
    return lm;
  }

  static Future<void> save(String folder, String name, String data) async {
    final dir = await getDir();
    final f = Directory('${dir.path}/$folder');
    if (!await f.exists()) await f.create(recursive: true);
    final tmp = File('${f.path}/$name.json.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename('${f.path}/$name.json');
  }

  static Future<String?> load(String folder, String name) async {
    final dir = await getDir();
    final file = File('${dir.path}/$folder/$name.json');
    if (await file.exists()) return await file.readAsString();
    return null;
  }

  static Future<void> delete(String folder, String name) async {
    final dir = await getDir();
    final file = File('${dir.path}/$folder/$name.json');
    if (await file.exists()) await file.delete();
  }
}

// ============================================================
//  حالة التطبيق
// ============================================================
class LiveMsg {
  final String text, reasoning;
  final List<String> tools;
  const LiveMsg(this.text, this.reasoning, this.tools);
}

class Approval {
  final String title, detail, tool;
  final Completer<int> done = Completer<int>();
  Approval(this.title, this.detail, this.tool);
}

/// جسر اختياري للتحكم بالتطبيقات (يحتاج جزء Kotlin أصلي — المرحلة 2).
/// إذا لم يكن موجوداً تختفي أدوات التطبيقات تلقائياً.
class PhoneBridge {
  static const MethodChannel _ch = MethodChannel('lmclient/phone');
  static Future<bool> ping() async {
    try {
      final r = await _ch.invokeMethod<String>('ping');
      return r == 'pong';
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, String>>> listApps() async {
    final r = await _ch.invokeMethod<List<dynamic>>('listApps');
    return (r ?? []).map((e) => Map<String, String>.from(e as Map)).toList();
  }

  static Future<bool> openApp(String pkg) async =>
      (await _ch.invokeMethod<bool>('openApp', {'package': pkg})) ?? false;
  static Future<bool> openUrl(String url) async =>
      (await _ch.invokeMethod<bool>('openUrl', {'url': url})) ?? false;
}

class AppState extends ChangeNotifier {
  final ValueNotifier<int> uiRev = ValueNotifier<int>(0);
  final ValueNotifier<LiveMsg?> live = ValueNotifier<LiveMsg?>(null);
  late Directory root, workspace, libDir;

  // إعدادات
  ThemeMode themeMode = ThemeMode.system;
  bool rtlUi = true, cursorKeys = false, autoContinue = true, planMode = false;
  int maxSteps = 40, compactAt = 120000;
  String replyLang = 'auto'; // auto | ar | en

  // === System Prompt العام (Fix4) ===
  String globalSystemPrompt = '';
  // === Streaming (Fix1) ===
  String streamMode = 'smooth'; // instant | smooth | typewriter
  int typewriterMs = 18;
  int smoothMs = 40;

  String buildSystemPrompt({Agent? forcedAgent, Project? forcedProject}) {
    final ag = forcedAgent ?? (agents.isNotEmpty ? agent : null);
    Project? pr = forcedProject;
    pr ??= cur?.projectId != null ? firstWhereOrNull(projects, (p) => p.id == cur!.projectId) : null;
    final parts = <String>[];
    if (globalSystemPrompt.trim().isNotEmpty) parts.add('# التعليمات العامة\n${globalSystemPrompt.trim()}');
    if (ag != null && ag.systemPrompt.trim().isNotEmpty) parts.add('# تعليمات الوكيل (${ag.name})\n${ag.systemPrompt.trim()}');
    if (pr != null && pr.systemPrompt.trim().isNotEmpty) parts.add('# تعليمات المشروع (${pr.name})\n${pr.systemPrompt.trim()}');
    // ذاكرة مثبتة
    final pinned = memory.where((m) => m.pinned).toList();
    if (pinned.isNotEmpty) parts.add('# ذاكرة مهمة\n${pinned.map((m) => '- ${m.title}: ${m.content}').join('\n')}');
    return parts.join('\n\n');
  }

  // بيانات
  List<ApiProfile> profiles = [];
  String? profileId, agentId;
  List<Agent> agents = [];
  List<Project> projects = [];
  List<MemoryPart> memory = [];
  List<LibItem> library = [];
  List<Workflow> workflows = [];
  List<Conversation> convs = [];
  Conversation? cur;

  // حالة التشغيل
  bool running = false, stopRequested = false, bridgeOk = false;
  String status = '';
  CancelToken? cancel;
  Approval? pending;
  final Set<String> sessionAllow = {};

  ApiProfile? get profile => firstWhereOrNull(profiles, (p) => p.id == profileId);
  Agent get agent => firstWhereOrNull(agents, (a) => a.id == agentId) ?? agents.first;
  void refresh() => notifyListeners();

  // ---------------- تحميل ----------------
  Future<void> init() async {
    root = await LocalStorage.getDir();
    workspace = Directory('${root.path}/workspace');
    libDir = Directory('${root.path}/library/files');
    await workspace.create(recursive: true);
    await libDir.create(recursive: true);
    final prefs = await SharedPreferences.getInstance();
    _loadSettings(prefs);
    _loadProfiles(prefs);
    agents = await _loadList<Agent>('agents', 'list', Agent.fromJson);
    projects = await _loadList<Project>('projects', 'list', Project.fromJson);
    memory = await _loadList<MemoryPart>('memory', 'parts', MemoryPart.fromJson);
    library = await _loadList<LibItem>('library', 'items', LibItem.fromJson);
    workflows = await _loadList<Workflow>('workflows', 'list', Workflow.fromJson);
    await _loadConvs();
    await _ensureDefaults();
    bridgeOk = await PhoneBridge.ping();
    cur = Conversation(id: newId())..loaded = true;
  }

  Future<List<T>> _loadList<T>(String folder, String name, T Function(Map<String, dynamic>) f) async {
    try {
      final s = await LocalStorage.load(folder, name);
      if (s == null) return [];
      return (jsonDecode(s) as List).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  void _loadSettings(SharedPreferences prefs) {
    final s = prefs.getString('lm_settings');
    if (s == null) return;
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      themeMode = ThemeMode.values.firstWhere((m) => m.name == j['theme'], orElse: () => ThemeMode.system);
      rtlUi = j['rtl'] != false;
      cursorKeys = j['cursorKeys'] == true;
      autoContinue = j['autoContinue'] != false;
      maxSteps = _int(j['maxSteps'], 40);
      compactAt = _int(j['compactAt'], 120000);
      replyLang = '${j['replyLang'] ?? 'auto'}';
      globalSystemPrompt = '${j['globalSystemPrompt'] ?? ''}';
      streamMode = '${j['streamMode'] ?? 'smooth'}';
      typewriterMs = _int(j['typewriterMs'], 18);
      smoothMs = _int(j['smoothMs'], 40);
      agentId = j['agentId'] as String?;
    } catch (_) {}
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'lm_settings',
        jsonEncode({
          'theme': themeMode.name,
          'rtl': rtlUi,
          'cursorKeys': cursorKeys,
          'autoContinue': autoContinue,
          'maxSteps': maxSteps,
          'compactAt': compactAt,
          'replyLang': replyLang,
          'globalSystemPrompt': globalSystemPrompt,
          'streamMode': streamMode,
          'typewriterMs': typewriterMs,
          'smoothMs': smoothMs,
          'agentId': agentId,
        }));
    uiRev.value++;
    notifyListeners();
  }

  void _loadProfiles(SharedPreferences prefs) {
    final js = prefs.getString('profiles');
    if (js != null) {
      try {
        profiles = (jsonDecode(js) as List)
            .map((e) => ApiProfile.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {}
    }
    profileId = prefs.getString('selected_profile');
    if (profiles.isEmpty) {
      final u = prefs.getString('api_baseUrl');
      if (u != null && u.isNotEmpty) {
        final p = ApiProfile(
            id: newId(),
            name: 'الحساب السابق',
            baseUrl: u,
            apiKey: prefs.getString('api_key') ?? '',
            model: prefs.getString('api_model') ?? '');
        profiles = [p];
        profileId = p.id;
      }
    }
    if (profileId == null && profiles.isNotEmpty) profileId = profiles.first.id;
  }

  Future<void> saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profiles', jsonEncode(profiles.map((e) => e.toJson()).toList()));
    if (profileId != null) await prefs.setString('selected_profile', profileId!);
    notifyListeners();
  }

  Future<void> _ensureDefaults() async {
    if (agents.isEmpty) {
      agents = [Agent(id: newId(), name: 'الافتراضي (مجلد العمل فقط)', canRead: true, canWrite: true)];
      await saveAgents();
    }
    if (workflows.isEmpty) {
      workflows = [
        Workflow(id: newId(), name: 'بناء مشروع كامل', desc: 'خطة ← تنفيذ ← مراجعة', steps: [
          'حلّل المتطلبات التالية واكتب خطة تفصيلية عبر todo_write دون تنفيذ أي ملفات بعد: \$ARGS',
          'نفّذ الخطة خطوة بخطوة: أنشئ هيكل المجلدات والملفات واكتب الكود كاملاً بلا اختصارات، وحدّث المهام أولاً بأول.',
          'راجع كل ما أنشأته: اقرأ الملفات الرئيسية، أصلح الأخطاء، ثم اكتب README.md يشرح الاستخدام، وأعطني ملخصاً نهائياً قصيراً.',
        ]),
        Workflow(id: newId(), name: 'مراجعة الكود', desc: 'يفحص مجلد العمل ويقترح تحسينات', steps: [
          'استكشف بنية مجلد العمل واقرأ الملفات الأساسية، ثم راجع الكود بحثاً عن الأخطاء والثغرات وسوء التصميم، وأعطني تقريراً مرتباً بالأولوية. \$ARGS',
        ]),
        Workflow(id: newId(), name: 'تلخيص ملفات المكتبة', desc: 'يقرأ ملفات المكتبة ويلخصها', steps: [
          'استخدم library_search و library_read لقراءة الملفات المتعلقة بـ: \$ARGS ثم لخّصها بنقاط واضحة.',
        ]),
      ];
      await saveWorkflows();
    }
    agentId ??= agents.first.id;
  }

  Future<void> _loadConvs() async {
    final s = await LocalStorage.load('conversations', 'index');
    if (s != null) {
      try {
        convs = (jsonDecode(s) as List)
            .map((e) => Conversation.fromMeta(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {}
    }
    if (convs.isEmpty) {
      final old = await LocalStorage.load('chats', 'current'); // ترحيل من النسخة القديمة
      if (old != null) {
        try {
          final list = jsonDecode(old) as List;
          if (list.isNotEmpty) {
            final c = Conversation(id: newId(), title: 'محادثة سابقة');
            c.msgs = list.map((e) => Msg.fromJson(Map<String, dynamic>.from(e as Map))).toList();
            c.loaded = true;
            await saveConv(c);
          }
        } catch (_) {}
      }
    }
    convs.sort((a, b) => b.updated.compareTo(a.updated));
  }

  // ---------------- حفظ القوائم ----------------
  Future<void> _saveList(String f, String n, List<Map<String, dynamic>> data) async {
    try {
      await LocalStorage.save(f, n, jsonEncode(data));
    } catch (e) {
      debugPrint('save $f/$n failed: $e');
    }
    notifyListeners();
  }

  Future<void> saveAgents() => _saveList('agents', 'list', agents.map((e) => e.toJson()).toList());
  Future<void> saveProjects() => _saveList('projects', 'list', projects.map((e) => e.toJson()).toList());
  Future<void> saveMemory() => _saveList('memory', 'parts', memory.map((e) => e.toJson()).toList());
  Future<void> saveLibrary() => _saveList('library', 'items', library.map((e) => e.toJson()).toList());
  Future<void> saveWorkflows() => _saveList('workflows', 'list', workflows.map((e) => e.toJson()).toList());

  // ---------------- المحادثات ----------------
  Future<void> saveIndex() async {
    await LocalStorage.save('conversations', 'index', jsonEncode(convs.map((c) => c.metaJson()).toList()));
  }

  Future<void> saveConv(Conversation c) async {
    c.updated = DateTime.now();
    if (c.msgs.isEmpty && !convs.contains(c)) return;
    convs.remove(c);
    convs.insert(0, c);
    try {
      await LocalStorage.save(
          'conv',
          c.id,
          jsonEncode({
            'msgs': c.msgs.map((m) => m.toJson()).toList(),
            'todos': c.todos.map((t) => t.toJson()).toList(),
          }));
      await saveIndex();
    } catch (e) {
      debugPrint('saveConv failed: $e');
    }
  }

  Future<void> loadConv(Conversation c) async {
    final s = await LocalStorage.load('conv', c.id);
    if (s != null) {
      try {
        final j = jsonDecode(s);
        if (j is Map) {
          c.msgs = ((j['msgs'] as List?) ?? [])
              .map((e) => Msg.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          c.todos = ((j['todos'] as List?) ?? [])
              .map((e) => Todo.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      } catch (_) {}
    }
    c.loaded = true;
  }

  Future<void> newChat({String? projectId}) async {
    if (running) {
      toast('أوقف التنفيذ الحالي أولاً');
      return;
    }
    final c = cur;
    if (c != null && c.msgs.isEmpty && c.projectId == projectId) {
      notifyListeners();
      return;
    }
    cur = Conversation(id: newId(), projectId: projectId)..loaded = true;
    sessionAllow.clear();
    notifyListeners();
  }

  Future<void> openChat(Conversation c) async {
    if (running) {
      toast('أوقف التنفيذ الحالي أولاً');
      return;
    }
    if (!c.loaded) await loadConv(c);
    cur = c;
    sessionAllow.clear();
    notifyListeners();
  }

  Future<void> deleteConv(Conversation c) async {
    if (running && cur == c) return;
    convs.remove(c);
    try {
      await LocalStorage.delete('conv', c.id);
      await saveIndex();
    } catch (_) {}
    if (cur == c) {
      cur = null;
      await newChat();
    }
    notifyListeners();
  }

  Future<void> renameConv(Conversation c, String t) async {
    c.title = t.trim().isEmpty ? c.title : t.trim();
    await saveConv(c);
    notifyListeners();
  }

  String cwdFor(Conversation c) {
    final pr = firstWhereOrNull(projects, (p) => p.id == c.projectId);
    final d = Directory('${workspace.path}/${pr?.folder ?? 'general'}');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  // Fix8: نسخة غير متزامنة — لا تجمّد الواجهة
  Future<String> cwdForAsync(Conversation c) async {
    final pr = firstWhereOrNull(projects, (p) => p.id == c.projectId);
    final d = Directory('${workspace.path}/${pr?.folder ?? 'general'}');
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  // ---------------- الموافقات ----------------
  Future<int> askApproval(String title, String detail, String tool) {
    final a = Approval(title, detail, tool);
    pending = a;
    status = 'بانتظار موافقتك…';
    notifyListeners();
    return a.done.future;
  }

  /// 0 = رفض، 1 = مرة واحدة، 2 = دائماً في هذه الجلسة
  void answerApproval(int r) {
    final a = pending;
    if (a == null) return;
    if (r == 2) sessionAllow.add(a.tool);
    pending = null;
    if (!a.done.isCompleted) a.done.complete(r == 0 ? 0 : 1);
    notifyListeners();
  }

  void stop() {
    if (!running) return;
    stopRequested = true;
    cancel?.cancel('stopped');
    if (pending != null) answerApproval(0);
    status = 'يتوقف…';
    notifyListeners();
  }

  bool needsApproval(ToolDef d) {
    final a = agent;
    if (a.approval == 'auto') return false;
    if (sessionAllow.contains(d.name)) return false;
    switch (d.kind) {
      case 'read':
      case 'meta':
        return false;
      case 'write':
        return a.approval == 'ask';
      default:
        return true; // exec / net / app / danger
    }
  }

  void toast(String m) {
    final s = messengerKey.currentState;
    if (s == null) return;
    s.hideCurrentSnackBar();
    s.showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------- الملفات والمكتبة — Fix6: حد حجم + ترميز آمن + مسار محصّن ----------------
  static const int kMaxLibraryFileBytes = 20 * 1024 * 1024; // 20MB — سد ثغرة إغراق التخزين
  Future<Attachment> importBytes(String name, List<int> bytes) async {
    if (bytes.length > kMaxLibraryFileBytes) throw 'الملف كبير جداً: ${fmtSize(bytes.length)} — الحد $kMaxLibraryFileBytes بايت (20MB)';
    final id = newId();
    var safe = clip(name.trim(), 180).replaceAll(RegExp(r'[^\w\.\- \u0600-\u06FF]'), '_');
    if (safe.isEmpty) safe = 'file';
    if (safe.length > 100) safe = safe.substring(0, 100);
    final path = '${libDir.path}/${id.substring(0, 8)}_$safe';
    final norm = normPath(path);
    if (!norm.startsWith(normPath(libDir.path))) throw 'مسار غير صالح';
    await File(norm).writeAsBytes(bytes, flush: true);
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    var mime = mimeOf(ext);
    String? text;
    if (!mime.startsWith('image/') && mime != 'application/pdf' && !looksBinary(bytes)) {
      // فك ترميز آمن: جرّب utf8 أولاً، ثم latin1 كـ fallback — يمنع فقدان النص العربي
      try {
        text = clip(utf8.decode(bytes), 30000);
      } catch (_) {
        try {
          text = clip(latin1.decode(bytes), 30000);
        } catch (_) {
          text = clip(utf8.decode(bytes, allowMalformed: true), 30000);
        }
      }
      if (mime == 'application/octet-stream') mime = 'text/plain';
    }
    library.add(LibItem(id: id, name: clip(name.trim(), 180), size: bytes.length, time: DateTime.now(), path: norm, mime: mime));
    await saveLibrary();
    return Attachment(name: clip(name.trim(), 180), mime: mime, path: norm, size: bytes.length, text: text);
  }

  Future<String> exportBackup() async {
    final d = Directory('${root.path}/backups');
    await d.create(recursive: true);
    final f = File('${d.path}/backup_${DateTime.now().millisecondsSinceEpoch}.json');
    final convData = [];
    for (final c in convs) {
      if (!c.loaded) await loadConv(c);
      convData.add({
        'meta': c.metaJson(),
        'msgs': c.msgs.map((m) => m.toJson()).toList(),
        'todos': c.todos.map((t) => t.toJson()).toList(),
      });
    }
    final data = {
      'profiles': profiles.map((p) => {...p.toJson(), 'apiKey': ''}).toList(),
      'agents': agents.map((e) => e.toJson()).toList(),
      'projects': projects.map((e) => e.toJson()).toList(),
      'memory': memory.map((e) => e.toJson()).toList(),
      'workflows': workflows.map((e) => e.toJson()).toList(),
      'conversations': convData,
    };
    await f.writeAsString(jsonEncode(data), flush: true);
    return f.path;
  }
}

// ============================================================
//  الصلاحيات (Sandbox) — فحص المسارات بعد التطبيع وحل الروابط الرمزية
//  (النسخة القديمة كانت تستخدم path.contains وهي قابلة للتجاوز بـ ../)
// ============================================================
class Sandbox {
  final Agent agent;
  final String cwd;
  Sandbox(this.agent, this.cwd);

  static String _real(String abs) {
    var cur = abs;
    final tail = <String>[];
    while (true) {
      try {
        if (FileSystemEntity.typeSync(cur) != FileSystemEntityType.notFound) {
          final r = Directory(cur).existsSync()
              ? Directory(cur).resolveSymbolicLinksSync()
              : File(cur).resolveSymbolicLinksSync();
          return normPath([r, ...tail.reversed].join('/'));
        }
      } catch (_) {}
      final i = cur.lastIndexOf('/');
      if (i <= 0) return abs;
      tail.add(cur.substring(i + 1));
      cur = cur.substring(0, i);
    }
  }

  // Fix8: نسخة غير متزامنة — لا تجمّد خيط الواجهة
  static Future<String> _realAsync(String abs) async {
    var cur = abs;
    final tail = <String>[];
    while (true) {
      try {
        final t = await FileSystemEntity.type(cur);
        if (t != FileSystemEntityType.notFound) {
          final isDir = await Directory(cur).exists();
          final r = isDir
              ? await Directory(cur).resolveSymbolicLinks()
              : await File(cur).resolveSymbolicLinks();
          return normPath([r, ...tail.reversed].join('/'));
        }
      } catch (_) {}
      final i = cur.lastIndexOf('/');
      if (i <= 0) return abs;
      tail.add(cur.substring(i + 1));
      cur = cur.substring(0, i);
    }
  }

  List<String> get roots => [cwd, ...agent.allowedPaths]
      .where((e) => e.trim().isNotEmpty)
      .map((e) {
        try {
          return _real(normPath(e.trim()));
        } catch (_) {
          return normPath(e.trim());
        }
      })
      .toList();

  Future<List<String>> rootsAsync() async {
    final out = <String>[];
    for (final e in [cwd, ...agent.allowedPaths].where((x) => x.trim().isNotEmpty)) {
      try {
        out.add(await _realAsync(normPath(e.trim())));
      } catch (_) {
        out.add(normPath(e.trim()));
      }
    }
    return out;
  }

  bool _inside(String p, List<String> rs) => rs.any((r) => p == r || p.startsWith(r.endsWith('/') ? r : '$r/'));

  String resolve(String p) {
    final t = p.trim();
    if (t.contains('\0')) throw 'مسار غير صالح';
    return normPath(t.startsWith('/') ? t : '$cwd/$t');
  }

  bool allows(String abs) {
    try {
      return _inside(_real(abs), roots);
    } catch (_) {
      return _inside(normPath(abs), roots);
    }
  }

  Future<bool> allowsAsync(String abs) async {
    try {
      return _inside(await _realAsync(abs), await rootsAsync());
    } catch (_) {
      return _inside(normPath(abs), await rootsAsync());
    }
  }

  bool isRoot(String abs) {
    try {
      return roots.contains(_real(abs));
    } catch (_) {
      return roots.contains(normPath(abs));
    }
  }

  Future<bool> isRootAsync(String abs) async {
    try {
      return (await rootsAsync()).contains(await _realAsync(abs));
    } catch (_) {
      return (await rootsAsync()).contains(normPath(abs));
    }
  }

  String check(String p) {
    final abs = resolve(p);
    final ok = allows(abs);
    if (!ok) throw 'المسار خارج الصلاحيات المسموحة: $abs — المسموح: ${roots.join(' ، ')}';
    return abs;
  }

  Future<String> checkAsync(String p) async {
    final abs = resolve(p);
    final ok = await allowsAsync(abs);
    if (!ok) throw 'المسار خارج الصلاحيات المسموحة: $abs — المسموح: ${(await rootsAsync()).join(' ، ')}';
    return abs;
  }
}

// ============================================================
//  تعريف الأدوات
// ============================================================
class ToolDef {
  final String name, kind, desc; // kind: read | write | danger | exec | net | app | meta
  final Map<String, dynamic> props;
  final List<String> req;
  ToolDef(this.name, this.kind, this.desc, this.props, [this.req = const []]);
  Map<String, dynamic> get schema => {'type': 'object', 'properties': props, 'required': req};
}

Map<String, dynamic> _s(String d) => {'type': 'string', 'description': d};
Map<String, dynamic> _i(String d) => {'type': 'integer', 'description': d};

final List<ToolDef> kAllTools = [
  ToolDef('list_dir', 'read', 'List files and folders of a directory. Relative paths resolve from the working directory.',
      {'path': _s('Directory path (default ".")')}),
  ToolDef('read_file', 'read', 'Read a text file with line numbers. Use offset/limit for big files.',
      {'path': _s('File path'), 'offset': _i('1-based first line (default 1)'), 'limit': _i('Max lines (default 2000)')},
      ['path']),
  ToolDef('search_files', 'read', 'Regex search (case-insensitive) inside text files, recursively. Returns file:line: text.',
      {'pattern': _s('Regular expression'), 'path': _s('Directory (default ".")'), 'glob': _s('Optional filename suffix such as ".dart"')},
      ['pattern']),
  ToolDef('write_file', 'write', 'Create or overwrite a file with the COMPLETE content. Parent folders are created automatically.',
      {'path': _s('File path'), 'content': _s('Complete file content')}, ['path', 'content']),
  ToolDef('edit_file', 'write', 'Replace exact text in an existing file. old_str must match exactly and be unique unless replace_all is true.',
      {
        'path': _s('File path'),
        'old_str': _s('Exact text to find'),
        'new_str': _s('Replacement text'),
        'replace_all': {'type': 'boolean', 'description': 'Replace every occurrence'}
      },
      ['path', 'old_str', 'new_str']),
  ToolDef('make_dir', 'write', 'Create a directory (recursive).', {'path': _s('Directory path')}, ['path']),
  ToolDef('delete_path', 'danger', 'Delete a file or a directory (recursive).', {'path': _s('Path to delete')}, ['path']),
  ToolDef('run_shell', 'exec',
      'Run a shell command (sh) on the Android device inside the app sandbox. Only basic toybox tools exist (ls, cat, cp, mv, grep, find, sed...).',
      {'command': _s('Shell command'), 'cwd': _s('Working directory (default: project workspace)'), 'timeout_s': _i('Timeout in seconds (default 60)')},
      ['command']),
  ToolDef('http_request', 'net', 'Make an HTTP request and return the status and the (truncated) text body.', {
    'url': _s('Full URL'),
    'method': _s('GET, POST, PUT, DELETE (default GET)'),
    'headers': {'type': 'object', 'description': 'Request headers'},
    'body': _s('Request body (string)')
  }, ['url']),
  ToolDef('todo_write', 'meta',
      'Create or replace the visible task list for multi-step work. Send the FULL list every time. Keep exactly one item in_progress.', {
    'todos': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'content': {'type': 'string', 'description': 'Task description'},
          'status': {'type': 'string', 'enum': ['pending', 'in_progress', 'completed']}
        },
        'required': ['content', 'status']
      }
    }
  }, ['todos']),
  ToolDef('memory_list', 'meta', 'List titles of saved memory parts.', {}),
  ToolDef('memory_read', 'meta', 'Read one memory part by its title.', {'title': _s('Memory title')}, ['title']),
  ToolDef('memory_save', 'meta', 'Save or update a memory part (long-term notes/preferences about the user or project).',
      {'title': _s('Short title'), 'content': _s('Content to remember')}, ['title', 'content']),
  ToolDef('library_search', 'meta', 'Search the user library (uploaded files) by file name or text content. Empty query lists all.',
      {'query': _s('Search text')}),
  ToolDef('library_read', 'meta', 'Read a text file from the user library by name.', {'name': _s('File name')}, ['name']),
  ToolDef('list_apps', 'app', 'List installed apps the user allowed you to control (label + package).', {}),
  ToolDef('open_app', 'app', 'Open an allowed app by package name.', {'package': _s('Android package name')}, ['package']),
  ToolDef('open_url', 'app', 'Open a URL in the phone browser.', {'url': _s('URL')}, ['url']),
];

ToolDef? toolByName(String n) => firstWhereOrNull(kAllTools, (t) => t.name == n);

List<ToolDef> toolsFor(Agent a, {required bool plan, required bool bridge}) {
  return kAllTools.where((t) {
    switch (t.kind) {
      case 'read':
        return a.canRead;
      case 'write':
      case 'danger':
        return a.canWrite && !plan;
      case 'exec':
        return a.canExecute && !plan;
      case 'net':
        return a.canNet;
      case 'app':
        return bridge && a.allowedApps.isNotEmpty && !plan;
      default:
        return true;
    }
  }).toList();
}

String _cut(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;
String _sh(dynamic v) {
  final s = '$v';
  final i = s.lastIndexOf('/');
  return i >= 0 && i < s.length - 1 ? s.substring(i + 1) : s;
}

String toolTitle(ToolCall tc) {
  final a = tc.args;
  switch (tc.name) {
    case 'list_dir': return 'عرض مجلد ${_sh(a['path'] ?? '.')}';
    case 'read_file': return 'قراءة ${_sh(a['path'])}';
    case 'search_files': return 'بحث: ${_cut('${a['pattern']}', 40)}';
    case 'write_file': return 'كتابة ${_sh(a['path'])}';
    case 'edit_file': return 'تعديل ${_sh(a['path'])}';
    case 'make_dir': return 'إنشاء مجلد ${_sh(a['path'])}';
    case 'delete_path': return 'حذف ${_sh(a['path'])}';
    case 'run_shell': return 'تنفيذ: ${_cut('${a['command']}', 50)}';
    case 'http_request': return 'طلب ${a['method'] ?? 'GET'} ${_cut('${a['url']}', 40)}';
    case 'todo_write': return 'تحديث قائمة المهام';
    case 'memory_save': return 'حفظ في الذاكرة: ${a['title']}';
    case 'memory_read': return 'قراءة من الذاكرة: ${a['title']}';
    case 'memory_list': return 'عرض الذاكرة';
    case 'library_search': return 'بحث بالمكتبة: ${a['query'] ?? ''}';
    case 'library_read': return 'قراءة من المكتبة: ${a['name']}';
    case 'open_app': return 'فتح تطبيق ${a['package']}';
    case 'open_url': return 'فتح رابط';
    case 'list_apps': return 'عرض التطبيقات المسموحة';
    default: return tc.name;
  }
}

String toolDetail(ToolCall tc) {
  final a = tc.args;
  switch (tc.name) {
    case 'write_file':
      return '${a['path']}\n\n${_cut('${a['content']}', 700)}';
    case 'edit_file':
      return '${a['path']}\n\n- ${_cut('${a['old_str']}', 300)}\n+ ${_cut('${a['new_str']}', 300)}';
    case 'run_shell':
      return '${a['command']}';
    case 'http_request':
      return '${a['method'] ?? 'GET'} ${a['url']}\n${_cut('${a['body'] ?? ''}', 300)}';
    case 'delete_path':
    case 'make_dir':
      return '${a['path']}';
    default:
      return const JsonEncoder.withIndent('  ').convert(a);
  }
}

IconData toolIcon(String n) {
  switch (n) {
    case 'list_dir': return Icons.folder_open;
    case 'read_file': return Icons.description;
    case 'search_files': return Icons.search;
    case 'write_file': return Icons.edit_note;
    case 'edit_file': return Icons.edit;
    case 'make_dir': return Icons.create_new_folder;
    case 'delete_path': return Icons.delete_outline;
    case 'run_shell': return Icons.terminal;
    case 'http_request': return Icons.language;
    case 'todo_write': return Icons.checklist;
    case 'memory_save':
    case 'memory_read':
    case 'memory_list': return Icons.memory;
    case 'library_search':
    case 'library_read': return Icons.library_books;
    case 'open_app':
    case 'list_apps':
    case 'open_url': return Icons.phone_android;
    default: return Icons.build;
  }
}

// ============================================================
//  تنفيذ الأدوات
// ============================================================
final Dio _http = Dio(BaseOptions(connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 60)));

Future<String> executeTool(ToolCall tc, Sandbox sb, Conversation conv) async {
  final a = tc.args;
  switch (tc.name) {
    case 'list_dir':
      {
        // Fix6: سقف مسار + سرد آمن
        final p = sb.check(clip(_str(a['path'], '.'), 500));
        final d = Directory(p);
        if (!await d.exists()) throw 'المجلد غير موجود: $p';
        final items = await d.list(followLinks: false).toList();
        items.sort((x, y) {
          final xd = x is Directory, yd = y is Directory;
          if (xd != yd) return xd ? -1 : 1;
          return x.path.toLowerCase().compareTo(y.path.toLowerCase());
        });
        final b = StringBuffer('$p\n');
        // Fix8: حجم غير متزامن
        final top = items.take(300).toList();
        final sizes = <int>[];
        for (final e in top) {
          if (e is Directory) { sizes.add(0); }
          else { try { sizes.add(await (e as File).length()); } catch (_) { sizes.add(0); } }
        }
        for (var i = 0; i < top.length; i++) {
          final e = top[i];
          final n = e.path.split('/').last;
          if (e is Directory) {
            b.writeln('d  $n/');
          } else {
            b.writeln('f  $n  (${fmtSize(sizes[i])})');
          }
        }
        if (items.length > 300) b.writeln('… +${items.length - 300} more');
        if (items.isEmpty) b.writeln('(empty)');
        return b.toString();
      }
    case 'read_file':
      {
        // Fix6: حد حجم + ترميز آمن + مسار محصّن + سقف إخراج
        final p = sb.check(clip(_str(a['path'], ''), 500));
        final f = File(p);
        if (!await f.exists()) throw 'الملف غير موجود: $p';
        var len = 0;
        try { len = await f.length(); } catch (_) {}
        if (len > 8 * 1024 * 1024) throw 'الملف كبير جداً للقراءة (${fmtSize(len)}) — الحد 8MB، استخدم offset/limit';
        final bytes = await f.readAsBytes();
        if (looksBinary(bytes)) return 'Binary file (${fmtSize(bytes.length)}) — cannot show as text.';
        String txt;
        try { txt = utf8.decode(bytes); } catch (_) {
          try { txt = latin1.decode(bytes); } catch (_) { txt = utf8.decode(bytes, allowMalformed: true); }
        }
        final lines = const LineSplitter().convert(txt);
        final off = clampInt(_int(a['offset'], 1), 1, lines.length + 1);
        final lim = clampInt(_int(a['limit'], 2000), 1, 5000);
        final end = clampInt(off - 1 + lim, 0, lines.length);
        final b = StringBuffer();
        for (var i = off - 1; i < end; i++) {
          b.writeln('${i + 1}\t${clip(lines[i], 600)}');
          if (b.length > 60000) {
            b.writeln('…[truncated at line ${i + 1} of ${lines.length}; use offset to continue]');
            break;
          }
        }
        if (b.isEmpty) return '(empty file or offset beyond end; total ${lines.length} lines)';
        if (end < lines.length && b.length <= 60000) b.writeln('…[${lines.length - end} more lines; use offset=${end + 1}]');
        return b.toString();
      }
    case 'search_files':
      {
        // Fix6: ترميز آمن + سقف حجم/نتائج + حد pattern + scan محدود
        final root = sb.check(clip(_str(a['path'], '.'), 500));
        final pat = clip(_str(a['pattern'], ''), 400);
        if (pat.isEmpty) throw 'pattern is required';
        if (pat.length > 400) throw 'pattern too long (max 400 chars)';
        RegExp re;
        try {
          re = RegExp(pat, caseSensitive: false);
        } catch (e) {
          throw 'Regex غير صالح: $e';
        }
        final glob = clip(_str(a['glob'], ''), 40);
        final out = <String>[];
        var scanned = 0;
        try {
          await for (final e in Directory(root).list(recursive: true, followLinks: false)) {
            if (e is! File) continue;
            final path = e.path;
            if (path.contains('/.git/') || path.contains('/node_modules/') || path.contains('/.dart_tool/')) continue;
            if (glob.isNotEmpty && !path.endsWith(glob)) continue;
            var len = 0;
            try { len = await e.length(); } catch (_) { continue; }
            if (len > 1500000) continue;
            var txt = '';
            try {
              final bytes = await e.readAsBytes();
              if (looksBinary(bytes)) continue;
              try { txt = utf8.decode(bytes); } catch (_) {
                try { txt = latin1.decode(bytes); } catch (_) { txt = utf8.decode(bytes, allowMalformed: true); }
              }
            } catch (_) { continue; }
            scanned++;
            if (scanned > 1200) break;
            final ls = txt.split('\n');
            for (var i = 0; i < ls.length; i++) {
              try {
                if (re.hasMatch(ls[i])) {
                  out.add('${clip(path.replaceFirst(root, '.'), 260)}:${i + 1}: ${_cut(clip(ls[i].trim(), 400), 200)}');
                  if (out.length >= 120) break;
                }
              } catch (_) {}
            }
            if (out.length >= 120) break;
          }
        } catch (_) {}
        final joined = out.isEmpty ? 'No matches ($scanned files scanned)' : out.join('\n');
        return clip(joined, 8000);
      }
    case 'write_file':
      {
        // Fix6: حد حجم + clip محتوى + مسار محصّن + منع كتابة عملاقة
        final p = sb.check(clip(_str(a['path'], ''), 500));
        final content = _str(a['content'], '');
        if (content.length > 600000) throw 'المحتوى كبير جداً (${content.length} chars) — الحد 600k حرف (قسّم الملف)';
        if (content.length > 5 * 1024 * 1024) throw 'المحتوى يتجاوز 5MB — قسّم الملف';
        final f = File(p);
        final existed = await f.exists();
        await f.parent.create(recursive: true);
        await f.writeAsString(content, flush: true);
        return '${existed ? 'Overwrote' : 'Created'} $p (${content.length} chars, ${'\n'.allMatches(content).length + 1} lines)';
      }
    case 'edit_file':
      {
        // Fix6: حراس حجم + ترميز آمن + منع ملف عملاق
        final p = sb.check(clip(_str(a['path'], ''), 500));
        final f = File(p);
        if (!await f.exists()) throw 'الملف غير موجود: $p';
        try { if (await f.length() > 8 * 1024 * 1024) throw 'الملف كبير جداً للتعديل (8MB حد)'; } catch (e) { if ('$e'.contains('كبير جداً')) rethrow; }
        final oldS = _str(a['old_str'], '');
        final newS = _str(a['new_str'], '');
        if (oldS.isEmpty) throw 'old_str is empty';
        if (oldS.length > 200000) throw 'old_str too large (max 200k)';
        if (newS.length > 600000) throw 'new_str too large (max 600k)';
        var text = '';
        try {
          final bytes = await f.readAsBytes();
          if (looksBinary(bytes)) throw 'لا يمكن تعديل ملف ثنائي';
          try { text = utf8.decode(bytes); } catch (_) {
            try { text = latin1.decode(bytes); } catch (_) { text = utf8.decode(bytes, allowMalformed: true); }
          }
        } catch (e) { if ('$e'.contains('ثنائي')) rethrow; text = await f.readAsString(); }
        final count = oldS.allMatches(text).length;
        if (count == 0) throw 'old_str not found in file (must match exactly, including whitespace)';
        final all = a['replace_all'] == true;
        if (count > 1 && !all) throw 'old_str appears $count times; add more context or set replace_all=true';
        String res;
        if (all) { res = text.replaceAll(oldS, newS); } else {
          final i = text.indexOf(oldS);
          res = text.substring(0, i) + newS + text.substring(i + oldS.length);
        }
        if (res.length > 6 * 1024 * 1024) throw 'النتيجة كبيرة جداً (${res.length} chars) — قسّم التعديل';
        await f.writeAsString(res, flush: true);
        return 'Edited $p ($count replacement${count > 1 ? 's' : ''})';
      }
    case 'make_dir':
      {
        // Fix6: سقف مسار
        final p = sb.check(clip(_str(a['path'], ''), 500));
        await Directory(p).create(recursive: true);
        return 'Created directory $p';
      }
    case 'delete_path':
      {
        // Fix6: حماية الجذور + منع حذف مجلد العمل العام
        final p = sb.check(clip(_str(a['path'], ''), 500));
        if (sb.isRoot(p)) throw 'لا يمكن حذف مجلد الصلاحيات الجذري';
        // حماية إضافية: لا تحذف جذر المشروع/الوكيل نفسه بدون تأكيد خارجي
        final norm = normPath(p);
        if (norm == normPath(sb.cwd)) throw 'لا يمكن حذف مجلد العمل الحالي نفسه — احذف محتوياته بدلاً منه';
        if (norm == normPath(app.libDir.path)) throw 'لا يمكن حذف مجلد المكتبة كاملاً من الأداة';
        final t = await FileSystemEntity.type(p);
        if (t == FileSystemEntityType.notFound) throw 'غير موجود: $p';
        if (t == FileSystemEntityType.directory) {
          await Directory(p).delete(recursive: true);
        } else {
          await File(p).delete();
        }
        return 'Deleted $p';
      }
    case 'run_shell':
      {
        // Fix7: حد طول الأمر + مسار wd محصّن + سقف وقت + حظر تسريب secrets افتراضياً
        final cmd = clip(_str(a['command'], ''), 8000);
        if (cmd.trim().isEmpty) throw 'command is empty';
        if (cmd.length > 8000) throw 'command too long (max 8000 chars)';
        // حظر أوامر خطرة جداً (يمكن تجاوزها بموافقة المستخدم عبر Approval)
        const dangerous = ['rm -rf /', 'mkfs', ':(){:|:&};', 'chmod 777 /', 'dd if='];
        for (final d in dangerous) { if (cmd.contains(d)) throw 'أمر خطير محظور: $d'; }
        final wd = sb.check(clip(_str(a['cwd'], '.'), 500));
        final secs = clampInt(_int(a['timeout_s'], 60), 1, 120);
        final sh = Platform.isAndroid ? '/system/bin/sh' : '/bin/sh';
        try {
          final r = await Process.run(sh, ['-c', cmd],
                  workingDirectory: wd, stdoutEncoding: utf8, stderrEncoding: utf8)
              .timeout(Duration(seconds: secs));
          return 'exit code: ${r.exitCode}\n--- stdout ---\n${clip('${r.stdout}', 20000)}\n--- stderr ---\n${clip('${r.stderr}', 8000)}';
        } on TimeoutException {
          return 'Timed out after ${secs}s';
        }
      }
    case 'http_request':
      {
        // Fix7: SSRF guard + سقف حجم/زمن صارم
        final url = clip(_str(a['url'], ''), 2000).trim();
        if (!url.startsWith('http://') && !url.startsWith('https://')) throw 'URL must start with http(s)://';
        if (url.length > 2000) throw 'URL too long';
        final u = Uri.tryParse(url);
        if (u == null || u.host.isEmpty) throw 'URL غير صالح';
        final host = u.host.toLowerCase();
        // Fix8: SSRF دقيق — 10/8 و 192.168/16 و 172.16/12 فقط + link-local/metadata/host
        bool is172Private(String h) {
          // 172.16.0.0/12 → 172.16.x.x حتى 172.31.x.x
          if (!h.startsWith('172.')) return false;
          final second = int.tryParse(h.split('.')[1]);
          return second != null && second >= 16 && second <= 31;
        }
        if (host == 'localhost' || host == '127.0.0.1' || host == '::1' || host == '0.0.0.0'
            || host == '::ffff:127.0.0.1'
            || host.startsWith('10.') || host.startsWith('192.168.') || is172Private(host)
            || host.startsWith('127.') || host.startsWith('0.') // 127.0.0.0/8 و 0.0.0.0/8
            || host.endsWith('.local') || host.endsWith('.internal')) {
          throw 'SSRF blocked: private/local hosts غير مسموحة ($host)';
        }
        if (host.startsWith('169.254.') || host == '169.254.169.254'
            || host == 'metadata.google.internal' || host == 'metadata.google'
            || host == 'instance-data') throw 'SSRF blocked: metadata endpoint محظور';
        final method = clip(_str(a['method'], 'GET'), 12).toUpperCase().trim();
        const allowedMethods = {'GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'};
        if (!allowedMethods.contains(method)) throw 'HTTP method غير مدعوم: $method';
        final headers = <String, dynamic>{};
        if (a['headers'] is Map) {
          final m = Map<String, dynamic>.from(a['headers'] as Map);
          if (m.length > 32) throw 'too many headers (max 32)';
          for (final k in m.keys) {
            if ('$k'.length > 120 || '${m[k]}'.length > 2000) throw 'header too large: $k';
          }
          headers.addAll(m);
        }
        final body = a['body'] is String ? clip(a['body'] as String, 200000) : a['body'];
        final res = await _http.request<String>(url,
            data: body,
            options: Options(
                method: method,
                headers: headers,
                responseType: ResponseType.plain,
                validateStatus: (_) => true,
                sendTimeout: const Duration(seconds: 25),
                receiveTimeout: const Duration(seconds: 30)));
        return 'HTTP ${res.statusCode}\n${clip(res.data ?? '', 20000)}';
      }
    case 'todo_write':
      {
        final list = a['todos'];
        if (list is! List) throw 'todos must be an array';
        conv.todos = list.map((e) {
          final m = e is Map ? e : {};
          var st = '${m['status'] ?? 'pending'}';
          if (st != 'pending' && st != 'in_progress' && st != 'completed') st = 'pending';
          return Todo('${m['content'] ?? ''}', st);
        }).toList();
        app.refresh();
        return 'Todo list updated (${conv.todos.length} items)';
      }
    case 'memory_list':
      return app.memory.isEmpty ? '(no memory parts)' : app.memory.map((m) => '- ${m.title}${m.pinned ? ' [pinned]' : ''}').join('\n');
    case 'memory_read':
      {
        final q = _str(a['title'], '').toLowerCase();
        final m = firstWhereOrNull(app.memory, (e) => e.title.toLowerCase() == q) ??
            firstWhereOrNull(app.memory, (e) => e.title.toLowerCase().contains(q));
        if (m == null) throw 'لا يوجد جزء ذاكرة بهذا العنوان';
        return '# ${m.title}\n${m.content}';
      }
    case 'memory_save':
      {
        // Fix6: حدود + clip + منع إغراق الذاكرة
        var t = clip(_str(a['title'], '').trim(), 120);
        var c = clip(_str(a['content'], ''), 8000);
        if (t.isEmpty || c.isEmpty) throw 'title and content are required';
        if (app.memory.length >= 120 && firstWhereOrNull(app.memory, (e) => e.title.toLowerCase() == t.toLowerCase()) == null) {
          throw 'الذاكرة ممتلئة (120 جزء كحد أقصى) — احذف جزءاً قديماً أولاً';
        }
        final ex = firstWhereOrNull(app.memory, (e) => e.title.toLowerCase() == t.toLowerCase());
        if (ex != null) {
          ex.content = c;
        } else {
          app.memory.add(MemoryPart(id: newId(), title: t, content: c));
        }
        await app.saveMemory();
        return ex != null ? 'Memory updated: $t' : 'Memory saved: $t';
      }
    case 'library_search':
      {
        // Fix8: async بالكامل — لا يوجد Sync يجمّد الواجهة
        final q = clip(_str(a['query'], ''), 200).toLowerCase().trim();
        final out = <String>[];
        var scanned = 0;
        for (final it in app.library) {
          if (it.path.isEmpty) continue;
          if (out.length >= 80) break;
          var hit = q.isEmpty || it.name.toLowerCase().contains(q);
          var snippet = '';
          if (!hit && q.isNotEmpty && !it.mime.startsWith('image/')) {
            try {
              final f = File(it.path);
              if (!await f.exists()) continue;
              if (await f.length() > 2000000) continue;
              final bytes = await f.readAsBytes();
              if (looksBinary(bytes)) continue;
              String t;
              try {
                t = utf8.decode(bytes);
              } catch (_) {
                try {
                  t = latin1.decode(bytes);
                } catch (_) {
                  t = utf8.decode(bytes, allowMalformed: true);
                }
              }
              final i = t.toLowerCase().indexOf(q);
              if (i >= 0) {
                hit = true;
                snippet = clip(t.substring(clampInt(i - 60, 0, t.length), clampInt(i + 100, 0, t.length)).replaceAll('\n', ' ').replaceAll('\r', ''), 160);
              }
              scanned++;
              if (scanned > 60) break;
            } catch (_) {}
          }
          if (hit) out.add('- ${clip(it.name, 120)} (${fmtSize(it.size)})${snippet.isEmpty ? '' : ' … $snippet …'}');
        }
        if (out.isEmpty) return q.isEmpty ? (app.library.isEmpty ? 'Library empty' : out.join('\n')) : 'No matches';
        return clip(out.join('\n'), 8000);
      }
    case 'library_read':
      {
        // Fix6: تحقق مسار + حد حجم + ترميز آمن + سقف إخراج
        final n = clip(_str(a['name'], ''), 180).toLowerCase().trim();
        if (n.isEmpty) throw 'اسم الملف مطلوب';
        final it = firstWhereOrNull(app.library, (e) => e.name.toLowerCase() == n && e.path.isNotEmpty) ??
            firstWhereOrNull(app.library, (e) => e.name.toLowerCase().contains(n) && e.path.isNotEmpty);
        if (it == null) throw 'الملف غير موجود في المكتبة';
        final norm = normPath(it.path);
        if (!norm.startsWith(normPath(app.libDir.path))) throw 'مسار غير صالح';
        final f = File(norm);
        if (!await f.exists()) throw 'الملف غير موجود على القرص';
        final _len = await f.length().catchError((_) => 0);
        if (_len > 8 * 1024 * 1024) throw 'الملف كبير جداً للعرض (${fmtSize(_len)}) — الحد 8MB';
        final bytes = await f.readAsBytes();
        if (looksBinary(bytes)) return 'Binary file (${fmtSize(bytes.length)}) — cannot show as text. استخدم المعاينة للمحتوى الثنائي.';
        String txt;
        try {
          txt = utf8.decode(bytes);
        } catch (_) {
          try {
            txt = latin1.decode(bytes);
          } catch (_) {
            txt = utf8.decode(bytes, allowMalformed: true);
          }
        }
        return clip(txt, 60000);
      }
    case 'list_apps':
      {
        final all = await PhoneBridge.listApps();
        final allowed = sb.agent.allowedApps;
        final f = all.where((e) => allowed.contains(e['package'])).toList();
        return f.isEmpty ? 'No allowed apps found' : f.map((e) => '${e['label']} — ${e['package']}').join('\n');
      }
    case 'open_app':
      {
        final pkg = _str(a['package'], '');
        if (!sb.agent.allowedApps.contains(pkg)) throw 'التطبيق غير مسموح: $pkg';
        final ok = await PhoneBridge.openApp(pkg);
        return ok ? 'Opened $pkg' : 'Failed to open $pkg';
      }
    case 'open_url':
      {
        final ok = await PhoneBridge.openUrl(_str(a['url'], ''));
        return ok ? 'Opened' : 'Failed to open URL';
      }
    default:
      throw 'Unknown tool: ${tc.name}';
  }
}

// ============================================================
//  عميل LLM — OpenAI-compatible + Anthropic Messages
//  إصلاح مشكلة العربي: فك UTF-8 بشكل متدفق (stateful) + تقسيم أسطر صحيح،
//  بدل utf8.decode(chunk) لكل دفعة (كان يكسر الحروف ويُسقط الكلمات بصمت).
// ============================================================
class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class LlmChunk {
  final String text, reasoning;
  final int? toolIndex, inTok, outTok;
  final String? toolId, toolName, toolArgs, finish;
  const LlmChunk({
    this.text = '',
    this.reasoning = '',
    this.toolIndex,
    this.toolId,
    this.toolName,
    this.toolArgs,
    this.finish,
    this.inTok,
    this.outTok,
  });
}

bool isCancelErr(Object e) {
  try {
    return CancelToken.isCancel(e as dynamic);
  } catch (_) {
    return false;
  }
}

String _cut(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
Future<String> dioMessage(Object e) async {
  try {
    final d = e as dynamic;
    final r = d.response;
    if (r != null) {
      final data = r.data;
      var body = '';
      if (data is ResponseBody) {
        final bytes = <int>[];
        await for (final b in data.stream) {
          bytes.addAll(b);
        }
        body = utf8.decode(bytes, allowMalformed: true);
      } else if (data != null) {
        body = data is String ? data : jsonEncode(data);
      }
      try {
        final j = jsonDecode(body);
        if (j is Map) {
          final er = j['error'];
          if (er is Map && er['message'] != null) {
            body = '${er['message']}';
          } else if (er is String) {
            body = er;
          } else if (j['message'] != null) {
            body = '${j['message']}';
          }
        }
      } catch (_) {}
      final code = r.statusCode ?? 0;
      String hint = '';
      if (code == 401 || code == 403) hint = ' — تحقّق من مفتاح الـ API والصلاحيات';
      if (code == 429) hint = ' — تجاوزت الحدّ، جرّب بعد قليل';
      if (code >= 500) hint = ' — الخادم مشغول، سيُعاد تلقائياً';
      return 'خطأ من الخادم (HTTP $code)$hint: ${_cut(body, 600)}';
    }
    final msg = '${d.message ?? e}';
    if (msg.toLowerCase().contains('timeout')) return 'انتهت مهلة الاتصال — تحقّق من الشبكة وسيُعاد تلقائياً';
    if (msg.toLowerCase().contains('socket') || msg.toLowerCase().contains('connection')) return 'انقطع الاتصال بالشبكة — سيُعاد تلقائياً عند عودتها';
    return msg;
  } catch (_) {
    return '$e';
  }
}

class LlmClient {
  // شبكة محسّنة: retry ذكي + timeouts أوضح + توفير توكنز عبر ضغط التاريخ داخل prepareHistory
  final Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 90),
    sendTimeout: const Duration(seconds: 30),
  ));

  static String endpoint(String base, String path) {
    var u = base.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith(path)) return u;
    if (u.endsWith('/v1') && path.startsWith('/v1/')) u = u.substring(0, u.length - 3);
    return u + path;
  }

  Map<String, String> _headers(ApiProfile p, {bool stream = true}) {
    final h = <String, String>{
      'Accept': stream ? 'text/event-stream' : 'application/json',
      'Accept-Charset': 'utf-8',
    };
    if (p.kind == 'anthropic') {
      h['x-api-key'] = p.apiKey;
      h['anthropic-version'] = '2023-06-01';
    } else if (p.apiKey.isNotEmpty) {
      h['Authorization'] = 'Bearer ${p.apiKey}';
    }
    h.addAll(p.headers);
    return h;
  }

  Future<List<String>> fetchModels(ApiProfile p) async {
    final url = endpoint(p.baseUrl, p.modelsEndpointPath);
    final res = await dio.get<String>(url,
        queryParameters: p.kind == 'anthropic' ? {'limit': 1000} : null,
        options: Options(headers: _headers(p, stream: false), responseType: ResponseType.plain));
    final d = jsonDecode(res.data ?? '{}');
    final list = d is Map ? (d['data'] ?? d['models'] ?? []) : (d is List ? d : []);
    final out = (list as List).map((e) => e is Map ? '${e['id'] ?? e['name']}' : '$e').toList();
    out.sort();
    return out;
  }

  // ---------- بناء الرسائل ----------
  Future<List<Map<String, dynamic>>> _oaiMessages(ApiProfile p, String system, List<Msg> msgs) async {
    final out = <Map<String, dynamic>>[];
    if (system.isNotEmpty) out.add({'role': p.systemRole, 'content': system});
    for (final m in msgs) {
      if (m.role == 'user') {
        final t = m.promptText().trim();
        final imgs = m.files.where((f) => f.isImage).toList();
        if (imgs.isEmpty) {
          out.add({'role': 'user', 'content': t.isEmpty ? '(no text)' : t});
        } else {
          final parts = <Map<String, dynamic>>[
            {'type': 'text', 'text': t.isEmpty ? '(see image)' : t}
          ];
          for (final f in imgs) {
            final d = await f.b64Async();
            if (d != null) {
              parts.add({
                'type': 'image_url',
                'image_url': {'url': 'data:${f.mime};base64,$d'}
              });
            }
          }
          out.add({'role': 'user', 'content': parts});
        }
      } else if (m.role == 'assistant') {
        final d = <String, dynamic>{'role': 'assistant', 'content': m.content};
        if (m.toolCalls.isNotEmpty) {
          d['tool_calls'] = m.toolCalls
              .map((t) => {
                    'id': t.id,
                    'type': 'function',
                    'function': {'name': t.name, 'arguments': jsonEncode(t.args)}
                  })
              .toList();
        } else if (m.content.trim().isEmpty) {
          continue;
        }
        out.add(d);
      } else if (m.role == 'tool') {
        out.add({
          'role': 'tool',
          'tool_call_id': m.toolCallId,
          'content': m.content.isEmpty ? '(empty)' : m.content
        });
      }
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _anMessages(List<Msg> msgs) async {
    final out = <Map<String, dynamic>>[];
    void push(String role, List<Map<String, dynamic>> blocks) {
      if (out.isNotEmpty && out.last['role'] == role) {
        (out.last['content'] as List).addAll(blocks);
      } else {
        out.add({'role': role, 'content': blocks});
      }
    }

    for (final m in msgs) {
      if (m.role == 'user') {
        final blocks = <Map<String, dynamic>>[];
        for (final f in m.files) {
          if (f.isImage || f.mime == 'application/pdf') {
            final d = await f.b64Async();
            if (d != null) {
              blocks.add({
                'type': f.isImage ? 'image' : 'document',
                'source': {'type': 'base64', 'media_type': f.mime, 'data': d}
              });
            }
          }
        }
        final t = m.promptText().trim();
        blocks.add({'type': 'text', 'text': t.isEmpty ? '(no text)' : t});
        push('user', blocks);
      } else if (m.role == 'assistant') {
        final blocks = <Map<String, dynamic>>[];
        if (m.content.trim().isNotEmpty) blocks.add({'type': 'text', 'text': m.content});
        for (final t in m.toolCalls) {
          blocks.add({'type': 'tool_use', 'id': t.id, 'name': t.name, 'input': t.args});
        }
        if (blocks.isEmpty) continue;
        push('assistant', blocks);
      } else if (m.role == 'tool') {
        push('user', [
          {
            'type': 'tool_result',
            'tool_use_id': m.toolCallId,
            'content': m.content.isEmpty ? '(empty)' : m.content,
            'is_error': m.status == 'error' || m.status == 'denied',
          }
        ]);
      }
    }
    return out;
  }

  // ---------- الطلب ----------
  Stream<LlmChunk> chat(
    ApiProfile p, {
    required String system,
    required List<Msg> msgs,
    required List<ToolDef> tools,
    CancelToken? cancel,
  }) async* {
    final anth = p.kind == 'anthropic';
    final url = endpoint(p.baseUrl, p.chatEndpointPath);
    final body = <String, dynamic>{'model': p.model, 'stream': p.stream};
    var defs = tools;
    if (anth && defs.isEmpty && msgs.any((m) => m.toolCalls.isNotEmpty)) defs = kAllTools;
    if (anth) {
      body['max_tokens'] = p.maxTokens ?? 16000;
      if (system.isNotEmpty) body['system'] = system;
      body['messages'] = await _anMessages(msgs);
      if (defs.isNotEmpty && p.tools) {
        body['tools'] = defs.map((t) => {'name': t.name, 'description': t.desc, 'input_schema': t.schema}).toList();
      }
    } else {
      if (p.maxTokens != null) body['max_tokens'] = p.maxTokens;
      body['messages'] = await _oaiMessages(p, system, msgs);
      if (defs.isNotEmpty && p.tools) {
        body['tools'] = defs
            .map((t) => {
                  'type': 'function',
                  'function': {'name': t.name, 'description': t.desc, 'parameters': t.schema}
                })
            .toList();
      }
    }
    if (p.temperature != null) body['temperature'] = p.temperature;
    if (p.extraBody.trim().isNotEmpty) {
      try {
        final x = jsonDecode(p.extraBody);
        if (x is Map) x.forEach((k, v) => body['$k'] = v);
      } catch (_) {}
    }

    // ——— Retry تلقائي للشبكة: يكافئ انقطاعات الواي فاي/الموبايل بلا تدخل من المستخدم ———
    Response<ResponseBody>? res;
    DioException? lastErr;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        res = await dio.post<ResponseBody>(url,
            data: body,
            cancelToken: cancel,
            options: Options(responseType: ResponseType.stream, headers: _headers(p, stream: p.stream)));
        break;
      } on DioException catch (e) {
        lastErr = e;
        if (isCancelErr(e)) rethrow;
        final isRetriable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.connectionError ||
            (e.response?.statusCode != null && e.response!.statusCode! >= 500);
        final shouldRetry = isRetriable && (p.stream || attempt < 2);
        if (!shouldRetry || attempt == 3) rethrow;
        await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
      }
    }
    if (res == null) throw lastErr ?? ApiError('فشل الاتصال بعد عدة محاولات');

    final lines = res.data!.stream
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());

    final raw = StringBuffer();
    var sawData = false;
    await for (final line in lines) {
      if (line.startsWith('data:')) {
        sawData = true;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        dynamic j;
        try {
          j = jsonDecode(data);
        } catch (_) {
          continue;
        }
        if (j is! Map) continue;
        for (final c in (anth ? _anParse(j) : _oaiParse(j))) {
          yield c;
        }
      } else if (!line.startsWith('event:') && !line.startsWith(':') && !line.startsWith('id:') && !line.startsWith('retry:')) {
        raw.writeln(line);
      }
    }
    if (!sawData && raw.toString().trim().isNotEmpty) {
      dynamic j;
      try {
        j = jsonDecode(raw.toString());
      } catch (_) {
        throw ApiError('رد غير مفهوم من الخادم: ${_cut(raw.toString(), 300)}');
      }
      if (j is Map) {
        final er = j['error'];
        if (er != null) throw ApiError(er is Map ? '${er['message']}' : '$er');
        for (final c in (anth ? _anFull(j) : _oaiParse(j))) {
          yield c;
        }
      }
    }
  }

  Iterable<LlmChunk> _oaiParse(Map j) sync* {
    final err = j['error'];
    if (err != null) throw ApiError(err is Map ? '${err['message']}' : '$err');
    final usage = j['usage'];
    if (usage is Map) {
      yield LlmChunk(inTok: _int(usage['prompt_tokens'], 0), outTok: _int(usage['completion_tokens'], 0));
    }
    final ch = j['choices'];
    if (ch is! List || ch.isEmpty) return;
    final c0 = ch[0];
    if (c0 is! Map) return;
    final d = c0['delta'] ?? c0['message'];
    if (d is Map) {
      final t = d['content'];
      if (t is String && t.isNotEmpty) yield LlmChunk(text: t);
      final r = d['reasoning_content'] ?? d['reasoning'];
      if (r is String && r.isNotEmpty) yield LlmChunk(reasoning: r);
      final tcs = d['tool_calls'];
      if (tcs is List) {
        for (var i = 0; i < tcs.length; i++) {
          final tc = tcs[i];
          if (tc is! Map) continue;
          final f = tc['function'] is Map ? tc['function'] as Map : {};
          yield LlmChunk(
            toolIndex: tc['index'] is int ? tc['index'] as int : i,
            toolId: tc['id']?.toString(),
            toolName: f['name']?.toString(),
            toolArgs: f['arguments']?.toString(),
          );
        }
      }
    }
    final fr = c0['finish_reason'];
    if (fr != null) yield LlmChunk(finish: '$fr');
  }

  Iterable<LlmChunk> _anParse(Map j) sync* {
    final t = j['type'];
    if (t == 'message_start') {
      final m = j['message'];
      final u = m is Map ? m['usage'] : null;
      if (u is Map) yield LlmChunk(inTok: _int(u['input_tokens'], 0));
    } else if (t == 'content_block_start') {
      final b = j['content_block'];
      if (b is Map && b['type'] == 'tool_use') {
        yield LlmChunk(toolIndex: _int(j['index'], 0), toolId: '${b['id'] ?? ''}', toolName: '${b['name'] ?? ''}', toolArgs: '');
      }
    } else if (t == 'content_block_delta') {
      final d = j['delta'];
      if (d is Map) {
        final dt = d['type'];
        if (dt == 'text_delta') {
          yield LlmChunk(text: '${d['text'] ?? ''}');
        } else if (dt == 'thinking_delta') {
          yield LlmChunk(reasoning: '${d['thinking'] ?? ''}');
        } else if (dt == 'input_json_delta') {
          yield LlmChunk(toolIndex: _int(j['index'], 0), toolArgs: '${d['partial_json'] ?? ''}');
        }
      }
    } else if (t == 'message_delta') {
      final d = j['delta'];
      final u = j['usage'];
      yield LlmChunk(
          finish: d is Map && d['stop_reason'] != null ? '${d['stop_reason']}' : null,
          outTok: u is Map ? _int(u['output_tokens'], 0) : null);
    } else if (t == 'error') {
      final e = j['error'];
      throw ApiError(e is Map ? '${e['message']}' : '$e');
    }
  }

  Iterable<LlmChunk> _anFull(Map j) sync* {
    final c = j['content'];
    if (c is List) {
      for (var i = 0; i < c.length; i++) {
        final b = c[i];
        if (b is! Map) continue;
        if (b['type'] == 'text') {
          yield LlmChunk(text: '${b['text']}');
        } else if (b['type'] == 'tool_use') {
          yield LlmChunk(toolIndex: i, toolId: '${b['id']}', toolName: '${b['name']}', toolArgs: jsonEncode(b['input'] ?? {}));
        }
      }
    }
    final u = j['usage'];
    yield LlmChunk(
        finish: j['stop_reason'] != null ? '${j['stop_reason']}' : null,
        inTok: u is Map ? _int(u['input_tokens'], 0) : null,
        outTok: u is Map ? _int(u['output_tokens'], 0) : null);
  }
}

// ============================================================
//  تجهيز التاريخ + System Prompt
// ============================================================
List<Msg> prepareHistory(List<Msg> all) {
  final act = all.where((m) => !m.excluded && m.role != 'note').toList();
  final out = <Msg>[];
  for (var i = 0; i < act.length; i++) {
    final m = act[i];
    if (m.role == 'assistant' && m.toolCalls.isNotEmpty) {
      out.add(m);
      final answered = <String>{};
      var j = i + 1;
      while (j < act.length && act[j].role == 'tool') {
        if (m.toolCalls.any((t) => t.id == act[j].toolCallId)) {
          out.add(act[j]);
          answered.add(act[j].toolCallId ?? '');
        }
        j++;
      }
      for (final t in m.toolCalls) {
        if (!answered.contains(t.id)) {
          out.add(Msg(role: 'tool', toolCallId: t.id, toolName: t.name, content: '[no result — interrupted]', status: 'error'));
        }
      }
      i = j - 1;
    } else if (m.role == 'tool') {
      continue;
    } else {
      out.add(m);
    }
  }
  while (out.isNotEmpty && out.first.role != 'user') {
    out.removeAt(0);
  }
  final n = out.length;
  return [
    for (var i = 0; i < n; i++)
      (out[i].role == 'tool' && i < n - 10 && out[i].content.length > 4000) ? _trimmedTool(out[i]) : out[i]
  ];
}

Msg _trimmedTool(Msg m) => Msg(
    id: m.id,
    role: 'tool',
    toolCallId: m.toolCallId,
    toolName: m.toolName,
    status: m.status,
    content:
        '${m.content.substring(0, 1800)}\n…[تم اقتطاع ناتج قديم لتوفير السياق]…\n${m.content.substring(m.content.length - 1200)}');

// Fix8: قراءة ملاحظات المشروع غير متزامنة — لا تجمّد الواجهة عند وجود ملفات كبيرة
Future<String> _projectNotes(String cwd) async {
  for (final n in ['CLAUDE.md', 'AGENTS.md', 'LMCLIENT.md']) {
    try {
      final f = File('$cwd/$n');
      if (await f.exists()) return '[$n]\n${clip(await f.readAsString(), 6000)}';
    } catch (_) {}
  }
  return '';
}

Future<String> buildSystem(Conversation c, Agent agent, Sandbox sb, List<ToolDef> tools) async {
  final pr = firstWhereOrNull(app.projects, (p) => p.id == c.projectId);
  final b = StringBuffer();
  // ——— HARNESS احترافي — يجعل أي نموذج يتصرّف مثل Claude Code ———
  b.writeln('You are LMClient Agent — an autonomous, highly capable coding agent running inside an Android app. You behave like Claude Code: you THINK, PLAN, ACT, and VERIFY in a tight loop until the task is truly finished. You never give up mid-task and you never leave code half-written.');
  b.writeln('You are given full ownership of this project — the user trusts you to improve, fix, and extend the code directly. Don\'t ask “shall I touch your code?” — just improve it professionally.');
  b.writeln();
  b.writeln('## Language');
  if (app.replyLang == 'ar') {
    b.writeln('Always reply in Arabic.');
  } else if (app.replyLang == 'en') {
    b.writeln('Always reply in English.');
  } else {
    b.writeln("Reply in the language the user writes in.");
  }
  b.writeln('When you write Arabic: use clear, natural, well-formed Arabic (Modern Standard Arabic by default; match the user\'s dialect if they write in dialect). Write complete, correctly spelled words with proper letters — never output separated, reversed, or isolated letters. Use Arabic punctuation (، ؛ ؟). Keep code, file paths, commands, identifiers and technical terms in their original Latin form instead of transliterating them. Do not put Arabic prose inside code blocks.');
  b.writeln();
  b.writeln('## Environment');
  b.writeln('- Platform: Android (app sandbox). Date: ${DateTime.now().toIso8601String().substring(0, 10)}.');
  b.writeln('- Working directory: ${sb.cwd} (relative paths resolve here).');
  b.writeln('- Allowed locations: ${[sb.cwd, ...agent.allowedPaths].join(' , ')}');
  b.writeln('- Permissions: read=${agent.canRead} write=${agent.canWrite} shell=${agent.canExecute} network=${agent.canNet}. Approval mode: ${agent.approval}.');
  b.writeln('- Available tools: ${tools.map((t) => t.name).join(', ')}.');
  b.writeln('- To deliver files to the user outside the app, write them into an allowed shared folder (if any) or tell the user the path.');
  b.writeln();
  b.writeln('## How to work — AGENT LOOP (mandatory)');
  b.writeln('1) THINK: analyze the request, explore the workspace with list_dir / search_files first — never guess file layout.');
  b.writeln('2) PLAN: for any task with >2 steps call todo_write with a concrete plan (exactly one item in_progress), then keep it updated as you go.');
  b.writeln('3) ACT: read before edit, use edit_file for small changes and write_file with COMPLETE content for new files (no placeholders, no “...rest...”). For large files split into smaller modules.');
  b.writeln('4) VERIFY: re-read or search or run checks after changes. Fix errors before finishing. Don\'t stop on first error.');
  b.writeln('5) FINISH: keep going until ALL todos are completed, then give a short summary: what was done, file paths, and what remains.');
  b.writeln('- Do not ask the user for permission to use tools: the app asks automatically when required. If a tool is denied, adapt or explain what you need.');
  b.writeln();
  b.writeln('## Token & cost discipline — CRITICAL');
  b.writeln('- Be extremely token-efficient: prefer search_files over reading many files, use read_file with limit/offset, never re-read the same file twice without reason.');
  b.writeln('- Prefer edit_file over write_file when only a small change is needed. Batch related edits.');
  b.writeln('- Keep tool outputs concise; for large outputs summarize and write full content to a file instead of dumping it in chat.');
  b.writeln('- Never send the same large file content multiple times — reference its path after the first write.');
  if (app.planMode) {
    b.writeln();
    b.writeln('## PLAN MODE (active)');
    b.writeln('You may only read and explore. Do NOT modify anything. Produce a concrete step-by-step plan and ask the user to approve it.');
  }
  // === Fix4: System Prompt ثلاث طبقات ===
  if (app.globalSystemPrompt.trim().isNotEmpty) {
    b.writeln();
    b.writeln('## Global instructions');
    b.writeln(app.globalSystemPrompt.trim());
  }
  if (agent.systemPrompt.trim().isNotEmpty) {
    b.writeln();
    b.writeln('## Agent instructions (${agent.name})');
    b.writeln(agent.systemPrompt.trim());
  }
  if (pr != null) {
    final ps = pr.systemPrompt.trim().isNotEmpty ? pr.systemPrompt.trim() : pr.instructions.trim();
    if (ps.isNotEmpty) {
      b.writeln();
      b.writeln('## Project instructions (${pr.name})');
      b.writeln(ps);
    }
  }
  final notes = _projectNotes(sb.cwd);
  if (notes.isNotEmpty) {
    b.writeln();
    b.writeln('## Project notes file');
    b.writeln(notes);
  }
  final pinned = app.memory.where((m) => m.pinned).toList();
  if (pinned.isNotEmpty) {
    b.writeln();
    b.writeln('## Pinned memory');
    for (final m in pinned) {
      b.writeln('- ${m.title}: ${clip(m.content, 1500)}');
    }
  }
  final others = app.memory.where((m) => !m.pinned).toList();
  if (others.isNotEmpty) {
    b.writeln();
    b.writeln('## Memory index (read details with memory_read)');
    b.writeln(others.map((m) => m.title).take(60).join(' | '));
  }
  final lib = app.library.where((l) => l.path.isNotEmpty).toList();
  if (lib.isNotEmpty) {
    b.writeln();
    b.writeln('## Library files (use library_search / library_read)');
    b.writeln(lib.map((l) => l.name).take(40).join(' | '));
  }
  return b.toString();
}

Future<String> debugContext(Conversation c) async {
  final agent = app.agent;
  final sb = Sandbox(agent, app.cwdFor(c));
  final tools = toolsFor(agent, plan: app.planMode, bridge: app.bridgeOk);
  final sys = await buildSystem(c, agent, sb, tools);
  final b = StringBuffer('=== SYSTEM ===\n$sys\n\n=== TOOLS ===\n${tools.map((t) => t.name).join(', ')}\n\n=== MESSAGES ===\n');
  for (final m in prepareHistory(c.msgs)) {
    var t = m.promptText();
    if (m.role == 'assistant' && m.toolCalls.isNotEmpty) {
      t = '${m.content}\n  → ${m.toolCalls.map((x) => '${x.name}(${jsonEncode(x.args)})').join(', ')}';
    }
    b.writeln('[${m.role}] $t\n');
  }
  return b.toString();
}

// ============================================================
//  حلقة الوكيل (Agent Loop)
// ============================================================
class _TcAcc {
  String id = '', name = '';
  final StringBuffer args = StringBuffer();
}

class _Acc {
  final StringBuffer text = StringBuffer(), reasoning = StringBuffer();
  final Map<int, _TcAcc> tools = {};
  String? finish;
  int inTok = 0, outTok = 0;

  bool get isEmpty => text.isEmpty && reasoning.isEmpty && tools.isEmpty;
  bool get truncated => finish == 'length' || finish == 'max_tokens';
  List<String> toolNamesList() => tools.values.map((t) => t.name).where((n) => n.isNotEmpty).toList();

  void add(LlmChunk c) {
    if (c.text.isNotEmpty) text.write(c.text);
    if (c.reasoning.isNotEmpty) reasoning.write(c.reasoning);
    if (c.toolIndex != null) {
      var idx = c.toolIndex!;
      final id = c.toolId ?? '';
      final ex = tools[idx];
      if (id.isNotEmpty && ex != null && ex.id.isNotEmpty && ex.id != id) {
        idx = tools.keys.fold<int>(0, (m, k) => k > m ? k : m) + 1;
      }
      final t = tools.putIfAbsent(idx, () => _TcAcc());
      if (id.isNotEmpty) t.id = id;
      if (c.toolName != null && c.toolName!.isNotEmpty) t.name = c.toolName!;
      if (c.toolArgs != null) t.args.write(c.toolArgs);
    }
    if (c.finish != null) finish = c.finish;
    if (c.inTok != null) inTok = c.inTok!;
    if (c.outTok != null) outTok = c.outTok!;
  }

  Msg toMsg() {
    final keys = tools.keys.toList()..sort();
    final calls = <ToolCall>[];
    for (final k in keys) {
      final t = tools[k]!;
      if (t.name.isEmpty) continue;
      var args = <String, dynamic>{};
      String? bad;
      final raw = t.args.toString().trim();
      if (raw.isNotEmpty) {
        try {
          final j = jsonDecode(raw);
          if (j is Map) {
            args = Map<String, dynamic>.from(j);
          } else {
            bad = 'arguments must be a JSON object';
          }
        } catch (_) {
          bad = 'invalid JSON arguments (the output was probably truncated)';
        }
      }
      calls.add(ToolCall(
          id: t.id.isEmpty ? 'call_${newId().substring(0, 8)}' : t.id, name: t.name, args: args, error: bad));
    }
    return Msg(role: 'assistant', content: text.toString(), reasoning: reasoning.toString(), toolCalls: calls);
  }
}

class AgentRunner {
  final LlmClient llm = LlmClient();
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);
  bool failed = false;

  bool _ready() {
    final p = app.profile;
    if (p == null || p.model.isEmpty || p.baseUrl.isEmpty) {
      app.toast('أضف بروفايل API واختر الموديل من الإعدادات أولاً');
      return false;
    }
    return true;
  }

  String _titleFrom(String text, List<Attachment> files) {
    var t = text.trim().split('\n').first.trim();
    if (t.isEmpty && files.isNotEmpty) t = files.first.name;
    if (t.isEmpty) return 'محادثة جديدة';
    return t.length > 40 ? '${t.substring(0, 40)}…' : t;
  }

  void _note(Conversation c, String t) {
    c.msgs.add(Msg(role: 'note', content: t));
    app.refresh();
  }

  Future<void> send(String text, List<Attachment> files, {bool auto = false}) async {
    final c = app.cur;
    if (c == null || app.running || !_ready()) return;
    c.msgs.add(Msg(role: 'user', content: text, files: files, auto: auto));
    if (c.title == 'محادثة جديدة') c.title = _titleFrom(text, files);
    await _start(c);
  }

  /// إعادة التشغيل على المحادثة الحالية دون إضافة رسالة (إعادة توليد / إعادة محاولة)
  Future<void> resume() async {
    final c = app.cur;
    if (c == null || app.running || !_ready()) return;
    await _start(c);
  }

  Future<void> _start(Conversation c) async {
    final p = app.profile!;
    // مانع تكرار الجولات: بصمة الطلب لمنع إعادة نفس الجولة بعد انقطاع الشبكة/اعادة اتصال بالخطأ
    final checkpointTag = '${DateTime.now().millisecondsSinceEpoch}_${c.msgs.length}';
    c.msgs.add(Msg(role: 'note', content: '⟦checkpoint:$checkpointTag⟧', auto: true, excluded: true));
    app.running = true;
    app.stopRequested = false;
    failed = false;
    app.cancel = CancelToken();
    app.status = 'يبدأ…';
    app.refresh();
    await app.saveConv(c);
    try {
      await _loop(c, p);
    } catch (e) {
      failed = true;
      if (!isCancelErr(e)) _note(c, '⚠️ ${e is ApiError ? e.message : e}');
    } finally {
      // إزالة تاغ checkpoint الخفي بعد الانتهاء (لا يُرسل للنموذج أصلاً بسبب excluded)
      c.msgs.removeWhere((m) => m.content == '⟦checkpoint:$checkpointTag⟧');
      app.running = false;
      app.live.value = null;
      app.status = '';
      app.cancel = null;
      if (app.pending != null) app.answerApproval(0);
      await app.saveConv(c);
      app.refresh();
    }
  }

  Future<void> runWorkflow(Workflow w, String args) async {
    final rawSteps = List<String>.from(w.steps);
    if (rawSteps.isEmpty) return;
    final repo = app.cwdFor(app.cur);
    final projName = (firstWhereOrNull(app.projects, (p) => p.id == app.cur?.projectId)?.name ?? 'بدون مشروع');
    String prev = '';
    // إذا لم يستخدم القالب أي متغير، نمرر وسيط المستخدم للخطوة الأولى كما قبل
    final usesVars = rawSteps.any((s) =>
        s.contains('\$ARGS') || s.contains('\$PREV') || s.contains('\$WORKSPACE') || s.contains('\$PROJECT') || RegExp(r'\$ARG\d').hasMatch(s));
    final steps = List<String>.from(rawSteps);
    if (args.isNotEmpty && !usesVars) steps[0] = '${steps[0]}\n\n$args';
    for (var i = 0; i < steps.length; i++) {
      if (app.stopRequested || failed) break;
      // حالة مستمرة بين الخطوات: نمرر ناتج الخطوة السابقة عبر $PREV
      final expanded = w.expandStep(steps[i], args: args, prev: prev, workspace: repo, projectName: projName);
      // نضيف سياقاً خفيفاً كرسالة نظام خفية لتقليل هلوسة النموذج حول متغيرات القالب (لا تُحفظ)
      await send(expanded, []);
      // التقط آخر رد assistant كناتج لهذه الخطوة (للـ $PREV التالي)
      if (app.cur != null) {
        final lastAssistant = app.cur!.msgs.reversed.cast<Msg?>().firstWhere(
              (m) => m != null && m.role == 'assistant' && m.content.trim().isNotEmpty,
              orElse: () => null,
            );
        if (lastAssistant != null) prev = clip(lastAssistant.content.trim(), 6000);
      }
      if (app.stopRequested || failed) break;
    }
  }

  // === Fix1: Stream Throttler ===
  Timer? _throttle;
  final StringBuffer _pendingBuf = StringBuffer();
  final List<String> _typeQueue = [];
  Timer? _typeTimer;

  void _flushPending(_Acc acc) {
    if (_pendingBuf.isEmpty) return;
    acc.text.write(_pendingBuf.toString());
    _pendingBuf.clear();
    app.live.value = LiveMsg(acc.text.toString(), acc.reasoning.toString(), acc.toolNamesList());
    _throttle = null;
  }

  void _pushChunk(String chunk, _Acc acc) {
    if (app.streamMode == 'instant') {
      acc.text.write(chunk);
      app.live.value = LiveMsg(acc.text.toString(), acc.reasoning.toString(), acc.toolNamesList());
      return;
    }
    if (app.streamMode == 'smooth') {
      _pendingBuf.write(chunk);
      _throttle ??= Timer(Duration(milliseconds: app.smoothMs), () => _flushPending(acc));
      return;
    }
    // typewriter
    _typeQueue.addAll(chunk.split(''));
    _typeTimer ??= Timer.periodic(Duration(milliseconds: app.typewriterMs), (_) {
      if (_typeQueue.isEmpty) { _typeTimer?.cancel(); _typeTimer = null; return; }
      acc.text.write(_typeQueue.removeAt(0));
      app.live.value = LiveMsg(acc.text.toString(), acc.reasoning.toString(), acc.toolNamesList());
    });
  }

  void _drainThrottle(_Acc acc) {
    _throttle?.cancel(); _throttle = null;
    if (_pendingBuf.isNotEmpty) { acc.text.write(_pendingBuf.toString()); _pendingBuf.clear(); }
    _typeTimer?.cancel(); _typeTimer = null;
    if (_typeQueue.isNotEmpty) { acc.text.write(_typeQueue.join()); _typeQueue.clear(); }
    app.live.value = LiveMsg(acc.text.toString(), acc.reasoning.toString(), acc.toolNamesList());
  }

  void _tick(_Acc a, {bool force = false}) {
    if (force) { _drainThrottle(a); return; }
    // في وضع smooth/typewriter لا نستخدم tick القديمة للـ text، فقط للـ reasoning/tools
    if (app.streamMode != 'instant') {
      final now = DateTime.now();
      if (now.difference(_lastTick).inMilliseconds < 70) return;
      _lastTick = now;
      // reasoning يُحدّث فورياً دائماً
      if (a.reasoning.isNotEmpty) app.live.value = LiveMsg(a.text.toString(), a.reasoning.toString(), a.toolNamesList());
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastTick).inMilliseconds < 70) return;
    _lastTick = now;
    app.live.value = LiveMsg(a.text.toString(), a.reasoning.toString(), a.toolNamesList());
  }

  bool _retryable(Object e) {
    if (e is ApiError) {
      final m = e.message.toLowerCase();
      return m.contains('overloaded') || m.contains('rate limit') || m.contains('temporarily') || m.contains('timeout') || m.contains('unavailable');
    }
    try {
      final d = e as dynamic;
      final code = d.response?.statusCode;
      if (code == null) {
        final t = '${d.type}'.toLowerCase();
        return t.contains('timeout') || t.contains('connectionerror') || t.contains('unknown') || t.contains('receive');
      }
      return code == 408 || code == 429 || code >= 500;
    } catch (_) {
      return false;
    }
  }

  Future<void> _stream(ApiProfile p, String system, Conversation c, List<ToolDef> tools, _Acc acc) async {
    final hist = prepareHistory(c.msgs);
    // حجر رحى توفير التوكنز: لو التاريخ ما يزال ضخماً بعد prepare/trim، نمرّره كما هو — الطبقة التالية compactIfNeeded ستضغطه
    for (var attempt = 0;; attempt++) {
      try {
        await for (final ch in llm.chat(p, system: system, msgs: hist, tools: tools, cancel: app.cancel)) {
          if (ch.text.isNotEmpty) {
            if (app.status != 'يكتب…') { app.status = 'يكتب…'; app.refresh(); }
            // نتجنّب ازدواج الكتابة: لا نستخدم acc.add للنص، بل ندفع عبر الثروتل
            if (ch.reasoning.isNotEmpty) acc.reasoning.write(ch.reasoning);
            if (ch.toolCalls.isNotEmpty) acc.toolCalls.addAll(ch.toolCalls);
            acc.truncated = acc.truncated || ch.truncated;
            _pushChunk(ch.text, acc);
            if (app.streamMode != 'instant') _tick(acc);
          } else {
            acc.add(ch);
            _tick(acc);
          }
        }
        _tick(acc, force: true);
        return;
      } catch (e) {
        if (app.stopRequested || isCancelErr(e)) return;
        // إعادة محاولة ذكية مع backoff أسي — ولا نعيد إرسال نفس الخطأ مرات عديدة عبثاً
        final retry = acc.isEmpty && attempt < 3 && _retryable(e);
        if (!retry) {
          if (e is ApiError) rethrow;
          throw ApiError(await dioMessage(e));
        }
        app.status = 'مشكلة بالشبكة — إعادة المحاولة ${attempt + 1}/3…';
        app.refresh();
        await Future.delayed(Duration(milliseconds: 800 * (1 << attempt)));
      }
    }
  }

  Future<void> _loop(Conversation c, ApiProfile p) async {
    var steps = 0, conts = 0;
    while (!app.stopRequested) {
      steps++;
      if (app.maxSteps > 0 && steps > app.maxSteps) {
        _note(c, 'توقف الوكيل لأنه بلغ حد الخطوات (${app.maxSteps}). اكتب «تابع» للاستمرار أو ارفع الحد من الإعدادات.');
        break;
      }
      await compactIfNeeded(c, p);
      final agent = app.agent;
      final sb = Sandbox(agent, app.cwdFor(c));
      final tools = toolsFor(agent, plan: app.planMode, bridge: app.bridgeOk);
      final system = await buildSystem(c, agent, sb, tools);
      final acc = _Acc();
      app.status = 'يفكر…';
      app.refresh();
      await _stream(p, system, c, tools, acc);
      if (acc.isEmpty && !app.stopRequested) {
        _note(c, 'أعاد الخادم رداً فارغاً. جرّب موديلاً آخر، أو عطّل خيار «الأدوات» من إعدادات البروفايل إن كان الموديل لا يدعمها.');
        break;
      }
      final am = acc.toMsg();
      if (app.stopRequested) am.toolCalls = [];
      if (am.content.trim().isNotEmpty || am.reasoning.isNotEmpty || am.toolCalls.isNotEmpty) c.msgs.add(am);
      app.live.value = null;
      await app.saveConv(c);
      app.refresh();
      if (app.stopRequested) break;

      if (am.toolCalls.isEmpty) {
        if (acc.truncated && app.autoContinue && conts < 5) {
          conts++;
          c.msgs.add(Msg(role: 'user', content: 'تم قطع ردك بسبب حد الطول. تابع من حيث توقفت تماماً.', auto: true));
          continue;
        }
        final txt = am.content.trimRight();
        final asks = txt.endsWith('?') || txt.endsWith('؟');
        final open = c.todos.any((t) => t.status != 'completed');
        if (open && app.autoContinue && !asks && conts < 8 && txt.isNotEmpty) {
          conts++;
          c.msgs.add(Msg(
              role: 'user',
              content: 'تابع العمل على المهام المتبقية في القائمة حتى تكتمل كلها، ثم لخّص النتيجة.',
              auto: true));
          continue;
        }
        break;
      }

      for (final tc in am.toolCalls) {
        if (app.stopRequested) {
          c.msgs.add(Msg(role: 'tool', toolCallId: tc.id, toolName: tc.name, content: '[cancelled by user]', status: 'error'));
          continue;
        }
        await _runTool(c, tc, sb);
      }
      await app.saveConv(c);
    }
    if (app.stopRequested) _note(c, '⏹ تم الإيقاف.');
  }

  Future<void> _runTool(Conversation c, ToolCall tc, Sandbox sb) async {
    final def = toolByName(tc.name);
    final avail = toolsFor(sb.agent, plan: app.planMode, bridge: app.bridgeOk);
    var out = '';
    var status = 'ok';
    if (def == null || !avail.any((t) => t.name == tc.name)) {
      out = 'Tool "${tc.name}" is not available (unknown or disabled by the current permissions).';
      status = 'error';
    } else if (tc.error != null) {
      out = 'Tool call rejected: ${tc.error}. If the content was too long, split it into smaller pieces.';
      status = 'error';
    } else {
      if (app.needsApproval(def)) {
        final r = await app.askApproval(toolTitle(tc), toolDetail(tc), def.name);
        if (r == 0) {
          out = 'The user denied this action.';
          status = 'denied';
        }
      }
      if (status == 'ok') {
        app.status = 'ينفّذ: ${toolTitle(tc)}';
        app.refresh();
        try {
          out = await executeTool(tc, sb, c);
        } catch (e) {
          out = 'Error: $e';
          status = 'error';
        }
      }
    }
    c.msgs.add(Msg(role: 'tool', toolCallId: tc.id, toolName: tc.name, content: clip(out, 40000), status: status));
    app.refresh();
  }

  // ---------- ضغط السياق ----------
  Future<void> compactNow() async {
    final c = app.cur;
    final p = app.profile;
    if (c == null || p == null || app.running) return;
    app.running = true;
    app.cancel = CancelToken();
    app.refresh();
    try {
      await compactIfNeeded(c, p, force: true);
    } finally {
      app.running = false;
      app.status = '';
      app.refresh();
    }
  }

  Future<void> compactIfNeeded(Conversation c, ApiProfile p, {bool force = false}) async {
    final act = c.msgs.where((m) => !m.excluded && m.role != 'note').toList();
    var tokens = 0;
    for (final m in act) {
      tokens += estimateTokens(m.content);
      for (final t in m.toolCalls) {
        tokens += estimateTokens(jsonEncode(t.args));
      }
    }
    if (!force && (app.compactAt <= 0 || tokens < app.compactAt)) return;
    if (act.length < 8) {
      if (force) app.toast('المحادثة قصيرة جداً للضغط');
      return;
    }
    var cut = act.length - 6;
    while (cut > 0 && act[cut].role != 'user') {
      cut--;
    }
    if (cut < 2) return;
    final older = act.sublist(0, cut);
    final b = StringBuffer();
    for (final m in older) {
      final who = m.role == 'user' ? 'USER' : (m.role == 'assistant' ? 'ASSISTANT' : 'TOOL(${m.toolName})');
      var t = m.content;
      if (m.role == 'assistant' && m.toolCalls.isNotEmpty) {
        t = '${m.content}\n[called: ${m.toolCalls.map((x) => toolTitle(x)).join('; ')}]';
      }
      b.writeln('[$who] ${clip(t, 1500)}\n');
    }
    app.status = 'يضغط السياق…';
    app.refresh();
    final sum = StringBuffer();
    try {
      await for (final ch in llm.chat(
        p,
        system:
            'You compress conversations. Produce a dense, faithful summary that preserves: the user goals, decisions, file paths created or modified, important facts and preferences, unresolved problems, and the current task state / todo list. Write it in the same language the user used. No preamble.',
        msgs: [Msg(role: 'user', content: clip(b.toString(), 90000))],
        tools: [],
        cancel: app.cancel,
      )) {
        sum.write(ch.text);
      }
    } catch (e) {
      if (force && !isCancelErr(e)) app.toast('فشل ضغط السياق: ${await dioMessage(e)}');
      return;
    }
    if (sum.toString().trim().isEmpty) return;
    final idx = c.msgs.indexOf(act[cut]);
    for (final m in older) {
      m.excluded = true;
    }
    c.msgs.insert(idx, Msg(role: 'user', content: '[ملخص تلقائي للمحادثة السابقة — تم ضغط السياق]\n${sum.toString().trim()}', auto: true));
    await app.saveConv(c);
    app.refresh();
  }
}

// ============================================================
//  الواجهة — بنمط تطبيق Claude للموبايل
// ============================================================
void pushPage(BuildContext c, Widget w) => Navigator.of(c).push(MaterialPageRoute(builder: (_) => w));

void goFromDrawer(BuildContext ctx, Widget page) {
  final n = Navigator.of(ctx);
  n.pop();
  n.push(MaterialPageRoute(builder: (_) => page));
}

Future<String?> askText(BuildContext ctx, String title, {String initial = '', String hint = '', int lines = 1}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: ctx,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        minLines: 1,
        maxLines: lines,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('موافق')),
      ],
    ),
  );
}

Future<bool> confirmDlg(BuildContext ctx, String msg) async {
  final r = await showDialog<bool>(
    context: ctx,
    builder: (d) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تأكيد')),
      ],
    ),
  );
  return r == true;
}

Future<void> speak(FlutterTts tts, String text) async {
  final clean = text.replaceAll(RegExp(r'[#*`>_~|]'), '').replaceAll(RegExp(r'\s+'), ' ');
  try {
    await tts.setLanguage(dirOf(clean) == TextDirection.rtl ? 'ar' : 'en-US');
    await tts.speak(clean);
  } catch (_) {}
}

class LMClientApp extends StatelessWidget {
  const LMClientApp({super.key});

  ThemeData _theme(bool dark) {
    final p = Pal(dark);
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: p.bg,
      colorScheme: dark
          ? ColorScheme.dark(primary: p.accent, onPrimary: Colors.white, secondary: p.accent, surface: p.surface, onSurface: p.text)
          : ColorScheme.light(primary: p.accent, onPrimary: Colors.white, secondary: p.accent, surface: p.surface, onSurface: p.text),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(color: p.text, fontWeight: FontWeight.w700, fontSize: 16),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.text.withAlpha(230),
        contentTextStyle: TextStyle(color: p.bg, fontSize: 13, fontWeight: FontWeight.w600),
        actionTextColor: p.accent2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.dragged) ? p.accent : p.accent.withAlpha(90)),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(20),
        thumbVisibility: WidgetStateProperty.all(false),
        interactive: true,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent, linearTrackColor: p.line, circularTrackColor: p.line),
      textSelectionTheme: TextSelectionThemeData(cursorColor: p.accent, selectionColor: p.selection, selectionHandleColor: p.accent),
      dialogBackgroundColor: p.surface,
      cardColor: p.surface,
      dividerColor: p.lineSoft,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: app.uiRev,
      builder: (_, __, ___) => MaterialApp(
        title: 'LMClient',
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: messengerKey,
        theme: _theme(false),
        darkTheme: _theme(true),
        themeMode: app.themeMode,
        builder: (ctx, child) => Directionality(
          textDirection: app.rtlUi ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const HomeShell(),
      ),
    );
  }
}

// ---------------- الشاشة الرئيسية ----------------
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (ctx, _) {
        final pal = Pal.of(ctx);
        final c = app.cur;
        final p = app.profile;
        final title = (c == null || c.msgs.isEmpty) ? 'LMClient' : c.title;
        final sub = p == null ? 'اضغط لاختيار الموديل' : '${p.name} · ${p.model.isEmpty ? 'بدون موديل' : p.model}';
        return Scaffold(
          drawer: const AppDrawer(),
          appBar: AppBar(
            title: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => showModelPicker(ctx),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: pal.sub))),
                    Icon(Icons.expand_more, size: 14, color: pal.sub),
                  ]),
                ]),
              ),
            ),
            actions: [
              IconButton(icon: const Icon(Icons.edit_square), tooltip: 'محادثة جديدة', onPressed: () => app.newChat()),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  final cc = app.cur;
                  if (cc == null) return;
                  if (v == 'plan') {
                    app.planMode = !app.planMode;
                    app.refresh();
                  } else if (v == 'compact') {
                    runner.compactNow();
                  } else if (v == 'context') {
                    showContextViewer(ctx, cc);
                  } else if (v == 'rename') {
                    final t = await askText(ctx, 'اسم المحادثة', initial: cc.title);
                    if (t != null) await app.renameConv(cc, t);
                  } else if (v == 'delete') {
                    if (await confirmDlg(ctx, 'حذف هذه المحادثة؟')) await app.deleteConv(cc);
                  }
                },
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(value: 'plan', checked: app.planMode, child: const Text('وضع التخطيط (قراءة فقط)')),
                  const PopupMenuItem(value: 'compact', child: Text('ضغط السياق الآن')),
                  const PopupMenuItem(value: 'context', child: Text('عرض ما يراه النموذج')),
                  const PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                  const PopupMenuItem(value: 'delete', child: Text('حذف المحادثة')),
                ],
              ),
            ],
          ),
          body: const ChatView(),
        );
      },
    );
  }
}

void showContextViewer(BuildContext ctx, Conversation c) {
  showDialog(
    context: ctx,
    builder: (d) => AlertDialog(
      title: const Text('ما يراه النموذج بالحرف'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: SingleChildScrollView(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FutureBuilder<String>(
              future: debugContext(c),
              builder: (fb, snap) => snap.hasData
                  ? SelectableText(snap.data!, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))
                  : const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            ),
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('إغلاق'))],
    ),
  );
}

// ---------------- القائمة الجانبية ----------------
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Drawer(
      backgroundColor: pal.bg,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (ctx, _) {
            Widget nav(IconData i, String t, Widget page) => ListTile(
                  dense: true,
                  leading: Icon(i, size: 22, color: pal.sub),
                  title: Text(t),
                  onTap: () => goFromDrawer(ctx, page),
                );
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(children: [
                  Icon(Icons.auto_awesome, color: pal.accent),
                  const SizedBox(width: 8),
                  const Text('LMClient', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: pal.accent),
                    onPressed: () {
                      Navigator.pop(ctx);
                      app.newChat();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('محادثة جديدة'),
                  ),
                ),
              ),
              nav(Icons.folder_special_outlined, 'المشاريع', const ProjectsScreen()),
              nav(Icons.bolt, 'Workflows', const WorkflowsScreen()),
              nav(Icons.shield_outlined, 'الصلاحيات (Agents)', const AgentsScreen()),
              nav(Icons.memory, 'الذاكرة', const MemoryScreen()),
              nav(Icons.library_books_outlined, 'المكتبة', const LibraryScreen()),
              nav(Icons.phone_android, 'ملفات الهاتف', const PhoneFilesScreen()),
              nav(Icons.settings_outlined, 'الإعدادات', const SettingsScreen()),
              const Divider(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text('المحادثات', style: TextStyle(fontSize: 12, color: pal.sub)),
                ),
              ),
              Expanded(
                child: app.convs.isEmpty
                    ? Center(child: Text('لا توجد محادثات بعد', style: TextStyle(color: pal.sub)))
                    : ListView.builder(
                        itemCount: app.convs.length,
                        itemBuilder: (c2, i) {
                          final cv = app.convs[i];
                          final pr = firstWhereOrNull(app.projects, (p) => p.id == cv.projectId);
                          return ListTile(
                            dense: true,
                            selected: cv == app.cur,
                            title: Text(cv.title, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: dirOf(cv.title, fallback: Directionality.of(c2))),
                            subtitle: pr == null ? null : Text(pr.name, maxLines: 1, style: const TextStyle(fontSize: 11)),
                            onTap: () {
                              Navigator.pop(ctx);
                              app.openChat(cv);
                            },
                            trailing: PopupMenuButton<String>(
                              icon: Icon(Icons.more_horiz, size: 18, color: pal.sub),
                              onSelected: (v) async {
                                if (v == 'rename') {
                                  final t = await askText(ctx, 'اسم المحادثة', initial: cv.title);
                                  if (t != null) await app.renameConv(cv, t);
                                } else if (v == 'delete') {
                                  if (await confirmDlg(ctx, 'حذف «${cv.title}»؟')) await app.deleteConv(cv);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'rename', child: Text('إعادة تسمية')),
                                PopupMenuItem(value: 'delete', child: Text('حذف')),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ---------------- اختيار البروفايل والموديل ----------------
void showModelPicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => const ModelPickerSheet(),
  );
}

class ModelPickerSheet extends StatefulWidget {
  const ModelPickerSheet({super.key});
  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  String filter = '';

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.72,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: app,
          builder: (ctx, _) {
            final p = app.profile;
            if (app.profiles.isEmpty) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('لا يوجد بروفايل API بعد'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      pushPage(context, const SettingsScreen());
                    },
                    child: const Text('أضف بروفايل'),
                  ),
                ]),
              );
            }
            final models = (p?.models ?? []).where((m) => m.toLowerCase().contains(filter.toLowerCase())).toList();
            return Column(children: [
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: app.profiles
                      .map((x) => Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: ChoiceChip(
                              label: Text(x.name),
                              selected: x.id == app.profileId,
                              onSelected: (_) {
                                app.profileId = x.id;
                                app.saveProfiles();
                              },
                            ),
                          ))
                      .toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'ابحث عن موديل أو اكتب اسمه',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => filter = v),
                  onSubmitted: (v) {
                    if (p != null && v.trim().isNotEmpty) {
                      p.model = v.trim();
                      app.saveProfiles();
                      Navigator.pop(ctx);
                    }
                  },
                ),
              ),
              Expanded(
                child: p == null
                    ? const SizedBox.shrink()
                    : models.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                p.models.isEmpty
                                    ? 'لم تُجلب الموديلات بعد — افتح الإعدادات ← البروفايل ← «جلب الموديلات»، أو اكتب اسم الموديل أعلاه واضغط Enter.'
                                    : 'لا نتائج. اكتب الاسم كاملاً واضغط Enter لاستخدامه.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: pal.sub),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: models.length,
                            itemBuilder: (c2, i) => ListTile(
                              dense: true,
                              title: Text(models[i], textDirection: TextDirection.ltr),
                              trailing: models[i] == p.model ? Icon(Icons.check, color: pal.accent) : null,
                              onTap: () {
                                p.model = models[i];
                                app.saveProfiles();
                                Navigator.pop(ctx);
                              },
                            ),
                          ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ============================================================
//  عرض الماركداون (يدعم RTL لكل فقرة + كتل الكود LTR)
// ============================================================
class _Block {
  final bool code;
  final String text, lang;
  _Block(this.code, this.text, [this.lang = '']);
}

final RegExp _listLine = RegExp(r'^\s*([-*+]|\d+[.)])\s');

List<_Block> splitBlocks(String src) {
  final out = <_Block>[];
  final buf = <String>[];
  var inCode = false;
  var lang = '';

  void flushText() {
    if (buf.isEmpty) return;
    final chunks = <String>[];
    var cur = <String>[];
    void push() {
      if (cur.isNotEmpty) {
        chunks.add(cur.join('\n'));
        cur = <String>[];
      }
    }

    for (final l in buf) {
      if (l.trim().isEmpty) {
        push();
      } else {
        cur.add(l);
      }
    }
    push();
    final merged = <String>[];
    for (final ch in chunks) {
      final first = ch.split('\n').first;
      if (merged.isNotEmpty && _listLine.hasMatch(first) && _listLine.hasMatch(merged.last.split('\n').first)) {
        merged[merged.length - 1] = '${merged.last}\n$ch';
      } else {
        merged.add(ch);
      }
    }
    for (final m in merged) {
      out.add(_Block(false, m));
    }
    buf.clear();
  }

  for (final line in src.split('\n')) {
    final t = line.trimLeft();
    if (t.startsWith('```')) {
      if (!inCode) {
        flushText();
        inCode = true;
        lang = t.substring(3).trim();
      } else {
        out.add(_Block(true, buf.join('\n'), lang));
        buf.clear();
        inCode = false;
        lang = '';
      }
      continue;
    }
    buf.add(line);
  }
  if (inCode) {
    out.add(_Block(true, buf.join('\n'), lang));
  } else {
    flushText();
  }
  return out;
}

class Md extends StatelessWidget {
  final String text;
  const Md({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final base = Directionality.of(context);
    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: TextStyle(fontSize: 16, height: 1.65, color: pal.text),
      h1: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: pal.text, height: 1.25),
      h2: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: pal.text, height: 1.3),
      h3: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text, height: 1.35),
      a: TextStyle(color: pal.accent, decoration: TextDecoration.underline, fontWeight: FontWeight.w600),
      code: TextStyle(fontFamily: 'monospace', fontSize: 13.2, color: pal.text, backgroundColor: pal.code),
      blockquoteDecoration: BoxDecoration(
        color: pal.bubble,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: pal.accent.withAlpha(90), width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      listBullet: TextStyle(fontSize: 16, color: pal.accent),
      listIndent: 20,
      tableHead: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
      tableBody: TextStyle(color: pal.text, height: 1.45),
      tableBorder: TableBorder.all(color: pal.line, width: 0.9),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line, width: 1))),
    );
    final blocks = splitBlocks(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: b.code
                ? CodeBlock(code: b.text, lang: b.lang)
                : Directionality(
                    textDirection: dirOf(b.text, fallback: base),
                    child: MarkdownBody(
                      data: b.text,
                      selectable: true,
                      softLineBreak: true,
                      styleSheet: sheet,
                      onTapLink: (t, href, title) {
                        if (href != null) {
                          Clipboard.setData(ClipboardData(text: href));
                          app.toast('تم نسخ الرابط');
                        }
                      },
                    ),
                  ),
          ),
      ],
    );
  }
}

class CodeBlock extends StatefulWidget {
  final String code, lang;
  const CodeBlock({super.key, required this.code, required this.lang});
  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  bool _copied = false;
  bool _expanded = false;
  static const _collapsedLines = 28;

  String get _langLabel {
    final l = widget.lang.trim().toLowerCase();
    if (l.isEmpty) return 'code';
    const known = {'dart': 'Dart', 'js': 'JS', 'ts': 'TS', 'py': 'Python', 'python': 'Python', 'json': 'JSON', 'yaml': 'YAML', 'sh': 'Shell', 'bash': 'Bash', 'sql': 'SQL', 'html': 'HTML', 'css': 'CSS', 'md': 'MD'};
    return known[l] ?? widget.lang;
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final lines = widget.code.split('\n');
    final over = lines.length > _collapsedLines + 6;
    final show = _expanded || !over ? widget.code : '${lines.take(_collapsedLines).join('\n')}\n… +${lines.length - _collapsedLines} سطر';
    final lineCount = _expanded || !over ? lines.length : _collapsedLines;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        decoration: BoxDecoration(
          color: pal.code,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: pal.lineSoft),
          boxShadow: [BoxShadow(color: pal.shadow.withAlpha(18), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: pal.bubble.withAlpha(pal.dark ? 90 : 140),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: pal.lineSoft)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: pal.accentSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: pal.accent.withOpacity(0.14))),
                child: Text(_langLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: pal.accent)),
              ),
              const SizedBox(width: 8),
              Text('${fmtSize(widget.code.length)} • ${lines.length} سطر', style: TextStyle(fontSize: 11, color: pal.sub)),
              const Spacer(),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _copied
                    ? Container(
                        key: const ValueKey('ok'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: pal.ok.withAlpha(20),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: pal.ok.withOpacity(0.22)),
                          boxShadow: [BoxShadow(color: pal.ok.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 3))],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_rounded, size: 14, color: pal.ok),
                          const SizedBox(width: 4),
                          Text('تم النسخ', style: TextStyle(fontSize: 11, color: pal.ok, fontWeight: FontWeight.w800)),
                        ]),
                      )
                    : Container(
                        key: const ValueKey('cp'),
                        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.lineSoft)),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'نسخ الكود',
                          icon: Icon(Icons.content_copy_rounded, size: 15, color: pal.sub),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: widget.code));
                            HapticFeedback.lightImpact();
                            app.toast('تم نسخ الكود — ${fmtSize(widget.code.length)}');
                            if (!mounted) return;
                            setState(() => _copied = true);
                            Future.delayed(const Duration(milliseconds: 1400), () {
                              if (mounted) setState(() => _copied = false);
                            });
                          },
                        ),
                      ),
              ),
            ]),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
              decoration: BoxDecoration(border: Border(right: BorderSide(color: pal.lineSoft))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(lineCount, (i) => Text('${i + 1}', style: TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.45, color: pal.sub.withAlpha(150)))),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: SelectableText(show, style: TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5, color: pal.text)),
              ),
            ),
          ]),
          if (over)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.line))),
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: pal.accent),
                    const SizedBox(width: 4),
                    Text(_expanded ? 'طي الكود' : 'عرض كامل (${lines.length} سطر)', style: TextStyle(fontSize: 12, color: pal.accent, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

// ============================================================
//  عناصر الرسائل
// ============================================================
class ReasoningTile extends StatefulWidget {
  final String text;
  final bool initiallyOpen;
  const ReasoningTile({super.key, required this.text, this.initiallyOpen = false});
  @override
  State<ReasoningTile> createState() => _ReasoningTileState();
}

class _ReasoningTileState extends State<ReasoningTile> {
  late bool open = widget.initiallyOpen;
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: pal.bubble.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: open ? pal.accent.withOpacity(0.14) : pal.lineSoft),
        boxShadow: open ? [BoxShadow(color: pal.starGlow.withOpacity(0.5), blurRadius: 14, offset: const Offset(0, 4))] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Icon(Icons.psychology_outlined, size: 18, color: pal.sub),
              const SizedBox(width: 6),
              Text('التفكير', style: TextStyle(fontSize: 13, color: pal.sub)),
              const Spacer(),
              Icon(open ? Icons.expand_less : Icons.expand_more, size: 18, color: pal.sub),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SelectableText(widget.text,
                textDirection: dirOf(widget.text, fallback: Directionality.of(context)),
                style: TextStyle(fontSize: 13, height: 1.5, color: pal.sub)),
          ),
      ]),
    );
  }
}

class ToolCard extends StatefulWidget {
  final ToolCall call;
  final Msg? result;
  final bool running;
  const ToolCard({super.key, required this.call, this.result, required this.running});
  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool open = false;
  void _copyToolArgs() {
    final s = widget.call.args.isEmpty ? '' : const JsonEncoder.withIndent('  ').convert(widget.call.args);
    Clipboard.setData(ClipboardData(text: s.isEmpty ? widget.call.name : '${widget.call.name}\n$s'));
    app.toast('تم نسخ مُدخلات الأداة');
  }

  void _copyToolResult() {
    final r = widget.result;
    if (r == null) return;
    Clipboard.setData(ClipboardData(text: r.content));
    app.toast('تم نسخ ناتج الأداة — ${fmtSize(r.content.length)}');
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final r = widget.result;
    Widget statusIcon;
    if (r == null) {
      statusIcon = widget.running
          ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: pal.accent))
          : Icon(Icons.more_horiz, size: 18, color: pal.sub);
    } else if (r.status == 'ok') {
      statusIcon = Icon(Icons.check_circle_outline, size: 18, color: pal.ok);
    } else if (r.status == 'denied') {
      statusIcon = Icon(Icons.block, size: 18, color: pal.sub);
    } else {
      statusIcon = Icon(Icons.error_outline, size: 18, color: pal.bad);
    }
    final args = const JsonEncoder.withIndent('  ').convert(widget.call.args);
    final bool ok = r != null && r.status == 'ok';
    final bool err = r != null && r.status != 'ok' && r.status != 'denied';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ok ? pal.ok.withOpacity(0.22) : err ? pal.bad.withOpacity(0.18) : r == null && widget.running ? pal.accent.withOpacity(0.16) : pal.lineSoft),
        boxShadow: open ? [BoxShadow(color: pal.starGlow.withOpacity(0.5), blurRadius: 14, offset: const Offset(0, 4))] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(color: pal.accentSoft, borderRadius: BorderRadius.circular(8), border: Border.all(color: pal.accent.withOpacity(0.14))),
                child: Icon(toolIcon(widget.call.name), size: 16, color: pal.accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(toolTitle(widget.call),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: dirOf(toolTitle(widget.call), fallback: Directionality.of(context)),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.text)),
              ),
              const SizedBox(width: 8),
              statusIcon,
            ]),
          ),
        ),
        if (open)
          Directionality(
            textDirection: TextDirection.ltr,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: pal.code.withOpacity(0.85), borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.lineSoft)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('args', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: pal.sub))),
                    InkWell(onTap: _copyToolArgs, child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.content_copy_rounded, size: 13, color: pal.sub))),
                  ]),
                  const SizedBox(height: 4),
                  SelectableText(clip(args, 1500), style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.5, color: pal.text)),
                  if (r != null) ...[
                    const SizedBox(height: 10),
                    Divider(height: 1, color: pal.lineSoft),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: Text('result', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: pal.sub))),
                      InkWell(onTap: _copyToolResult, child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.content_copy_rounded, size: 13, color: pal.sub))),
                    ]),
                    const SizedBox(height: 4),
                    SelectableText(clip(r.content, 3000), style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.5, color: pal.text)),
                  ],
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class MessageItem extends StatelessWidget {
  final Msg msg;
  final Map<String, Msg> results;
  final Conversation conv;
  final FlutterTts tts;
  const MessageItem({super.key, required this.msg, required this.results, required this.conv, required this.tts});

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final base = Directionality.of(context);
    final w = MediaQuery.of(context).size.width;

    if (msg.role == 'note') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: pal.bad.withAlpha(28), borderRadius: BorderRadius.circular(12)),
        child: SelectableText(msg.content, textDirection: dirOf(msg.content, fallback: base), style: TextStyle(fontSize: 14, color: pal.text)),
      );
    }

    if (msg.role == 'user') {
      if (msg.auto) {
        final label = msg.content.startsWith('[ملخص') ? '🗜 تم ضغط السياق تلقائياً' : '▶ متابعة تلقائية';
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: pal.bubble, borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(fontSize: 12, color: pal.sub)),
          ),
        );
      }
      return Opacity(
        opacity: msg.excluded ? 0.45 : 1,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: w * 0.86),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: pal.bubble, borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (msg.files.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: msg.files
                            .map((f) => Chip(
                                  visualDensity: VisualDensity.compact,
                                  avatar: Icon(f.isImage ? Icons.image : Icons.insert_drive_file, size: 16),
                                  label: Text(f.name, style: const TextStyle(fontSize: 11)),
                                ))
                            .toList(),
                      ),
                    ),
                  if (msg.content.isNotEmpty)
                    SelectableText(msg.content,
                        textDirection: dirOf(msg.content, fallback: base),
                        style: TextStyle(fontSize: 16, height: 1.5, color: pal.text)),
                ]),
              ),
              InkWell(
                onTap: () => showMsgSheet(context, conv, msg, tts),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Icon(Icons.more_horiz, size: 18, color: pal.sub),
                ),
              ),
            ]),
          ),
        ),
      );
    }

    // assistant
    return Opacity(
      opacity: msg.excluded ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (msg.reasoning.isNotEmpty) ReasoningTile(text: msg.reasoning),
          if (msg.content.trim().isNotEmpty) Md(text: msg.content),
          for (final tc in msg.toolCalls) ToolCard(call: tc, result: results[tc.id], running: app.running),
          if (msg.content.trim().isNotEmpty)
            Row(children: [
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: msg.content));
                  app.toast('تم النسخ');
                },
                child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.content_copy, size: 16, color: pal.sub)),
              ),
              InkWell(
                onTap: () => showMsgSheet(context, conv, msg, tts),
                child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.more_horiz, size: 18, color: pal.sub)),
              ),
              const Spacer(),
              Text('~${estimateTokens(msg.content)} tok', style: TextStyle(fontSize: 10, color: pal.sub)),
            ]),
        ]),
      ),
    );
  }
}

void showMsgSheet(BuildContext context, Conversation c, Msg m, FlutterTts tts) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) {
      Widget item(IconData i, String t, VoidCallback f) => ListTile(
            leading: Icon(i),
            title: Text(t),
            onTap: () {
              Navigator.pop(ctx);
              f();
            },
          );
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          item(Icons.copy, 'نسخ', () {
            Clipboard.setData(ClipboardData(text: m.content));
            app.toast('تم النسخ');
          }),
          if (m.role == 'assistant' && m.content.isNotEmpty) item(Icons.volume_up, 'استماع', () => speak(tts, m.content)),
          if (m.role == 'assistant' && m.content.isNotEmpty)
            item(Icons.bookmark_add, 'حفظ في الذاكرة', () async {
              final t = await askText(context, 'عنوان جزء الذاكرة', initial: 'من الشات ${DateTime.now().day}/${DateTime.now().month}');
              if (t != null && t.trim().isNotEmpty) {
                app.memory.add(MemoryPart(id: newId(), title: t.trim(), content: m.content));
                await app.saveMemory();
                app.toast('تم الحفظ في الذاكرة');
              }
            }),
          item(Icons.edit, 'تعديل', () async {
            final t = await askText(context, 'تعديل الرسالة', initial: m.content, lines: 10);
            if (t != null) {
              m.content = t;
              await app.saveConv(c);
              app.refresh();
            }
          }),
          item(m.excluded ? Icons.visibility : Icons.visibility_off, m.excluded ? 'تضمين في السياق' : 'استبعاد من السياق', () async {
            m.excluded = !m.excluded;
            await app.saveConv(c);
            app.refresh();
          }),
          if (m.role == 'user')
            item(Icons.refresh, 'إعادة التوليد من هنا', () async {
              if (app.running) {
                app.toast('أوقف التنفيذ الحالي أولاً');
                return;
              }
              final i = c.msgs.indexOf(m);
              if (i >= 0) c.msgs.removeRange(i + 1, c.msgs.length);
              await app.saveConv(c);
              app.refresh();
              runner.resume();
            }),
          item(Icons.delete_outline, 'حذف', () async {
            if (app.running) {
              app.toast('أوقف التنفيذ الحالي أولاً');
              return;
            }
            c.msgs.remove(m);
            if (m.toolCalls.isNotEmpty) {
              final ids = m.toolCalls.map((t) => t.id).toSet();
              c.msgs.removeWhere((x) => x.role == 'tool' && ids.contains(x.toolCallId));
            }
            await app.saveConv(c);
            app.refresh();
          }),
        ]),
      );
    },
  );
}

// ============================================================
//  شاشة الدردشة
// ============================================================
class ChatView extends StatefulWidget {
  const ChatView({super.key});
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController ctrl = TextEditingController();
  final ScrollController scroll = ScrollController();
  final FlutterTts tts = FlutterTts();
  final SpeechToText stt = SpeechToText();
  List<Attachment> pending = [];
  bool listening = false, todosOpen = false;
  late TextDirection inputDir = app.rtlUi ? TextDirection.rtl : TextDirection.ltr;

  @override
  void initState() {
    super.initState();
    app.live.addListener(_stick);
    app.addListener(_onApp);
    ctrl.addListener(_onText);
  }

  @override
  void dispose() {
    app.live.removeListener(_stick);
    app.removeListener(_onApp);
    try { ctrl.dispose(); } catch (_) {}
    scroll.dispose();
    _focus.dispose();
    tts.stop(); stt.cancel();
    super.dispose();
  }

  void _onApp() {
    if (mounted) setState(() {});
    _stick();
  }

  void _onText() {
    final d = dirOf(ctrl.text, fallback: app.rtlUi ? TextDirection.rtl : TextDirection.ltr);
    if (d != inputDir && mounted) setState(() => inputDir = d);
  }

  // === Fix2+3: Composer focus + keyboard inset + history ===
  final FocusNode _focus = FocusNode();
  final _history = <String>[]; int _hIdx = -1;
  bool _kbdVisible = false;

  void _stick() {
    if (!scroll.hasClients) return;
    final pos = scroll.position;
    if (pos.maxScrollExtent - pos.pixels < 180) _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
    });
  }

  void _pushHistory(String t) {
    final s = t.trim(); if (s.isEmpty) return;
    _history.remove(s); _history.insert(0, s); if (_history.length > 80) _history.removeLast(); _hIdx = -1;
  }
  void _historyNav(bool up) {
    if (_history.isEmpty) return;
    if (up) { if (_hIdx < _history.length - 1) { _hIdx++; ctrl.text = _history[_hIdx]; ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length); setState(() {}); } }
    else { if (_hIdx > 0) { _hIdx--; ctrl.text = _history[_hIdx]; ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length); setState(() {}); } else if (_hIdx == 0) { _hIdx = -1; ctrl.clear(); setState(() {}); } }
  }

  KeyEventResult _handleKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final isEnter = e.logicalKey == LogicalKeyboardKey.enter;
    final isUp = e.logicalKey == LogicalKeyboardKey.arrowUp, isDown = e.logicalKey == LogicalKeyboardKey.arrowDown;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (isEnter && !shift) { _send(); return KeyEventResult.handled; }
    if (isUp) { if (ctrl.text.trim().isEmpty || ctrl.selection.baseOffset == 0) { _historyNav(true); return KeyEventResult.handled; } }
    if (isDown) { if (_hIdx != -1) { _historyNav(false); return KeyEventResult.handled; } }
    return KeyEventResult.ignored;
  }

  Future<void> _attach() async {
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (res == null) return;
      final list = <Attachment>[];
      for (final f in res.files) {
        List<int>? bytes = f.bytes;
        if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
        if (bytes == null) continue;
        list.add(await app.importBytes(f.name, bytes));
      }
      if (mounted) setState(() => pending = [...pending, ...list]);
    } catch (e) {
      app.toast('تعذر إرفاق الملف: $e');
    }
  }

  void _send() {
    final t = ctrl.text.trim();
    if (t.isEmpty && pending.isEmpty) return;
    _pushHistory(t);
    final files = List<Attachment>.from(pending);
    ctrl.clear();
    setState(() => pending = []);
    _focus.requestFocus();
    runner.send(t, files);
    _toBottom();
  }

  Future<void> _toggleListen() async {
    if (listening) {
      await stt.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    final ok = await stt.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) setState(() => listening = false);
      },
      onError: (e) {
        if (mounted) setState(() => listening = false);
      },
    );
    if (!ok) {
      app.toast('التعرف على الصوت غير متاح — تحقق من صلاحية الميكروفون');
      return;
    }
    String? locale;
    if (app.rtlUi) {
      try {
        final ls = await stt.locales();
        final ar = ls.where((l) => l.localeId.toLowerCase().startsWith('ar')).toList();
        if (ar.isNotEmpty) locale = ar.first.localeId;
      } catch (_) {}
    }
    final base = ctrl.text;
    if (mounted) setState(() => listening = true);
    stt.listen(
      localeId: locale,
      onResult: (r) {
        final t = r.recognizedWords;
        ctrl.text = base.isEmpty ? t : '$base $t';
        ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
      },
    );
  }

  void _moveCursor(bool right) {
    final p = ctrl.selection.baseOffset;
    if (p < 0) return;
    var d = right ? 1 : -1;
    if (inputDir == TextDirection.rtl) d = -d;
    ctrl.selection = TextSelection.collapsed(offset: clampInt(p + d, 0, ctrl.text.length));
  }

  void _pickWorkflow() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          if (app.workflows.isEmpty) const ListTile(title: Text('لا توجد Workflows بعد')),
          for (final w in app.workflows)
            ListTile(
              leading: Icon(Icons.bolt, color: Pal.of(ctx).accent),
              title: Text(w.name),
              subtitle: w.desc.isEmpty ? null : Text(w.desc),
              onTap: () {
                Navigator.pop(ctx);
                _runWorkflow(w);
              },
            ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('إدارة Workflows'),
            onTap: () {
              Navigator.pop(ctx);
              pushPage(context, const WorkflowsScreen());
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _runWorkflow(Workflow w) async {
    var args = '';
    if (w.steps.any((s) => s.contains('\$ARGS'))) {
      final t = await askText(context, w.name, hint: 'اكتب التفاصيل / المتطلبات', lines: 6);
      if (t == null) return;
      args = t;
    }
    runner.runWorkflow(w, args);
    _toBottom();
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final c = app.cur;
    if (c == null) return const SizedBox.shrink();
    final msgs = c.msgs.where((m) => m.role != 'tool').toList();
    final results = <String, Msg>{
      for (final m in c.msgs)
        if (m.role == 'tool' && m.toolCallId != null) m.toolCallId!: m
    };
    return Column(children: [
      Expanded(
        child: (msgs.isEmpty && app.live.value == null)
            ? _empty(pal)
            : ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: msgs.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == msgs.length) return _liveItem();
                  return MessageItem(msg: msgs[i], results: results, conv: c, tts: tts);
                },
              ),
      ),
      _statusBar(pal),
      _approvalCard(pal),
      _todoBar(pal, c),
      _composer(pal),
    ]);
  }

  Widget _empty(Pal pal) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, size: 44, color: pal.accent),
          const SizedBox(height: 14),
          const Text('كيف أقدر أساعدك اليوم؟', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('وكيل ذكي يخطط وينفّذ ويتحقق — بملفاتك وأدواتك', textAlign: TextAlign.center, style: TextStyle(color: pal.sub)),
          const SizedBox(height: 18),
          if (app.profile == null)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: pal.accent),
              onPressed: () => pushPage(context, const SettingsScreen()),
              icon: const Icon(Icons.key),
              label: const Text('أضف بروفايل API للبدء'),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: app.workflows
                  .take(4)
                  .map((w) => ActionChip(
                        avatar: Icon(Icons.bolt, size: 16, color: pal.accent),
                        label: Text(w.name),
                        onPressed: () => _runWorkflow(w),
                      ))
                  .toList(),
            ),
        ]),
      ),
    );
  }

  Widget _liveItem() {
    return ValueListenableBuilder<LiveMsg?>(
      valueListenable: app.live,
      builder: (ctx, l, _) {
        if (l == null) return const SizedBox.shrink();
        final pal = Pal.of(ctx);
        final liveTokens = (l.text.isEmpty ? 0 : estimateTokens(l.text)) + (l.reasoning.isEmpty ? 0 : estimateTokens(l.reasoning) ~/ 2);
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Color(0x14D97757)),
            boxShadow: [BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: Offset(0, 3))],
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(colors: [Color(0x08D97757), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (l.reasoning.isNotEmpty) ReasoningTile(text: l.reasoning, initiallyOpen: l.text.isEmpty),
            if (l.text.isNotEmpty)
              Stack(children: [
                Md(text: l.text),
                if (app.running)
                  PositionedDirectional(
                    bottom: 0,
                    end: dirOf(l.text) == TextDirection.rtl ? null : 0,
                    start: dirOf(l.text) == TextDirection.rtl ? 0 : null,
                    child: Container(width: 8, height: 16, decoration: BoxDecoration(color: pal.accent, borderRadius: BorderRadius.circular(2))),
                  ),
              ]),
            if (l.tools.isNotEmpty)
              for (final t in l.tools)
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: pal.accent.withAlpha(10), borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.accent.withAlpha(14))),
                  child: Row(children: [
                    Icon(toolIcon(t), size: 14, color: pal.accent),
                    const SizedBox(width: 6),
                    Expanded(child: Text('يجهّز أداة: $t', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: pal.text))),
                    if (liveTokens > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: pal.line)),
                        child: Text('~$liveTokens tok', style: TextStyle(fontSize: 10, color: pal.sub)),
                      ),
                  ]),
                ),
            if (l.text.isEmpty && l.reasoning.isEmpty && l.tools.isEmpty)
              Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: pal.accent)),
                const SizedBox(width: 10),
                Row(children: List.generate(3, (i) => Container(width: 6, height: 6, margin: EdgeInsets.only(left: i == 2 ? 0 : 4), decoration: BoxDecoration(color: pal.accent.withAlpha(190 - i * 40), shape: BoxShape.circle)))),
                const SizedBox(width: 8),
                Text('يفكّر…', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.sub)),
                const Spacer(),
                if (liveTokens > 0)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: pal.bubble, borderRadius: BorderRadius.circular(20)), child: Text('~$liveTokens', style: TextStyle(fontSize: 11, color: pal.sub))),
              ]),
            if (l.text.isNotEmpty && app.running)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: pal.ok, shape: BoxShape.circle, boxShadow: [BoxShadow(color: pal.ok.withAlpha(90), blurRadius: 6)])),
                  const SizedBox(width: 6),
                  Text('~$liveTokens tok · ستريمنغ حيّ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: pal.sub.withAlpha(190))),
                ]),
              ),
          ]),
        );
      },
    );
  }

  Widget _statusBar(Pal pal) {
    if (!app.running) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [pal.surface, pal.bubble.withAlpha(150)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x24D97757)),
        boxShadow: [BoxShadow(color: const Color(0x0A000000), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: pal.accent.withAlpha(18), shape: BoxShape.circle),
          child: Padding(padding: const EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2, color: pal.accent)),
        ),
        const SizedBox(width: 8),
        Container(width: 7, height: 7, decoration: BoxDecoration(color: pal.ok, shape: BoxShape.circle, boxShadow: [BoxShadow(color: pal.ok.withAlpha(90), blurRadius: 6)])),
        const SizedBox(width: 8),
        Expanded(child: Text(app.status, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: pal.text))),
        if (app.planMode)
          Container(
            margin: const EdgeInsetsDirectional.only(start: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: pal.accent.withAlpha(16), borderRadius: BorderRadius.circular(20), border: Border.all(color: pal.accent.withAlpha(28))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, size: 11, color: pal.accent), const SizedBox(width: 4), Text('وضع التخطيط', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: pal.accent))]),
          ),
      ]),
    );
  }

  Widget _approvalCard(Pal pal) {
    final a = app.pending;
    if (a == null) return const SizedBox.shrink();
    final danger = a.title.contains('حذف') || a.title.contains('كتابة') || a.title.toLowerCase().contains('delete') || a.title.toLowerCase().contains('write');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: danger ? const Color(0x2EE57373) : const Color(0x2ED97757), width: 1.2),
        boxShadow: [BoxShadow(color: (danger ? const Color(0xFFE57373) : pal.accent).withAlpha(16), blurRadius: 14, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: danger ? const Color(0xFFE57373).withAlpha(10) : pal.accent.withAlpha(10),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border(bottom: BorderSide(color: danger ? const Color(0xFFE57373).withAlpha(18) : pal.accent.withAlpha(14))),
          ),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: danger ? const Color(0xFFE57373).withAlpha(16) : pal.accent.withAlpha(14), shape: BoxShape.circle),
              child: Icon(danger ? Icons.warning_amber_rounded : Icons.shield_outlined, size: 16, color: danger ? const Color(0xFFE57373) : pal.accent),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('طلب إذن: ${a.title}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: pal.text))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: danger ? const Color(0xFFE57373) : pal.accent, borderRadius: BorderRadius.circular(20)),
              child: Text(danger ? 'حساس' : 'إذن', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 130),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: pal.code, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.line)),
              child: SingleChildScrollView(
                child: Directionality(textDirection: TextDirection.ltr, child: SelectableText(a.detail, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: pal.text))),
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE57373), side: const BorderSide(color: Color(0x40E57373)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () => app.answerApproval(0),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.close, size: 14), SizedBox(width: 4), Text('رفض')]),
              ),
              const Spacer(),
              TextButton(onPressed: () => app.answerApproval(2), child: Text('دائماً (هذه الجلسة)', style: TextStyle(color: pal.sub, fontSize: 12))),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: danger ? const Color(0xFFE57373) : pal.ok, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                onPressed: () => app.answerApproval(1),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(danger ? Icons.warning_amber_rounded : Icons.check, size: 14, color: Colors.white), const SizedBox(width: 4), const Text('سماح')]),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _todoBar(Pal pal, Conversation c) {
    if (c.todos.isEmpty) return const SizedBox.shrink();
    final done = c.todos.where((t) => t.status == 'completed').length;
    final remain = c.todos.length - done;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: remain == 0 ? pal.ok.withAlpha(90) : pal.line),
        boxShadow: remain == 0 ? [BoxShadow(color: pal.ok.withAlpha(18), blurRadius: 10)] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => todosOpen = !todosOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Icon(Icons.checklist, size: 18, color: pal.accent),
              const SizedBox(width: 8),
              Text(remain == 0 ? 'اكتملت كل المهام ✓  $done/${c.todos.length}' : 'المهام  $done/${c.todos.length} — باقٍ $remain',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: remain == 0 ? pal.ok : null)),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: c.todos.isEmpty ? 0 : done / c.todos.length, minHeight: 5, color: pal.accent, backgroundColor: pal.bubble),
                ),
              ),
              const SizedBox(width: 8),
              Icon(todosOpen ? Icons.expand_more : Icons.expand_less, size: 18, color: pal.sub),
            ]),
          ),
        ),
        if (todosOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: c.todos.map((t) {
                final isDone = t.status == 'completed';
                final cur = t.status == 'in_progress';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(isDone ? Icons.check_circle : (cur ? Icons.play_circle_outline : Icons.radio_button_unchecked),
                        size: 18, color: isDone ? pal.ok : (cur ? pal.accent : pal.sub)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(t.text,
                          textDirection: dirOf(t.text, fallback: Directionality.of(context)),
                          style: TextStyle(
                              fontSize: 13,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                              color: isDone ? pal.sub : pal.text)),
                    ),
                  ]),
                );
              }).toList(),
            ),
          ),
      ]),
    );
  }

  // === Fix2+3: Composer أسطوري كامل ===
  Widget _composer(Pal pal) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 0),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Container(
            decoration: BoxDecoration(
              color: pal.surface, borderRadius: BorderRadius.circular(26), border: Border.all(color: pal.line),
              boxShadow: [BoxShadow(color: pal.shadow, blurRadius: 10, offset: const Offset(0, 3))],
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (pending.isNotEmpty)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: pending
                        .map((f) => Padding(
                              padding: const EdgeInsetsDirectional.only(end: 6),
                              child: Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(f.isImage ? Icons.image : Icons.insert_drive_file, size: 16),
                                label: Text(f.name, style: const TextStyle(fontSize: 11)),
                                onDeleted: () => setState(() => pending.remove(f)),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              Focus(
                onKeyEvent: _handleKey,
                child: TextField(
                  controller: ctrl,
                  focusNode: _focus,
                  autofocus: false,
                  minLines: 1,
                  maxLines: 8,
                  textDirection: inputDir,
                  cursorColor: pal.accent,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  onSubmitted: (_) => _send(),
                  onTap: _toBottom,
                  style: TextStyle(fontSize: 16, height: 1.4, color: pal.text),
                  decoration: InputDecoration(
                    hintTextDirection: inputDir,
                    hintText: app.running
                        ? (inputDir == TextDirection.rtl ? 'الوكيل يعمل… اكتب للمتابعة بعد الانتهاء' : 'Agent working… type to continue')
                        : (inputDir == TextDirection.rtl ? 'اكتب رسالتك… (Enter إرسال • Shift+Enter سطر جديد  ↑↓ التاريخ)' : 'Type a message… (Enter send • Shift+Enter new line)'),
                    hintStyle: TextStyle(color: pal.sub.withOpacity(0.7), fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              Row(children: [
                IconButton(icon: Icon(Icons.add, color: pal.sub), tooltip: 'إرفاق ملف', onPressed: _attach),
                IconButton(icon: Icon(Icons.bolt, color: pal.sub), tooltip: 'Workflows', onPressed: _pickWorkflow),
                IconButton(icon: Icon(listening ? Icons.mic : Icons.mic_none, color: listening ? pal.accent : pal.sub), tooltip: 'إملاء صوتي', onPressed: _toggleListen),
                IconButton(
                  icon: Icon(Icons.history, size: 18, color: _history.isEmpty ? pal.sub.withOpacity(0.35) : pal.sub),
                  tooltip: _history.isEmpty ? 'لا يوجد تاريخ' : 'السابق ↑ (${_history.length})',
                  onPressed: _history.isEmpty ? null : () => _historyNav(true),
                ),
                if (app.cursorKeys) ...[
                  Container(width: 1, height: 20, color: pal.line, margin: const EdgeInsets.symmetric(horizontal: 4)),
                  IconButton(icon: Icon(Icons.arrow_back, size: 18, color: pal.sub), tooltip: 'حرف للخلف', onPressed: () => _moveCursor(false)),
                  IconButton(icon: Icon(Icons.arrow_forward, size: 18, color: pal.sub), tooltip: 'حرف للأمام', onPressed: () => _moveCursor(true)),
                ],
                const Spacer(),
                ValueListenableBuilder<LiveMsg?>(
                  valueListenable: app.live,
                  builder: (_, l, __) {
                    final hasText = ctrl.text.trim().isNotEmpty || pending.isNotEmpty;
                    final canSend = hasText && !app.running;
                    return Material(
                      color: canSend ? pal.accent : (app.running ? pal.bad : pal.sub.withAlpha(90)),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: app.running ? app.stop : (canSend ? _send : null),
                        child: SizedBox(
                          width: 40, height: 40,
                          child: Icon(app.running ? Icons.stop : (hasText ? Icons.arrow_upward : Icons.auto_awesome), color: Colors.white, size: app.running ? 22 : 20),
                        ),
                      ),
                    );
                  },
                ),
              ]),
              if (_history.isNotEmpty && _hIdx != -1)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('↑↓ للتنقّل • ${_hIdx + 1}/${_history.length}', style: TextStyle(fontSize: 10, color: pal.sub.withOpacity(0.55))),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ============================================================
//  شاشات إضافية
// ============================================================
Widget _fab(BuildContext context, VoidCallback f) => FloatingActionButton(
      backgroundColor: Pal.of(context).accent,
      foregroundColor: Colors.white,
      onPressed: f,
      child: const Icon(Icons.add),
    );

Widget _emptyMsg(String t) => Builder(builder: (context) {
      final pal = Pal.of(context);
      final parts = t.split('\n');
      final title = parts.first.trim();
      final sub = parts.length > 1 ? parts.skip(1).join('\n').trim() : '';
      IconData icon = Icons.inbox_outlined;
      if (t.contains('مشروع')) icon = Icons.folder_special_outlined;
      else if (t.contains('ذاكرة')) icon = Icons.psychology_outlined;
      else if (t.contains('مكتبة')) icon = Icons.library_books_outlined;
      else if (t.contains('Workflow')) icon = Icons.bolt_outlined;
      else if (t.contains('Agent') || t.contains('وكيل')) icon = Icons.smart_toy_outlined;
      else if (t.contains('المجلد فارغ') || t.contains('فارغ')) icon = Icons.folder_open_rounded;
      else if (t.contains('لا نتائج')) icon = Icons.search_off_rounded;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: pal.accentSoft,
                shape: BoxShape.circle,
                border: Border.all(color: pal.accent.withOpacity(0.18)),
                boxShadow: [BoxShadow(color: pal.starGlow.withOpacity(0.6), blurRadius: 18, offset: const Offset(0, 6))],
              ),
              child: Icon(icon, size: 28, color: pal.accent),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: pal.text, height: 1.4)),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, height: 1.6, color: pal.sub)),
            ],
          ]),
        ),
      );
    });

// ---------------- المشاريع ----------------
Future<void> editProject(BuildContext ctx, Project? p) async {
  final n = TextEditingController(text: p?.name ?? '');
  final sys = TextEditingController(text: (p?.systemPrompt.isNotEmpty == true ? p!.systemPrompt : p?.instructions ?? ''));
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (d) {
      final pal = Pal.of(d);
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          Icon(p == null ? Icons.folder_special_outlined : Icons.edit_outlined, color: pal.accent, size: 20),
          const SizedBox(width: 8),
          Text(p == null ? 'مشروع جديد' : 'تعديل المشروع', style: const TextStyle(fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: n,
              textDirection: dirOf(n.text, fallback: TextDirection.rtl),
              decoration: InputDecoration(
                labelText: 'اسم المشروع',
                hintText: 'مثلاً: متجر إلكتروني',
                prefixIcon: const Icon(Icons.title, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: sys,
              minLines: 3,
              maxLines: 8,
              textDirection: dirOf(sys.text, fallback: TextDirection.rtl),
              decoration: InputDecoration(
                labelText: 'تعليمات المشروع — System Prompt',
                hintText: 'تُرسل قبل كل محادثة داخل هذا المشروع (3 طبقات: عام + مشروع + محادثة)',
                prefixIcon: const Icon(Icons.psychology_outlined, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
                filled: true,
                fillColor: pal.surface,
              ),
            ),
            const SizedBox(height: 6),
            Text('تُحفظ في Project.systemPrompt — مع ترحيل تلقائي من instructions القديم.', style: TextStyle(fontSize: 11, color: pal.sub)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
        ],
      );
    },
  );
  if (ok != true || n.text.trim().isEmpty) return;
  final cleaned = clip(sys.text.trim(), 8000);
  if (p == null) {
    app.projects.add(Project(id: newId(), name: clip(n.text.trim(), 120), instructions: cleaned, systemPrompt: cleaned));
  } else {
    p.name = clip(n.text.trim(), 120);
    p.instructions = cleaned;
    p.systemPrompt = cleaned;
  }
  await app.saveProjects();
}

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المشاريع')),
      floatingActionButton: _fab(context, () => editProject(context, null)),
      body: ListenableBuilder(
        listenable: app,
        builder: (ctx, _) {
          if (app.projects.isEmpty) return _emptyMsg('لا توجد مشاريع.\nكل مشروع له تعليماته ومجلد عمل مستقل يبني فيه الوكيل ملفاته.');
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: app.projects.length,
            itemBuilder: (c, i) {
              final p = app.projects[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_special_outlined),
                  title: Text(p.name),
                  subtitle: Text(p.instructions.isEmpty ? 'بدون تعليمات' : p.instructions, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => pushPage(ctx, ProjectPage(project: p)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirmDlg(ctx, 'حذف المشروع «${p.name}»؟ (ملفاته تبقى في مجلد العمل)')) {
                        app.projects.remove(p);
                        await app.saveProjects();
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ProjectPage extends StatelessWidget {
  final Project project;
  const ProjectPage({super.key, required this.project});
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return ListenableBuilder(
      listenable: app,
      builder: (ctx, _) {
        final chats = app.convs.where((c) => c.projectId == project.id).toList();
        final dir = '${app.workspace.path}/${project.folder}';
        return Scaffold(
          appBar: AppBar(title: Text(project.name), actions: [
            IconButton(icon: const Icon(Icons.edit), onPressed: () => editProject(ctx, project)),
          ]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('التعليمات', style: TextStyle(fontSize: 12, color: pal.sub)),
                  const SizedBox(height: 4),
                  Text(project.instructions.isEmpty ? 'بدون تعليمات — اضغط ✏️ للإضافة' : project.instructions,
                      textDirection: dirOf(project.instructions, fallback: Directionality.of(ctx))),
                  const SizedBox(height: 10),
                  Text('مجلد العمل', style: TextStyle(fontSize: 12, color: pal.sub)),
                  Directionality(textDirection: TextDirection.ltr, child: SelectableText(dir, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
                  const SizedBox(height: 4),
                  Text('نصيحة: ضع ملف CLAUDE.md في المجلد ليقرأه الوكيل تلقائياً كذاكرة للمشروع.', style: TextStyle(fontSize: 11, color: pal.sub)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: pal.accent),
                  onPressed: () {
                    app.newChat(projectId: project.id);
                    Navigator.of(ctx).popUntil((r) => r.isFirst);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('محادثة جديدة'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Directory(dir).createSync(recursive: true);
                    pushPage(ctx, PhoneFilesScreen(initialPath: dir));
                  },
                  icon: const Icon(Icons.folder_open),
                  label: const Text('ملفات المشروع'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Text('محادثات المشروع', style: TextStyle(fontSize: 12, color: pal.sub)),
            if (chats.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text('لا توجد محادثات بعد', style: TextStyle(color: pal.sub))),
            ...chats.map((c) => ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () async {
                    await app.openChat(c);
                    if (ctx.mounted) Navigator.of(ctx).popUntil((r) => r.isFirst);
                  },
                )),
          ]),
        );
      },
    );
  }
}

// ---------------- Workflows ----------------
class WorkflowsScreen extends StatelessWidget {
  const WorkflowsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workflows')),
      floatingActionButton: _fab(context, () => pushPage(context, const WorkflowEditor())),
      body: ListenableBuilder(
        listenable: app,
        builder: (ctx, _) {
          if (app.workflows.isEmpty) return _emptyMsg('لا توجد Workflows');
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: app.workflows.length,
            itemBuilder: (c, i) {
              final w = app.workflows[i];
              return Card(
                child: ListTile(
                  leading: Icon(Icons.bolt, color: Pal.of(ctx).accent),
                  title: Text(w.name),
                  subtitle: Text('${w.steps.length} خطوات${w.desc.isEmpty ? '' : ' · ${w.desc}'}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => pushPage(ctx, WorkflowEditor(workflow: w)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirmDlg(ctx, 'حذف «${w.name}»؟')) {
                        app.workflows.remove(w);
                        await app.saveWorkflows();
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class WorkflowEditor extends StatefulWidget {
  final Workflow? workflow;
  const WorkflowEditor({super.key, this.workflow});
  @override
  State<WorkflowEditor> createState() => _WorkflowEditorState();
}

class _WorkflowEditorState extends State<WorkflowEditor> {
  late final TextEditingController name = TextEditingController(text: widget.workflow?.name ?? '');
  late final TextEditingController desc = TextEditingController(text: widget.workflow?.desc ?? '');
  late final List<TextEditingController> steps =
      (widget.workflow?.steps ?? ['']).map((s) => TextEditingController(text: s)).toList();

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      app.toast('اكتب اسم الـ Workflow');
      return;
    }
    final list = steps.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (list.isEmpty) {
      app.toast('أضف خطوة واحدة على الأقل');
      return;
    }
    final w = widget.workflow;
    if (w == null) {
      app.workflows.add(Workflow(id: newId(), name: name.text.trim(), desc: desc.text.trim(), steps: list));
    } else {
      w.name = name.text.trim();
      w.desc = desc.text.trim();
      w.steps = list;
    }
    await app.saveWorkflows();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.workflow == null ? 'Workflow جديد' : 'تعديل Workflow'), actions: [
        TextButton(onPressed: _save, child: const Text('حفظ')),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 8),
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'وصف قصير (اختياري)')),
        const SizedBox(height: 12),
        Text('الخطوات — تُنفَّذ بالترتيب، كل خطوة تعمل حتى تنتهي ثم تبدأ التالية.',
            style: TextStyle(fontSize: 12, color: pal.sub)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: pal.bubble, borderRadius: BorderRadius.circular(10), border: Border.all(color: pal.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('متغيّرات القوالب المتاحة:', style: TextStyle(fontWeight: FontWeight.bold, color: pal.sub, fontSize: 11)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final chip in ['\$ARGS', '\$ARG1..\$ARG9', '\$PREV', '\$WORKSPACE', '\$PROJECT'])
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: pal.surface, borderRadius: BorderRadius.circular(100), border: Border.all(color: pal.line)), child: Text(chip, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'))),
            ]),
            const SizedBox(height: 6),
            Text('• \$ARGS = كل وسائط المستخدم  • \$PREV = ناتج الخطوة السابقة (مختصر)  • \$WORKSPACE/\$PROJECT = مسار المشروع/اسمه',
                style: TextStyle(fontSize: 10, color: pal.sub)),
          ]),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 12, backgroundColor: pal.accent, child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.white))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: steps[i], minLines: 2, maxLines: 8, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'مثال: ابحث عن ... ثم عدّل ... استخدم \$ARGS للمتغيرات'))),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: steps.length > 1 ? () => setState(() => steps.removeAt(i)) : null,
              ),
            ]),
          ),
        OutlinedButton.icon(onPressed: () => setState(() => steps.add(TextEditingController())), icon: const Icon(Icons.add), label: const Text('إضافة خطوة')),
      ]),
    );
  }
}

// ---------------- الصلاحيات (Agents) ----------------
class AgentsScreen extends StatelessWidget {
  const AgentsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الصلاحيات (Agents)')),
      floatingActionButton: _fab(context, () => pushPage(context, const AgentEditor())),
      body: ListenableBuilder(
        listenable: app,
        builder: (ctx, _) {
          final pal = Pal.of(ctx);
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: app.agents.length,
            itemBuilder: (c, i) {
              final a = app.agents[i];
              final sel = a.id == app.agentId;
              final perms = [
                if (a.canRead) 'قراءة',
                if (a.canWrite) 'كتابة',
                if (a.canExecute) 'شيل',
                if (a.canNet) 'إنترنت',
              ].join(' · ');
              final mode = a.approval == 'auto' ? 'تلقائي' : (a.approval == 'edits' ? 'تعديلات تلقائية' : 'اسأل دائماً');
              return Card(
                color: sel ? pal.bubble : null,
                child: ListTile(
                  leading: Icon(sel ? Icons.check_circle : Icons.circle_outlined, color: pal.accent),
                  title: Text(a.name, style: TextStyle(fontWeight: sel ? FontWeight.bold : null)),
                  subtitle: Text('$perms\nالموافقة: $mode · مسارات: ${a.allowedPaths.length} · تطبيقات: ${a.allowedApps.length}'),
                  isThreeLine: true,
                  onTap: () {
                    app.agentId = a.id;
                    app.saveSettings();
                  },
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => pushPage(ctx, AgentEditor(agent: a))),
                    if (app.agents.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmDlg(ctx, 'حذف «${a.name}»؟')) {
                            app.agents.remove(a);
                            if (app.agentId == a.id) app.agentId = app.agents.first.id;
                            await app.saveAgents();
                            await app.saveSettings();
                          }
                        },
                      ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class AgentEditor extends StatefulWidget {
  final Agent? agent;
  const AgentEditor({super.key, this.agent});
  @override
  State<AgentEditor> createState() => _AgentEditorState();
}

class _AgentEditorState extends State<AgentEditor> {
  late final TextEditingController name = TextEditingController(text: widget.agent?.name ?? '');
  late final TextEditingController prompt = TextEditingController(text: widget.agent?.systemPrompt ?? '');
  late final TextEditingController paths = TextEditingController(text: (widget.agent?.allowedPaths ?? []).join('\n'));
  late final TextEditingController apps = TextEditingController(text: (widget.agent?.allowedApps ?? []).join('\n'));
  late bool canRead = widget.agent?.canRead ?? true;
  late bool canWrite = widget.agent?.canWrite ?? true;
  late bool canExec = widget.agent?.canExecute ?? false;
  late bool canNet = widget.agent?.canNet ?? false;
  late String approval = widget.agent?.approval ?? 'ask';

  List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> _pickDir() async {
    try {
      final d = await FilePicker.platform.getDirectoryPath();
      if (d != null) {
        final cur = _lines(paths);
        if (!cur.contains(d)) cur.add(d);
        setState(() => paths.text = cur.join('\n'));
      }
    } catch (e) {
      app.toast('تعذر اختيار المجلد: $e');
    }
  }

  Future<void> _save() async {
    if (name.text.trim().isEmpty) {
      app.toast('اكتب اسماً');
      return;
    }
    final a = widget.agent;
    if (a == null) {
      app.agents.add(Agent(
        id: newId(),
        name: name.text.trim(),
        systemPrompt: prompt.text,
        allowedPaths: _lines(paths),
        allowedApps: _lines(apps),
        canRead: canRead,
        canWrite: canWrite,
        canExecute: canExec,
        canNet: canNet,
        approval: approval,
      ));
    } else {
      a.name = name.text.trim();
      a.systemPrompt = prompt.text;
      a.allowedPaths = _lines(paths);
      a.allowedApps = _lines(apps);
      a.canRead = canRead;
      a.canWrite = canWrite;
      a.canExecute = canExec;
      a.canNet = canNet;
      a.approval = approval;
    }
    await app.saveAgents();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.agent == null ? 'Agent جديد' : 'تعديل Agent'), actions: [
        TextButton(onPressed: _save, child: const Text('حفظ')),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
        const SizedBox(height: 8),
        TextField(controller: prompt, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'تعليمات إضافية للوكيل (اختياري)')),
        const SizedBox(height: 16),
        const Text('الصلاحيات', style: TextStyle(fontWeight: FontWeight.bold)),
        SwitchListTile(title: const Text('قراءة الملفات والبحث'), value: canRead, onChanged: (v) => setState(() => canRead = v)),
        SwitchListTile(title: const Text('كتابة / تعديل / حذف الملفات'), value: canWrite, onChanged: (v) => setState(() => canWrite = v)),
        SwitchListTile(
          title: const Text('تنفيذ أوامر شيل'),
          subtitle: const Text('أقوى صلاحية: الأوامر لا تتقيد بقائمة المسارات. تُطلب موافقتك عليها دائماً ما لم تختر «تلقائي».'),
          value: canExec,
          onChanged: (v) => setState(() => canExec = v),
        ),
        SwitchListTile(title: const Text('الوصول للإنترنت (طلبات HTTP)'), value: canNet, onChanged: (v) => setState(() => canNet = v)),
        const SizedBox(height: 12),
        const Text('وضع الموافقة', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'ask', label: Text('اسأل')),
            ButtonSegment(value: 'edits', label: Text('تعديلات تلقائية')),
            ButtonSegment(value: 'auto', label: Text('تلقائي')),
          ],
          selected: {approval},
          onSelectionChanged: (s) => setState(() => approval = s.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            approval == 'ask'
                ? 'يسألك قبل أي كتابة أو شيل أو إنترنت.'
                : approval == 'edits'
                    ? 'يكتب ويعدّل ملفات المسارات المسموحة بلا سؤال، ويسأل عن الشيل والإنترنت والحذف.'
                    : 'ينفّذ كل شيء ضمن الصلاحيات بلا أي سؤال (استخدمه بحذر).',
            style: TextStyle(fontSize: 12, color: pal.sub),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          const Expanded(child: Text('مسارات إضافية مسموحة', style: TextStyle(fontWeight: FontWeight.bold))),
          TextButton.icon(onPressed: _pickDir, icon: const Icon(Icons.folder_open, size: 18), label: const Text('اختر مجلد')),
        ]),
        Text('مجلد عمل المشروع مسموح دائماً. هنا أضف مجلدات من ذاكرة الهاتف (مسار كامل، سطر لكل مسار).', style: TextStyle(fontSize: 12, color: pal.sub)),
        const SizedBox(height: 6),
        TextField(
          controller: paths,
          minLines: 2,
          maxLines: 6,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '/storage/emulated/0/Download'),
        ),
        const SizedBox(height: 16),
        const Text('تطبيقات مسموحة (package name)', style: TextStyle(fontWeight: FontWeight.bold)),
        Text(
          app.bridgeOk
              ? 'الجسر الأصلي مفعّل — سطر لكل تطبيق، مثل: com.whatsapp'
              : 'يحتاج «جسر الهاتف» (جزء Kotlin) وهو غير مثبّت بعد، فهذه القائمة لن تُستخدم حالياً.',
          style: TextStyle(fontSize: 12, color: pal.sub),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: apps,
          minLines: 2,
          maxLines: 5,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'com.example.app'),
        ),
      ]),
    );
  }
}

// ---------------- الذاكرة ----------------
class MemoryScreen extends StatelessWidget {
  const MemoryScreen({super.key});

  Future<void> _edit(BuildContext ctx, MemoryPart? m) async {
    final t = TextEditingController(text: m?.title ?? '');
    final c = TextEditingController(text: m?.content ?? '');
    var pin = m?.pinned ?? false;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => StatefulBuilder(
        builder: (d2, setSt) {
          final pal = Pal.of(d2);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(children: [
              Icon(m == null ? Icons.add_circle_outline : Icons.edit_outlined, color: pal.accent, size: 20),
              const SizedBox(width: 8),
              Text(m == null ? 'ذكرى جديدة' : 'تعديل الذكرى', style: const TextStyle(fontSize: 16)),
            ]),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: t,
                  textDirection: dirOf(t.text, fallback: TextDirection.rtl),
                  decoration: InputDecoration(
                    labelText: 'العنوان',
                    hintText: 'مثلاً: تفضيلاتي في الكتابة',
                    prefixIcon: const Icon(Icons.title, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: c,
                  minLines: 4,
                  maxLines: 10,
                  textDirection: dirOf(c.text, fallback: TextDirection.rtl),
                  decoration: InputDecoration(
                    labelText: 'المحتوى',
                    hintText: 'اكتب ما تريد أن يتذكره الوكيل…',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: pal.bubble, borderRadius: BorderRadius.circular(10)),
                  child: SwitchListTile(
                    dense: true,
                    title: Row(children: [
                      Icon(Icons.push_pin, size: 16, color: pin ? pal.accent : pal.sub),
                      const SizedBox(width: 6),
                      const Text('مثبّت — يُرسل دائماً للنموذج', style: TextStyle(fontSize: 13)),
                    ]),
                    value: pin,
                    activeThumbColor: pal.accent,
                    onChanged: (v) => setSt(() => pin = v),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: pal.accent),
                onPressed: () => Navigator.pop(d, true),
                child: const Text('حفظ'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || t.text.trim().isEmpty || c.text.trim().isEmpty) return;
    if (m == null) {
      app.memory.add(MemoryPart(id: newId(), title: t.text.trim(), content: c.text, pinned: pin));
    } else {
      m.title = t.text.trim();
      m.content = c.text;
      m.pinned = pin;
    }
    await app.saveMemory();
  }

  @override
  Widget build(BuildContext context) {
    return _MemoryBody(edit: _edit);
  }
}

class _MemoryBody extends StatefulWidget {
  final Future<void> Function(BuildContext, MemoryPart?) edit;
  const _MemoryBody({required this.edit});
  @override
  State<_MemoryBody> createState() => _MemoryBodyState();
}

class _MemoryBodyState extends State<_MemoryBody> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الذاكرة')),
      floatingActionButton: _fab(context, () => widget.edit(context, null)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'ابحث في الذاكرة… (فوري)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              isDense: true,
            ),
            onChanged: (v) => setState(() => q = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: app,
            builder: (ctx, _) {
              final all = app.memory.where((e) => q.isEmpty || e.title.toLowerCase().contains(q) || e.content.toLowerCase().contains(q)).toList();
              if (all.isEmpty) {
                return q.isEmpty
                    ? _emptyMsg('لا توجد ذاكرة.\nيمكنك إضافة أجزاء هنا، ويستطيع الوكيل أيضاً حفظ وقراءة أجزاء بنفسه.')
                    : _emptyMsg('لا نتائج لـ «$q»');
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: all.length,
                itemBuilder: (c, i) {
                  final m = all[i];
                  return Card(
                    child: ListTile(
                      leading: IconButton(
                        icon: Icon(m.pinned ? Icons.push_pin : Icons.push_pin_outlined, color: m.pinned ? pal.accent : null),
                        tooltip: m.pinned ? 'مثبّت (يُرسل دائماً)' : 'تثبيت',
                        onPressed: () async {
                          m.pinned = !m.pinned;
                          await app.saveMemory();
                        },
                      ),
                      title: Text(m.title),
                      subtitle: Text(m.content, maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: dirOf(m.content, fallback: Directionality.of(ctx))),
                      onTap: () => widget.edit(ctx, m),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.content_copy, size: 18),
                          tooltip: 'نسخ',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: '${m.title}\n${m.content}'));
                            app.toast('تم النسخ');
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'حذف',
                          onPressed: () async {
                            if (!await confirmDlg(ctx, 'حذف «${m.title}»؟')) return;
                            app.memory.remove(m);
                            await app.saveMemory();
                          },
                        ),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---------------- المكتبة ----------------
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String q = '';

  Future<void> _add() async {
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (res == null) return;
      for (final f in res.files) {
        List<int>? bytes = f.bytes;
        if (bytes == null && f.path != null) bytes = await File(f.path!).readAsBytes();
        if (bytes != null) await app.importBytes(f.name, bytes);
      }
    } catch (e) {
      app.toast('تعذر إضافة الملف: $e');
    }
  }

  Future<void> _preview(LibItem it) async {
    if (it.path.isEmpty) {
      app.toast('هذا السجل قديم (بدون محتوى محفوظ)');
      return;
    }
    final pal = Pal.of(context);
    Widget body;
    bool isImg = it.mime.startsWith('image/');
    if (isImg) {
      body = ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(it.path), fit: BoxFit.contain));
    } else {
      try {
        final bytes = await File(it.path).readAsBytes();
        body = looksBinary(bytes)
            ? Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: pal.bubble, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Icon(Icons.inventory_2_outlined, color: pal.sub),
                  const SizedBox(width: 10),
                  Expanded(child: Text('ملف ثنائي — ${fmtSize(bytes.length)} • ${it.mime}', style: TextStyle(color: pal.sub))),
                ]),
              )
            : Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: pal.code, borderRadius: BorderRadius.circular(12), border: Border.all(color: pal.line)),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(clip(utf8.decode(bytes, allowMalformed: true), 9000), style: TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5, color: pal.text)),
                ),
              );
      } catch (e) {
        body = Text('تعذر القراءة: $e', style: TextStyle(color: pal.bad));
      }
    }
    if (!mounted) return;
    final name = it.name;
    showDialog(
      context: context,
      builder: (d) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(children: [
                Icon(isImg ? Icons.image : Icons.article_outlined, color: pal.accent, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(d)),
              ]),
            ),
            Divider(height: 1, color: pal.line),
            Flexible(child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: body)),
            Divider(height: 1, color: pal.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                Text('${fmtSize(it.size)} • ${it.mime}', style: TextStyle(fontSize: 11, color: pal.sub)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.content_copy, size: 16),
                  label: const Text('نسخ المسار'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: it.path));
                    app.toast('تم نسخ المسار');
                  },
                ),
                const SizedBox(width: 6),
                FilledButton(onPressed: () => Navigator.pop(d), child: const Text('إغلاق')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المكتبة')),
      floatingActionButton: _fab(context, _add),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'ابحث في المكتبة…', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), isDense: true),
            onChanged: (v) => setState(() => q = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: app,
            builder: (ctx, _) {
              final low = q.toLowerCase();
              final items = app.library
                  .where((e) => low.isEmpty || e.name.toLowerCase().contains(low) || e.mime.toLowerCase().contains(low))
                  .toList()
                  .reversed
                  .toList();
              if (items.isEmpty) {
                return q.isEmpty
                    ? _emptyMsg('المكتبة فارغة.\nكل ملف ترفقه في الشات يُحفظ هنا، ويستطيع الوكيل البحث فيه وقراءته.')
                    : _emptyMsg('لا نتائج لـ «$q»');
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (c, i) {
                  final it = items[i];
                  return ListTile(
                    leading: Icon(it.mime.startsWith('image/') ? Icons.image : Icons.insert_drive_file_outlined),
                    title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${fmtSize(it.size)} · ${it.time.day}/${it.time.month}/${it.time.year} · ${it.mime}'),
                    onTap: () => _preview(it),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.content_copy, size: 18),
                        tooltip: 'نسخ المسار',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: it.path.isEmpty ? it.name : it.path));
                          app.toast('تم النسخ');
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'حذف',
                        onPressed: () async {
                          if (!await confirmDlg(ctx, 'حذف «${it.name}»؟')) return;
                          try {
                            if (it.path.isNotEmpty) await File(it.path).delete();
                          } catch (_) {}
                          app.library.remove(it);
                          await app.saveLibrary();
                        },
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ---------------- ملفات الهاتف ----------------
class PhoneFilesScreen extends StatefulWidget {
  final String? initialPath;
  const PhoneFilesScreen({super.key, this.initialPath});
  @override
  State<PhoneFilesScreen> createState() => _PhoneFilesScreenState();
}

class _PhoneFilesScreenState extends State<PhoneFilesScreen> {
  late String currentPath = widget.initialPath ?? app.workspace.path;
  List<FileSystemEntity> files = [];
  Map<String, int> sizes = {}; // مسار → حجم (غير متزامن)
  bool loading = true;
  String? err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _perm() async {
    try {
      final s = await Permission.manageExternalStorage.request();
      if (!s.isGranted) await Permission.storage.request();
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      err = null;
    });
    if (currentPath.startsWith('/storage') || currentPath.startsWith('/sdcard')) await _perm();
    try {
      final l = await Directory(currentPath).list(followLinks: false).toList();
      l.sort((x, y) {
        final xd = x is Directory, yd = y is Directory;
        if (xd != yd) return xd ? -1 : 1;
        return x.path.toLowerCase().compareTo(y.path.toLowerCase());
      });
      files = l;
      sizes = {};
      // أحجام غير متزامنة — لا تجمّد الواجهة
      for (final e in l.where((x) => x is! Directory)) {
        try { sizes[e.path] = await (e as File).length(); } catch (_) { sizes[e.path] = 0; }
      }
    } catch (e) {
      files = [];
      sizes = {};
      err = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  void _go(String p) {
    currentPath = normPath(p);
    _load();
  }

  Future<void> _open(File f) async {
    try {
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      final txt = looksBinary(bytes) ? '(ملف ثنائي — ${fmtSize(bytes.length)})' : clip(utf8.decode(bytes, allowMalformed: true), 6000);
      showDialog(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(f.path.split('/').last, style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: double.maxFinite,
            height: 340,
            child: SingleChildScrollView(child: SelectableText(txt, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'), textDirection: dirOf(txt))),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('إغلاق'))],
        ),
      );
    } catch (e) {
      app.toast('$e');
    }
  }

  Future<void> _create() async {
    final n = TextEditingController();
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('إنشاء ملف'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'الاسم', hintText: 'notes.txt')),
          TextField(controller: c, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'المحتوى')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('إنشاء')),
        ],
      ),
    );
    if (ok != true || n.text.trim().isEmpty) return;
    try {
      final f = File('$currentPath/${n.text.trim()}');
      await f.parent.create(recursive: true);
      await f.writeAsString(c.text, flush: true);
      _load();
    } catch (e) {
      app.toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    final sb = Sandbox(app.agent, app.workspace.path);
    final name = currentPath.split('/').last;
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'الهاتف' : name),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            tooltip: 'مجلد أعلى',
            onPressed: () {
              final i = currentPath.lastIndexOf('/');
              if (i > 0) _go(currentPath.substring(0, i));
            },
          ),
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'السماح للوكيل بهذا المجلد',
            onPressed: () async {
              if (sb.allows(currentPath)) {
                app.toast('هذا المجلد مسموح للوكيل أصلاً');
                return;
              }
              if (await confirmDlg(context, 'السماح للوكيل «${app.agent.name}» بالوصول إلى:\n$currentPath ؟')) {
                app.agent.allowedPaths.add(currentPath);
                await app.saveAgents();
                if (mounted) setState(() {});
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: pal.accent,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: const Icon(Icons.note_add),
        label: const Text('ملف جديد'),
      ),
      body: Column(children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final e in {
                'مجلد العمل': app.workspace.path,
                'الذاكرة الداخلية': '/storage/emulated/0',
                'التنزيلات': '/storage/emulated/0/Download',
                'المستندات': '/storage/emulated/0/Documents',
              }.entries)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ActionChip(label: Text(e.key), onPressed: () => _go(e.value)),
                ),
            ],
          ),
        ),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Align(alignment: Alignment.centerLeft, child: Text(currentPath, style: TextStyle(fontSize: 10.5, color: pal.sub, fontFamily: 'monospace'))),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : err != null
                  ? _emptyMsg('تعذر فتح المجلد.\nقد تحتاج السماح بـ «الوصول لكل الملفات» من إعدادات التطبيق.\n\n$err')
                  : files.isEmpty
                      ? _emptyMsg('المجلد فارغ')
                      : ListView.builder(
                          itemCount: files.length,
                          itemBuilder: (c, i) {
                            final f = files[i];
                            final isDir = f is Directory;
                            final size = isDir ? 0 : (sizes[f.path] ?? 0);
                            return ListTile(
                              dense: true,
                              leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file_outlined, color: isDir ? const Color(0xFFE0A526) : null),
                              title: Text(f.path.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                              subtitle: Text(isDir ? 'مجلد' : fmtSize(size)),
                              trailing: sb.allows(f.path) ? Icon(Icons.shield, size: 16, color: pal.ok) : null,
                              onTap: () {
                                if (isDir) {
                                  _go(f.path);
                                } else {
                                  _open(f as File);
                                }
                              },
                              onLongPress: () async {
                                if (await confirmDlg(context, 'حذف «${f.path.split('/').last}»؟')) {
                                  try {
                                    await f.delete(recursive: true);
                                  } catch (e) {
                                    app.toast('$e');
                                  }
                                  _load();
                                }
                              },
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

// ---------------- الإعدادات ----------------
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _dd<T>(String label, T value, Map<T, String> items, void Function(T) on) {
    final v = items.containsKey(value) ? value : items.keys.first;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: DropdownButton<T>(
        value: v,
        underline: const SizedBox.shrink(),
        items: items.entries.map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value))).toList(),
        onChanged: (x) {
          if (x != null) on(x);
        },
      ),
    );
  }

  Widget _h(String t) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListenableBuilder(
        listenable: app,
        builder: (ctx, _) {
          final pal = Pal.of(ctx);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
            _h('المظهر واللغة'),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('فاتح'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('داكن'), icon: Icon(Icons.dark_mode)),
                ButtonSegment(value: ThemeMode.system, label: Text('تلقائي'), icon: Icon(Icons.auto_mode)),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (s) {
                app.themeMode = s.first;
                app.saveSettings();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('واجهة من اليمين لليسار (RTL)'),
              value: app.rtlUi,
              onChanged: (v) {
                app.rtlUi = v;
                app.saveSettings();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('أزرار تحريك المؤشر في خانة الكتابة'),
              value: app.cursorKeys,
              onChanged: (v) {
                app.cursorKeys = v;
                app.saveSettings();
              },
            ),
            const Text('لغة ردود النموذج'),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'auto', label: Text('حسب لغتي')),
                ButtonSegment(value: 'ar', label: Text('عربي')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {app.replyLang},
              onSelectionChanged: (s) {
                app.replyLang = s.first;
                app.saveSettings();
              },
            ),
            _h('سلوك الوكيل'),
            _dd<int>('أقصى عدد خطوات للمهمة الواحدة', app.maxSteps, const {10: '10', 25: '25', 40: '40', 80: '80', 150: '150', 0: 'بلا حد'}, (v) {
              app.maxSteps = v;
              app.saveSettings();
            }),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('متابعة تلقائية'),
              subtitle: const Text('إذا توقف النموذج وفي القائمة مهام غير مكتملة، يكمل بنفسه'),
              value: app.autoContinue,
              onChanged: (v) {
                app.autoContinue = v;
                app.saveSettings();
              },
            ),
            _dd<int>('ضغط السياق تلقائياً عند', app.compactAt, const {0: 'معطّل', 30000: '30k توكن', 60000: '60k توكن', 120000: '120k توكن', 200000: '200k توكن'}, (v) {
              app.compactAt = v;
              app.saveSettings();
            }),
            _h('التعليمات العامة (System Prompt) — تُرسل قبل كل محادثة'),
            Builder(builder: (_) {
              final c = TextEditingController(text: app.globalSystemPrompt);
              // نحافظ على المؤشر في النهاية عند كل بناء
              c.selection = TextSelection.collapsed(offset: c.text.length);
              return TextField(
                controller: c,
                minLines: 3,
                maxLines: 6,
                textDirection: dirOf(c.text, fallback: TextDirection.rtl),
                decoration: InputDecoration(
                  hintText: 'مثال: أجب دائماً بالعربية الفصحى، كن مختصراً ومباشراً...',
                  hintStyle: TextStyle(color: pal.sub.withOpacity(0.7), fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.psychology_outlined, size: 18),
                  isDense: true,
                  filled: true,
                  fillColor: pal.surface,
                ),
                onChanged: (v) {
                  app.globalSystemPrompt = v;
                  app.saveSettings();
                },
              );
            }),
            _h('نمط الكتابة المتدفقة'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'instant', label: Text('فوري'), icon: Icon(Icons.bolt_outlined, size: 16)),
                ButtonSegment(value: 'smooth', label: Text('سلس'), icon: Icon(Icons.water_drop_outlined, size: 16)),
                ButtonSegment(value: 'typewriter', label: Text('آلة كاتبة'), icon: Icon(Icons.keyboard_outlined, size: 16)),
              ],
              selected: {app.streamMode},
              onSelectionChanged: (s) {
                app.streamMode = s.first;
                app.saveSettings();
                app.toast(s.first == 'instant' ? 'فوري — بدون تأخير' : s.first == 'smooth' ? 'سلس — 35ms/حرف' : 'آلة كاتبة — 70ms/حرف');
              },
            ),
            const SizedBox(height: 4),
            Text('الفوري: يظهر النص كاملاً فور وصوله. السلس والآلة الكاتبة يستخدمان throttle ذكي.', style: TextStyle(fontSize: 11, color: pal.sub)),
            Row(children: [
              const Expanded(child: Text('بروفايلات الـ API', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: pal.accent),
                onPressed: () => pushPage(ctx, const ProfileEditor()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة'),
              ),
            ]),
            const SizedBox(height: 8),
            if (app.profiles.isEmpty) Text('لا توجد بروفايلات — اضغط إضافة', style: TextStyle(color: pal.sub)),
            ...app.profiles.map((p) {
              final sel = p.id == app.profileId;
              return Card(
                color: sel ? pal.bubble : null,
                child: ListTile(
                  leading: Icon(sel ? Icons.check_circle : Icons.circle_outlined, color: pal.accent),
                  title: Text(p.name, style: TextStyle(fontWeight: sel ? FontWeight.bold : null)),
                  subtitle: Text('${p.kind == 'anthropic' ? 'Anthropic' : 'OpenAI-compatible'} · ${p.model.isEmpty ? 'بدون موديل' : p.model}\n${p.baseUrl}',
                      maxLines: 2, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr),
                  isThreeLine: true,
                  onTap: () {
                    app.profileId = p.id;
                    app.saveProfiles();
                  },
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => pushPage(ctx, ProfileEditor(profile: p))),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (!await confirmDlg(ctx, 'حذف «${p.name}»؟')) return;
                        app.profiles.remove(p);
                        if (app.profileId == p.id) app.profileId = app.profiles.isEmpty ? null : app.profiles.first.id;
                        await app.saveProfiles();
                      },
                    ),
                  ]),
                ),
              );
            }),
            _h('الهاتف والصلاحيات'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_open),
              title: const Text('صلاحيات النظام للتطبيق'),
              subtitle: const Text('فعّل «الوصول لكل الملفات» ليصل الوكيل لذاكرة الهاتف'),
              trailing: IconButton(icon: const Icon(Icons.settings), onPressed: () => openAppSettings()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(app.bridgeOk ? Icons.link : Icons.link_off),
              title: const Text('جسر التحكم بالتطبيقات'),
              subtitle: Text(app.bridgeOk ? 'مفعّل' : 'غير مثبّت (يحتاج جزء Kotlin أصلي — المرحلة 2)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.backup),
              title: const Text('تصدير نسخة احتياطية'),
              subtitle: const Text('يحفظ كل شيء (بدون مفاتيح الـ API) في ملف JSON'),
              onTap: () async {
                try {
                  final p = await app.exportBackup();
                  app.toast('تم الحفظ: $p');
                } catch (e) {
                  app.toast('فشل التصدير: $e');
                }
              },
            ),
          ]);
        },
      ),
    );
  }
}

// ---------------- محرر البروفايل ----------------
class ProfileEditor extends StatefulWidget {
  final ApiProfile? profile;
  const ProfileEditor({super.key, this.profile});
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final ApiProfile p = widget.profile?.copy() ?? ApiProfile(id: newId(), name: '');
  late final TextEditingController name = TextEditingController(text: p.name);
  late final TextEditingController url = TextEditingController(text: p.baseUrl);
  late final TextEditingController key = TextEditingController(text: p.apiKey);
  late final TextEditingController model = TextEditingController(text: p.model);
  late final TextEditingController chatPath = TextEditingController(text: p.chatPath);
  late final TextEditingController modelsPath = TextEditingController(text: p.modelsPath);
  late final TextEditingController sysRole = TextEditingController(text: p.systemRole);
  late final TextEditingController temp = TextEditingController(text: p.temperature?.toString() ?? '');
  late final TextEditingController maxTok = TextEditingController(text: p.maxTokens?.toString() ?? '');
  late final TextEditingController headers = TextEditingController(text: p.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'));
  late final TextEditingController extra = TextEditingController(text: p.extraBody);
  bool hideKey = true, busy = false;

  void _preset(String n, String kind, String u, {String chat = '', String models = ''}) {
    setState(() {
      p.kind = kind;
      if (name.text.trim().isEmpty) name.text = n;
      url.text = u;
      chatPath.text = chat;
      modelsPath.text = models;
    });
  }

  void _collect() {
    p.name = name.text.trim();
    p.baseUrl = url.text.trim();
    p.apiKey = key.text.trim();
    p.model = model.text.trim();
    p.chatPath = chatPath.text.trim();
    p.modelsPath = modelsPath.text.trim();
    p.systemRole = sysRole.text.trim().isEmpty ? 'system' : sysRole.text.trim();
    p.temperature = double.tryParse(temp.text.trim());
    p.maxTokens = int.tryParse(maxTok.text.trim());
    p.extraBody = extra.text.trim();
    final h = <String, String>{};
    for (final l in headers.text.split('\n')) {
      final i = l.indexOf(':');
      if (i > 0) h[l.substring(0, i).trim()] = l.substring(i + 1).trim();
    }
    p.headers = h;
  }

  Future<void> _fetch() async {
    _collect();
    if (p.baseUrl.isEmpty) {
      app.toast('اكتب الـ Base URL أولاً');
      return;
    }
    setState(() => busy = true);
    try {
      final list = await runner.llm.fetchModels(p);
      p.models = list;
      if (p.model.isEmpty && list.isNotEmpty) {
        p.model = list.first;
        model.text = p.model;
      }
      app.toast('تم جلب ${list.length} موديل');
    } catch (e) {
      app.toast('فشل الاتصال: ${await dioMessage(e)}');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _save() async {
    _collect();
    if (p.name.isEmpty || p.baseUrl.isEmpty) {
      app.toast('الاسم والـ Base URL مطلوبان');
      return;
    }
    if (p.extraBody.isNotEmpty) {
      try {
        if (jsonDecode(p.extraBody) is! Map) throw 'not a map';
      } catch (_) {
        app.toast('JSON الإضافي غير صالح (يجب أن يكون كائناً {...})');
        return;
      }
    }
    final i = app.profiles.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      app.profiles[i] = p;
    } else {
      app.profiles.add(p);
    }
    app.profileId = p.id;
    await app.saveProfiles();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pal = Pal.of(context);
    const ltr = TextDirection.ltr;
    return Scaffold(
      appBar: AppBar(title: Text(widget.profile == null ? 'بروفايل جديد' : 'تعديل البروفايل'), actions: [
        TextButton(onPressed: _save, child: const Text('حفظ')),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('قوالب سريعة', style: TextStyle(fontSize: 12, color: pal.sub)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 4, children: [
          ActionChip(label: const Text('OpenAI'), onPressed: () => _preset('OpenAI', 'openai', 'https://api.openai.com')),
          ActionChip(label: const Text('Anthropic'), onPressed: () => _preset('Anthropic', 'anthropic', 'https://api.anthropic.com')),
          ActionChip(label: const Text('OpenRouter'), onPressed: () => _preset('OpenRouter', 'openai', 'https://openrouter.ai/api')),
          ActionChip(label: const Text('Groq'), onPressed: () => _preset('Groq', 'openai', 'https://api.groq.com/openai')),
          ActionChip(
              label: const Text('Gemini'),
              onPressed: () => _preset('Gemini', 'openai', 'https://generativelanguage.googleapis.com/v1beta/openai', chat: '/chat/completions', models: '/models')),
          ActionChip(label: const Text('CleanAPIs'), onPressed: () => _preset('CleanAPIs', 'openai', 'https://cleanapis.com')),
        ]),
        const SizedBox(height: 14),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم البروفايل')),
        const SizedBox(height: 10),
        const Text('نوع الواجهة'),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'openai', label: Text('OpenAI-compatible')),
            ButtonSegment(value: 'anthropic', label: Text('Anthropic')),
          ],
          selected: {p.kind},
          onSelectionChanged: (s) => setState(() => p.kind = s.first),
        ),
        const SizedBox(height: 10),
        TextField(controller: url, textDirection: ltr, decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://api.example.com')),
        const SizedBox(height: 10),
        TextField(
          controller: key,
          textDirection: ltr,
          obscureText: hideKey,
          decoration: InputDecoration(
            labelText: 'API Key',
            suffixIcon: IconButton(icon: Icon(hideKey ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => hideKey = !hideKey)),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: model, textDirection: ltr, decoration: const InputDecoration(labelText: 'الموديل'))),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: pal.accent),
            onPressed: busy ? null : _fetch,
            child: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('جلب الموديلات'),
          ),
        ]),
        if (p.models.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DropdownButton<String>(
              isExpanded: true,
              hint: const Text('اختر من الموديلات المجلوبة'),
              value: p.models.contains(model.text) ? model.text : null,
              items: p.models.map((m) => DropdownMenuItem(value: m, child: Text(m, textDirection: ltr))).toList(),
              onChanged: (v) {
                if (v != null) setState(() => model.text = v);
              },
            ),
          ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('إعدادات متقدمة (Custom API)'),
            children: [
              TextField(controller: chatPath, textDirection: ltr, decoration: InputDecoration(labelText: 'مسار الدردشة', hintText: p.kind == 'anthropic' ? '/v1/messages' : '/v1/chat/completions')),
              const SizedBox(height: 8),
              TextField(controller: modelsPath, textDirection: ltr, decoration: const InputDecoration(labelText: 'مسار الموديلات', hintText: '/v1/models')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: temp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'temperature', hintText: 'افتراضي'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: maxTok, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'max_tokens', hintText: p.kind == 'anthropic' ? '16000' : 'افتراضي الخادم'))),
              ]),
              const SizedBox(height: 8),
              if (p.kind == 'openai') TextField(controller: sysRole, textDirection: ltr, decoration: const InputDecoration(labelText: 'دور رسالة النظام', hintText: 'system | developer | user')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('بث الرد (stream)'), value: p.stream, onChanged: (v) => setState(() => p.stream = v)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إرسال الأدوات (Tool calling)'),
                subtitle: const Text('عطّله إن كان الموديل لا يدعم الأدوات'),
                value: p.tools,
                onChanged: (v) => setState(() => p.tools = v),
              ),
              TextField(controller: headers, textDirection: ltr, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Headers مخصصة (Key: Value في كل سطر)')),
              const SizedBox(height: 8),
              TextField(controller: extra, textDirection: ltr, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'JSON إضافي يُدمج في الطلب', hintText: '{"top_p": 0.9}')),
            ],
          ),
        ),
      ]),
    );
  }
}
