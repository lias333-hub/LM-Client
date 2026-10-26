// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, unused_local_variable, avoid_print, deprecated_member_use, use_build_context_synchronously, prefer_const_constructors, prefer_const_literals_to_create_immutables, depend_on_referenced_packages, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, unnecessary_import
part of 'main.dart';

// =====================================================================
//  Backup / restore
// =====================================================================
Future<Map<String, dynamic>> buildBackup({required bool keys, required bool chats}) async {
  final c = appContainer;
  final profiles = c.read(profilesProvider);
  final m = <String, dynamic>{
    'app': kAppName,
    'version': kAppVersion,
    'time': DateTime.now().toIso8601String(),
    'settings': c.read(settingsProvider).m,
    'profiles': profiles.list.map((e) {
      final j = e.toJson();
      if (!keys) j['apiKey'] = '';
      return j;
    }).toList(),
    'selectedProfile': profiles.selectedId,
    'memory': c.read(memoryProvider).map((e) => e.toJson()).toList(),
    'projects': c.read(projectsProvider).map((e) => e.toJson()).toList(),
    'agents': c.read(agentsProvider).map((e) => e.toJson()).toList(),
  };
  if (chats) {
    final idx = c.read(convListProvider);
    m['convIndex'] = idx.map((e) => e.toJson()).toList();
    final convs = <String, dynamic>{};
    for (final cv in idx) {
      final raw = await LocalStorage.load('chats', cv.id);
      if (raw == null) continue;
      try {
        convs[cv.id] = jsonDecode(raw);
      } catch (_) {}
    }
    m['chats'] = convs;
  }
  return m;
}

Future<String> restoreBackup(String raw) async {
  final dynamic decoded = jsonDecode(raw);
  if (decoded is! Map) throw const FormatException('الملف ليس نسخة احتياطية صالحة');
  final j = asMap(decoded);
  if (!j.containsKey('profiles') && !j.containsKey('settings') && !j.containsKey('chats')) {
    throw const FormatException('لا توجد بيانات معروفة داخل الملف');
  }
  final c = appContainer;
  int nProfiles = 0, nMem = 0, nProj = 0, nAgents = 0, nChats = 0;
  if (j['settings'] is Map) c.read(settingsProvider.notifier).replaceAll(asMap(j['settings']));
  final pn = c.read(profilesProvider.notifier);
  for (final e in asList(j['profiles'])) {
    var pr = ApiProfile.fromJson(asMap(e));
    if (pr.apiKey.isEmpty) {
      for (final old in c.read(profilesProvider).list) {
        if (old.id == pr.id) pr = pr.copyWith(apiKey: old.apiKey); // لا نمسح مفتاحاً موجوداً بنسخة بلا مفاتيح
      }
    }
    await pn.upsert(pr);
    nProfiles++;
  }
  final sel = j['selectedProfile'];
  if (sel is String && c.read(profilesProvider).list.any((x) => x.id == sel)) await pn.select(sel);
  for (final e in asList(j['memory'])) {
    await c.read(memoryProvider.notifier).upsert(MemoryPart.fromJson(asMap(e)));
    nMem++;
  }
  for (final e in asList(j['projects'])) {
    await c.read(projectsProvider.notifier).upsert(Project.fromJson(asMap(e)));
    nProj++;
  }
  for (final e in asList(j['agents'])) {
    await c.read(agentsProvider.notifier).upsert(Agent.fromJson(asMap(e)));
    nAgents++;
  }
  final chats = asMap(j['chats']);
  if (chats.isNotEmpty) {
    final metas = <String, ConvMeta>{};
    for (final e in asList(j['convIndex'])) {
      final cm = ConvMeta.fromJson(asMap(e));
      metas[cm.id] = cm;
    }
    for (final id in chats.keys) {
      final v = chats[id];
      if (v is! List) continue;
      await LocalStorage.save('chats', id, jsonEncode(v));
      final meta = metas[id] ?? ConvMeta(id: id, title: 'محادثة مستعادة');
      await c.read(convListProvider.notifier).upsert(meta);
      nChats++;
    }
  }
  return 'الملفات المستعادة: $nProfiles مزوّد · $nMem ذاكرة · $nProj مشروع · $nAgents Agent · $nChats محادثة';
}

Future<void> showBackupSheet(BuildContext context) {
  bool keys = false;
  bool chats = true;
  return showSheet<void>(context, (c) {
    return StatefulBuilder(builder: (c, setSt) {
      final p = pal(c);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetHandle(),
            Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 6), child: Text('نسخة احتياطية', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600))),
            SwitchListTile(
              value: chats,
              onChanged: (v) => setSt(() => chats = v),
              title: Text('تضمين المحادثات', style: TextStyle(color: p.text, fontSize: 14.5)),
              subtitle: Text('ملفات المكتبة والمرفقات الثنائية لا تُضمَّن', style: TextStyle(color: p.muted, fontSize: 12)),
            ),
            SwitchListTile(
              value: keys,
              onChanged: (v) => setSt(() => keys = v),
              title: Text('تضمين مفاتيح الـ API', style: TextStyle(color: keys ? p.danger : p.text, fontSize: 14.5)),
              subtitle: Text(keys ? 'تحذير: الملف سيحوي مفاتيحك نصاً صريحاً. لا تشاركه.' : 'موصى به: بدون المفاتيح', style: TextStyle(color: keys ? p.danger : p.muted, fontSize: 12)),
            ),
            SheetAction(
              icon: Icons.save_alt,
              title: 'حفظ كملف JSON',
              subtitle: 'في مجلد Download إن أمكن',
              onTap: () async {
                Navigator.pop(c);
                try {
                  final data = await buildBackup(keys: keys, chats: chats);
                  final path = await exportTextFile('lmclient_backup_${fmtDate(DateTime.now())}.json', const JsonEncoder.withIndent(' ').convert(data));
                  toast(savedMessage(path));
                } catch (e) {
                  toast('فشل التصدير: $e');
                }
              },
            ),
            SheetAction(
              icon: Icons.copy_rounded,
              title: 'نسخ إلى الحافظة',
              onTap: () async {
                Navigator.pop(c);
                try {
                  final data = await buildBackup(keys: keys, chats: chats);
                  await Clipboard.setData(ClipboardData(text: jsonEncode(data)));
                  toast('تم النسخ');
                } catch (e) {
                  toast('فشل التصدير: $e');
                }
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
    });
  });
}

Future<void> importBackup(BuildContext context) async {
  final String raw;
  try {
    final res = await FilePicker.platform.pickFiles(withData: true, type: FileType.any);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    Uint8List? b = f.bytes;
    if (b == null && f.path != null) b = await File(f.path!).readAsBytes();
    if (b == null) {
      toast('تعذر قراءة الملف');
      return;
    }
    raw = utf8.decode(b, allowMalformed: true);
  } catch (e) {
    toast('تعذر اختيار الملف: $e');
    return;
  }
  if (!context.mounted) return;
  final ok = await confirmDialog(context, 'استعادة نسخة احتياطية', 'ستُستبدل الإعدادات الحالية وتُدمج بقية البيانات (المزوّدون، الذاكرة، المشاريع، الـ Agents، المحادثات) مع الموجود.', ok: 'استعادة');
  if (!ok) return;
  try {
    final msg = await restoreBackup(raw);
    toast(msg);
  } catch (e) {
    toast('فشلت الاستعادة: $e');
  }
}

// =====================================================================
//  Settings screen
// =====================================================================
class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Group({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final kids = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) kids.add(Divider(height: 1, color: p.border));
      kids.add(children[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionLabel(title),
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        decoration: cardDeco(p),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids),
      ),
    ]);
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.title, this.subtitle, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title, style: TextStyle(color: p.text, fontSize: 14.5)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool danger;
  const _NavRow({required this.icon, required this.title, this.subtitle, required this.onTap, this.trailing, this.danger = false});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: danger ? p.danger : p.muted, size: 22),
      title: Text(title, style: TextStyle(color: danger ? p.danger : p.text, fontSize: 14.5)),
      subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
      trailing: trailing,
    );
  }
}

class _Block extends StatelessWidget {
  final String title;
  final String? hint;
  final Widget child;
  final String? value;
  const _Block({required this.title, this.hint, required this.child, this.value});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: TextStyle(color: p.text, fontSize: 14.5))),
          if (value != null) Text(value!, style: TextStyle(color: p.accent, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ]),
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(hint!, style: TextStyle(color: p.muted, fontSize: 12, height: 1.4))),
        const SizedBox(height: 8),
        child,
      ]),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  final String? section;
  const SettingsScreen({super.key, this.section});

  Future<void> _askInt(BuildContext context, WidgetRef ref, String key, String title, String hint, int cur, {int min = 0, int fallback = 0}) async {
    final t = await askText(context, title, initial: cur > 0 ? '$cur' : '', hint: hint);
    if (t == null) return;
    int v = int.tryParse(t.trim()) ?? fallback;
    if (v < min) v = fallback;
    ref.read(settingsProvider.notifier).set(key, v);
  }

  Future<void> _sttLocale(BuildContext context, WidgetRef ref, String cur) {
    const opts = <List<String>>[
      <String>['', 'تلقائي (لغة الجهاز)'],
      <String>['ar_SA', 'العربية'],
      <String>['en_US', 'English (US)'],
      <String>['fr_FR', 'Français'],
      <String>['tr_TR', 'Türkçe'],
    ];
    return showSheet<void>(context, (c) {
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetHandle(),
          ...opts.map((o) => SheetAction(
                icon: cur == o[0] ? Icons.check_circle : Icons.circle_outlined,
                title: o[1],
                onTap: () {
                  ref.read(settingsProvider.notifier).set('sttLocale', o[0]);
                  Navigator.pop(c);
                },
              )),
          const SizedBox(height: 8),
        ]),
      );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final s = ref.watch(settingsProvider);
    final ps = ref.watch(profilesProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final convs = ref.watch(convListProvider);

    String tempText = s.temperature < 0 ? 'افتراضي' : s.temperature.toStringAsFixed(1);
    String topText = s.topP < 0 ? 'افتراضي' : s.topP.toStringAsFixed(2);

    final all = <String, List<Widget>>{
      'providers': <Widget>[
        SectionLabel('مزوّدو الـ API'),
        if (ps.list.isEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(16),
            decoration: cardDeco(p),
            child: Text('لا يوجد مزوّد. أضف Anthropic أو OpenAI أو Gemini أو أي خادم متوافق مع OpenAI (OpenRouter، DeepSeek، Groq، Ollama…).', style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.5)),
          ),
        ...ps.list.map((x) {
          final on = x.id == ps.selectedId;
          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => ref.read(profilesProvider.notifier).select(x.id),
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 2, 10),
                decoration: cardDeco(p, selected: on),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: Icon(on ? Icons.check_circle : Icons.circle_outlined, color: on ? p.accent : p.muted, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15.5, fontWeight: FontWeight.w600))),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(8)),
                          child: Text(x.kindLabel, style: TextStyle(color: p.muted, fontSize: 11)),
                        ),
                      ]),
                      const SizedBox(height: 3),
                      Directionality(textDirection: TextDirection.ltr, child: Text(x.baseUrl, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12))),
                      Text(x.selectedModel.isEmpty ? 'بدون موديل' : x.selectedModel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
                      if (x.apiKey.isEmpty && x.kind != kOpenAI) Text('⚠ لا يوجد مفتاح API', style: TextStyle(color: p.danger, fontSize: 12)),
                    ]),
                  ),
                  PopupMenuButton<String>(
                    color: p.surface,
                    surfaceTintColor: Colors.transparent,
                    icon: Icon(Icons.more_vert, color: p.muted, size: 20),
                    onSelected: (v) async {
                      if (v == 'edit') {
                        openProfileEditor(context, x);
                      } else if (v == 'delete') {
                        final ok = await confirmDialog(context, 'حذف المزوّد', 'حذف "${x.name}"؟');
                        if (ok) await ref.read(profilesProvider.notifier).remove(x.id);
                      }
                    },
                    itemBuilder: (_) => <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(value: 'edit', child: Text('تعديل', style: TextStyle(color: p.text))),
                      PopupMenuItem<String>(value: 'delete', child: Text('حذف', style: TextStyle(color: p.danger))),
                    ],
                  ),
                ]),
              ),
            ),
          );
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: OutlinedButton.icon(onPressed: () => openProfileEditor(context, null), icon: const Icon(Icons.add, size: 18), label: const Text('إضافة مزوّد')),
        ),

      ],
      'appearance': <Widget>[
        _Group(title: 'المظهر', children: <Widget>[
          _Block(
            title: 'السمة',
            hint: 'Terminal: أسود نقي بخط monospace على كل التطبيق',
            child: SegPicker<int>(values: const <int>[0, 1, 2, 3], labels: const <String>['تلقائي', 'فاتح', 'داكن', 'Terminal'], value: s.themeMode, onChanged: (v) => notifier.set('themeMode', v)),
          ),
          _SwitchRow(title: 'الواجهة من اليمين لليسار', subtitle: 'اتجاه التطبيق العام. اتجاه كل رسالة يُكتشف تلقائياً من لغتها.', value: s.rtl, onChanged: (v) => notifier.set('rtl', v)),
          _SwitchRow(title: 'خط Serif لنص المحادثة', subtitle: 'مثل تطبيق Claude', value: s.serif, onChanged: (v) => notifier.set('serif', v)),
          _Block(
            title: 'حجم الخط',
            value: '${(s.fontScale * 100).round()}%',
            child: Slider(value: s.fontScale.clamp(0.8, 1.5).toDouble(), min: 0.8, max: 1.5, divisions: 14, onChanged: (v) => notifier.set('fontScale', double.parse(v.toStringAsFixed(2)))),
          ),
          _SwitchRow(
              title: 'تنسيق غني في الردود',
              subtitle: 'مربعات تنبيه وألوان وتمييز. يُرسل للنموذج دليل صغير لاستخدامها',
              value: s.richFormat,
              onChanged: (v) => notifier.set('richFormat', v)),
          _SwitchRow(title: 'أزرار تحريك المؤشر في الإدخال', value: s.cursorBtns, onChanged: (v) => notifier.set('cursorBtns', v)),
        ]),

      ],
      'generation': <Widget>[
        _Group(title: 'التوليد', children: <Widget>[
          _Block(
            title: 'مستوى التفكير',
            hint: 'Anthropic: Extended/Adaptive thinking · OpenAI: reasoning_effort · Gemini: thinkingBudget. النماذج التي لا تدعمه يُعاد الطلب بدونه تلقائياً.',
            child: SegPicker<int>(values: const <int>[0, 1, 2, 3], labels: const <String>['إيقاف', 'منخفض', 'متوسط', 'عالٍ'], value: s.thinkLevel, onChanged: (v) => notifier.set('thinkLevel', v)),
          ),
          _Block(
            title: 'Temperature',
            value: tempText,
            hint: 'Anthropic يقبل 0–1. بعض نماذج التفكير تتجاهله أو ترفضه (يُحذف تلقائياً عند الرفض).',
            child: Row(children: [
              Expanded(child: Slider(value: (s.temperature < 0 ? 1.0 : s.temperature).clamp(0.0, 2.0).toDouble(), min: 0, max: 2, divisions: 20, onChanged: (v) => notifier.set('temperature', double.parse(v.toStringAsFixed(1))))),
              TextButton(onPressed: s.temperature < 0 ? null : () => notifier.set('temperature', -1.0), child: const Text('افتراضي')),
            ]),
          ),
          _NavRow(
            icon: Icons.compress,
            title: 'ميزانية السياق (توكنز تقريبية)',
            subtitle: s.contextBudget > 0
                ? '${s.contextBudget} — عند تجاوزها يُلخَّص الأقدم (أو يُحذف إن عُطّل التلخيص) ويبقى الدور الحالي'
                : 'بلا حد (المحادثات الطويلة تكلّف أكثر وقد تتجاوز نافذة النموذج)',
            onTap: () => _askInt(context, ref, 'contextBudget', 'ميزانية السياق', 'اتركه فارغاً لإلغاء الحد (الافتراضي 60000)', s.contextBudget),
          ),
          _NavRow(
            icon: Icons.notes,
            title: 'تعليمات عامة (System prompt)',
            subtitle: s.instructions.trim().isEmpty ? 'غير محددة' : clip(s.instructions.trim().replaceAll('\n', ' '), 80),
            onTap: () async {
              final t = await askText(context, 'تعليمات عامة', initial: s.instructions, hint: 'تُرسل مع كل محادثة…', multiline: true);
              if (t != null) notifier.set('instructions', t.trim());
            },
          ),
        ]),

      ],
      'behaviour': <Widget>[
        _Group(title: 'السلوك', children: <Widget>[
          _SwitchRow(title: 'الأدوات (Function calling)', subtitle: 'ذاكرة، مكتبة، وملفات/ويب عبر الـ Agent', value: s.tools, onChanged: (v) => notifier.set('tools', v)),
          _SwitchRow(title: 'طلب موافقتي قبل الكتابة وفتح الروابط', subtitle: 'يُنصح بإبقائه مفعّلاً', value: s.confirm, onChanged: (v) => notifier.set('confirm', v)),
          _NavRow(
            icon: Icons.terminal,
            title: 'بيئات التنفيذ (هذا الهاتف / SSH)',
            subtitle: 'طرفية لـ Claude مع موافقة على كل أمر، واختبار التنفيذ',
            onTap: () => pushScreen(const WorkspacesScreen()),
          ),
          _NavRow(
            icon: Icons.auto_awesome,
            title: 'المهارات (Skills)',
            subtitle: 'تعليمات جاهزة يحمّلها النموذج عند الحاجة · استيراد من GitHub أو .claude/skills',
            onTap: () => pushScreen(const SkillsScreen()),
          ),
          _SwitchRow(title: 'تسمية المحادثات تلقائياً بالنموذج', subtitle: 'طلب إضافي صغير بعد أول رد (يستهلك توكنز)', value: s.autoTitle, onChanged: (v) => notifier.set('autoTitle', v)),
        ]),

      ],
      'voice': <Widget>[
        _Group(title: 'الصوت', children: <Widget>[
          _Block(
            title: 'سرعة القراءة الصوتية',
            value: s.ttsRate.toStringAsFixed(2),
            child: Slider(value: s.ttsRate.clamp(0.2, 1.0).toDouble(), min: 0.2, max: 1.0, divisions: 16, onChanged: (v) => notifier.set('ttsRate', double.parse(v.toStringAsFixed(2)))),
          ),
          _NavRow(
            icon: Icons.mic_none,
            title: 'لغة التعرف على الصوت',
            subtitle: s.sttLocale.isEmpty ? 'تلقائي' : s.sttLocale,
            onTap: () => _sttLocale(context, ref, s.sttLocale),
          ),
        ]),

      ],
      'data': <Widget>[
        _Group(title: 'البيانات', children: <Widget>[
          _NavRow(icon: Icons.backup_outlined, title: 'نسخة احتياطية', subtitle: 'تصدير الإعدادات والمزوّدين والمحادثات', onTap: () => showBackupSheet(context)),
          _NavRow(icon: Icons.description_outlined, title: 'تصدير المحادثات (Markdown)', subtitle: 'ملف واحد في مجلد Download', onTap: () => exportAllChats(markdown: true)),
          _NavRow(icon: Icons.data_object, title: 'تصدير المحادثات (JSON)', subtitle: 'ملف واحد في مجلد Download', onTap: () => exportAllChats(markdown: false)),
          _NavRow(icon: Icons.restore, title: 'استعادة من ملف', onTap: () => importBackup(context)),
          _NavRow(icon: Icons.folder_open, title: 'صلاحيات الملفات', subtitle: 'فتح إعدادات التطبيق في النظام', onTap: () => openAppSettings()),
          _NavRow(
            icon: Icons.folder_zip_outlined,
            title: 'مجلد البيانات',
            subtitle: 'اضغط لنسخ المسار',
            onTap: () async {
              final d = await LocalStorage.getDir();
              await Clipboard.setData(ClipboardData(text: d.path));
              toast('تم نسخ: ${d.path}');
            },
          ),
          _NavRow(
            icon: Icons.delete_sweep_outlined,
            title: 'حذف كل المحادثات',
            subtitle: '${convs.length} محادثة',
            danger: true,
            onTap: () async {
              if (convs.isEmpty) {
                toast('لا توجد محادثات');
                return;
              }
              final ok = await confirmDialog(context, 'حذف كل المحادثات', 'سيتم حذف ${convs.length} محادثة نهائياً. لا يمكن التراجع.', ok: 'حذف الكل');
              if (!ok) return;
              for (final c in <ConvMeta>[...convs]) {
                await hub.delete(c.id);
              }
              toast('تم الحذف');
            },
          ),
        ]),

      ],
      'about': <Widget>[
        _Group(title: 'حول', children: <Widget>[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(Icons.auto_awesome, color: p.accent),
            title: Text('$kAppName  v$kAppVersion', style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w600)),
            subtitle: Text('عميل API عام: Anthropic · OpenAI-compatible · Gemini. مفاتيحك تُحفظ على جهازك فقط، نصاً غير مشفّر داخل تخزين التطبيق.', style: TextStyle(color: p.muted, fontSize: 12, height: 1.5)),
          ),
        ]),
      ],
    };
    const titles = <String, String>{
      'providers': 'مزوّدو الـ API',
      'appearance': 'المظهر',
      'generation': 'التوليد',
      'behaviour': 'السلوك',
      'voice': 'الصوت',
      'data': 'البيانات',
      'about': 'حول',
    };
    final sec = section;
    if (sec == null) {
      final sel = ps.selected;
      final selName = sel == null ? '' : sel.name;
      final rows = <Widget>[
        NavRow(icon: Icons.key_outlined, title: titles['providers']!, subtitle: ps.list.isEmpty ? 'لم تُضف مزوّداً بعد' : '${ps.list.length} مزوّد${selName.isEmpty ? '' : ' · $selName'}', onTap: () => _open(context, 'providers')),
        NavRow(icon: Icons.palette_outlined, title: titles['appearance']!, subtitle: 'السمة، الاتجاه، الخط', onTap: () => _open(context, 'appearance')),
        NavRow(icon: Icons.tune, title: titles['generation']!, subtitle: 'التفكير، الحرارة، حدود السياق', onTap: () => _open(context, 'generation')),
        NavRow(icon: Icons.toggle_on_outlined, title: titles['behaviour']!, subtitle: 'الأدوات، الموافقات، التلخيص', onTap: () => _open(context, 'behaviour')),
        NavRow(icon: Icons.mic_none, title: titles['voice']!, subtitle: 'سرعة القراءة، لغة الإملاء', onTap: () => _open(context, 'voice')),
        NavRow(icon: Icons.storage_outlined, title: titles['data']!, subtitle: 'نسخ احتياطي، الصلاحيات، الحذف', onTap: () => _open(context, 'data')),
        NavRow(icon: Icons.info_outline, title: titles['about']!, subtitle: '$kAppName v$kAppVersion', onTap: () => _open(context, 'about')),
      ];
      final kids = <Widget>[];
      for (int i = 0; i < rows.length; i++) {
        if (i > 0) kids.add(Divider(height: 1, color: p.border));
        kids.add(rows[i]);
      }
      return Scaffold(
        appBar: AppBar(title: const Text('الإعدادات')),
        body: ListView(padding: const EdgeInsets.fromLTRB(14, 8, 14, 40), children: <Widget>[
          Container(
            decoration: cardDeco(p),
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids),
          ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(titles[sec] ?? 'الإعدادات')),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: all[sec] ?? <Widget>[]),
    );
  }

  void _open(BuildContext context, String key) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(section: key)));
  }
}

// =====================================================================
//  Profile editor
// =====================================================================
Future<void> openProfileEditor(BuildContext context, ApiProfile? profile) {
  return showSheet<void>(context, (c) => FractionallySizedBox(heightFactor: 0.95, child: ProfileEditor(profile: profile)));
}

class ProfileEditor extends ConsumerStatefulWidget {
  final ApiProfile? profile;
  const ProfileEditor({super.key, this.profile});
  @override
  ConsumerState<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<ProfileEditor> {
  late final String _id;
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _headers;
  late final TextEditingController _model;
  late String _kind;
  late bool _streamUsage;
  late List<String> _models;
  bool _showKey = false;
  bool _fetching = false;
  bool _testing = false;
  String _msg = '';
  bool _msgOk = false;

  @override
  void initState() {
    super.initState();
    final x = widget.profile;
    _id = x?.id ?? newId();
    _name = TextEditingController(text: x?.name ?? '');
    _url = TextEditingController(text: x?.baseUrl ?? '');
    _key = TextEditingController(text: x?.apiKey ?? '');
    _headers = TextEditingController(text: x?.headers ?? '');
    _model = TextEditingController(text: x?.selectedModel ?? '');
    _kind = x?.kind ?? kOpenAI;
    _streamUsage = x?.streamUsage ?? true;
    _models = <String>[...(x?.models ?? const <String>[])];
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _key.dispose();
    _headers.dispose();
    _model.dispose();
    super.dispose();
  }

  ApiProfile _draft() {
    return ApiProfile(
      id: _id,
      name: _name.text.trim(),
      kind: _kind,
      baseUrl: _url.text.trim(),
      apiKey: _key.text.trim(),
      selectedModel: _model.text.trim(),
      models: _models,
      headers: _headers.text.trim(),
      streamUsage: _streamUsage,
    );
  }

  String _endpoint() {
    final u = _url.text.trim();
    if (u.isEmpty) return '';
    try {
      if (_kind == kAnthropic) return '${anthropicRoot(u)}/messages';
      if (_kind == kGemini) return '${geminiRoot(u)}/models/<model>:streamGenerateContent';
      return '${openAiRoot(u)}/chat/completions';
    } catch (_) {
      return '';
    }
  }

  void _applyPreset(List<String> pr) {
    setState(() {
      if (_name.text.trim().isEmpty || kPresets.any((x) => x[0] == _name.text.trim())) _name.text = pr[0];
      _kind = pr[1];
      _url.text = pr[2];
      _models = <String>[];
      _msg = '';
    });
  }

  Future<void> _fetch() async {
    final d = _draft();
    if (d.baseUrl.isEmpty) {
      toast('أدخل الرابط أولاً');
      return;
    }
    setState(() {
      _fetching = true;
      _msg = '';
    });
    try {
      final l = await listModels(d);
      if (!mounted) return;
      setState(() {
        _models = l;
        if (_model.text.trim().isEmpty && l.isNotEmpty) _model.text = l.first;
        _msgOk = true;
        _msg = 'تم جلب ${l.length} موديل';
      });
    } catch (e) {
      final ae = await toApiException(e);
      if (!mounted) return;
      setState(() {
        _msgOk = false;
        _msg = 'فشل جلب الموديلات: ${ae.message}\nيمكنك إدخال اسم الموديل يدوياً.';
      });
    }
    if (mounted) setState(() => _fetching = false);
  }

  Future<void> _pickModel() async {
    if (_models.isEmpty) {
      toast('اضغط "جلب الموديلات" أولاً، أو اكتب الاسم يدوياً');
      return;
    }
    final r = await showSheet<String>(context, (c) => _ModelListSheet(models: _models, current: _model.text.trim()));
    if (r != null && mounted) setState(() => _model.text = r);
  }

  Future<void> _test() async {
    final d = _draft();
    if (d.baseUrl.isEmpty) {
      toast('أدخل الرابط أولاً');
      return;
    }
    if (d.selectedModel.isEmpty) {
      setState(() {
        _msgOk = false;
        _msg = 'اختر أو اكتب اسم موديل أولاً';
      });
      return;
    }
    setState(() {
      _testing = true;
      _msg = '';
    });
    final sw = Stopwatch()..start();
    final cancel = CancelToken();
    final timer = Timer(const Duration(seconds: 45), () => cancel.cancel('timeout'));
    String out = '';
    String? err;
    try {
      final req = GenRequest(
        profile: d,
        model: d.selectedModel,
        system: 'Reply with the single word OK.',
        msgs: <RMsg>[
          RMsg.user(<RPart>[RPart.text('ping')])
        ],
        tools: <ToolDef>[],
        maxTokens: 32,
        cache: false,
      );
      int attempt = 0;
      while (true) {
        try {
          out = '';
          await for (final ev in executeCall(prepareCall(req), req, cancel)) {
            out += ev.text;
          }
          break;
        } catch (e) {
          if (isCancel(e)) rethrow;
          final ae = await toApiException(e);
          if (req.tryHeal(ae)) continue;
          if (ae.retriable && attempt < 1) {
            attempt++;
            await Future<void>.delayed(const Duration(seconds: 2));
            continue;
          }
          throw ae;
        }
      }
    } catch (e) {
      if (isCancel(e)) {
        err = 'انتهت المهلة (45 ثانية) دون رد';
      } else {
        err = (await toApiException(e)).message;
      }
    }
    timer.cancel();
    sw.stop();
    if (!mounted) return;
    setState(() {
      _testing = false;
      if (err != null) {
        _msgOk = false;
        _msg = err;
      } else {
        _msgOk = true;
        _msg = out.trim().isEmpty ? 'الاتصال ناجح لكن الرد فارغ (${sw.elapsedMilliseconds}ms)' : 'يعمل ✓  الرد: ${clip(out.trim(), 60)}  (${sw.elapsedMilliseconds}ms)';
      }
    });
  }

  Future<void> _save() async {
    final d = _draft();
    if (d.name.isEmpty || d.baseUrl.isEmpty) {
      toast('الاسم والرابط مطلوبان');
      return;
    }
    if (d.baseUrl.contains(' ')) {
      toast('الرابط يحتوي مسافات');
      return;
    }
    await ref.read(profilesProvider.notifier).upsert(d, select: widget.profile == null);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, 'حذف المزوّد', 'حذف "${_name.text.trim()}"؟');
    if (!ok) return;
    await ref.read(profilesProvider.notifier).remove(_id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final ep = _endpoint();
    final http = _url.text.trim().toLowerCase().startsWith('http://');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
          child: Row(children: [
            Expanded(child: Text(widget.profile == null ? 'مزوّد جديد' : 'تعديل المزوّد', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600))),
            FilledButton(onPressed: _save, child: const Text('حفظ')),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
            Text('قوالب جاهزة', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kPresets
                  .map((pr) => ActionChip(
                        label: Text(pr[0]),
                        backgroundColor: p.surfaceHi,
                        side: BorderSide.none,
                        labelStyle: TextStyle(color: p.text, fontSize: 12.5),
                        onPressed: () => _applyPreset(pr),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            TextField(controller: _name, decoration: fieldDeco(context, label: 'اسم المزوّد')),
            const SizedBox(height: 12),
            Text('نوع الـ API', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SegPicker<String>(
              values: const <String>[kOpenAI, kAnthropic, kGemini],
              labels: const <String>['OpenAI', 'Anthropic', 'Gemini'],
              value: _kind,
              onChanged: (v) => setState(() => _kind = v),
            ),
            const SizedBox(height: 4),
            Text(
              _kind == kOpenAI ? 'لكل خادم يتبع صيغة /chat/completions (OpenAI، OpenRouter، DeepSeek، Groq، Ollama، LM Studio، وكلاء…).' : (_kind == kAnthropic ? 'صيغة /v1/messages الرسمية مع x-api-key.' : 'صيغة generateContent الرسمية مع x-goog-api-key.'),
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(controller: _url, minLines: 1, maxLines: 3, keyboardType: TextInputType.url, autocorrect: false, onChanged: (_) => setState(() {}), decoration: fieldDeco(context, label: 'Base URL', hint: 'https://api.example.com')),
            ),
            if (ep.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Directionality(textDirection: TextDirection.ltr, child: Text('→ $ep', style: TextStyle(color: p.muted, fontSize: 11.5, fontFamily: 'monospace'))),
              ),
            if (http)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('رابط http:// (غير مشفّر): يعمل على أندرويد فقط إذا فعّلت usesCleartextTraffic في AndroidManifest. للخوادم المحلية (Ollama/LM Studio) استخدم عنوان IP الحاسوب لا localhost.', style: TextStyle(color: p.danger, fontSize: 12, height: 1.4)),
              ),
            const SizedBox(height: 12),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _key,
                obscureText: !_showKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: fieldDeco(
                  context,
                  label: 'API Key',
                  suffix: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility, size: 20, color: p.muted), onPressed: () => setState(() => _showKey = !_showKey)),
                    IconButton(
                      icon: Icon(Icons.content_paste, size: 20, color: p.muted),
                      onPressed: () async {
                        final d = await Clipboard.getData(Clipboard.kTextPlain);
                        final t = d?.text;
                        if (t != null && t.trim().isNotEmpty) setState(() => _key.text = t.trim());
                      },
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(controller: _model, autocorrect: false, onChanged: (_) => setState(() {}), decoration: fieldDeco(context, label: 'الموديل (Model ID)', hint: 'claude-sonnet-4-5 / gpt-4o / gemini-2.5-pro', suffix: IconButton(icon: Icon(Icons.list, color: p.muted), tooltip: 'اختيار من القائمة', onPressed: _pickModel))),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _fetching ? null : _fetch,
                  icon: _fetching ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)) : const Icon(Icons.cloud_download_outlined, size: 18),
                  label: Text(_models.isEmpty ? 'جلب الموديلات' : 'تحديث (${_models.length})'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)) : const Icon(Icons.bolt, size: 18),
                  label: const Text('اختبار الاتصال'),
                ),
              ),
            ]),
            if (_msg.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: (_msgOk ? p.success : p.danger).withAlpha(24), borderRadius: BorderRadius.circular(12), border: Border.all(color: (_msgOk ? p.success : p.danger).withAlpha(90))),
                child: SelectableText(_msg, style: TextStyle(color: p.text, fontSize: 13, height: 1.5)),
              ),
            const SizedBox(height: 16),
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(controller: _headers, minLines: 2, maxLines: 5, autocorrect: false, decoration: fieldDeco(context, label: 'Headers إضافية (اختياري)', hint: 'X-Title: LMClient\nHTTP-Referer: https://…')),
            ),
            if (_kind == kOpenAI)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _streamUsage,
                onChanged: (v) => setState(() => _streamUsage = v),
                title: Text('طلب عدّاد التوكنز مع البث', style: TextStyle(color: p.text, fontSize: 14)),
                subtitle: Text('stream_options.include_usage — أوقفه إن رفض الخادم هذا الحقل', style: TextStyle(color: p.muted, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Text('المفتاح يُحفظ على جهازك فقط (غير مشفّر داخل تخزين التطبيق) ولا يُرسل إلا إلى الرابط أعلاه.', style: TextStyle(color: p.muted, fontSize: 12, height: 1.5)),
            if (widget.profile != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: p.danger),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('حذف هذا المزوّد'),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _ModelListSheet extends StatefulWidget {
  final List<String> models;
  final String current;
  const _ModelListSheet({required this.models, required this.current});
  @override
  State<_ModelListSheet> createState() => _ModelListSheetState();
}

class _ModelListSheetState extends State<_ModelListSheet> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final q = _q.trim().toLowerCase();
    final list = widget.models.where((m) => q.isEmpty || m.toLowerCase().contains(q)).toList();
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: TextField(onChanged: (v) => setState(() => _q = v), decoration: fieldDeco(context, hint: 'بحث…', prefix: Icon(Icons.search, size: 20, color: p.muted))),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (c, i) => ListTile(
                dense: true,
                title: Directionality(textDirection: TextDirection.ltr, child: Text(list[i], style: TextStyle(color: p.text, fontSize: 14, fontWeight: list[i] == widget.current ? FontWeight.w600 : FontWeight.w400))),
                trailing: list[i] == widget.current ? Icon(Icons.check, color: p.accent, size: 20) : null,
                onTap: () => Navigator.pop(context, list[i]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
