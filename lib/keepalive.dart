part of 'main.dart';

// =====================================================================
//  البقاء حيّاً في الخلفية (v2.10.0): خدمة مقدّمة أندرويد + قفل تشغيل جزئي أثناء عمل الـ Agent.
//  بدونها يجمّد أندرويد التطبيق بعد دقائق من إغلاق الشاشة أو التبديل لتطبيق آخر فيموت العمل الطويل.
//  الجانب الأصلي: packages/lm_keepalive (Kotlin). العدّ مرجعي: كل جلسة تعمل تحجز، وتتوقف الخدمة عند آخر إفراج.
//  كل الاستدعاءات آمنة: خارج أندرويد أو بلا إضافة لا يحدث شيء.
// =====================================================================
class KeepAlive {
  static const MethodChannel _ch = MethodChannel('lmclient/keepalive');
  static int _holds = 0;
  static bool _on = false;
  static bool _askedThisRun = false;
  static String _text = '';

  static Future<bool> _call(String m, [Map<String, dynamic>? args]) async {
    try {
      final dynamic r = await _ch.invokeMethod<dynamic>(m, args);
      return r == true;
    } catch (_) {
      return false;
    }
  }

  static bool get enabled => appContainer.read(settingsProvider).keepAlive;

  static Future<void> acquire(String text) async {
    _holds++;
    _text = text;
    if (!enabled || _on) return;
    final bool ok = await _call('start', <String, dynamic>{'title': 'LMClient', 'text': text});
    _on = ok;
    if (ok) unawaited(_askNotificationsOnce());
  }

  static Future<void> note(String text) async {
    if (!_on || text == _text) return;
    _text = text;
    await _call('update', <String, dynamic>{'title': 'LMClient', 'text': text});
  }

  static Future<void> release() async {
    if (_holds > 0) _holds--;
    if (_holds == 0 && _on) {
      _on = false;
      await _call('stop');
    }
  }

  /// إذن الإشعارات (أندرويد 13+): يُطلب مرة واحدة فقط لكل تثبيت. بدونه تعمل الخدمة لكن لا يظهر الإشعار.
  static Future<void> _askNotificationsOnce() async {
    if (_askedThisRun) return;
    _askedThisRun = true;
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      if (p.getBool('askedNotifications') == true) return;
      if (await _call('notificationsAllowed')) return;
      await p.setBool('askedNotifications', true);
      await _call('requestNotifications');
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------
//  اختبار ذاتي (يُشغَّل في فحص المحاكي بالـ CI): الخدمة تبدأ فعلاً وتتوقف، وCI يفحص النظام من الخارج عند العلامة SHOT.
// ---------------------------------------------------------------------
Future<void> runKeepAliveSelfTest() async {
  int fails = 0;
  int total = 0;
  // ignore: avoid_print
  void out(String s) => print('LMPROBE|KEEPALIVE $s');
  void rec(String name, bool ok, String detail) {
    total++;
    if (!ok) fails++;
    out('${ok ? 'OK  ' : 'FAIL'} $name${detail.isEmpty ? '' : ' :: $detail'}');
  }

  try {
    final bool before = await KeepAlive._call('isRunning');
    rec('not running before the test', !before, '');
    final bool started = await KeepAlive._call('start', <String, dynamic>{'title': 'LMClient probe', 'text': 'keepalive self-test'});
    rec('start accepted', started, '');
    await Future<void>.delayed(const Duration(seconds: 2));
    rec('service is running', await KeepAlive._call('isRunning'), '');
    out('info notificationsAllowed=${await KeepAlive._call('notificationsAllowed')}');
    // ignore: avoid_print
    print('LMPROBE|SHOT keepalive');
    await Future<void>.delayed(const Duration(seconds: 7));
    rec('update accepted while running', await KeepAlive._call('update', <String, dynamic>{'title': 'LMClient probe', 'text': 'tool: read_file'}), '');
    rec('stop accepted', await KeepAlive._call('stop'), '');
    await Future<void>.delayed(const Duration(seconds: 2));
    rec('service stopped', !(await KeepAlive._call('isRunning')), '');
    // العدّ المرجعي عبر الواجهة العليا
    await KeepAlive.acquire('a');
    await KeepAlive.acquire('b');
    await Future<void>.delayed(const Duration(seconds: 1));
    rec('acquire starts the service', await KeepAlive._call('isRunning'), '');
    await KeepAlive.release();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    rec('one release keeps it running (two holders)', await KeepAlive._call('isRunning'), '');
    await KeepAlive.release();
    await Future<void>.delayed(const Duration(seconds: 2));
    rec('last release stops it', !(await KeepAlive._call('isRunning')), '');
  } catch (e) {
    rec('keepalive tests', false, '$e');
  }
  out('DONE fails=$fails total=$total');
}
