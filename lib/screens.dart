part of 'main.dart';

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
                _navChip(p, Icons.desktop_windows_outlined, 'المساحة', () => openProjectWorkspace(context)),
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
                    Text(pr == null ? 'اضغط لإضافة مزوّد' : (pr.selectedModel.isEmpty ? pr.kindLabel : pr.selectedModel), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
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
            Padding(padding: const EdgeInsets.all(16), child: Text('لا توجد مشاريع بعد. أنشئ مشروعاً من قسم المشاريع.', style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.4))),
          const SizedBox(height: 8),
        ]),
      ),
    );
  });
}
