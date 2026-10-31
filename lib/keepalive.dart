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

  static Timer? _stopTimer;
  // لا نوقف الخدمة فور آخر إفراج: تشغيلات قصيرة متتالية (أو «تابع» بعد توقّف) كانت تبدأ وتوقف الخدمة في أجزاء من الثانية.
  static const Duration _stopDelay = Duration(seconds: 2);

  static Future<void> acquire(String text) async {
    _holds++;
    _text = text;
    _stopTimer?.cancel();
    _stopTimer = null;
    if (!enabled || _on) return;
    _on = true; // قبل الانتظار: حاجزان متزامنان لا يبدآن الخدمة مرتين
    final bool ok = await _call('start', <String, dynamic>{'title': 'LMClient', 'text': text});
    if (!ok) _on = false;
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
      _stopTimer?.cancel();
      _stopTimer = Timer(_stopDelay, () {
        _stopTimer = null;
        if (_holds == 0 && _on) {
          _on = false;
          unawaited(_call('stop'));
        }
      });
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
    await Future<void>.delayed(const Duration(milliseconds: 500));
    rec('stop is delayed after the last release', await KeepAlive._call('isRunning'), '');
    await Future<void>.delayed(const Duration(seconds: 4));
    rec('last release stops it after the delay', !(await KeepAlive._call('isRunning')), '');

    // ---- سباقات بدء/إيقاف سريعة (v2.12.2): كانت تُسقط التطبيق بـ ForegroundServiceDidNotStartInTimeException ----
    await KeepAlive._call('start', <String, dynamic>{'title': 'LMClient probe', 'text': 'race 1'});
    await KeepAlive._call('stop'); // قبل أن تصل الخدمة إلى startForeground: كان الإيقاف يُهمَل والخدمة تبقى عالقة
    await Future<void>.delayed(const Duration(seconds: 3));
    rec('start then immediate stop ends stopped', !(await KeepAlive._call('isRunning')), '');

    for (int i = 0; i < 25; i++) {
      await KeepAlive._call('start', <String, dynamic>{'title': 'LMClient probe', 'text': 'storm $i'});
      await KeepAlive._call('update', <String, dynamic>{'title': 'LMClient probe', 'text': 'storm update $i'});
      await KeepAlive._call('stop');
    }
    await Future<void>.delayed(const Duration(seconds: 4));
    rec('25 rapid start/update/stop cycles: app alive and service stopped', !(await KeepAlive._call('isRunning')), '');

    for (int i = 0; i < 12; i++) {
      await KeepAlive.acquire('rapid $i');
      await KeepAlive.release();
    }
    await Future<void>.delayed(const Duration(seconds: 4));
    rec('12 rapid acquire/release cycles end stopped', !(await KeepAlive._call('isRunning')), '');

    await KeepAlive.acquire('again 1');
    await KeepAlive.release();
    await KeepAlive.acquire('again 2'); // داخل مهلة التأخير: لا يجوز أن تُوقَف الخدمة
    await Future<void>.delayed(const Duration(seconds: 4));
    rec('re-acquire inside the delay keeps it running', await KeepAlive._call('isRunning'), '');
    await KeepAlive.release();
    await Future<void>.delayed(const Duration(seconds: 4));
    rec('and it stops after the final release', !(await KeepAlive._call('isRunning')), '');

    // stop ثم start مباشرة (جولة جديدة تبدأ فور انتهاء السابقة): الطلب الأحدث يجب أن يبقي الخدمة حيّة
    await KeepAlive._call('start', <String, dynamic>{'title': 'LMClient probe', 'text': 'newer start wins 1'});
    await Future<void>.delayed(const Duration(seconds: 1));
    await KeepAlive._call('stop');
    await KeepAlive._call('start', <String, dynamic>{'title': 'LMClient probe', 'text': 'newer start wins 2'});
    await Future<void>.delayed(const Duration(seconds: 3));
    rec('a newer start right after a stop keeps it running', await KeepAlive._call('isRunning'), '');
    await KeepAlive._call('stop');
    await Future<void>.delayed(const Duration(seconds: 3));
    rec('final stop ends it', !(await KeepAlive._call('isRunning')), '');
  } catch (e) {
    rec('keepalive tests', false, '$e');
  }
  out('DONE fails=$fails total=$total');
}
