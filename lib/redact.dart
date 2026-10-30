part of 'main.dart';

// =====================================================================
//  إخفاء الأسرار من نتائج الأدوات قبل أن تصل إلى المزوّد (ومن بطاقات الأدوات).
//  السبب: أمر واحد مثل `cat ~/.bashrc` يضع مفتاحاً حقيقياً في سياق المحادثة، فيُرسَل لمزوّد النموذج
//  مع كل جولة لاحقة. النموذج لا يستطيع «نسيانه»؛ الحل الوحيد ألا يصل أصلاً.
//
//  طبقتان:
//   1) أنماط عالية الدقة (مفاتيح بصيغ معروفة، كتل المفاتيح الخاصة، JWT) + أسرار التطبيق نفسه (مفاتيح بروفايلاتك
//      وكلمات سرّ بيئات SSH تُطابَق حرفياً). تُطبَّق على كل الأدوات.
//   2) تخمين بالأسماء (TOKEN=… أو "apiKey": "…") لا يُطبَّق إلا على مخرجات الصدفة وعلى قراءة ملفات حسّاسة
//      الاسم (.env/.bashrc/credentials…)، كي لا نفسد قراءة الشيفرة العادية فيفشل تعديلها.
// =====================================================================
class Redacted {
  final String text;
  final int count;
  const Redacted(this.text, this.count);
}

class _RedRule {
  final RegExp re;
  final String label;
  const _RedRule(this.re, this.label);
}

class Redactor {
  static const int _minKnown = 8;

  static final List<_RedRule> _strong = <_RedRule>[
    _RedRule(RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|$)'), 'private-key'),
    _RedRule(RegExp(r'\bAIza[0-9A-Za-z_\-]{35}\b'), 'google-key'),
    _RedRule(RegExp(r'\bAQ\.[A-Za-z0-9_\-]{30,}'), 'google-token'),
    _RedRule(RegExp(r'\bsk-[A-Za-z0-9_\-]{24,}'), 'api-key'),
    _RedRule(RegExp(r'\bgh[pousr]_[A-Za-z0-9]{30,}'), 'github-token'),
    _RedRule(RegExp(r'\bgithub_pat_[A-Za-z0-9_]{30,}'), 'github-token'),
    _RedRule(RegExp(r'\bxox[abprs]-[A-Za-z0-9\-]{10,}'), 'slack-token'),
    _RedRule(RegExp(r'\bAKIA[0-9A-Z]{16}\b'), 'aws-key'),
    _RedRule(RegExp(r'\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'), 'jwt'),
  ];

  /// «Bearer xxxxx» (ترويسة Authorization).
  static final RegExp _bearer = RegExp(r'(\bbearer\s+)[A-Za-z0-9._~+/\-]{24,}=*', caseSensitive: false);

  /// NAME=value حيث الاسم يدلّ على سرّ، والقيمة تشبه سرّاً (حروف وأرقام معاً، 12+ خانة).
  static final RegExp _assign = RegExp(
    r'''((?:API[_-]?KEY|SECRET|TOKEN|PASSWORD|PASSWD|PRIVATE[_-]?KEY|ACCESS[_-]?KEY|CREDENTIALS?)[A-Za-z0-9_\-]*["']?\s*[=:]\s*)(["']?)([A-Za-z0-9_\-./+=~]{12,})\2''',
    caseSensitive: false,
  );

  static bool _looksSecret(String v) {
    if (v.startsWith('[REDACTED')) return false;
    final bool hasDigit = RegExp(r'\d').hasMatch(v);
    final bool hasAlpha = RegExp(r'[A-Za-z]').hasMatch(v);
    return hasDigit && hasAlpha;
  }

  static final RegExp _sensitiveName = RegExp(
    r'(^|/)(\.env[^/]*|\.bashrc|\.bash_profile|\.zshrc|\.profile|\.zprofile|\.npmrc|\.netrc|\.pypirc|\.pgpass|\.git-credentials|\.claude\.json|credentials(\.json)?|secrets\.(json|ya?ml|env|txt|toml)|id_(rsa|dsa|ecdsa|ed25519)|[^/]*\.(pem|key|p12|pfx))$',
    caseSensitive: false,
  );

  /// هل اسم هذا الملف يوحي بأنه يحمل أسراراً؟ (يفعّل التخمين بالأسماء عند قراءته).
  static bool sensitivePath(String p) => _sensitiveName.hasMatch(p.replaceAll('\\', '/'));

  /// أسرار التطبيق نفسه: تُطابَق حرفياً مهما كان شكلها.
  static List<String> knownSecrets() {
    final List<String> out = <String>[];
    try {
      for (final ApiProfile p in appContainer.read(profilesProvider).list) {
        final String k = p.apiKey.trim();
        if (k.length >= _minKnown) out.add(k);
      }
    } catch (_) {}
    try {
      for (final WorkspaceConfig w in appContainer.read(workspacesProvider)) {
        if (w.password.length >= _minKnown) out.add(w.password);
      }
    } catch (_) {}
    return out;
  }

  /// [heuristics]: فعّل التخمين بالأسماء (للصدفة وللملفات الحسّاسة الاسم).
  static Redacted clean(String text, {bool heuristics = false, List<String>? known}) {
    if (text.isEmpty) return Redacted(text, 0);
    int n = 0;
    String t = text;
    for (final String k in (known ?? knownSecrets())) {
      if (t.contains(k)) {
        final int c = k.allMatches(t).length;
        n += c;
        t = t.replaceAll(k, '[REDACTED:saved-secret]');
      }
    }
    for (final _RedRule r in _strong) {
      t = t.replaceAllMapped(r.re, (Match m) {
        n++;
        return '[REDACTED:${r.label}]';
      });
    }
    t = t.replaceAllMapped(_bearer, (Match m) {
      n++;
      return '${m.group(1)}[REDACTED]';
    });
    if (heuristics) {
      t = t.replaceAllMapped(_assign, (Match m) {
        final String v = m.group(3) ?? '';
        if (!_looksSecret(v)) return m.group(0) ?? '';
        n++;
        final String q = m.group(2) ?? '';
        return '${m.group(1)}$q[REDACTED]$q';
      });
      t = t.replaceAllMapped(
        RegExp(r'''("[A-Za-z0-9_\-]*(?:api[_-]?key|secret|token|password|passwd|private[_-]?key)[A-Za-z0-9_\-]*"\s*:\s*")([^"\n]{8,})(")''', caseSensitive: false),
        (Match m) {
          final String v = m.group(2) ?? '';
          if (v.startsWith('[REDACTED') || v.contains(' ')) return m.group(0) ?? '';
          n++;
          return '${m.group(1)}[REDACTED]${m.group(3)}';
        },
      );
    }
    return Redacted(t, n);
  }

  static const String note = '[note: the app hid secret values in this output before sending it to the model. Do not try to recover, print or guess them.]';

  /// نتيجة أداة جاهزة للإرسال: النص بعد الإخفاء (+ ملاحظة للنموذج إن أُخفي شيء).
  static String forTool(String toolName, Map<String, dynamic> args, String text) {
    final bool shell = toolName == kToolBash || toolName == kToolBashOut;
    final dynamic path = args['path'];
    final bool sensitiveFile = toolName == kToolReadFile && path is String && sensitivePath(path);
    final Redacted r = clean(text, heuristics: shell || sensitiveFile);
    if (r.count == 0) return text;
    return '${r.text}\n$note';
  }
}
