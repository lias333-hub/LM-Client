// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, unused_local_variable, avoid_print, deprecated_member_use, use_build_context_synchronously, prefer_const_constructors, prefer_const_literals_to_create_immutables, depend_on_referenced_packages, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, unnecessary_import
part of 'main.dart';

// =====================================================================
//  Shared helpers for secondary screens
// =====================================================================
class EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyHint({super.key, required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: p.muted.withAlpha(150)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 14, height: 1.6)),
        ]),
      ),
    );
  }
}

BoxDecoration cardDeco(Pal p, {bool selected = false}) => BoxDecoration(
      color: selected ? p.accent.withAlpha(20) : p.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: selected ? p.accent : p.border),
    );

/// يختار ملفات من الجهاز ويعيدها كمرفقات جاهزة (بايتات في الذاكرة).
Future<List<PendingAtt>> pickAttachments({bool images = false}) async {
  final out = <PendingAtt>[];
  try {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: images ? FileType.image : FileType.any);
    if (res == null) return out;
    for (final f in res.files) {
      Uint8List? b = f.bytes;
      if (b == null && f.path != null) {
        try {
          b = await File(f.path!).readAsBytes();
        } catch (_) {}
      }
      if (b == null) continue;
      if (b.length > 30 * 1024 * 1024) {
        toast('الملف ${f.name} أكبر من 30MB وتم تجاهله');
        continue;
      }
      out.add(PendingAtt(id: newId(), name: f.name, mime: mimeFromName(f.name), size: b.length, bytes: b));
    }
  } catch (e) {
    toast('تعذر اختيار الملف: $e');
  }
  return out;
}

void showExportSheet(BuildContext context, String title, String md) {
  showSheet<void>(context, (c) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SheetHandle(),
        SheetAction(
          icon: Icons.copy_rounded,
          title: 'نسخ كنص Markdown',
          onTap: () async {
            Navigator.pop(c);
            await Clipboard.setData(ClipboardData(text: md));
            toast('تم النسخ');
          },
        ),
        SheetAction(
          icon: Icons.save_alt,
          title: 'حفظ كملف .md',
          subtitle: 'في مجلد Download إن أمكن',
          onTap: () async {
            Navigator.pop(c);
            final path = await exportTextFile('${safeFileName(title.isEmpty ? 'chat' : title)}.md', md);
            toast('تم الحفظ: $path');
          },
        ),
        const SizedBox(height: 8),
      ]),
    );
  });
}

/// بحث نصي في محتوى كل المحادثات المحفوظة. يعيد {id: مقتطف}.
Future<Map<String, String>> searchChats(String q) async {
  final out = <String, String>{};
  final needle = q.trim().toLowerCase();
  if (needle.isEmpty) return out;
  final convs = appContainer.read(convListProvider);
  int n = 0;
  for (final c in convs) {
    n++;
    if (n % 8 == 0) await Future<void>.delayed(Duration.zero);
    final raw = await LocalStorage.load('chats', c.id);
    if (raw == null) continue;
    try {
      for (final e in asList(jsonDecode(raw))) {
        final t = asStr(asMap(e)['content']);
        final low = t.toLowerCase();
        final i = low.indexOf(needle);
        if (i < 0) continue;
        final st = clampInt(i - 40, 0, t.length);
        final en = clampInt(i + needle.length + 70, 0, t.length);
        out[c.id] = '…${t.substring(st, en).replaceAll('\n', ' ')}…';
        break;
      }
    } catch (_) {}
  }
  return out;
}

// =====================================================================
//  Drawer (history grouped by date, search, navigation)
// =====================================================================
class _DrawerRow {
  final String? header;
  final ConvMeta? conv;
  _DrawerRow.h(String t)
      : header = t,
        conv = null;
  _DrawerRow.c(ConvMeta m)
      : header = null,
        conv = m;
}

String dateGroup(DateTime t, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(t.year, t.month, t.day);
  final diff = today.difference(d).inDays;
  if (diff <= 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  if (diff < 7) return 'آخر 7 أيام';
  if (diff < 30) return 'آخر 30 يوماً';
  return 'أقدم';
}

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});
  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  final TextEditingController _q = TextEditingController();
  Map<String, String>? _hits;
  bool _scanning = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _go(Widget w) {
    Navigator.pop(context);
    pushScreen(w);
  }

  Future<void> _scan() async {
    final q = _q.text.trim();
    if (q.length < 2) return;
    setState(() => _scanning = true);
    final r = await searchChats(q);
    if (!mounted) return;
    setState(() {
      _hits = r;
      _scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final convs = <ConvMeta>[...ref.watch(convListProvider)];
    final projects = ref.watch(projectsProvider);
    final ps = ref.watch(profilesProvider);
    final curId = hub.current.value.meta.id;
    final q = _q.text.trim().toLowerCase();
    convs.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    final rows = <_DrawerRow>[];
    final filtered = <ConvMeta>[];
    for (final c in convs) {
      if (q.isEmpty) {
        filtered.add(c);
      } else if (c.title.toLowerCase().contains(q) || (_hits != null && _hits!.containsKey(c.id))) {
        filtered.add(c);
      }
    }
    final now = DateTime.now();
    String lastGroup = '';
    for (final c in filtered) {
      final g = c.pinned ? 'مثبّتة' : dateGroup(c.updatedAt, now);
      if (g != lastGroup) {
        rows.add(_DrawerRow.h(g));
        lastGroup = g;
      }
      rows.add(_DrawerRow.c(c));
    }
    final pr = ps.selected;
    return Drawer(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 4),
            child: Row(children: [
              Icon(Icons.auto_awesome, color: p.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(kAppName, style: TextStyle(color: p.text, fontSize: 22, fontFamily: 'serif', fontFamilyFallback: const <String>['Noto Serif', 'Georgia']))),
              IconButton(
                tooltip: 'محادثة جديدة',
                icon: Icon(Icons.edit_square, color: p.text, size: 22),
                onPressed: () {
                  Navigator.pop(context);
                  hub.newChat();
                },
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() => _hits = null),
              onSubmitted: (_) => _scan(),
              decoration: fieldDeco(
                context,
                hint: 'ابحث في المحادثات…',
                prefix: Icon(Icons.search, size: 20, color: p.muted),
                suffix: _q.text.isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(Icons.close, size: 18, color: p.muted),
                        onPressed: () => setState(() {
                          _q.clear();
                          _hits = null;
                        }),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: <Widget>[
                _navChip(p, Icons.folder_outlined, 'المشاريع', () => _go(const ProjectsScreen())),
                _navChip(p, Icons.library_books_outlined, 'المكتبة', () => _go(const LibraryScreen())),
                _navChip(p, Icons.bookmark_border, 'الذاكرة', () => _go(const MemoryScreen())),
                _navChip(p, Icons.smart_toy_outlined, 'Agents', () => _go(const AgentsScreen())),
                _navChip(p, Icons.phone_android, 'ملفات الهاتف', () => _go(const PhoneFilesScreen())),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (q.length >= 2 && _hits == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: TextButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: _scanning ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent)) : const Icon(Icons.manage_search, size: 18),
                label: const Text('ابحث أيضاً داخل نصوص المحادثات'),
              ),
            ),
          Expanded(
            child: rows.isEmpty
                ? EmptyHint(icon: Icons.chat_bubble_outline, text: q.isEmpty ? 'لا توجد محادثات بعد' : 'لا نتائج')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: rows.length,
                    itemBuilder: (c, i) {
                      final r = rows[i];
                      final h = r.header;
                      if (h != null) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                          child: Text(h, style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                        );
                      }
                      final m = r.conv!;
                      String? proj;
                      for (final x in projects) {
                        if (x.id == m.projectId) proj = x.name;
                      }
                      final snippet = _hits == null ? null : _hits![m.id];
                      return Material(
                        color: m.id == curId ? p.surfaceHi : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            Navigator.pop(context);
                            hub.open(m.id);
                          },
                          onLongPress: () => showConvActions(context, ref, m),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(m.title.isEmpty ? 'محادثة' : m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 14.5)),
                                  if (snippet != null) Text(snippet, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12, height: 1.35)),
                                  if (proj != null && snippet == null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.folder_outlined, size: 12, color: p.muted),
                                        const SizedBox(width: 4),
                                        Flexible(child: Text(proj, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 11.5))),
                                      ]),
                                    ),
                                ]),
                              ),
                              if (m.pinned) Icon(Icons.push_pin, size: 14, color: p.muted),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(),
          InkWell(
            onTap: () => _go(const SettingsScreen()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: p.accent,
                  child: Text(pr == null || pr.name.isEmpty ? '؟' : String.fromCharCode(pr.name.runes.first).toUpperCase(), style: TextStyle(color: p.onAccent, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(pr == null ? 'لا يوجد مزوّد' : pr.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w600)),
                    Text(pr == null ? 'اضغط لإضافة مزوّد' : (pr.selectedModel.isEmpty ? pr.kindLabel : pr.selectedModel), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
                ),
                Icon(Icons.settings_outlined, color: p.muted, size: 22),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _navChip(Pal p, IconData i, String t, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: p.border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 17, color: p.accent),
            const SizedBox(width: 6),
            Text(t, style: TextStyle(color: p.text, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

Future<void> showConvActions(BuildContext context, WidgetRef ref, ConvMeta m) {
  return showSheet<void>(context, (c) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(m.title.isEmpty ? 'محادثة' : m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal(c).muted, fontSize: 13)),
          ),
        ),
        SheetAction(
          icon: Icons.drive_file_rename_outline,
          title: 'إعادة تسمية',
          onTap: () async {
            Navigator.pop(c);
            final t = await askText(context, 'اسم المحادثة', initial: m.title);
            if (t == null || t.trim().isEmpty) return;
            m.title = t.trim();
            await hub.updateMeta(m);
          },
        ),
        SheetAction(
          icon: m.pinned ? Icons.push_pin_outlined : Icons.push_pin,
          title: m.pinned ? 'إلغاء التثبيت' : 'تثبيت',
          onTap: () async {
            Navigator.pop(c);
            m.pinned = !m.pinned;
            await hub.updateMeta(m);
          },
        ),
        SheetAction(
          icon: Icons.folder_open,
          title: 'نقل إلى مشروع',
          onTap: () {
            Navigator.pop(c);
            showMoveToProject(context, ref, m);
          },
        ),
        SheetAction(
          icon: Icons.ios_share,
          title: 'تصدير',
          onTap: () async {
            Navigator.pop(c);
            final raw = await LocalStorage.load('chats', m.id);
            if (raw == null) {
              toast('تعذر قراءة المحادثة');
              return;
            }
            final msgs = <ChatMessage>[];
            try {
              for (final e in asList(jsonDecode(raw))) {
                msgs.add(ChatMessage.fromJson(asMap(e)));
              }
            } catch (_) {}
            if (!context.mounted) return;
            showExportSheet(context, m.title.isEmpty ? 'chat' : m.title, conversationToMarkdown(m, msgs));
          },
        ),
        SheetAction(
          icon: Icons.delete_outline,
          title: 'حذف',
          danger: true,
          onTap: () async {
            Navigator.pop(c);
            final ok = await confirmDialog(context, 'حذف المحادثة', 'سيتم حذف "${m.title}" نهائياً.');
            if (ok) await hub.delete(m.id);
          },
        ),
        const SizedBox(height: 8),
      ]),
    );
  });
}

Future<void> showMoveToProject(BuildContext context, WidgetRef ref, ConvMeta m) {
  return showSheet<void>(context, (c) {
    final projects = ref.read(projectsProvider);
    final p = pal(c);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetHandle(),
          SheetAction(
            icon: m.projectId == null ? Icons.check_circle : Icons.circle_outlined,
            title: 'بدون مشروع',
            onTap: () async {
              Navigator.pop(c);
              m.projectId = null;
              await hub.updateMeta(m);
            },
          ),
          ...projects.map((x) => SheetAction(
                icon: m.projectId == x.id ? Icons.check_circle : Icons.circle_outlined,
                title: x.name,
                onTap: () async {
                  Navigator.pop(c);
                  m.projectId = x.id;
                  await hub.updateMeta(m);
                },
              )),
          if (projects.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text('لا توجد مشاريع بعد. أنشئ مشروعاً من قسم المشاريع.', style: TextStyle(color: p.muted, fontSize: 13))),
          const SizedBox(height: 8),
        ]),
      ),
    );
  });
}

// =====================================================================
//  Projects
// =====================================================================
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final ins = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        final p = pal(c);
        return AlertDialog(
          backgroundColor: p.surface,
          surfaceTintColor: Colors.transparent,
          title: Text('مشروع جديد', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, decoration: fieldDeco(c, label: 'اسم المشروع')),
              const SizedBox(height: 10),
              TextField(controller: ins, minLines: 3, maxLines: 8, decoration: fieldDeco(c, label: 'تعليمات المشروع', hint: 'تُرسل للنموذج في كل محادثة داخل المشروع')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('إلغاء', style: TextStyle(color: p.muted))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إنشاء')),
          ],
        );
      },
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final pr = Project(id: newId(), name: name.text.trim(), instructions: ins.text.trim());
    await ref.read(projectsProvider.notifier).upsert(pr);
    pushScreen(ProjectDetailScreen(projectId: pr.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final projects = ref.watch(projectsProvider);
    final convs = ref.watch(convListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('المشاريع')),
      body: projects.isEmpty
          ? const EmptyHint(icon: Icons.folder_outlined, text: 'المشروع = تعليمات + ملفات معرفة + محادثات مجمّعة.\nاضغط + لإنشاء أول مشروع.')
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: projects.length,
              itemBuilder: (c, i) {
                final x = projects[i];
                final n = convs.where((e) => e.projectId == x.id).length;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => pushScreen(ProjectDetailScreen(projectId: x.id)),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: cardDeco(p),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.folder_special_outlined, color: p.accent, size: 22),
                          const SizedBox(width: 10),
                          Expanded(child: Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600))),
                        ]),
                        if (x.instructions.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(x.instructions.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45)),
                          ),
                        const SizedBox(height: 8),
                        Text('${x.knowledge.length} ملف معرفة · $n محادثة', style: TextStyle(color: p.muted, fontSize: 12.5)),
                      ]),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        onPressed: () => _create(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class ProjectDetailScreen extends ConsumerStatefulWidget {
  final String projectId;
  const ProjectDetailScreen({super.key, required this.projectId});
  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  late final TextEditingController _name;
  late final TextEditingController _ins;
  Timer? _debounce;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final pr = ref.read(projectsProvider.notifier).byId(widget.projectId);
    _name = TextEditingController(text: pr?.name ?? '');
    _ins = TextEditingController(text: pr?.instructions ?? '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_dirty) {
      final nm = _name.text;
      final ins = _ins.text;
      // نؤجّل الكتابة: تعديل الـ provider أثناء تفكيك الشجرة يرمي خطأ في وضع debug.
      Future<void>.microtask(() => _write(nm, ins));
    }
    _name.dispose();
    _ins.dispose();
    super.dispose();
  }

  void _write(String name, String instructions) {
    final n = appContainer.read(projectsProvider.notifier);
    final cur = n.byId(widget.projectId);
    if (cur == null) return;
    n.upsert(cur.copyWith(name: name.trim().isEmpty ? cur.name : name.trim(), instructions: instructions));
  }

  void _flush() {
    _write(_name.text, _ins.text);
    _dirty = false;
  }

  void _changed() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _flush);
  }

  Future<void> _setKnowledge(Project pr, List<String> ids) async {
    await ref.read(projectsProvider.notifier).upsert(pr.copyWith(knowledge: ids));
  }

  Future<void> _addFromLibrary(Project pr) async {
    final lib = ref.read(libraryProvider).where((e) => e.path != null && !e.isImage && !pr.knowledge.contains(e.id)).toList();
    if (lib.isEmpty) {
      toast('لا توجد ملفات نصية أخرى في المكتبة');
      return;
    }
    final chosen = <String>{};
    await showSheet<void>(context, (c) {
      final p = pal(c);
      return StatefulBuilder(builder: (c, setSt) {
        return FractionallySizedBox(
          heightFactor: 0.7,
          child: Column(children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: Row(children: [
                Expanded(child: Text('اختر ملفات المعرفة', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600))),
                FilledButton(
                  onPressed: chosen.isEmpty
                      ? null
                      : () {
                          Navigator.pop(c);
                          _setKnowledge(pr, <String>[...pr.knowledge, ...chosen]);
                        },
                  child: Text('إضافة (${chosen.length})'),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                children: lib
                    .map((it) => CheckboxListTile(
                          value: chosen.contains(it.id),
                          onChanged: (v) => setSt(() {
                            if (v == true) {
                              chosen.add(it.id);
                            } else {
                              chosen.remove(it.id);
                            }
                          }),
                          title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 14.5)),
                          subtitle: Text('${it.mime} · ${fmtBytes(it.size)}', style: TextStyle(color: p.muted, fontSize: 12)),
                          dense: true,
                        ))
                    .toList(),
              ),
            ),
          ]),
        );
      });
    });
  }

  Future<void> _upload(Project pr) async {
    final files = await pickAttachments();
    if (files.isEmpty) return;
    final ids = <String>[...pr.knowledge];
    for (final f in files) {
      final b = f.bytes;
      if (b == null) continue;
      final it = await ref.read(libraryProvider.notifier).addBytes(f.name, b, mime: f.mime);
      ids.add(it.id);
    }
    await _setKnowledge(pr, ids);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final plist = ref.watch(projectsProvider);
    Project? found;
    for (final x in plist) {
      if (x.id == widget.projectId) found = x;
    }
    final lib = ref.watch(libraryProvider);
    final convs = ref.watch(convListProvider).where((e) => e.projectId == widget.projectId).toList();
    convs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (found == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyHint(icon: Icons.folder_off_outlined, text: 'المشروع غير موجود'));
    }
    final Project pr = found;
    final docs = <LibraryItem>[];
    for (final id in pr.knowledge) {
      for (final it in lib) {
        if (it.id == id) docs.add(it);
      }
    }
    int totalBytes = 0;
    for (final d in docs) {
      totalBytes += d.size;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('المشروع'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'حذف المشروع',
            onPressed: () async {
              final ok = await confirmDialog(context, 'حذف المشروع', 'سيُحذف المشروع فقط. المحادثات والملفات تبقى (تُفصل عن المشروع).');
              if (!ok) return;
              _dirty = false;
              for (final cv in ref.read(convListProvider)) {
                if (cv.projectId == pr.id) {
                  cv.projectId = null;
                  await hub.updateMeta(cv);
                }
              }
              await ref.read(projectsProvider.notifier).remove(pr.id);
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _name, onChanged: (_) => _changed(), decoration: fieldDeco(context, label: 'اسم المشروع')),
        const SizedBox(height: 12),
        TextField(
          controller: _ins,
          onChanged: (_) => _changed(),
          minLines: 4,
          maxLines: 12,
          decoration: fieldDeco(context, label: 'تعليمات المشروع', hint: 'مثال: أنت مساعد برمجة. أجب دائماً بالعربية…'),
        ),
        const SectionLabelPad('ملفات المعرفة'),
        if (docs.isEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('لا توجد ملفات. الملفات النصية المضافة هنا تُدرج في سياق كل محادثة داخل المشروع.', style: TextStyle(color: p.muted, fontSize: 13, height: 1.5)))
        else ...[
          ...docs.map((d) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: cardDeco(p),
                child: ListTile(
                  dense: true,
                  leading: Icon(d.isPdf ? Icons.picture_as_pdf_outlined : Icons.description_outlined, color: p.muted),
                  title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 14)),
                  subtitle: Text(fmtBytes(d.size), style: TextStyle(color: p.muted, fontSize: 12)),
                  trailing: IconButton(
                    icon: Icon(Icons.close, color: p.muted, size: 20),
                    onPressed: () => _setKnowledge(pr, pr.knowledge.where((e) => e != d.id).toList()),
                  ),
                ),
              )),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('تنبيه: نصوص هذه الملفات تُرسل كاملة (حتى الحد الأقصى للأحرف في الإعدادات) مع كل رسالة، فتستهلك توكنز. الحجم الإجمالي ${fmtBytes(totalBytes)}.', style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.5)),
          ),
        ],
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => _addFromLibrary(pr), icon: const Icon(Icons.library_books_outlined, size: 18), label: const Text('من المكتبة'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: () => _upload(pr), icon: const Icon(Icons.upload_file, size: 18), label: const Text('رفع ملف'))),
        ]),
        const SectionLabelPad('المحادثات'),
        FilledButton.icon(
          onPressed: () {
            _flush();
            hub.newChat(projectId: pr.id);
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
          icon: const Icon(Icons.add_comment_outlined, size: 18),
          label: const Text('محادثة جديدة في المشروع'),
        ),
        const SizedBox(height: 10),
        ...convs.map((cv) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: cardDeco(p),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.chat_bubble_outline, color: p.muted, size: 20),
                title: Text(cv.title.isEmpty ? 'محادثة' : cv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 14)),
                subtitle: Text(fmtDate(cv.updatedAt), style: TextStyle(color: p.muted, fontSize: 12)),
                onTap: () {
                  hub.open(cv.id);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
            )),
        if (convs.isEmpty) Text('لا توجد محادثات في هذا المشروع بعد.', style: TextStyle(color: p.muted, fontSize: 13)),
      ]),
    );
  }
}

/// عنوان قسم داخل ListView بهوامش أفقية صفرية (مختلف عن SectionLabel الذي له padding 16).
class SectionLabelPad extends StatelessWidget {
  final String text;
  const SectionLabelPad(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
        child: Text(text, style: TextStyle(color: pal(context).muted, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
      );
}

// =====================================================================
//  Library
// =====================================================================
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _q = '';
  int _filter = 0; // 0 all, 1 images, 2 pdf, 3 text, 4 other

  bool _match(LibraryItem it) {
    if (_q.isNotEmpty && !it.name.toLowerCase().contains(_q)) return false;
    switch (_filter) {
      case 1:
        return it.isImage;
      case 2:
        return it.isPdf;
      case 3:
        return it.isText;
      case 4:
        return !it.isImage && !it.isPdf && !it.isText;
    }
    return true;
  }

  Future<void> _upload() async {
    final files = await pickAttachments();
    int n = 0;
    for (final f in files) {
      final b = f.bytes;
      if (b == null) continue;
      await ref.read(libraryProvider.notifier).addBytes(f.name, b, mime: f.mime);
      n++;
    }
    if (n > 0) toast('تمت إضافة $n ملف');
  }

  Future<void> _delete(LibraryItem it) async {
    final ok = await confirmDialog(context, 'حذف الملف', 'سيُحذف "${it.name}" من المكتبة نهائياً. المحادثات التي أُرفق بها ستعرض "مرفق غير متوفر".');
    if (!ok) return;
    for (final pr in ref.read(projectsProvider)) {
      if (pr.knowledge.contains(it.id)) {
        await ref.read(projectsProvider.notifier).upsert(pr.copyWith(knowledge: pr.knowledge.where((e) => e != it.id).toList()));
      }
    }
    await ref.read(libraryProvider.notifier).removeItem(it.id);
  }

  void _attach(LibraryItem it) {
    if (it.path == null) {
      toast('لا توجد نسخة محفوظة من هذا الملف');
      return;
    }
    ref.read(pendingProvider.notifier).add(PendingAtt(id: newId(), name: it.name, mime: it.mime, size: it.size, path: it.path));
    toast('أُضيف إلى رسالتك القادمة');
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  IconData _icon(LibraryItem it) {
    if (it.isImage) return Icons.image_outlined;
    if (it.isPdf) return Icons.picture_as_pdf_outlined;
    if (it.isText) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final lib = <LibraryItem>[...ref.watch(libraryProvider)];
    lib.sort((a, b) => b.time.compareTo(a.time));
    final shown = lib.where(_match).toList();
    const labels = <String>['الكل', 'صور', 'PDF', 'نصوص', 'أخرى'];
    int total = 0;
    for (final it in lib) {
      total += it.size;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('المكتبة')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            decoration: fieldDeco(context, hint: 'ابحث في أسماء الملفات…', prefix: Icon(Icons.search, size: 20, color: p.muted)),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: labels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (c, i) => ChoiceChip(
              label: Text(labels[i]),
              selected: _filter == i,
              selectedColor: p.accent,
              backgroundColor: p.surfaceHi,
              side: BorderSide.none,
              labelStyle: TextStyle(color: _filter == i ? p.onAccent : p.text, fontSize: 13),
              onSelected: (_) => setState(() => _filter = i),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Align(alignment: AlignmentDirectional.centerStart, child: Text('${lib.length} ملف · ${fmtBytes(total)}', style: TextStyle(color: p.muted, fontSize: 12))),
        ),
        Expanded(
          child: shown.isEmpty
              ? EmptyHint(icon: Icons.library_books_outlined, text: lib.isEmpty ? 'المكتبة فارغة.\nالملفات التي ترفقها في المحادثات تُحفظ هنا تلقائياً، ويمكنك أيضاً رفع ملفات بزر +.' : 'لا نتائج')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
                  itemCount: shown.length,
                  itemBuilder: (c, i) {
                    final it = shown[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: cardDeco(p),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => previewAttachment(context, name: it.name, mime: it.mime, path: it.path, size: it.size),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 4, 8),
                          child: Row(children: [
                            it.isImage
                                ? SizedBox(width: 46, height: 46, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: _LibThumb(path: it.path)))
                                : Container(
                                    width: 46,
                                    height: 46,
                                    decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(10)),
                                    child: Icon(_icon(it), color: p.muted, size: 22),
                                  ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 14.5)),
                                const SizedBox(height: 2),
                                Text('${fmtBytes(it.size)} · ${fmtDate(it.time)}', style: TextStyle(color: p.muted, fontSize: 12)),
                              ]),
                            ),
                            PopupMenuButton<String>(
                              color: p.surface,
                              surfaceTintColor: Colors.transparent,
                              icon: Icon(Icons.more_vert, color: p.muted, size: 20),
                              onSelected: (v) {
                                if (v == 'attach') _attach(it);
                                if (v == 'view') previewAttachment(context, name: it.name, mime: it.mime, path: it.path, size: it.size);
                                if (v == 'delete') _delete(it);
                              },
                              itemBuilder: (_) => <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(value: 'attach', child: Text('إرفاق بالمحادثة', style: TextStyle(color: p.text))),
                                PopupMenuItem<String>(value: 'view', child: Text('عرض', style: TextStyle(color: p.text))),
                                PopupMenuItem<String>(value: 'delete', child: Text('حذف', style: TextStyle(color: p.danger))),
                              ],
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        onPressed: _upload,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _LibThumb extends StatefulWidget {
  final String? path;
  const _LibThumb({required this.path});
  @override
  State<_LibThumb> createState() => _LibThumbState();
}

class _LibThumbState extends State<_LibThumb> {
  late final Future<Uint8List?> _fut = LocalStorage.readRel(widget.path);
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return FutureBuilder<Uint8List?>(
      future: _fut,
      builder: (c, snap) {
        final d = snap.data;
        if (d == null) return Container(color: p.surfaceHi, child: Icon(Icons.image_outlined, color: p.muted));
        return Image.memory(d, fit: BoxFit.cover, cacheWidth: 140, gaplessPlayback: true);
      },
    );
  }
}

// =====================================================================
//  Memory
// =====================================================================
class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, MemoryPart? ex) async {
    final t = TextEditingController(text: ex?.title ?? '');
    final c = TextEditingController(text: ex?.content ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) {
        final p = pal(d);
        return AlertDialog(
          backgroundColor: p.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(ex == null ? 'إضافة للذاكرة' : 'تعديل', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: t, autofocus: ex == null, decoration: fieldDeco(d, label: 'العنوان')),
              const SizedBox(height: 10),
              TextField(controller: c, minLines: 4, maxLines: 10, decoration: fieldDeco(d, label: 'المحتوى')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('إلغاء', style: TextStyle(color: p.muted))),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حفظ')),
          ],
        );
      },
    );
    if (ok != true || t.text.trim().isEmpty || c.text.trim().isEmpty) return;
    await ref.read(memoryProvider.notifier).upsert(MemoryPart(id: ex?.id ?? newId(), title: t.text.trim(), content: c.text.trim()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final mem = ref.watch(memoryProvider);
    final s = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الذاكرة'),
        actions: [
          if (mem.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'مسح الكل',
              onPressed: () async {
                final ok = await confirmDialog(context, 'مسح الذاكرة', 'سيتم حذف ${mem.length} عنصر نهائياً.', ok: 'مسح');
                if (ok) await ref.read(memoryProvider.notifier).setAll(<MemoryPart>[]);
              },
            ),
        ],
      ),
      body: Column(children: [
        SwitchListTile(
          value: s.memoryOn,
          onChanged: (v) => ref.read(settingsProvider.notifier).set('memoryOn', v),
          title: Text('إرسال الذاكرة للنموذج', style: TextStyle(color: p.text, fontSize: 14.5)),
          subtitle: Text('تُضاف المحتويات إلى تعليمات النظام. يحفظ النموذج هنا أيضاً حين تطلب منه "تذكّر".', style: TextStyle(color: p.muted, fontSize: 12)),
        ),
        const Divider(),
        Expanded(
          child: mem.isEmpty
              ? const EmptyHint(icon: Icons.bookmark_border, text: 'لا توجد عناصر في الذاكرة.\nاضغط + أو احفظ رداً من المحادثة.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 90),
                  itemCount: mem.length,
                  itemBuilder: (c, i) {
                    final m = mem[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _edit(context, ref, m),
                        child: Container(
                          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 4, 10),
                          decoration: cardDeco(p),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(m.content, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.45)),
                              ]),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: p.muted, size: 20),
                              onPressed: () async {
                                final ok = await confirmDialog(context, 'حذف', 'حذف "${m.title}"؟');
                                if (ok) await ref.read(memoryProvider.notifier).remove(m.id);
                              },
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        onPressed: () => _edit(context, ref, null),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// =====================================================================
//  Agents (scoped phone access + web) — with a real path guard
// =====================================================================
class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final agents = ref.watch(agentsProvider);
    final sel = ref.watch(selectedAgentProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Agents')),
      body: Column(children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(12)),
          child: Text(
            'الـ Agent هو "تصريح" يسمح للنموذج باستدعاء أدوات على هاتفك (قراءة/كتابة ملفات داخل مجلدات تحددها، وفتح روابط ويب). لا يوجد تنفيذ أوامر. حدّد المجلدات بدقة، وأبقِ "طلب الموافقة" مفعّلاً في الإعدادات.',
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.5),
          ),
        ),
        Expanded(
          child: agents.isEmpty
              ? const EmptyHint(icon: Icons.smart_toy_outlined, text: 'لا يوجد Agents.\nاضغط + لإنشاء أول Agent.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 90),
                  itemCount: agents.length,
                  itemBuilder: (c, i) {
                    final a = agents[i];
                    final on = sel == a.id;
                    final perms = <String>[if (a.canRead) 'قراءة', if (a.canWrite) 'كتابة', if (a.canExecute) 'ويب'];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => ref.read(selectedAgentProvider.notifier).choose(on ? null : a.id),
                        child: Container(
                          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 2, 10),
                          decoration: cardDeco(p, selected: on),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(on ? Icons.check_circle : Icons.circle_outlined, color: on ? p.accent : p.muted, size: 22)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(a.name, style: TextStyle(color: p.text, fontSize: 15.5, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                Text(perms.isEmpty ? 'بلا صلاحيات' : perms.join(' · '), style: TextStyle(color: p.muted, fontSize: 12.5)),
                                Text(a.allowedPaths.isEmpty ? 'المجلدات: كل التخزين المشترك ⚠' : 'المجلدات: ${a.allowedPaths.join(', ')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: a.allowedPaths.isEmpty && (a.canRead || a.canWrite) ? p.danger : p.muted, fontSize: 12.5)),
                                if (a.systemPrompt.trim().isNotEmpty)
                                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(a.systemPrompt.trim(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4))),
                              ]),
                            ),
                            PopupMenuButton<String>(
                              color: p.surface,
                              surfaceTintColor: Colors.transparent,
                              icon: Icon(Icons.more_vert, color: p.muted, size: 20),
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  showAgentEditor(context, a);
                                } else if (v == 'delete') {
                                  final ok = await confirmDialog(context, 'حذف الـ Agent', 'حذف "${a.name}"؟');
                                  if (!ok) return;
                                  if (sel == a.id) await ref.read(selectedAgentProvider.notifier).choose(null);
                                  await ref.read(agentsProvider.notifier).remove(a.id);
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
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        onPressed: () => showAgentEditor(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }
}

Future<void> showAgentEditor(BuildContext context, Agent? a) {
  return showSheet<void>(context, (c) => FractionallySizedBox(heightFactor: 0.94, child: AgentEditor(agent: a)));
}

class AgentEditor extends ConsumerStatefulWidget {
  final Agent? agent;
  const AgentEditor({super.key, this.agent});
  @override
  ConsumerState<AgentEditor> createState() => _AgentEditorState();
}

class _AgentEditorState extends ConsumerState<AgentEditor> {
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late final TextEditingController _paths;
  late bool _read;
  late bool _write;
  late bool _web;

  @override
  void initState() {
    super.initState();
    final a = widget.agent;
    _name = TextEditingController(text: a?.name ?? '');
    _prompt = TextEditingController(text: a?.systemPrompt ?? '');
    _paths = TextEditingController(text: a == null ? '' : a.allowedPaths.join('\n'));
    _read = a?.canRead ?? true;
    _write = a?.canWrite ?? false;
    _web = a?.canExecute ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _paths.dispose();
    super.dispose();
  }

  List<String> _parsePaths() {
    return _paths.text.split(RegExp(r'[\n,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> _pickDir() async {
    try {
      final d = await FilePicker.platform.getDirectoryPath();
      if (d == null || d.isEmpty) return;
      final cur = _parsePaths();
      if (!cur.contains(d)) cur.add(d);
      setState(() => _paths.text = cur.join('\n'));
    } catch (e) {
      toast('تعذر اختيار المجلد: $e');
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast('أدخل اسم الـ Agent');
      return;
    }
    final a = Agent(
      id: widget.agent?.id ?? newId(),
      name: name,
      systemPrompt: _prompt.text.trim(),
      allowedPaths: _parsePaths(),
      canRead: _read,
      canWrite: _write,
      canExecute: _web,
    );
    await ref.read(agentsProvider.notifier).upsert(a);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final risky = (_read || _write) && _parsePaths().isEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 12, 4),
          child: Row(children: [
            Expanded(child: Text(widget.agent == null ? 'Agent جديد' : 'تعديل Agent', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600))),
            FilledButton(onPressed: _save, child: const Text('حفظ')),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(controller: _name, decoration: fieldDeco(context, label: 'الاسم')),
            const SizedBox(height: 12),
            TextField(controller: _prompt, minLines: 3, maxLines: 8, decoration: fieldDeco(context, label: 'تعليمات الـ Agent (اختياري)')),
            const SectionLabelPad('الصلاحيات'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _read,
              onChanged: (v) => setState(() => _read = v),
              title: Text('قراءة الملفات والمجلدات', style: TextStyle(color: p.text, fontSize: 14.5)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _write,
              onChanged: (v) => setState(() => _write = v),
              title: Text('كتابة وإنشاء ملفات', style: TextStyle(color: p.text, fontSize: 14.5)),
              subtitle: Text('يُطلب منك الموافقة قبل كل كتابة (إن كان الخيار مفعّلاً)', style: TextStyle(color: p.muted, fontSize: 12)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _web,
              onChanged: (v) => setState(() => _web = v),
              title: Text('فتح روابط الويب', style: TextStyle(color: p.text, fontSize: 14.5)),
              subtitle: Text('أداة fetch_url (الشبكات المحلية محجوبة)', style: TextStyle(color: p.muted, fontSize: 12)),
            ),
            const SectionLabelPad('المجلدات المسموحة'),
            TextField(
              controller: _paths,
              minLines: 2,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: fieldDeco(context, hint: 'مسار في كل سطر، مثال:\nDownload\nDocuments/notes'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(onPressed: _pickDir, icon: const Icon(Icons.create_new_folder_outlined, size: 18), label: const Text('اختيار مجلد')),
            ),
            if (risky)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.danger.withAlpha(24), borderRadius: BorderRadius.circular(12), border: Border.all(color: p.danger.withAlpha(90))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, color: p.danger, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('لم تحدد مجلدات: سيصل هذا الـ Agent إلى كامل التخزين الداخلي. الأفضل تحديد مجلد أو اثنين فقط.', style: TextStyle(color: p.text, fontSize: 13, height: 1.5))),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}

// =====================================================================
//  Phone files browser
// =====================================================================
class _Ent {
  final FileSystemEntity e;
  final bool isDir;
  final int size;
  _Ent(this.e, this.isDir, this.size);
  String get name => e.path.split('/').last;
}

class PhoneFilesScreen extends ConsumerStatefulWidget {
  const PhoneFilesScreen({super.key});
  @override
  ConsumerState<PhoneFilesScreen> createState() => _PhoneFilesScreenState();
}

class _PhoneFilesScreenState extends ConsumerState<PhoneFilesScreen> {
  String _path = PhoneStorage.root;
  List<_Ent> _items = <_Ent>[];
  bool _loading = true;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await PhoneStorage.requestPermissions();
    _denied = !ok;
    await _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final list = await PhoneStorage.listFiles(_path);
    final out = <_Ent>[];
    for (final e in list) {
      if (e is Directory) {
        out.add(_Ent(e, true, 0));
      } else {
        int sz = 0;
        try {
          sz = (await e.stat()).size;
        } catch (_) {}
        out.add(_Ent(e, false, sz));
      }
    }
    if (!mounted) return;
    setState(() {
      _items = out;
      _loading = false;
    });
  }

  void _up() {
    if (_path == PhoneStorage.root || _path == '/' || _path.isEmpty) return;
    final i = _path.lastIndexOf('/');
    _path = i <= 0 ? '/' : _path.substring(0, i);
    _load();
  }

  Future<void> _createFile() async {
    final name = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        final p = pal(c);
        return AlertDialog(
          backgroundColor: p.surface,
          surfaceTintColor: Colors.transparent,
          title: Text('إنشاء ملف', style: TextStyle(color: p.text, fontSize: 17, fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, autofocus: true, decoration: fieldDeco(c, label: 'اسم الملف', hint: 'note.txt')),
              const SizedBox(height: 10),
              TextField(controller: body, minLines: 3, maxLines: 8, decoration: fieldDeco(c, label: 'المحتوى')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('إلغاء', style: TextStyle(color: p.muted))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إنشاء')),
          ],
        );
      },
    );
    final n = name.text.trim();
    if (ok != true || n.isEmpty) return;
    if (n.contains('/') || n.contains('..')) {
      toast('اسم الملف غير صالح');
      return;
    }
    try {
      await File('$_path/$n').writeAsString(body.text, flush: true);
      toast('تم إنشاء $n');
      await _load();
    } catch (e) {
      toast('تعذر الإنشاء: $e');
    }
  }

  Future<void> _fileSheet(_Ent it) async {
    final mime = mimeFromName(it.name);
    await showSheet<void>(context, (c) {
      final p = pal(c);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${fmtBytes(it.size)} · $mime', style: TextStyle(color: p.muted, fontSize: 12.5)),
              ]),
            ),
            SheetAction(
              icon: Icons.visibility_outlined,
              title: 'عرض',
              onTap: () {
                Navigator.pop(c);
                _view(it, mime);
              },
            ),
            SheetAction(
              icon: Icons.attach_file,
              title: 'إرفاق بالمحادثة',
              onTap: () {
                Navigator.pop(c);
                _attach(it, mime);
              },
            ),
            SheetAction(
              icon: Icons.link,
              title: 'نسخ المسار',
              onTap: () async {
                Navigator.pop(c);
                await Clipboard.setData(ClipboardData(text: it.e.path));
                toast('تم نسخ المسار');
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      );
    });
  }

  Future<Uint8List?> _readBytes(_Ent it, int max) async {
    if (it.size > max) {
      toast('الملف كبير (${fmtBytes(it.size)})');
      return null;
    }
    try {
      return await File(it.e.path).readAsBytes();
    } catch (e) {
      toast('تعذر قراءة الملف: $e');
      return null;
    }
  }

  Future<void> _view(_Ent it, String mime) async {
    final b = await _readBytes(it, 8 * 1024 * 1024);
    if (b == null || !mounted) return;
    if (mime.startsWith('image/')) {
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
    if (looksBinary(b)) {
      toast('ملف ثنائي: لا يمكن عرضه كنص');
      return;
    }
    final txt = utf8.decode(b, allowMalformed: true);
    await showSheet<void>(context, (c) {
      final p = pal(c);
      return FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHandle(),
          Padding(padding: const EdgeInsets.fromLTRB(16, 2, 16, 8), child: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600))),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Directionality(
                textDirection: detectDir(txt) ?? TextDirection.ltr,
                child: SelectableText(clip(txt, 60000), style: TextStyle(color: p.text, fontSize: 13.5, height: 1.5, fontFamily: 'monospace')),
              ),
            ),
          ),
        ]),
      );
    });
  }

  Future<void> _attach(_Ent it, String mime) async {
    final b = await _readBytes(it, 30 * 1024 * 1024);
    if (b == null) return;
    ref.read(pendingProvider.notifier).add(PendingAtt(id: newId(), name: it.name, mime: mime, size: b.length, bytes: b));
    toast('أُضيف إلى رسالتك القادمة');
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final shown = _path == PhoneStorage.root ? '/' : _path.replaceFirst(PhoneStorage.root, '');
    return Scaffold(
      appBar: AppBar(
        title: const Text('ملفات الهاتف'),
        actions: [
          IconButton(icon: const Icon(Icons.arrow_upward), tooltip: 'مجلد أعلى', onPressed: _path == PhoneStorage.root ? null : _up),
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'تحديث', onPressed: _load),
        ],
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: p.surfaceHi,
          child: Directionality(textDirection: TextDirection.ltr, child: Text(shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5, fontFamily: 'monospace'))),
        ),
        if (_denied)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.danger.withAlpha(24), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(child: Text('لم تُمنح صلاحية الوصول للملفات. فعّلها من إعدادات التطبيق.', style: TextStyle(color: p.text, fontSize: 13))),
              TextButton(onPressed: () => openAppSettings(), child: const Text('فتح الإعدادات')),
            ]),
          ),
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
              : (_items.isEmpty
                  ? const EmptyHint(icon: Icons.folder_open, text: 'المجلد فارغ أو لا يمكن الوصول إليه')
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (c, i) {
                        final it = _items[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(it.isDir ? Icons.folder : Icons.insert_drive_file_outlined, color: it.isDir ? p.accent : p.muted),
                          title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 14.5)),
                          subtitle: it.isDir ? null : Text(fmtBytes(it.size), style: TextStyle(color: p.muted, fontSize: 12)),
                          onTap: () {
                            if (it.isDir) {
                              _path = it.e.path;
                              _load();
                            } else {
                              _fileSheet(it);
                            }
                          },
                        );
                      },
                    )),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        tooltip: 'إنشاء ملف',
        onPressed: _createFile,
        child: const Icon(Icons.note_add_outlined),
      ),
    );
  }
}
