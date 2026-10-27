part of 'main.dart';

// =====================================================================
//  الأسرار (مفاتيح API، مفاتيح SSH الخاصة، كلمات السر) في Android Keystore عبر التخزين المشفّر،
//  لا في SharedPreferences ولا في ملفات JSON العادية.
//  السبب: `LocalExec` يشغّل أوامر بصلاحيات التطبيق نفسها، وملف نصي عادي يقرؤه أمر `cat` واحد
//  (مثلاً بعد حقن تعليمات في صفحة ويب مع الوضع التلقائي).
//  إن تعذّر المخزن نُبقي السرّ في الملف بدل أن يضيع، ولا نحذف أسراراً لأن قراءتها فشلت.
// =====================================================================
class SecretStore {
  static const FlutterSecureStorage _s = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  /// آخر قراءة فشلت (استثناء) وليست «غير موجود».
  static bool lastFailed = false;

  static Future<String?> read(String key) async {
    try {
      lastFailed = false;
      return await _s.read(key: key);
    } catch (_) {
      lastFailed = true;
      return null;
    }
  }

  static Future<bool> write(String key, String value) async {
    try {
      await _s.write(key: key, value: value);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> delete(String key) async {
    try {
      await _s.delete(key: key);
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------
//  اختبار ذاتي (فحص المحاكي في الـ CI): الذهاب والإياب، ترحيل النسخ القديمة، وخلوّ ملفات JSON من الأسرار.
// ---------------------------------------------------------------------
Future<void> runSecretsSelfTest() async {
  int fails = 0;
  int total = 0;
  // ignore: avoid_print
  void out(String s) => print('LMPROBE|SECRETS $s');
  void rec(String name, bool ok, String detail) {
    total++;
    if (!ok) fails++;
    final String d = detail.replaceAll('\n', ' ⏎ ');
    out('${ok ? 'OK  ' : 'FAIL'} $name${d.isEmpty ? '' : ' :: ${d.length > 200 ? d.substring(0, 200) : d}'}');
  }

  try {
    final bool w = await SecretStore.write('ci:probe', 'v1');
    final String? r = await SecretStore.read('ci:probe');
    rec('keystore round trip', w && r == 'v1', 'w=$w r=$r');
    await SecretStore.delete('ci:probe');
    final String? r2 = await SecretStore.read('ci:probe');
    rec('keystore delete', r2 == null, '$r2');

    // ---- مفاتيح API: ترحيل نسخة قديمة بنص عادي
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(
      'profiles',
      jsonEncode(<Map<String, dynamic>>[
        <String, dynamic>{'id': 'sec-p1', 'name': 'legacy', 'kind': 'anthropic', 'baseUrl': 'https://example.invalid', 'apiKey': 'sk-legacy-123', 'selectedModel': 'm'},
      ]),
    );
    final ProviderContainer c1 = ProviderContainer();
    await c1.read(profilesProvider.notifier).load();
    final List<ApiProfile> l1 = c1.read(profilesProvider).list;
    rec('legacy api key still usable after migration', l1.length == 1 && l1[0].apiKey == 'sk-legacy-123', '${l1.length}');
    final String rawAfter = p.getString('profiles') ?? '';
    rec('profiles file no longer holds the key', rawAfter.isNotEmpty && !rawAfter.contains('sk-legacy-123'), rawAfter);
    final String? inStore = await SecretStore.read('apikey:sec-p1');
    rec('api key is in the keystore', inStore == 'sk-legacy-123', '$inStore');
    final ProviderContainer c2 = ProviderContainer();
    await c2.read(profilesProvider.notifier).load();
    final List<ApiProfile> l2 = c2.read(profilesProvider).list;
    rec('api key restored after a restart', l2.length == 1 && l2[0].apiKey == 'sk-legacy-123', '${l2.length}');
    await c2.read(profilesProvider.notifier).remove('sec-p1');
    rec('removing a profile deletes its key', (await SecretStore.read('apikey:sec-p1')) == null, '');
    c1.dispose();
    c2.dispose();

    // ---- بيئات SSH: مفتاح خاص وكلمة سر
    final WorkspaceConfig wc = WorkspaceConfig(id: 'sec-w1', name: 'srv', host: 'example.invalid', port: 22, user: 'u', keyPem: 'PEM-SECRET-XYZ', password: 'PW-SECRET-XYZ');
    await LocalStorage.save('workspaces', 'list', jsonEncode(<Map<String, dynamic>>[wc.toJson()]));
    final ProviderContainer c3 = ProviderContainer();
    await c3.read(workspacesProvider.notifier).load();
    final List<WorkspaceConfig> w3 = c3.read(workspacesProvider);
    rec('legacy ssh secrets still usable after migration', w3.length == 1 && w3[0].keyPem == 'PEM-SECRET-XYZ' && w3[0].password == 'PW-SECRET-XYZ', '${w3.length}');
    final String raw3 = (await LocalStorage.load('workspaces', 'list')) ?? '';
    rec('workspaces file holds no secrets', raw3.isNotEmpty && !raw3.contains('PEM-SECRET-XYZ') && !raw3.contains('PW-SECRET-XYZ'), raw3);
    final ProviderContainer c4 = ProviderContainer();
    await c4.read(workspacesProvider.notifier).load();
    final List<WorkspaceConfig> w4 = c4.read(workspacesProvider);
    rec('ssh secrets restored after a restart', w4.length == 1 && w4[0].keyPem == 'PEM-SECRET-XYZ' && w4[0].password == 'PW-SECRET-XYZ', '${w4.length}');
    await c4.read(workspacesProvider.notifier).remove('sec-w1');
    rec('removing a workspace deletes its secrets', (await SecretStore.read('ws:sec-w1:key')) == null && (await SecretStore.read('ws:sec-w1:pw')) == null, '');
    c3.dispose();
    c4.dispose();
  } catch (e) {
    rec('secrets tests', false, '$e');
  }
  out('DONE fails=$fails total=$total');
}
