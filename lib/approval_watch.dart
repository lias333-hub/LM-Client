part of 'main.dart';

// =====================================================================
//  مراقب انتظار الموافقة (v2.14.4): في أول تشغيل حقيقي ضاع 81% من الوقت في انتظار موافقات (إحداها 12 دقيقة) لأن المستخدم لم يعلم
//  أن الـ agent واقف عليه. بعد [kApprovalAlertAfter] من الانتظار: شريط تنبيه فوق الإدخال في Terminal ونبض في حدود البطاقة،
//  ونص إشعار الخدمة يتغيّر، وإن كان التطبيق في الخلفية يُرسَل إشعار منبّه واحد (قناة عالية الأهمية). لا أزرار موافقة داخل الإشعار
//  عمداً: الموافقة على أمر دون رؤية نصه الكامل غير آمنة.
//  كل نقاط الموافقة تمرّ من هنا (guard)، فلا يلزم أن يعرف كل موضع بالمنطق.
// =====================================================================
/// مهلة الانتظار قبل التنبيه (30 ثانية، كما في النموذج المرئي المعتمد).
const Duration kApprovalAlertAfter = Duration(seconds: 30);

class ApprovalWait {
  /// وصف قصير لما ينتظر الموافقة، مثل «bash · sh todo_test/test.sh».
  final String label;
  final bool danger;
  final DateTime since;

  /// صحيح بعد مرور [kApprovalAlertAfter] وبدء التنبيه.
  final bool alerted;
  const ApprovalWait(this.label, this.danger, this.since, {this.alerted = false});
  ApprovalWait asAlerted() => ApprovalWait(label, danger, since, alerted: true);
}

/// نص مختصر لطلب موافقة: سطر الأمر (يبدأ بـ «$ ») إن وُجد، وإلا العنوان.
String approvalLabel(String title, String body) {
  for (final String l in body.split('\n')) {
    if (l.startsWith(r'$ ')) return 'bash · ${clip(l.substring(2).trim(), 70)}';
  }
  return clip(title, 70);
}

class ApprovalWatch {
  /// الانتظار الجاري (null = لا موافقة معلّقة). تستمع إليه الواجهة.
  static final ValueNotifier<ApprovalWait?> current = ValueNotifier<ApprovalWait?>(null);
  static int _open = 0;
  static Timer? _timer;

  /// خطّاف للاختبار: يُستدعى عند بدء التنبيه بدل الإشعار الحقيقي (null = السلوك العادي).
  static void Function(ApprovalWait w)? alertHook;

  /// يلفّ سؤالاً للمستخدم: يبدأ المراقبة قبله وينهيها بعده مهما كانت النتيجة.
  static Future<T> guard<T>(String label, bool danger, Future<T> Function() ask, {Duration after = kApprovalAlertAfter}) async {
    begin(label, danger, after: after);
    try {
      return await ask();
    } finally {
      end();
    }
  }

  static void begin(String label, bool danger, {Duration after = kApprovalAlertAfter}) {
    _open++;
    if (_open > 1) return; // موافقات متداخلة (مثلاً نافذة بديلة عن بطاقة): نحتفظ بالأولى
    current.value = ApprovalWait(label, danger, DateTime.now());
    _timer?.cancel();
    _timer = Timer(after, _fire);
  }

  static void end() {
    if (_open > 0) _open--;
    if (_open > 0) return;
    _timer?.cancel();
    _timer = null;
    final ApprovalWait? w = current.value;
    current.value = null;
    if (w != null && w.alerted) unawaited(KeepAlive.clearAlert());
  }

  static void _fire() {
    _timer = null;
    final ApprovalWait? w = current.value;
    if (w == null || w.alerted) return;
    final ApprovalWait a = w.asAlerted();
    current.value = a;
    final void Function(ApprovalWait)? hook = alertHook;
    if (hook != null) {
      hook(a);
      return;
    }
    final String title = a.danger ? 'أمر خطير ينتظر موافقتك' : 'ينتظر موافقتك منذ ${kApprovalAlertAfter.inSeconds} ثانية';
    // نص إشعار الخدمة (إن كانت تعمل) يتغيّر دائماً؛ الإشعار المنبّه فقط والتطبيق خارج الواجهة (داخلها الشريط يكفي).
    unawaited(KeepAlive.note('$title · ${a.label}'));
    final AppLifecycleState? ls = WidgetsBinding.instance.lifecycleState;
    if (ls != null && ls != AppLifecycleState.resumed) unawaited(KeepAlive.alert(title, a.label));
  }

  /// «0:42» لمدة الانتظار.
  static String elapsed(ApprovalWait w) => fmtElapsed(DateTime.now().difference(w.since));
}
