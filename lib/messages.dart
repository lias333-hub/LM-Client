// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, unused_local_variable, avoid_print, deprecated_member_use, use_build_context_synchronously, prefer_const_constructors, prefer_const_literals_to_create_immutables, depend_on_referenced_packages, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, unnecessary_import
part of 'main.dart';

// =====================================================================
//  Messages: bubble, markdown, code blocks, thinking, tool cards, actions
// =====================================================================

// ---- Text to speech (one global engine) ------------------------------
final FlutterTts tts = FlutterTts();
final ValueNotifier<String?> speakingId = ValueNotifier<String?>(null);
bool _ttsInit = false;

void _initTts() {
  if (_ttsInit) return;
  _ttsInit = true;
  try {
    tts.setCompletionHandler(() => speakingId.value = null);
    tts.setCancelHandler(() => speakingId.value = null);
    tts.setErrorHandler((dynamic e) => speakingId.value = null);
  } catch (_) {}
}

Future<void> toggleSpeak(ChatMessage m, AppSettings s) async {
  _initTts();
  if (speakingId.value == m.id) {
    try {
      await tts.stop();
    } catch (_) {}
    speakingId.value = null;
    return;
  }
  final text = stripMarkdown(m.content);
  if (text.isEmpty) return;
  try {
    await tts.stop();
    await tts.setSpeechRate(s.ttsRate);
    final d = detectDir(text);
    await tts.setLanguage(d == TextDirection.rtl ? 'ar' : 'en-US');
    speakingId.value = m.id;
    await tts.speak(clip(text, 3900));
  } catch (e) {
    speakingId.value = null;
    toast('تعذّرت القراءة الصوتية');
  }
}

// ---- Tool presentation --------------------------------------------------
String toolLabel(String name) {
  switch (name) {
    case kToolSaveMemory:
      return 'حفظ في الذاكرة';
    case kToolReadMemory:
      return 'قراءة من الذاكرة';
    case kToolSearchLib:
      return 'بحث في المكتبة';
    case kToolReadLib:
      return 'قراءة ملف من المكتبة';
    case kToolListDir:
      return 'عرض مجلد';
    case kToolReadFile:
      return 'قراءة ملف';
    case kToolWriteFile:
      return 'كتابة ملف';
    case kToolFetchUrl:
      return 'فتح رابط';
    case kToolEditFile:
      return 'تعديل ملف';
    case kToolSearchFiles:
      return 'بحث في الملفات';
    case kToolOutline:
      return 'خريطة الملف';
    case kToolBash:
      return 'أمر Bash';
    case kToolBashOut:
      return 'مخرجات مهمة خلفية';
    case kToolKillShell:
      return 'إيقاف مهمة خلفية';
    case kToolTime:
      return 'الوقت الحالي';
  }
  return name;
}

IconData toolIcon(String name) {
  switch (name) {
    case kToolSaveMemory:
    case kToolReadMemory:
      return Icons.bookmark_border;
    case kToolSearchLib:
    case kToolReadLib:
      return Icons.library_books_outlined;
    case kToolListDir:
      return Icons.folder_open;
    case kToolReadFile:
      return Icons.description_outlined;
    case kToolWriteFile:
      return Icons.edit_note;
    case kToolFetchUrl:
      return Icons.public;
    case kToolEditFile:
      return Icons.edit_outlined;
    case kToolSearchFiles:
      return Icons.search;
    case kToolOutline:
      return Icons.account_tree_outlined;
    case kToolBash:
    case kToolBashOut:
    case kToolKillShell:
      return Icons.terminal;
    case kToolTime:
      return Icons.schedule;
  }
  return Icons.build_outlined;
}

String toolSummary(ToolCall c) {
  if (c.name == kToolSearchFiles) {
    final pt = asStr(c.args['pattern']).trim();
    final gl = asStr(c.args['glob']).trim();
    final where = asStr(c.args['path']).trim().split('/').where((e) => e.isNotEmpty).toList();
    final tail = where.isEmpty ? '' : ' · ${where.last}';
    if (pt.isNotEmpty || gl.isNotEmpty) return '${pt.isNotEmpty ? pt : gl}$tail';
  }
  if (c.name == kToolBash) {
    final cmd = asStr(c.args['command']).trim().split('\n').first;
    if (cmd.isNotEmpty) return clip(cmd, 120);
  }
  if (c.name == kToolReadFile) {
    final off = c.args['offset'];
    final p = asStr(c.args['path']).trim();
    if (p.isNotEmpty) return off is num && off > 1 ? '$p:${off.toInt()}' : p;
  }
  for (final k in <String>['path', 'url', 'query', 'title', 'name']) {
    final v = c.args[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return '';
}

String statusLabel(String st) {
  if (st == 'connecting') return 'جارٍ الاتصال…';
  if (st == 'thinking') return 'يفكّر…';
  if (st == 'writing') return 'يكتب…';
  if (st == 'compacting') return 'يلخّص السياق…';
  if (st.startsWith('retry:')) return 'إعادة المحاولة (${st.substring(6)})…';
  if (st.startsWith('tool:')) return 'يستخدم أداة: ${toolLabel(st.substring(5))}…';
  return 'يعمل…';
}

// ---- Fence splitter (``` blocks) ---------------------------------------
class Seg {
  final bool code;
  final String lang;
  final String text;
  final bool open; // fence not closed yet (still streaming)
  const Seg(this.code, this.text, {this.lang = '', this.open = false});
}

int _runLen(String t, String ch) {
  int n = 0;
  while (n < t.length && t[n] == ch) {
    n++;
  }
  return n;
}

List<Seg> splitFences(String s) {
  final out = <Seg>[];
  final lines = s.split('\n');
  final buf = <String>[];
  bool inCode = false;
  String ch = '`';
  int fenceLen = 3;
  String lang = '';

  void flushText() {
    final t = buf.join('\n');
    buf.clear();
    if (t.trim().isNotEmpty) out.add(Seg(false, t));
  }

  for (final line in lines) {
    final t = line.trimLeft();
    if (!inCode) {
      String? c;
      if (t.startsWith('`')) c = '`';
      if (t.startsWith('~')) c = '~';
      if (c != null) {
        final n = _runLen(t, c);
        if (n >= 3) {
          flushText();
          inCode = true;
          ch = c;
          fenceLen = n;
          final info = t.substring(n).trim();
          lang = info.isEmpty ? '' : info.split(RegExp(r'\s+')).first;
          continue;
        }
      }
      buf.add(line);
    } else {
      bool closes = false;
      if (t.startsWith(ch)) {
        final n = _runLen(t, ch);
        if (n >= fenceLen && t.substring(n).trim().isEmpty) closes = true;
      }
      if (closes) {
        out.add(Seg(true, buf.join('\n'), lang: lang));
        buf.clear();
        inCode = false;
        lang = '';
      } else {
        buf.add(line);
      }
    }
  }
  if (inCode) {
    out.add(Seg(true, buf.join('\n'), lang: lang, open: true));
  } else {
    flushText();
  }
  return out;
}

// ---- Tiny syntax highlighter ---------------------------------------------
const Set<String> _hashLangs = <String>{
  'python', 'py', 'sh', 'bash', 'shell', 'zsh', 'yaml', 'yml', 'toml', 'ruby', 'rb', 'ini', 'dockerfile', 'r', 'perl', 'makefile', 'powershell', 'ps1', 'conf', 'env'
};

const Set<String> _kw = <String>{
  'if', 'else', 'elif', 'for', 'foreach', 'while', 'do', 'switch', 'case', 'default', 'break', 'continue', 'return', 'function', 'def', 'class', 'struct', 'enum',
  'interface', 'import', 'from', 'export', 'package', 'public', 'private', 'protected', 'static', 'final', 'const', 'var', 'let', 'val', 'fun', 'void', 'int',
  'double', 'float', 'bool', 'boolean', 'string', 'String', 'new', 'this', 'self', 'super', 'try', 'catch', 'except', 'finally', 'throw', 'throws', 'raise',
  'async', 'await', 'in', 'is', 'as', 'null', 'nil', 'None', 'true', 'false', 'True', 'False', 'and', 'or', 'not', 'with', 'yield', 'lambda', 'extends',
  'implements', 'override', 'abstract', 'typedef', 'late', 'required', 'namespace', 'using', 'include', 'select', 'where', 'insert', 'update', 'delete',
  'create', 'table', 'into', 'values', 'join', 'on', 'group', 'by', 'order', 'limit', 'pub', 'fn', 'mut', 'impl', 'use', 'mod', 'match', 'type', 'go', 'defer',
  'chan', 'range', 'func', 'echo', 'then', 'fi', 'done', 'print', 'pass', 'del', 'global', 'volatile', 'char', 'long', 'short', 'unsigned', 'sizeof', 'template',
};

List<TextSpan> highlightCode(String code, String lang, Pal p) {
  if (code.length > 9000) return <TextSpan>[TextSpan(text: code)];
  final l = lang.toLowerCase();
  String comment;
  if (_hashLangs.contains(l)) {
    comment = r'#[^\n]*';
  } else if (l == 'sql') {
    comment = r'--[^\n]*|/\*[\s\S]*?\*/';
  } else if (l == 'html' || l == 'xml' || l == 'svg') {
    comment = r'<!--[\s\S]*?-->';
  } else {
    comment = r'//[^\n]*|/\*[\s\S]*?\*/';
  }
  final RegExp re = RegExp('($comment)|' + r'''("(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`)|(\b\d+(?:\.\d+)?\b)|(\b[A-Za-z_][A-Za-z0-9_]*\b)''');
  final cKw = TextStyle(color: p.accent);
  final cStr = TextStyle(color: p.success);
  final cNum = TextStyle(color: p.accent.withAlpha(210));
  final cCom = TextStyle(color: p.muted, fontStyle: FontStyle.italic);
  final spans = <TextSpan>[];
  int last = 0;
  for (final m in re.allMatches(code)) {
    if (m.start > last) spans.add(TextSpan(text: code.substring(last, m.start)));
    final t = m.group(0) ?? '';
    TextStyle? st;
    if (m.group(1) != null) {
      st = cCom;
    } else if (m.group(2) != null) {
      st = cStr;
    } else if (m.group(3) != null) {
      st = cNum;
    } else {
      final w = l == 'sql' ? t.toLowerCase() : t;
      if (_kw.contains(w)) st = cKw;
    }
    spans.add(TextSpan(text: t, style: st));
    last = m.end;
  }
  if (last < code.length) spans.add(TextSpan(text: code.substring(last)));
  return spans;
}

class CodeBlock extends StatefulWidget {
  final String lang;
  final String code;
  final bool open;
  const CodeBlock({super.key, required this.lang, required this.code, this.open = false});
  @override
  State<CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<CodeBlock> {
  List<TextSpan>? _spans;
  String _src = '';
  int _themeKey = -1;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future<void>.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final tk = Theme.of(context).brightness.index;
    if (_spans == null || _src != widget.code || _themeKey != tk) {
      _spans = highlightCode(widget.code, widget.lang, p);
      _src = widget.code;
      _themeKey = tk;
    }
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 12.8, height: 1.5, color: p.codeText);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 2, 6, 2),
            color: p.surfaceHi.withAlpha(120),
            child: Row(children: [
              Expanded(
                child: Text(widget.lang.isEmpty ? 'code' : widget.lang, style: TextStyle(color: p.muted, fontSize: 12, fontFamily: 'monospace')),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: p.muted, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: _copy,
                icon: Icon(_copied ? Icons.check : Icons.copy_rounded, size: 15),
                label: Text(_copied ? 'Copied' : 'Copy', style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: Text.rich(TextSpan(style: mono, children: _spans), style: mono),
          ),
        ]),
      ),
    );
  }
}

// ---- Markdown ------------------------------------------------------------
MarkdownStyleSheet buildMdSheet(BuildContext c, Pal p, AppSettings s) {
  final base = MarkdownStyleSheet.fromTheme(Theme.of(c));
  final fs = 16.0 * s.fontScale;
  final body = TextStyle(
    color: p.text,
    fontSize: fs,
    height: 1.62,
    fontFamily: s.serif ? 'serif' : null,
    fontFamilyFallback: s.serif ? const <String>['Noto Serif', 'Georgia'] : null,
  );
  TextStyle h(double k) => body.copyWith(fontSize: fs * k, fontWeight: FontWeight.w700, height: 1.35);
  return base.copyWith(
    p: body,
    h1: h(1.5),
    h2: h(1.32),
    h3: h(1.18),
    h4: h(1.08),
    h5: h(1.0),
    h6: h(1.0),
    strong: body.copyWith(fontWeight: FontWeight.w700),
    em: body.copyWith(fontStyle: FontStyle.italic),
    a: body.copyWith(color: p.accent, decoration: TextDecoration.underline),
    code: TextStyle(fontFamily: 'monospace', fontSize: fs * 0.86, color: p.text, backgroundColor: p.surfaceHi),
    blockquote: body.copyWith(color: p.muted),
    blockquotePadding: const EdgeInsets.all(12),
    blockquoteDecoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10)),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
    listBullet: body,
    tableHead: body.copyWith(fontWeight: FontWeight.w700, fontSize: fs * 0.94),
    tableBody: body.copyWith(fontSize: fs * 0.94),
    tableBorder: TableBorder.all(color: p.border, width: 1),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: p.border, width: 1))),
    blockSpacing: 12,
  );
}

// ---- تنسيق غني: ألوان، تمييز، ومربعات تنبيه (GitHub alerts) ----------------
Color mdColor(String name, bool dark) {
  switch (name) {
    case 'red':
      return dark ? const Color(0xFFF2766B) : const Color(0xFFB3261E);
    case 'green':
      return dark ? const Color(0xFF6CC48F) : const Color(0xFF1E7A45);
    case 'orange':
      return dark ? const Color(0xFFF0A35E) : const Color(0xFFB45B09);
    case 'violet':
      return dark ? const Color(0xFFB69CF5) : const Color(0xFF6A3FC4);
    case 'gray':
      return dark ? const Color(0xFF9A988F) : const Color(0xFF5F5E5A);
    case 'yellow':
      return dark ? const Color(0xFFE6C84F) : const Color(0xFF8A6D00);
    default:
      return dark ? const Color(0xFF7DB1F5) : const Color(0xFF1F5FBF);
  }
}

class ColorSyntax extends md.InlineSyntax {
  ColorSyntax() : super(r':(blue|red|green|orange|violet|gray|yellow)\[([^\]\n]+)\]');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element.text('lmcolor', match[2]!);
    el.attributes['c'] = match[1]!;
    parser.addNode(el);
    return true;
  }
}

class MarkSyntax extends md.InlineSyntax {
  MarkSyntax() : super(r'==([^=\n]+)==');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('lmmark', match[1]!));
    return true;
  }
}

class ColorBuilder extends MarkdownElementBuilder {
  final bool dark;
  ColorBuilder(this.dark);
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final c = mdColor(element.attributes['c'] ?? 'blue', dark);
    return RichText(text: TextSpan(text: element.textContent, style: (preferredStyle ?? const TextStyle()).copyWith(color: c, fontWeight: FontWeight.w600)));
  }
}

class MarkBuilder extends MarkdownElementBuilder {
  final bool dark;
  MarkBuilder(this.dark);
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final bg = dark ? const Color(0x55E6C84F) : const Color(0x88FFE680);
    return RichText(text: TextSpan(text: element.textContent, style: (preferredStyle ?? const TextStyle()).copyWith(backgroundColor: bg)));
  }
}

class _AlertSeg {
  final String? kind;
  final String text;
  const _AlertSeg(this.kind, this.text);
}

List<_AlertSeg> splitAlerts(String s) {
  if (!s.contains('[!')) return <_AlertSeg>[_AlertSeg(null, s)];
  final re = RegExp(r'^\s*>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION|INFO)\]\s*(.*)$', caseSensitive: false);
  final out = <_AlertSeg>[];
  final buf = <String>[];
  final lines = s.split('\n');
  void flush() {
    final t = buf.join('\n');
    buf.clear();
    if (t.trim().isNotEmpty) out.add(_AlertSeg(null, t));
  }

  var i = 0;
  while (i < lines.length) {
    final m = re.firstMatch(lines[i]);
    if (m == null) {
      buf.add(lines[i]);
      i++;
      continue;
    }
    flush();
    final body = <String>[];
    final first = (m.group(2) ?? '').trim();
    if (first.isNotEmpty) body.add(first);
    i++;
    while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
      var l = lines[i].trimLeft().substring(1);
      if (l.startsWith(' ')) l = l.substring(1);
      body.add(l);
      i++;
    }
    out.add(_AlertSeg(m.group(1)!.toUpperCase(), body.join('\n')));
  }
  flush();
  return out;
}

Widget _alertBox(bool dark, String kind, Widget body) {
  String label;
  IconData icon;
  String color;
  switch (kind) {
    case 'TIP':
      label = 'نصيحة';
      icon = Icons.lightbulb_outline;
      color = 'green';
      break;
    case 'IMPORTANT':
      label = 'مهم';
      icon = Icons.priority_high;
      color = 'violet';
      break;
    case 'WARNING':
      label = 'تنبيه';
      icon = Icons.warning_amber_rounded;
      color = 'orange';
      break;
    case 'CAUTION':
      label = 'تحذير';
      icon = Icons.error_outline;
      color = 'red';
      break;
    default:
      label = 'ملاحظة';
      icon = Icons.info_outline;
      color = 'blue';
  }
  final c = mdColor(color, dark);
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: c.withAlpha(dark ? 30 : 22), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withAlpha(120))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Row(children: <Widget>[
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
      const SizedBox(height: 6),
      body,
    ]),
  );
}

class RichMarkdown extends StatefulWidget {
  final String data;
  final bool streaming;
  final AppSettings settings;
  const RichMarkdown({super.key, required this.data, required this.settings, this.streaming = false});
  @override
  State<RichMarkdown> createState() => _RichMarkdownState();
}

class _RichMarkdownState extends State<RichMarkdown> {
  MarkdownStyleSheet? _sheet;
  String _sheetKey = '';
  List<Seg> _segs = const <Seg>[];
  String _segData = '\u0000';

  Widget _blockedImage(Pal p, String url, String? alt) {
    // لا نحمّل صوراً من الشبكة تلقائياً: ردود النموذج قد تحمل بيانات في الرابط (تسريب).
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: url));
        toast('تم نسخ رابط الصورة');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.image_not_supported_outlined, size: 16, color: p.muted),
          const SizedBox(width: 6),
          Flexible(child: Text((alt == null || alt.isEmpty) ? 'صورة (اضغط لنسخ الرابط)' : alt, style: TextStyle(color: p.muted, fontSize: 13))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final s = widget.settings;
    final key = '${Theme.of(context).brightness.index}|${s.fontScale}|${s.serif}';
    if (_sheet == null || _sheetKey != key) {
      _sheet = buildMdSheet(context, p, s);
      _sheetKey = key;
    }
    if (_segData != widget.data) {
      _segs = splitFences(widget.data);
      _segData = widget.data;
    }
    final sheet = _sheet;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rich = s.richFormat;
    final syntaxes = rich ? <md.InlineSyntax>[ColorSyntax(), MarkSyntax()] : null;
    final builders = rich ? <String, MarkdownElementBuilder>{'lmcolor': ColorBuilder(dark), 'lmmark': MarkBuilder(dark)} : <String, MarkdownElementBuilder>{};
    Widget mdBody(String data, Key key) {
      return MarkdownBody(
        key: key,
        data: data,
        styleSheet: sheet,
        inlineSyntaxes: syntaxes,
        builders: builders,
        onTapLink: (text, href, title) {
          if (href != null && href.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: href));
            toast('تم نسخ الرابط');
          }
        },
        imageBuilder: (uri, title, alt) => _blockedImage(p, uri.toString(), alt),
      );
    }

    final kids = <Widget>[];
    for (int i = 0; i < _segs.length; i++) {
      final sg = _segs[i];
      if (kids.isNotEmpty) kids.add(const SizedBox(height: 8));
      if (sg.code) {
        kids.add(CodeBlock(key: ValueKey<String>('c$i'), lang: sg.lang, code: sg.text, open: sg.open && widget.streaming));
      } else if (rich) {
        final parts = splitAlerts(sg.text);
        for (int j = 0; j < parts.length; j++) {
          final pt = parts[j];
          if (j > 0) kids.add(const SizedBox(height: 8));
          final k = pt.kind;
          if (k == null) {
            kids.add(mdBody(pt.text, ValueKey<String>('t$i.$j')));
          } else {
            kids.add(_alertBox(dark, k, mdBody(pt.text, ValueKey<String>('a$i.$j'))));
          }
        }
      } else {
        kids.add(mdBody(sg.text, ValueKey<String>('t$i')));
      }
    }
    return SelectionArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids));
  }
}

// ---- Small animated bits --------------------------------------------------
class PulseDots extends StatefulWidget {
  final Color color;
  const PulseDots({super.key, required this.color});
  @override
  State<PulseDots> createState() => _PulseDotsState();
}

class _PulseDotsState extends State<PulseDots> with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final dots = <Widget>[];
        for (int i = 0; i < 3; i++) {
          final x = (_c.value + i * 0.18) % 1.0;
          final o = x < 0.5 ? x * 2 : (1 - x) * 2;
          dots.add(Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: widget.color.withAlpha((70 + 185 * o).round()), shape: BoxShape.circle),
          ));
        }
        return Row(mainAxisSize: MainAxisSize.min, children: dots);
      },
    );
  }
}

final ValueNotifier<int> _idleTick = ValueNotifier<int>(0);

// ---- Thinking block ---------------------------------------------------------
class ThinkingBlock extends StatefulWidget {
  final ChatMessage msg;
  final bool active;
  final TextDirection dir;
  const ThinkingBlock({super.key, required this.msg, required this.active, required this.dir});
  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final m = widget.msg;
    final hasText = m.thinking.trim().isNotEmpty;
    final secs = (m.thinkMs / 1000).round();
    String title;
    if (widget.active) {
      title = 'يفكّر';
    } else if (!hasText && m.redacted.isNotEmpty) {
      title = 'تفكير مشفّر من المزوّد';
    } else {
      title = secs > 0 ? 'فكّر لمدة $secs ث' : 'التفكير';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: hasText ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.psychology_outlined, size: 18, color: p.muted),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: p.muted, fontSize: 13.5)),
              if (widget.active) ...[const SizedBox(width: 8), PulseDots(color: p.muted)],
              if (hasText) Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: p.muted),
            ]),
          ),
        ),
        if (_open && hasText)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsetsDirectional.only(start: 12),
            decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: p.border, width: 2))),
            child: Directionality(
              textDirection: widget.dir,
              child: Text(m.thinking.trim(), style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.55)),
            ),
          ),
      ]),
    );
  }
}

// ---- Tool card -------------------------------------------------------------
class ToolCard extends StatefulWidget {
  final ToolCall call;
  const ToolCard({super.key, required this.call});
  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _open = false;

  String _argsText(ToolCall c) {
    try {
      return clip(const JsonEncoder.withIndent('  ').convert(c.args), 3000);
    } catch (_) {
      return c.args.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final c = widget.call;
    final running = c.status == 'running' || c.status == 'pending';
    final sum = toolSummary(c);
    Widget trail;
    if (running) {
      trail = SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent));
    } else if (c.isError) {
      trail = Icon(Icons.error_outline, size: 18, color: p.danger);
    } else {
      trail = Icon(Icons.check_circle_outline, size: 18, color: p.success);
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(toolIcon(c.name), size: 18, color: p.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(toolLabel(c.name), style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w600)),
                  if (sum.isNotEmpty)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(sum, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
                    ),
                ]),
              ),
              const SizedBox(width: 8),
              trail,
              Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: p.muted),
            ]),
          ),
        ),
        if (_open)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                'args:\n${_argsText(c)}\n\nresult:\n${clip(c.result ?? '(pending)', 3000)}',
                style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.45, color: p.text),
              ),
            ),
          ),
      ]),
    );
  }
}

// ---- Error card ----------------------------------------------------------------
class ErrorCard extends StatelessWidget {
  final ChatSession session;
  final ChatMessage msg;
  final bool canAct;
  const ErrorCard({super.key, required this.session, required this.msg, required this.canAct});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final e = msg.error ?? '';
    final settingsHint = e.contains('بروفايل') || e.contains('مفتاح') || e.contains('Base URL') || e.contains('الرابط') || e.contains('موديل') || e.contains('401') || e.contains('403');
    final hasContent = msg.content.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.danger.withAlpha(22), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.danger.withAlpha(90))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, size: 18, color: p.danger),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(e, style: TextStyle(color: p.text, fontSize: 13.5, height: 1.5))),
        ]),
        if (canAct)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(spacing: 6, children: [
              TextButton.icon(
                onPressed: () => session.regenerate(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
              if (hasContent)
                TextButton.icon(
                  onPressed: () => session.continueReply(),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('متابعة'),
                ),
              if (settingsHint)
                TextButton.icon(
                  onPressed: () => pushScreen(const SettingsScreen()),
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('الإعدادات'),
                ),
            ]),
          ),
      ]),
    );
  }
}

// ---- Attachment preview ------------------------------------------------------------
Future<void> previewAttachment(BuildContext context, {required String name, required String mime, required String? path, int size = 0}) async {
  final p = pal(context);
  if (mime.startsWith('image/')) {
    final b = await LocalStorage.readRel(path);
    if (b == null) {
      toast('الملف غير موجود');
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(children: [
          InteractiveViewer(minScale: 0.8, maxScale: 6, child: Center(child: Image.memory(b, fit: BoxFit.contain))),
          Positioned(top: 4, right: 4, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(c))),
        ]),
      ),
    );
    return;
  }
  final it = LibraryItem(id: 'tmp', name: name, size: size, time: DateTime.now(), mime: mime, path: path);
  final txt = await readLibText(it);
  if (txt == null) {
    toast(path == null ? 'لا توجد نسخة محفوظة من هذا الملف' : 'لا يمكن عرض هذا النوع كنص');
    return;
  }
  if (!context.mounted) return;
  await showSheet<void>(context, (c) {
    final pp = pal(c);
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pp.text, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Directionality(
              textDirection: detectDir(txt) ?? TextDirection.ltr,
              child: SelectableText(clip(txt, 60000), style: TextStyle(color: pp.text, fontSize: 13.5, height: 1.5, fontFamily: 'monospace')),
            ),
          ),
        ),
      ]),
    );
  });
}

// ---- Message view -------------------------------------------------------------------------------
class MessageView extends ConsumerStatefulWidget {
  final ChatSession session;
  final ChatMessage msg;
  final bool isLast;
  final bool showActions;
  final bool selecting;
  final bool selected;
  final VoidCallback onTapSelect;
  final VoidCallback onEnterSelect;
  const MessageView({
    super.key,
    required this.session,
    required this.msg,
    required this.isLast,
    required this.showActions,
    required this.selecting,
    required this.selected,
    required this.onTapSelect,
    required this.onEnterSelect,
  });
  @override
  ConsumerState<MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends ConsumerState<MessageView> {
  bool _expanded = false;
  bool _sumOpen = false;

  Widget _summaryCard(Pal p, ChatMessage m) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _sumOpen = !_sumOpen),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.compress, size: 18, color: p.accent),
            const SizedBox(width: 8),
            Expanded(child: Text('ملخّص الجزء السابق من المحادثة', style: TextStyle(color: p.text, fontSize: 13.5, fontWeight: FontWeight.w600))),
            Icon(_sumOpen ? Icons.expand_less : Icons.expand_more, size: 20, color: p.muted),
          ]),
          if (_sumOpen)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(m.content, style: TextStyle(color: p.text, fontSize: 13.5, height: 1.5)),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final s = ref.watch(settingsProvider);
    final m = widget.msg;
    final session = widget.session;
    final streaming = identical(session.streamingMsg, m);
    Widget body;
    if (m.summary) {
      body = _summaryCard(p, m);
    } else if (m.role == 'user') {
      body = _user(context, p, s);
    } else {
      body = AnimatedBuilder(
        animation: streaming ? session.tick : _idleTick,
        builder: (c, _) => _assistant(c, p, s, streaming),
      );
    }
    if (m.excluded) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.visibility_off_outlined, size: 14, color: p.muted),
            const SizedBox(width: 4),
            Text('مستبعدة من السياق', style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]),
        ),
        Opacity(opacity: 0.5, child: body),
      ]);
    }
    return RepaintBoundary(
      child: GestureDetector(
        behavior: widget.selecting ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
        onTap: widget.selecting ? widget.onTapSelect : null,
        onLongPress: widget.selecting
            ? null
            : () {
                HapticFeedback.selectionClick();
                showMessageActions(context, ref, session, m, widget.onEnterSelect);
              },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 7),
          padding: widget.selected ? const EdgeInsets.all(6) : EdgeInsets.zero,
          decoration: widget.selected ? BoxDecoration(color: p.accent.withAlpha(26), borderRadius: BorderRadius.circular(14), border: Border.all(color: p.accent, width: 1.2)) : null,
          child: IgnorePointer(ignoring: widget.selecting, child: body),
        ),
      ),
    );
  }

  // ---- user ----
  Widget _user(BuildContext context, Pal p, AppSettings s) {
    final m = widget.msg;
    final dir = detectDir(m.content) ?? (s.rtl ? TextDirection.rtl : TextDirection.ltr);
    final maxW = MediaQuery.of(context).size.width * 0.86;
    final long = m.content.length > 1400;
    final quote = m.quote;
    final kids = <Widget>[];
    if (m.attachments.isNotEmpty) {
      kids.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: m.attachments
              .map((a) => GestureDetector(
                    onTap: () => previewAttachment(context, name: a.name, mime: a.mime, path: a.path, size: a.size),
                    child: AttachTile(key: ValueKey<String>('a${a.id}'), name: a.name, mime: a.mime, path: a.path),
                  ))
              .toList(),
        ),
      ));
    }
    if (m.content.trim().isNotEmpty || (quote != null && quote.isNotEmpty)) {
      kids.add(ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(18)),
          child: Directionality(
            textDirection: dir,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (quote != null && quote.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: p.border.withAlpha(110), borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.reply, size: 14, color: p.muted),
                    const SizedBox(width: 6),
                    Flexible(child: Text(clip(quote.replaceAll('\n', ' '), 160), maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5))),
                  ]),
                ),
              if (m.content.trim().isNotEmpty)
                Text(
                  (long && !_expanded) ? clip(m.content, 1400) : m.content,
                  style: TextStyle(color: p.text, fontSize: 16 * s.fontScale, height: 1.5, fontFamily: s.serif ? 'serif' : null, fontFamilyFallback: s.serif ? const <String>['Noto Serif', 'Georgia'] : null),
                ),
              if (long)
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_expanded ? 'عرض أقل' : 'عرض المزيد', style: TextStyle(color: p.accent, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ),
        ),
      ));
    }
    return Align(alignment: Alignment.centerRight, child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: kids));
  }

  // ---- assistant ----
  Widget _assistant(BuildContext context, Pal p, AppSettings s, bool streaming) {
    final m = widget.msg;
    final session = widget.session;
    final dir = detectDir(m.content) ?? detectDir(m.thinking) ?? (s.rtl ? TextDirection.rtl : TextDirection.ltr);
    final thinkingNow = streaming && session.status == 'thinking';
    final kids = <Widget>[];
    if (m.thinking.trim().isNotEmpty || m.redacted.isNotEmpty || thinkingNow) {
      kids.add(ThinkingBlock(key: ValueKey<String>('th${m.id}'), msg: m, active: thinkingNow, dir: dir));
    }
    if (m.content.isNotEmpty) {
      kids.add(Directionality(textDirection: dir, child: RichMarkdown(key: ValueKey<String>('md${m.id}'), data: m.content, settings: s, streaming: streaming)));
    }
    for (final c in m.toolCalls) {
      kids.add(ToolCard(key: ValueKey<String>('tc${c.id}'), call: c));
    }
    if (streaming && (m.content.isEmpty || session.status != 'writing') && !thinkingNow) {
      kids.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          PulseDots(color: p.accent),
          const SizedBox(width: 8),
          Text(statusLabel(session.status), style: TextStyle(color: p.muted, fontSize: 13)),
        ]),
      ));
    }
    if (m.error != null) {
      kids.add(ErrorCard(session: session, msg: m, canAct: widget.isLast && !session.generating));
    } else if (!streaming && m.stopReason == 'cancelled') {
      kids.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('تم إيقاف الرد', style: TextStyle(color: p.muted, fontSize: 12.5)),
      ));
    }
    if (!streaming && widget.showActions) {
      kids.add(_actions(context, p, s));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids);
  }

  bool get _truncated {
    final sr = widget.msg.stopReason ?? '';
    return sr == 'max_tokens' || sr == 'length' || sr == 'MAX_TOKENS';
  }

  Widget _actions(BuildContext context, Pal p, AppSettings s) {
    final m = widget.msg;
    final session = widget.session;
    final busy = session.generating;
    Widget ic(IconData i, String tip, VoidCallback? onTap, {Color? color}) {
      return IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
        iconSize: 19,
        icon: Icon(i, color: color ?? p.muted),
        onPressed: onTap,
      );
    }

    final tokText = !s.showTokens
        ? ''
        : (m.outTok > 0 || m.inTok > 0)
            ? '${m.tokExact ? '' : '~'}${m.inTok}↑${m.cacheTok > 0 ? ' (⚡${m.cacheTok})' : ''} ${m.tokExact ? '' : '~'}${m.outTok}↓'
            : '~${estimateTokens(m.content)} tok';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_truncated && widget.isLast && !busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: TextButton.icon(
              onPressed: () => session.continueReply(),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('تابع الرد (وصل للحد الأقصى)'),
            ),
          ),
        Row(children: [
          ic(Icons.copy_rounded, 'نسخ', () async {
            await Clipboard.setData(ClipboardData(text: m.content));
            toast('تم النسخ');
          }),
          ValueListenableBuilder<String?>(
            valueListenable: speakingId,
            builder: (c, id, _) => ic(id == m.id ? Icons.stop_circle_outlined : Icons.volume_up_outlined, id == m.id ? 'إيقاف' : 'قراءة', m.content.trim().isEmpty ? null : () => toggleSpeak(m, s),
                color: id == m.id ? p.accent : null),
          ),
          if (widget.isLast) ic(Icons.refresh, 'إعادة التوليد', busy ? null : () => session.regenerate()),
          ic(Icons.bookmark_add_outlined, 'حفظ في الذاكرة', m.content.trim().isEmpty ? null : () => saveMessageToMemory(context, ref, m)),
          ic(Icons.more_horiz, 'المزيد', () => showMessageActions(context, ref, session, m, widget.onEnterSelect)),
          const Spacer(),
          if (tokText.isNotEmpty) Text(tokText, style: TextStyle(color: p.muted.withAlpha(200), fontSize: 11.5)),
        ]),
      ]),
    );
  }
}

// ---- Actions on a message ---------------------------------------------------------------------------
Future<void> saveMessageToMemory(BuildContext context, WidgetRef ref, ChatMessage m) async {
  final first = m.content.trim().split('\n').first;
  final t = await askText(context, 'عنوان الذاكرة', initial: clip(first, 40));
  if (t == null || t.trim().isEmpty) return;
  await ref.read(memoryProvider.notifier).upsert(MemoryPart(id: newId(), title: clip(t.trim(), 120), content: clip(m.content.trim(), 4000)));
  toast('تم الحفظ في الذاكرة');
}

Future<void> showEditDialog(BuildContext context, ChatSession session, ChatMessage m) async {
  if (session.generating) {
    toast('أوقف الرد الجاري أولاً');
    return;
  }
  final ctrl = TextEditingController(text: m.content);
  final isUser = m.role == 'user';
  // لا نستدعي ctrl.dispose() هنا: الحوار ما زال يُنفّذ حركة الإغلاق بعد اكتمال الـ Future.
  await showDialog<void>(
    context: context,
    builder: (c) {
      final p = pal(c);
      return AlertDialog(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        title: Text('تعديل الرسالة', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600)),
        content: TextField(controller: ctrl, autofocus: true, minLines: 3, maxLines: 12, decoration: fieldDeco(c)),
        actionsOverflowButtonSpacing: 4,
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('إلغاء', style: TextStyle(color: p.muted))),
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              session.updateContent(m.id, ctrl.text);
            },
            child: const Text('حفظ'),
          ),
          if (isUser)
            FilledButton(
              onPressed: () {
                Navigator.pop(c);
                session.editAndResend(m.id, ctrl.text);
              },
              child: const Text('حفظ وإعادة الإرسال'),
            ),
        ],
      );
    },
  );
}

void showSelectText(BuildContext context, ChatMessage m) {
  showSheet<void>(context, (c) {
    final p = pal(c);
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('حدّد وانسخ ما تريد', style: TextStyle(color: p.muted, fontSize: 13)),
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Directionality(
              textDirection: detectDir(m.content) ?? Directionality.of(c),
              child: SelectableText(m.content, style: TextStyle(color: p.text, fontSize: 16, height: 1.6)),
            ),
          ),
        ),
      ]),
    );
  });
}

void showMessageInfo(BuildContext context, ChatMessage m) {
  final p = pal(context);
  final rows = <List<String>>[
    <String>['الدور', m.role == 'user' ? 'المستخدم' : 'المساعد'],
    if (m.model != null) <String>['الموديل', m.model!],
    <String>['الوقت', '${fmtDate(m.time)} ${fmtClock(m.time)}'],
    <String>['الطول', '${m.content.length} حرف'],
    if (m.role == 'assistant') <String>['التوكنز (دخل/خرج)', '${m.tokExact ? '' : '~'}${m.inTok}${m.cacheTok > 0 ? ' (من الكاش ${m.cacheTok})' : ''} / ${m.tokExact ? '' : '~'}${m.outTok}'],
    if (m.role == 'assistant' && m.thinkMs > 0) <String>['مدة التفكير', '${(m.thinkMs / 1000).toStringAsFixed(1)} ث'],
    if (m.stopReason != null) <String>['سبب التوقف', m.stopReason!],
    if (m.toolCalls.isNotEmpty) <String>['الأدوات المستدعاة', '${m.toolCalls.length}'],
    if (m.attachments.isNotEmpty) <String>['المرفقات', '${m.attachments.length}'],
    <String>['في السياق', m.excluded ? 'لا (مستبعدة)' : 'نعم'],
  ];
  showSheet<void>(context, (c) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SheetHandle(),
        ...rows.map((r) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: Text(r[0], style: TextStyle(color: p.muted, fontSize: 13.5))),
                Expanded(child: SelectableText(r[1], style: TextStyle(color: p.text, fontSize: 13.5))),
              ]),
            )),
        const SizedBox(height: 10),
      ]),
    );
  });
}

Future<void> showMessageActions(BuildContext context, WidgetRef ref, ChatSession session, ChatMessage m, VoidCallback onSelect) {
  return showSheet<void>(context, (c) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetHandle(),
          SheetAction(
            icon: Icons.copy_rounded,
            title: 'نسخ',
            onTap: () async {
              Navigator.pop(c);
              await Clipboard.setData(ClipboardData(text: m.content));
              toast('تم النسخ');
            },
          ),
          SheetAction(
            icon: Icons.text_fields,
            title: 'تحديد نص',
            subtitle: 'لنسخ جزء من الرسالة',
            onTap: () {
              Navigator.pop(c);
              showSelectText(context, m);
            },
          ),
          SheetAction(
            icon: Icons.reply,
            title: 'اقتباس والرد',
            onTap: () {
              Navigator.pop(c);
              ref.read(quoteProvider.notifier).set(clip(m.content.trim(), 1500));
            },
          ),
          SheetAction(
            icon: Icons.edit_outlined,
            title: 'تعديل',
            subtitle: m.role == 'user' ? 'مع إمكانية إعادة الإرسال' : null,
            onTap: () {
              Navigator.pop(c);
              showEditDialog(context, session, m);
            },
          ),
          SheetAction(
            icon: m.excluded ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            title: m.excluded ? 'إرجاع إلى السياق' : 'استبعاد من السياق',
            subtitle: m.excluded ? null : 'تبقى ظاهرة لكن لا تُرسل للنموذج',
            onTap: () {
              Navigator.pop(c);
              session.setExcluded(<String>{m.id}, !m.excluded);
            },
          ),
          if (m.role == 'assistant' && m.content.trim().isNotEmpty)
            SheetAction(
              icon: Icons.bookmark_add_outlined,
              title: 'حفظ في الذاكرة',
              onTap: () {
                Navigator.pop(c);
                saveMessageToMemory(context, ref, m);
              },
            ),
          SheetAction(
            icon: Icons.checklist,
            title: 'تحديد عدة رسائل',
            onTap: () {
              Navigator.pop(c);
              onSelect();
            },
          ),
          SheetAction(
            icon: Icons.info_outline,
            title: 'معلومات',
            onTap: () {
              Navigator.pop(c);
              showMessageInfo(context, m);
            },
          ),
          SheetAction(
            icon: Icons.delete_outline,
            title: 'حذف',
            danger: true,
            onTap: () async {
              Navigator.pop(c);
              if (session.generating) {
                toast('أوقف الرد الجاري أولاً');
                return;
              }
              final ok = await confirmDialog(context, 'حذف الرسالة', 'سيتم حذف هذه الرسالة نهائياً.');
              if (ok) await session.deleteMessages(<String>{m.id});
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  });
}
