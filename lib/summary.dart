part of 'main.dart';

// =====================================================================
//  الملخّص الحيّ للتقدّم (v2.13.0): لوحة «الملخّص» كما في تطبيق Claude.
//  - لا نص تفكير خام ولا طلب إضافي للنموذج: الخطوات تُبنى من رسائل التشغيل نفسها (بقاؤها بعد إعادة فتح المحادثة مجاني).
//  - لكل أداة عنوان قصير يكتبه النموذج في وسيط اختياري `description` (يُضاف لأدوات الملفات والبحث والروابط…)،
//    وإن غاب اشتُقّ عنوان من اسم الأداة ووسائطها. وتحته سطر خافت: الأمر أو المسار أو الرابط.
//  - بين الأدوات جملة السرد التي يكتبها النموذج قبل كل دفعة (kWorkStyleGuide).
//  - الترويسة بعد الانتهاء مجمَّعة: «عُدّل ملفان، وكُتب ملف، و31 خطوة أخرى».
//  كل الدوال هنا نقية (بلا واجهة) كي تُختبر في CI.
// =====================================================================

/// أدوات تُعطى وسيطاً اختيارياً `description`. أما bash و task فلهما وسيط بهذا الاسم أصلاً.
const Set<String> kStepTitleTools = <String>{
  kToolReadFile,
  kToolWriteFile,
  kToolEditFile,
  kToolListDir,
  kToolSearchFiles,
  kToolOutline,
  kToolFetchUrl,
  kToolSearchLib,
  kToolReadLib,
  kToolReadMemory,
  kToolSaveMemory,
  kToolUseSkill,
  kToolKillShell,
  kToolBashOut,
};

const String kStepTitleHint = 'Optional: a title of at most 8 words, in the user\'s language, naming this step (shown to the user in the progress summary).';

/// يضيف الوسيط الاختياري `description` إلى الأدوات المعنيّة (قائمة الأدوات تبقى ثابتة داخل المحادثة فلا ينكسر الكاش).
List<ToolDef> withStepTitles(List<ToolDef> defs) {
  final List<ToolDef> out = <ToolDef>[];
  for (final ToolDef d in defs) {
    if (!kStepTitleTools.contains(d.name)) {
      out.add(d);
      continue;
    }
    final Map<String, dynamic> props = asMap(d.schema['properties']);
    if (props.containsKey('description')) {
      out.add(d);
      continue;
    }
    final Map<String, dynamic> schema = Map<String, dynamic>.from(d.schema);
    final Map<String, dynamic> np = Map<String, dynamic>.from(props);
    np['description'] = _pStr(kStepTitleHint);
    schema['properties'] = np;
    out.add(ToolDef(d.name, d.description, schema));
  }
  return out;
}

/// وسائط الاستدعاء لبصمة كاشف الحلقات: العنوان الذي يكتبه النموذج يتغيّر كل مرة فلا يدخل في المقارنة.
Map<String, dynamic> argsForSig(Map<String, dynamic> a) {
  if (!a.containsKey('description')) return a;
  final Map<String, dynamic> m = Map<String, dynamic>.from(a);
  m.remove('description');
  return m;
}

/// خطوة واحدة في لوحة الملخّص: إمّا جملة سرد (note) أو أداة.
class RunStep {
  final bool note;
  final String title;
  final String detail;
  final String tool;
  final String status; // running | done | failed
  final String? minus;
  final String? plus;
  final String? file;
  final bool edit;
  final bool write;
  const RunStep({
    required this.note,
    required this.title,
    this.detail = '',
    this.tool = '',
    this.status = 'done',
    this.minus,
    this.plus,
    this.file,
    this.edit = false,
    this.write = false,
  });

  bool get failed => status == 'failed';
  bool get running => status == 'running';
}

String _baseName(String p) {
  final List<String> parts = p.trim().split('/').where((String e) => e.isNotEmpty).toList();
  return parts.isEmpty ? p.trim() : parts.last;
}

String _hostOf(String url) {
  final Uri? u = Uri.tryParse(url.trim());
  if (u != null && u.host.isNotEmpty) return u.host;
  return url.trim();
}

String _firstLine(String s) {
  for (final String l in s.split('\n')) {
    if (l.trim().isNotEmpty) return l.trimRight();
  }
  return '';
}

/// عنوان مشتقّ حين لا يكتب النموذج `description`.
String stepFallbackTitle(ToolCall c) {
  final String path = asStr(c.args['path']).trim();
  final String file = _baseName(path);
  switch (c.name) {
    case kToolReadFile:
      return file.isEmpty ? 'قراءة ملف' : 'قراءة $file';
    case kToolWriteFile:
      return file.isEmpty ? 'كتابة ملف' : 'كتابة $file';
    case kToolEditFile:
      return file.isEmpty ? 'تعديل ملف' : 'تعديل $file';
    case kToolListDir:
      return file.isEmpty ? 'عرض مجلد' : 'عرض $file';
    case kToolOutline:
      return file.isEmpty ? 'خريطة ملف' : 'خريطة $file';
    case kToolSearchFiles:
      final String pt = asStr(c.args['pattern']).trim();
      return pt.isEmpty ? 'بحث في الملفات' : 'بحث عن «${clip(pt, 40)}»';
    case kToolFetchUrl:
      final String u = asStr(c.args['url']).trim();
      return u.isEmpty ? 'فتح رابط' : 'فتح ${_hostOf(u)}';
    case kToolBash:
      final String cmd = _firstLine(asStr(c.args['command']).trim());
      return cmd.isEmpty ? 'تشغيل أمر' : 'تشغيل: ${clip(cmd, 50)}';
    case kToolBashOut:
      return 'قراءة مخرجات مهمة خلفية';
    case kToolKillShell:
      return 'إيقاف مهمة خلفية';
    case kToolSearchLib:
      return 'بحث في المكتبة';
    case kToolReadLib:
      return 'قراءة ملف من المكتبة';
    case kToolReadMemory:
      return 'قراءة من الذاكرة';
    case kToolSaveMemory:
      return 'حفظ في الذاكرة';
    case kToolUseSkill:
      final String n = asStr(c.args['name']).trim();
      return n.isEmpty ? 'تحميل مهارة' : 'تحميل المهارة $n';
    case kToolTodoWrite:
      return 'تحديث قائمة المهام';
    case kToolAskUser:
      return 'سؤال للمستخدم';
    case kToolEnterPlan:
      return 'دخول وضع التخطيط';
    case kToolExitPlan:
      return 'عرض الخطة للموافقة';
    case kToolTask:
      return 'وكيل فرعي';
    case kToolTime:
      return 'قراءة الوقت';
  }
  return toolLabel(c.name);
}

/// خطوة أداة. `live`: التشغيل ما زال جارياً (وإلا فاستدعاء لم يكتمل يُعدّ فاشلاً، مثلاً بعد إغلاق التطبيق وسط أداة).
RunStep stepOf(ToolCall c, {required bool live}) {
  final String given = asStr(c.args['description']).trim().replaceAll(RegExp(r'\s+'), ' ');
  final String title = given.isNotEmpty ? clip(given, 90) : stepFallbackTitle(c);
  String detail = toolSummary(c);
  if (detail == title || c.name == kToolTask) detail = '';
  final String st = (c.status == 'error' || c.isError) ? 'failed' : (c.status == 'done' ? 'done' : (live ? 'running' : 'failed'));
  final String path = asStr(c.args['path']).trim();
  final bool isEdit = c.name == kToolEditFile && st == 'done';
  final bool isWrite = c.name == kToolWriteFile && st == 'done';
  String? minus;
  String? plus;
  if (isEdit) {
    String o = asStr(c.args['old_string']);
    String n = asStr(c.args['new_string']);
    final List<dynamic> eds = asList(c.args['edits']);
    if (o.isEmpty && eds.isNotEmpty) {
      final Map<String, dynamic> e0 = asMap(eds.first);
      o = asStr(e0['old_string']);
      n = asStr(e0['new_string']);
    }
    final String o1 = _firstLine(o);
    final String n1 = _firstLine(n);
    if (o1.isNotEmpty) minus = '- ${clip(o1, 90)}';
    if (n1.isNotEmpty) plus = '+ ${clip(n1, 90)}';
  }
  return RunStep(
    note: false,
    title: title,
    detail: detail,
    tool: c.name,
    status: st,
    minus: minus,
    plus: plus,
    file: (isEdit || isWrite) && path.isNotEmpty ? path : null,
    edit: isEdit,
    write: isWrite,
  );
}

/// خطوات التشغيل الحالي/الأخير (كل ما بعد آخر رسالة بدأها المستخدم). الجواب النهائي (رسالة بلا أدوات) ليس خطوة.
List<RunStep> buildRunSteps(List<ChatMessage> msgs, {bool live = false}) {
  int start = 0;
  for (int i = msgs.length - 1; i >= 0; i--) {
    if (msgs[i].startsTurn) {
      start = i + 1;
      break;
    }
  }
  final List<RunStep> out = <RunStep>[];
  for (int i = start; i < msgs.length; i++) {
    final ChatMessage m = msgs[i];
    if (m.role != 'assistant' || m.excluded || m.toolCalls.isEmpty) continue;
    final String t = m.content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isNotEmpty) out.add(RunStep(note: true, title: t.length <= 200 ? t : '${t.substring(0, 197)}…'));
    for (final ToolCall c in m.toolCalls) {
      out.add(stepOf(c, live: live));
    }
  }
  return out;
}

String _arFiles(int n) {
  if (n == 1) return 'ملف';
  if (n == 2) return 'ملفان';
  if (n <= 10) return '$n ملفات';
  return '$n ملفاً';
}

String _arSteps(int n, {required bool more}) {
  if (n == 1) return more ? 'خطوة أخرى' : 'خطوة واحدة';
  if (n == 2) return more ? 'خطوتان أخريان' : 'خطوتان';
  if (n <= 10) return more ? '$n خطوات أخرى' : '$n خطوات';
  return more ? '$n خطوة أخرى' : '$n خطوة';
}

/// الترويسة المجمَّعة بعد الانتهاء، مثل «عُدّل ملفان، وكُتب ملف، و31 خطوة أخرى».
/// «كُتب» لا «أُنشئ»: نتيجة write_file لا تفرّق بين إنشاء ملف جديد وإعادة كتابة ملف موجود، ولا نخمّن.
String runSummaryHeader(List<RunStep> steps) {
  final Set<String> edited = <String>{};
  final Set<String> written = <String>{};
  int tools = 0;
  int fileSteps = 0;
  for (final RunStep s in steps) {
    if (s.note) continue;
    tools++;
    final String? f = s.file;
    if (f == null) continue;
    if (s.edit) {
      edited.add(f);
      fileSteps++;
    } else if (s.write) {
      written.add(f);
      fileSteps++;
    }
  }
  final List<String> parts = <String>[];
  final int e = edited.length;
  final int w = written.length;
  if (e > 0) parts.add('${(e >= 3 && e <= 10) ? 'عُدّلت' : 'عُدّل'} ${_arFiles(e)}');
  if (w > 0) parts.add('${(w >= 3 && w <= 10) ? 'كُتبت' : 'كُتب'} ${_arFiles(w)}');
  final int other = tools - fileSteps;
  if (other > 0) parts.add(_arSteps(other, more: parts.isNotEmpty));
  if (parts.isEmpty) return '';
  final StringBuffer b = StringBuffer(parts.first);
  for (int i = 1; i < parts.length; i++) {
    b.write('، و${parts[i]}');
  }
  return b.toString();
}
