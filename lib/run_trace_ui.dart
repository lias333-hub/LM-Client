part of 'main.dart';

// =====================================================================
//  واجهة سجل التشغيل: ورقة التصدير (من قائمة المحادثة ⋮ ومن الأمر /trace) وورقة اختيار المستوى الافتراضي (الإعدادات).
// =====================================================================

/// ورقة التصدير: تعرض حجم السجل وتتيح اختيار المستوى لهذا التصدير (المسبق من الإعدادات)، ثم نسخ أو حفظ كملف.
Future<void> showTraceExportSheet(BuildContext context, String convId, String title) async {
  final TraceInfo info = await RunTrace.info(convId);
  if (info.records == 0) {
    toast('لا يوجد سجل تشغيل لهذه المحادثة بعد. شغّل مهمة أولاً ثم صدّره.');
    return;
  }
  if (!context.mounted) return;
  String level = appContainer.read(settingsProvider).traceLevel;
  await showSheet<void>(context, (BuildContext c) {
    return StatefulBuilder(builder: (BuildContext c2, StateSetter setS) {
      final Pal p = pal(c2);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text('سجل التشغيل · ${info.runs} تشغيل · ${fmtBytes(info.bytes)}', style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegPicker<String>(
                values: const <String>[kTraceNumbers, kTraceStandard, kTraceFull],
                labels: const <String>['أرقام فقط', 'قياسي', 'كامل'],
                value: level,
                onChanged: (String v) => setS(() => level = v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text('${traceLevelHelp(level)}\nالأسرار (المفاتيح والرموز) تُحجب دائماً في كل المستويات.', style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.5)),
            ),
            SheetAction(
              icon: Icons.copy,
              title: 'نسخ',
              subtitle: 'للسجلات الصغيرة؛ الكبيرة تُحفظ كملف',
              onTap: () async {
                final String txt = await RunTrace.build(convId, title, level);
                if (txt.length > 300000) {
                  toast('الحجم كبير للنسخ (${fmtBytes(txt.length)}). احفظه كملف بدلاً من ذلك.');
                  return;
                }
                await Clipboard.setData(ClipboardData(text: txt));
                if (c2.mounted) Navigator.pop(c2);
                toast('تم نسخ سجل التشغيل (${fmtBytes(txt.length)})');
              },
            ),
            SheetAction(
              icon: Icons.save_alt,
              title: 'حفظ كملف في مجلد Download',
              subtitle: 'ملف نصي واحد جاهز للإرسال',
              onTap: () async {
                if (c2.mounted) Navigator.pop(c2);
                try {
                  final String txt = await RunTrace.build(convId, title, level);
                  final String nm = safeFileName(title.trim().isEmpty ? 'chat' : clip(title.trim(), 24));
                  final String path = await exportTextFile('lmclient_trace_${fmtDate(DateTime.now())}_$nm.txt', txt);
                  toast(savedMessage(path));
                } catch (e) {
                  toast('تعذّر الحفظ: $e');
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

/// ورقة اختيار المستوى الافتراضي لتصدير السجل (الإعدادات ← البيانات).
Future<void> showTraceLevelSheet(BuildContext context) {
  return showSheet<void>(context, (BuildContext c) {
    return Consumer(builder: (BuildContext c2, WidgetRef ref, Widget? child) {
      final Pal p = pal(c2);
      final String cur = ref.watch(settingsProvider).traceLevel;
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const SheetHandle(),
            for (final String l in const <String>[kTraceStandard, kTraceNumbers, kTraceFull])
              SheetAction(
                icon: l == cur ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                title: traceLevelLabel(l) + (l == kTraceStandard ? ' (الافتراضي)' : ''),
                subtitle: traceLevelHelp(l),
                onTap: () {
                  ref.read(settingsProvider.notifier).set('traceLevel', l);
                  Navigator.pop(c2);
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: Text('يمكنك تغيير المستوى عند كل تصدير من الورقة نفسها. الأسرار تُحجب دائماً.', style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.5)),
            ),
          ]),
        ),
      );
    });
  });
}
