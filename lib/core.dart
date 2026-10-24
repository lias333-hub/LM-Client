// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, unused_local_variable, avoid_print, deprecated_member_use, use_build_context_synchronously, prefer_const_constructors, prefer_const_literals_to_create_immutables, depend_on_referenced_packages, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, unnecessary_import
part of 'main.dart';

// ---------------------------------------------------------------------
//  Globals
// ---------------------------------------------------------------------
const String kAppName = 'LMClient';
const String kAppVersion = '2.5.0';
const String kOpenAI = 'openai';
const String kAnthropic = 'anthropic';
const String kGemini = 'gemini';
const int kMaxToolRounds = 12;

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
final ProviderContainer appContainer = ProviderContainer();
final Dio httpClient = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 30),
  sendTimeout: const Duration(seconds: 120),
  receiveTimeout: const Duration(minutes: 15),
));

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(UncontrolledProviderScope(container: appContainer, child: const LMClientApp()));
}

// ---------------------------------------------------------------------
//  Small utilities
// ---------------------------------------------------------------------
String newId() => const Uuid().v4();

Map<String, dynamic> asMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> asList(dynamic v) => v is List ? v : <dynamic>[];
String asStr(dynamic v, [String d = '']) => v is String ? v : (v == null ? d : v.toString());

String two(int n) => n.toString().padLeft(2, '0');
String fmtClock(DateTime t) => '${two(t.hour)}:${two(t.minute)}';
String fmtDate(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)}';
String fmtBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1048576).toStringAsFixed(1)} MB';
}

String clip(String s, int n) => s.length <= n ? s : s.substring(0, n) + '…';

bool isRtlRune(int r) => (r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF);
bool isLatinRune(int r) => (r >= 65 && r <= 90) || (r >= 97 && r <= 122) || (r >= 0xC0 && r <= 0x24F);

/// يكتشف اتجاه النص من أول حرف قوي. null = لا يوجد حرف (أرقام/رموز فقط).
TextDirection? detectDir(String s) {
  int n = 0;
  for (final r in s.runes) {
    if (isRtlRune(r)) return TextDirection.rtl;
    if (isLatinRune(r)) return TextDirection.ltr;
    n++;
    if (n > 400) break;
  }
  return null;
}

/// تقدير تقريبي للتوكنز (العربية أغلى من الإنجليزية). الأرقام الحقيقية تأتي من الـ API إن وُجدت.
int estimateTokens(String t) {
  double x = 0;
  for (final r in t.runes) {
    if (r < 128) {
      x += (r == 32 || r == 10) ? 0.15 : 0.27;
    } else if (isRtlRune(r)) {
      x += 0.5;
    } else {
      x += 0.8;
    }
  }
  return x.ceil();
}

String mimeFromName(String name) {
  final n = name.toLowerCase();
  final i = n.lastIndexOf('.');
  final ext = i < 0 ? '' : n.substring(i + 1);
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'pdf':
      return 'application/pdf';
    case 'json':
      return 'application/json';
    case 'csv':
      return 'text/csv';
    case 'html':
    case 'htm':
      return 'text/html';
    case 'md':
    case 'markdown':
      return 'text/markdown';
    case 'xml':
      return 'application/xml';
    case 'txt':
    case 'log':
    case 'dart':
    case 'py':
    case 'js':
    case 'ts':
    case 'tsx':
    case 'jsx':
    case 'java':
    case 'kt':
    case 'c':
    case 'cpp':
    case 'h':
    case 'cs':
    case 'go':
    case 'rs':
    case 'rb':
    case 'php':
    case 'swift':
    case 'sh':
    case 'yaml':
    case 'yml':
    case 'toml':
    case 'ini':
    case 'sql':
    case 'css':
    case 'srt':
    case 'gradle':
    case 'properties':
      return 'text/plain';
  }
  return 'application/octet-stream';
}

bool isTextMime(String m) =>
    m.startsWith('text/') || m == 'application/json' || m == 'application/xml' || m == 'application/javascript';

String safeFileName(String s) {
  final r = s.replaceAll(RegExp(r'[^\w؀-ۿ.\-]+'), '_');
  return r.isEmpty ? 'file' : r;
}

/// حذف علامات Markdown قبل القراءة الصوتية.
String stripMarkdown(String s) {
  var t = s.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
  t = t.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1) ?? '');
  t = t.replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1) ?? '');
  t = t.replaceAll(RegExp(r'[#*_>~|]+'), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ---------------------------------------------------------------------
//  Palette (Claude-like warm palette)
// ---------------------------------------------------------------------
class Pal {
  final Color bg, surface, surfaceHi, border, text, muted, accent, onAccent, danger, success, codeBg, codeText;
  const Pal({
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.success,
    required this.codeBg,
    required this.codeText,
  });
}

const Pal lightPal = Pal(
  bg: Color(0xFFFAF9F5),
  surface: Color(0xFFFFFFFF),
  surfaceHi: Color(0xFFF0EEE6),
  border: Color(0xFFE3E0D6),
  text: Color(0xFF1F1E1D),
  muted: Color(0xFF73726C),
  accent: Color(0xFFC96442),
  onAccent: Color(0xFFFFFFFF),
  danger: Color(0xFFB3261E),
  success: Color(0xFF2E7D4F),
  codeBg: Color(0xFFF3F1EA),
  codeText: Color(0xFF2B2A28),
);

const Pal darkPal = Pal(
  bg: Color(0xFF262624),
  surface: Color(0xFF30302E),
  surfaceHi: Color(0xFF3A3938),
  border: Color(0xFF494845),
  text: Color(0xFFF0EEE6),
  muted: Color(0xFFA8A69E),
  accent: Color(0xFFD97757),
  onAccent: Color(0xFF1F1E1D),
  danger: Color(0xFFF2766B),
  success: Color(0xFF6CC48F),
  codeBg: Color(0xFF1E1E1C),
  codeText: Color(0xFFE6E4DC),
);

// ثيم Terminal: أسود دافئ، حدود رفيعة، نفس لون Claude البرتقالي.
const Pal termPal = Pal(
  bg: Color(0xFF111110),
  surface: Color(0xFF181817),
  surfaceHi: Color(0xFF232321),
  border: Color(0xFF34332F),
  text: Color(0xFFE6E4DC),
  muted: Color(0xFF8C8A82),
  accent: Color(0xFFD97757),
  onAccent: Color(0xFF111110),
  danger: Color(0xFFF2766B),
  success: Color(0xFF6CC48F),
  codeBg: Color(0xFF0A0A09),
  codeText: Color(0xFFE6E4DC),
);

class PalExt extends ThemeExtension<PalExt> {
  final Pal pal;
  const PalExt(this.pal);
  @override
  PalExt copyWith({Pal? pal}) => PalExt(pal ?? this.pal);
  @override
  PalExt lerp(ThemeExtension<PalExt>? other, double t) => (t >= 0.5 && other is PalExt) ? other : this;
}

Pal pal(BuildContext c) {
  final t = Theme.of(c);
  final ext = t.extension<PalExt>();
  if (ext != null) return ext.pal;
  return t.brightness == Brightness.dark ? darkPal : lightPal;
}

ThemeData buildTheme(Brightness b, {Pal? custom, bool mono = false}) {
  final p = custom ?? (b == Brightness.dark ? darkPal : lightPal);
  // fromSeed يعطي ألواناً دافئة متناسقة لكل ما لا نحدده يدوياً (بدل البنفسجي الافتراضي).
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: b).copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    secondaryContainer: p.surfaceHi,
    onSecondaryContainer: p.text,
    surface: p.surface,
    onSurface: p.text,
    error: p.danger,
    outline: p.border,
    outlineVariant: p.border,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    fontFamily: mono ? 'monospace' : null,
    extensions: <ThemeExtension<dynamic>>[PalExt(p)],
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: p.text,
      centerTitle: true,
    ),
    // بدل ChoiceChip(showCheckmark:) الذي لا يوجد في إصدارات Flutter الأقدم.
    chipTheme: const ChipThemeData(showCheckmark: false),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.accent.withAlpha(70),
      selectionHandleColor: p.accent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.text,
      contentTextStyle: TextStyle(color: p.bg, fontSize: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: p.surface,
    ),
    drawerTheme: DrawerThemeData(backgroundColor: p.bg, surfaceTintColor: Colors.transparent),
  );
}

// ---------------------------------------------------------------------
//  Toast / confirm helpers (usable from anywhere, incl. non-widget code)
// ---------------------------------------------------------------------
void toast(String msg) {
  final m = messengerKey.currentState;
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

Future<bool> askConfirm(String title, String body, {String ok = 'موافقة', String cancel = 'رفض'}) async {
  if (inlineApprovalHosts > 0) {
    if (alwaysAllowed.contains('$title|$body')) return true;
    return requestInlineApproval(title, body, ok, cancel);
  }
  return askConfirmDialog(title, body, ok: ok, cancel: cancel);
}

Future<bool> askConfirmDialog(String title, String body, {String ok = 'موافقة', String cancel = 'رفض'}) async {
  final ctx = navKey.currentContext;
  if (ctx == null) return false;
  final r = await showDialog<bool>(
    context: ctx,
    barrierDismissible: false,
    builder: (c) {
      final p = pal(c);
      return AlertDialog(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(title, style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(child: SelectableText(body, style: TextStyle(color: p.text, fontSize: 13.5, height: 1.45))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel, style: TextStyle(color: p.muted))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      );
    },
  );
  return r == true;
}

/// حوار نصي بسيط (إعادة تسمية…).
Future<String?> askText(BuildContext context, String title, {String initial = '', String hint = '', bool multiline = false}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) {
      final p = pal(c);
      return AlertDialog(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(title, style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: multiline ? 8 : 1,
          decoration: fieldDeco(c, hint: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text('إلغاء', style: TextStyle(color: p.muted))),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('حفظ')),
        ],
      );
    },
  );
  return r;
}

Future<bool> confirmDialog(BuildContext context, String title, String body, {String ok = 'حذف'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) {
      final p = pal(c);
      return AlertDialog(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(title, style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600)),
        content: Text(body, style: TextStyle(color: p.muted, fontSize: 14, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text('إلغاء', style: TextStyle(color: p.muted))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true),
            child: Text(ok),
          ),
        ],
      );
    },
  );
  return r == true;
}

InputDecoration fieldDeco(BuildContext c, {String? label, String? hint, Widget? suffix, Widget? prefix}) {
  final p = pal(c);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffix,
    prefixIcon: prefix,
    filled: true,
    fillColor: p.surfaceHi,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    labelStyle: TextStyle(color: p.muted),
    hintStyle: TextStyle(color: p.muted.withAlpha(180)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.accent, width: 1.2)),
  );
}

Future<T?> showSheet<T>(BuildContext context, WidgetBuilder builder, {bool full = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: pal(context).surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: builder,
  );
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 38,
          height: 4,
          margin: const EdgeInsets.only(top: 10, bottom: 8),
          decoration: BoxDecoration(color: pal(context).border, borderRadius: BorderRadius.circular(4)),
        ),
      );
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(text, style: TextStyle(color: pal(context).muted, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
      );
}

class SheetAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;
  final Widget? trailing;
  const SheetAction({super.key, required this.icon, required this.title, required this.onTap, this.subtitle, this.danger = false, this.trailing});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final col = danger ? p.danger : p.text;
    return ListTile(
      leading: Icon(icon, color: danger ? p.danger : p.muted, size: 22),
      title: Text(title, style: TextStyle(color: col, fontSize: 15)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(color: p.muted, fontSize: 12.5)),
      trailing: trailing,
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.comfortable,
    );
  }
}
