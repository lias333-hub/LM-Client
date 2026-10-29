// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, unused_local_variable, avoid_print, deprecated_member_use, use_build_context_synchronously, prefer_const_constructors, prefer_const_literals_to_create_immutables, depend_on_referenced_packages, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, unnecessary_import
part of 'main.dart';

// ---------------------------------------------------------------------
//  Settings (stored as one JSON map; missing keys fall back to defaults)
// ---------------------------------------------------------------------
class AppSettings {
  final Map<String, dynamic> m;
  const AppSettings(this.m);

  bool _b(String k, bool d) {
    final v = m[k];
    return v is bool ? v : d;
  }

  int _i(String k, int d) {
    final v = m[k];
    return v is num ? v.toInt() : d;
  }

  double _d(String k, double d) {
    final v = m[k];
    return v is num ? v.toDouble() : d;
  }

  String _s(String k, String d) {
    final v = m[k];
    return v is String ? v : d;
  }

  AppSettings set(String k, dynamic v) {
    final n = Map<String, dynamic>.from(m);
    n[k] = v;
    return AppSettings(n);
  }

  // appearance
  int get themeMode => _i('themeMode', 0); // 0 system, 1 light, 2 dark, 3 terminal (pure black)
  int get uiMode => _i('uiMode', 0); // 0 chat, 1 terminal
  bool get rtl => _b('rtl', true);
  bool get serif => _b('serif', true);
  double get fontScale => _d('fontScale', 1.0);
  // generation
  String get instructions => _s('instructions', '');
  double get temperature => _d('temperature', -1); // <0 = unset
  double get topP => _d('topP', -1); // <0 = unset
  int get maxTokens => _i('maxTokens', 0); // 0 = unset
  int get thinkLevel => _i('thinkLevel', 0); // 0 off/default, 1 low, 2 medium, 3 high
  int get thinkMode => _i('thinkMode', 0); // 0 auto, 1 adaptive, 2 budget (Anthropic)
  int get contextLimit => _i('contextLimit', 0); // 0 = all messages
  /// ميزانية السياق بالتوكنز التقريبية (0 = بلا حد). عند تجاوزها تُحذف أقدم الأدوار دفعة واحدة.
  int get contextBudget => _i('contextBudget', 60000);
  /// عند تجاوز الميزانية: يلخّص النموذج الأقدم (طلب إضافي واحد) بدل حذفه.
  bool get autoCompact => _b('autoCompact', true);
  /// ميزانية توكنز التشغيل الواحد (مجموع ما عالجه النموذج في كل جولاته؛ 0 = بلا حد). شبكة أمان ضد الحلقات المكلفة.
  int get taskBudget => _i('taskBudget', 1000000);
  /// سقف جولات الأدوات لكل رسالة (كان 12 ثابتاً؛ المشاريع الحقيقية تحتاج عشرات الجولات). إعداد مخفي.
  int get maxToolRounds {
    final int v = _i('maxToolRounds', 60);
    return v < 5 ? 5 : (v > 500 ? 500 : v);
  }
  bool get promptCache => _b('promptCache', true);
  bool get trimOldResults => _b('trimOldResults', true);
  // behaviour
  bool get tools => _b('tools', true);
  bool get confirm => _b('confirm', true);
  /// موافقة أوامر bash: 'ask' (اسأل) أو 'auto' (تلقائي عدا الأوامر الخطرة).
  String get bashApproval => _s('bashApproval', 'ask');
  bool get autoTitle => _b('autoTitle', false);
  bool get includeDate => _b('includeDate', true);
  bool get memoryOn => _b('memoryOn', true);
  /// خدمة المقدّمة + قفل التشغيل أثناء عمل الـ Agent (إشعار دائم)، كي لا يوقفه أندرويد عند إغلاق الشاشة.
  bool get keepAlive => _b('keepAlive', true);
  bool get showTokens => _b('showTokens', true);
  bool get richFormat => _b('richFormat', true);
  bool get cursorBtns => _b('cursorBtns', false);
  int get maxChars => _i('maxChars', 30000);
  // voice
  double get ttsRate => _d('ttsRate', 0.5);
  String get sttLocale => _s('sttLocale', '');
}

// ---------------------------------------------------------------------
//  Core models
// ---------------------------------------------------------------------
class Attachment {
  final String id;
  final String name;
  final String mime;
  final int size;
  final String? path; // نسخة محفوظة في المكتبة
  const Attachment({required this.id, required this.name, this.mime = '', this.size = 0, this.path});
  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'mime': mime, 'size': size, 'path': path};
  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: asStr(j['id'], newId()),
        name: asStr(j['name']),
        mime: asStr(j['mime']),
        size: (j['size'] is num) ? (j['size'] as num).toInt() : 0,
        path: j['path'] is String ? j['path'] as String : null,
      );
}

class ToolCall {
  final String id;
  final String name;
  Map<String, dynamic> args;
  String? result;
  bool isError;
  String status; // pending | running | done | error
  String? sig; // Gemini thoughtSignature
  String? rawArgs;
  ToolCall({
    required this.id,
    required this.name,
    Map<String, dynamic>? args,
    this.result,
    this.isError = false,
    this.status = 'pending',
    this.sig,
    this.rawArgs,
  }) : args = args ?? <String, dynamic>{};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'args': args,
        'result': result,
        'isError': isError,
        'status': status,
        'sig': sig,
      };
  factory ToolCall.fromJson(Map<String, dynamic> j) => ToolCall(
        id: asStr(j['id'], newId()),
        name: asStr(j['name']),
        args: asMap(j['args']),
        result: j['result'] is String ? j['result'] as String : null,
        isError: j['isError'] == true,
        status: asStr(j['status'], 'done'),
        sig: j['sig'] is String ? j['sig'] as String : null,
      );
}

class ChatMessage {
  final String id;
  final String role; // user | assistant
  String content;
  String thinking;
  String? thinkSig;
  List<String> redacted;
  List<Attachment> attachments;
  DateTime time;
  bool excluded;
  List<ToolCall> toolCalls;
  String? error;
  String? model;
  int inTok;
  int outTok;
  int cacheTok; // توكنز دخل قُرئت من الكاش (أرخص بكثير)
  bool tokExact;
  String? stopReason;
  String? quote;
  int thinkMs;
  /// رسالة كتبها المستخدم أثناء عمل النموذج وسُلّمت بين جولات الأدوات (جزء من نفس الدور لا دور جديد).
  bool injected;
  /// ملخّص أنشأه النموذج لأجزاء قديمة من المحادثة (الأصلية صارت "مستبعدة من السياق").
  bool summary;

  /// هل هي رسالة مستخدم تبدأ دوراً جديداً؟ (ليست محقونة وسط الأدوات ولا ملخّصاً)
  bool get startsTurn => role == 'user' && !injected && !summary;

  ChatMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.thinking = '',
    this.thinkSig,
    List<String>? redacted,
    List<Attachment>? attachments,
    DateTime? time,
    this.excluded = false,
    List<ToolCall>? toolCalls,
    this.error,
    this.model,
    this.inTok = 0,
    this.outTok = 0,
    this.cacheTok = 0,
    this.tokExact = false,
    this.stopReason,
    this.quote,
    this.thinkMs = 0,
    this.injected = false,
    this.summary = false,
  })  : redacted = redacted ?? <String>[],
        attachments = attachments ?? <Attachment>[],
        time = time ?? DateTime.now(),
        toolCalls = toolCalls ?? <ToolCall>[];

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'content': content,
        'thinking': thinking,
        'thinkSig': thinkSig,
        'redacted': redacted,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'time': time.toIso8601String(),
        'excluded': excluded,
        'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
        'error': error,
        'model': model,
        'inTok': inTok,
        'outTok': outTok,
        'cacheTok': cacheTok,
        'tokExact': tokExact,
        'stopReason': stopReason,
        'quote': quote,
        'thinkMs': thinkMs,
        'injected': injected,
        'summary': summary,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final atts = <Attachment>[];
    for (final a in asList(j['attachments'])) {
      atts.add(Attachment.fromJson(asMap(a)));
    }
    // توافق مع الصيغة القديمة: fileNames فقط
    if (atts.isEmpty) {
      for (final n in asList(j['fileNames'])) {
        atts.add(Attachment(id: newId(), name: asStr(n)));
      }
    }
    DateTime t;
    try {
      t = DateTime.parse(asStr(j['time']));
    } catch (_) {
      t = DateTime.now();
    }
    return ChatMessage(
      id: asStr(j['id'], newId()),
      role: asStr(j['role'], 'user'),
      content: asStr(j['content']),
      thinking: asStr(j['thinking']),
      thinkSig: j['thinkSig'] is String ? j['thinkSig'] as String : null,
      redacted: asList(j['redacted']).map((e) => e.toString()).toList(),
      attachments: atts,
      time: t,
      excluded: j['excluded'] == true,
      toolCalls: asList(j['toolCalls']).map((e) => ToolCall.fromJson(asMap(e))).toList(),
      error: j['error'] is String ? j['error'] as String : null,
      model: j['model'] is String ? j['model'] as String : null,
      inTok: (j['inTok'] is num) ? (j['inTok'] as num).toInt() : 0,
      outTok: (j['outTok'] is num) ? (j['outTok'] as num).toInt() : 0,
      cacheTok: (j['cacheTok'] is num) ? (j['cacheTok'] as num).toInt() : 0,
      tokExact: j['tokExact'] == true,
      stopReason: j['stopReason'] is String ? j['stopReason'] as String : null,
      quote: j['quote'] is String ? j['quote'] as String : null,
      thinkMs: (j['thinkMs'] is num) ? (j['thinkMs'] as num).toInt() : 0,
      injected: j['injected'] == true,
      summary: j['summary'] == true,
    );
  }
}

class ConvMeta {
  final String id;
  String title;
  DateTime createdAt;
  DateTime updatedAt;
  bool pinned;
  String? projectId;
  ConvMeta({required this.id, this.title = '', DateTime? createdAt, DateTime? updatedAt, this.pinned = false, this.projectId})
      : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pinned': pinned,
        'projectId': projectId,
      };
  factory ConvMeta.fromJson(Map<String, dynamic> j) {
    DateTime c, u;
    try {
      c = DateTime.parse(asStr(j['createdAt']));
    } catch (_) {
      c = DateTime.now();
    }
    try {
      u = DateTime.parse(asStr(j['updatedAt']));
    } catch (_) {
      u = c;
    }
    return ConvMeta(
      id: asStr(j['id'], newId()),
      title: asStr(j['title']),
      createdAt: c,
      updatedAt: u,
      pinned: j['pinned'] == true,
      projectId: j['projectId'] is String ? j['projectId'] as String : null,
    );
  }
}

class Project {
  final String id;
  final String name;
  final String instructions;
  final List<String> knowledge; // معرّفات ملفات المكتبة
  const Project({required this.id, required this.name, this.instructions = '', this.knowledge = const <String>[]});
  Project copyWith({String? name, String? instructions, List<String>? knowledge}) =>
      Project(id: id, name: name ?? this.name, instructions: instructions ?? this.instructions, knowledge: knowledge ?? this.knowledge);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'instructions': instructions, 'knowledge': knowledge};
  factory Project.fromJson(Map<String, dynamic> j) => Project(
        id: asStr(j['id'], newId()),
        name: asStr(j['name']),
        instructions: asStr(j['instructions']),
        knowledge: asList(j['knowledge']).map((e) => e.toString()).toList(),
      );
}

class MemoryPart {
  final String id;
  final String title;
  final String content;
  const MemoryPart({required this.id, required this.title, required this.content});
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'content': content};
  factory MemoryPart.fromJson(Map<String, dynamic> j) =>
      MemoryPart(id: asStr(j['id'], newId()), title: asStr(j['title']), content: asStr(j['content']));
}

class Agent {
  final String id;
  final String name;
  final String systemPrompt;
  final List<String> allowedPaths;
  final bool canRead;
  final bool canWrite;
  final bool canExecute;
  final bool canShell;
  const Agent({
    required this.id,
    required this.name,
    this.systemPrompt = '',
    this.allowedPaths = const <String>[],
    this.canRead = true,
    this.canWrite = false,
    this.canExecute = false,
    this.canShell = false,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'systemPrompt': systemPrompt,
        'allowedPaths': allowedPaths,
        'canRead': canRead,
        'canWrite': canWrite,
        'canExecute': canExecute,
        'canShell': canShell,
      };
  factory Agent.fromJson(Map<String, dynamic> j) => Agent(
        id: asStr(j['id'], newId()),
        name: asStr(j['name']),
        systemPrompt: asStr(j['systemPrompt']),
        allowedPaths: asList(j['allowedPaths']).map((e) => e.toString()).toList(),
        canRead: j['canRead'] != false,
        canWrite: j['canWrite'] == true,
        canExecute: j['canExecute'] == true,
        canShell: j['canShell'] == true,
      );
}

class LibraryItem {
  final String id;
  final String name;
  final int size;
  final String mime;
  final DateTime time;
  final String? path;
  const LibraryItem({required this.id, required this.name, required this.size, required this.time, this.mime = '', this.path});
  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';
  bool get isText => isTextMime(mime);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'size': size, 'mime': mime, 'time': time.toIso8601String(), 'path': path};
  factory LibraryItem.fromJson(Map<String, dynamic> j) {
    DateTime t;
    try {
      t = DateTime.parse(asStr(j['time']));
    } catch (_) {
      t = DateTime.now();
    }
    final name = asStr(j['name']);
    final m = asStr(j['mime']);
    return LibraryItem(
      id: asStr(j['id'], newId()),
      name: name,
      size: (j['size'] is num) ? (j['size'] as num).toInt() : 0,
      mime: m.isEmpty ? mimeFromName(name) : m,
      time: t,
      path: j['path'] is String ? j['path'] as String : null,
    );
  }
}

class ApiProfile {
  final String id;
  final String name;
  final String kind; // openai | anthropic | gemini
  final String baseUrl;
  final String apiKey;
  final String selectedModel;
  final List<String> models;
  final String headers; // "Key: Value" لكل سطر
  final bool streamUsage;
  const ApiProfile({
    required this.id,
    required this.name,
    this.kind = kOpenAI,
    required this.baseUrl,
    required this.apiKey,
    this.selectedModel = '',
    this.models = const <String>[],
    this.headers = '',
    this.streamUsage = true,
  });
  ApiProfile copyWith({
    String? name,
    String? kind,
    String? baseUrl,
    String? apiKey,
    String? selectedModel,
    List<String>? models,
    String? headers,
    bool? streamUsage,
  }) =>
      ApiProfile(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        selectedModel: selectedModel ?? this.selectedModel,
        models: models ?? this.models,
        headers: headers ?? this.headers,
        streamUsage: streamUsage ?? this.streamUsage,
      );
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'selectedModel': selectedModel,
        'models': models,
        'headers': headers,
        'streamUsage': streamUsage,
      };
  factory ApiProfile.fromJson(Map<String, dynamic> j) => ApiProfile(
        id: asStr(j['id'], newId()),
        name: asStr(j['name']),
        kind: asStr(j['kind'], kOpenAI),
        baseUrl: asStr(j['baseUrl']),
        apiKey: asStr(j['apiKey']),
        selectedModel: asStr(j['selectedModel']),
        models: asList(j['models']).map((e) => e.toString()).toList(),
        headers: asStr(j['headers']),
        streamUsage: j['streamUsage'] != false,
      );
  String get kindLabel => kind == kAnthropic ? 'Anthropic' : (kind == kGemini ? 'Gemini' : 'OpenAI-compatible');
}

/// قوالب جاهزة لإنشاء بروفايل بسرعة: [الاسم، النوع، الرابط]
const List<List<String>> kPresets = <List<String>>[
  <String>['Anthropic', kAnthropic, 'https://api.anthropic.com'],
  <String>['OpenAI', kOpenAI, 'https://api.openai.com/v1'],
  <String>['Gemini', kGemini, 'https://generativelanguage.googleapis.com'],
  <String>['OpenRouter', kOpenAI, 'https://openrouter.ai/api/v1'],
  <String>['DeepSeek', kOpenAI, 'https://api.deepseek.com'],
  <String>['Groq', kOpenAI, 'https://api.groq.com/openai/v1'],
  <String>['Mistral', kOpenAI, 'https://api.mistral.ai/v1'],
  <String>['xAI', kOpenAI, 'https://api.x.ai/v1'],
  <String>['Together', kOpenAI, 'https://api.together.xyz/v1'],
  <String>['Ollama', kOpenAI, 'http://localhost:11434/v1'],
  <String>['LM Studio', kOpenAI, 'http://localhost:1234/v1'],
  <String>['cleanapis', kOpenAI, 'https://cleanapis.com'],
];

/// مرفق ينتظر الإرسال (بايتات في الذاكرة أو ملف من المكتبة).
class PendingAtt {
  final String id;
  final String name;
  final String mime;
  final int size;
  final Uint8List? bytes;
  final String? path;
  const PendingAtt({required this.id, required this.name, required this.mime, required this.size, this.bytes, this.path});
  bool get isImage => mime.startsWith('image/');
}
