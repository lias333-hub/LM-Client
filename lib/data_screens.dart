part of 'main.dart';

// ---------------------------------------------------------------------
// شاشات البيانات: الذاكرة، المكتبة، المشاريع، ملفات الهاتف + التصدير.
// كلها فوق الـ providers الموجودة (memoryProvider/libraryProvider/projectsProvider).
// ---------------------------------------------------------------------

String _fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
}

AppBar _plainBar(Pal p, String title, {List<Widget> actions = const <Widget>[]}) {
  return AppBar(
    backgroundColor: p.bg,
    elevation: 0,
    iconTheme: IconThemeData(color: p.text),
    title: Text(title, style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w600)),
    actions: actions,
  );
}

Widget _listCard(Pal p, {required Widget child, VoidCallback? onTap}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(Rd.card),
      onTap: onTap,
      child: Container(decoration: cardDeco(p), padding: const EdgeInsets.fromLTRB(14, 12, 6, 12), child: child),
    ),
  );
}

// ------------------------------ الذاكرة ------------------------------
class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [MemoryPart? m]) async {
    final title = await askText(context, m == null ? 'ذاكرة جديدة' : 'العنوان', initial: m?.title ?? '', hint: 'عنوان قصير');
    if (title == null || title.trim().isEmpty) return;
    if (!context.mounted) return;
    final content = await askText(context, 'المحتوى', initial: m?.content ?? '', hint: 'ما الذي يجب أن يتذكره النموذج؟', multiline: true);
    if (content == null || content.trim().isEmpty) return;
    await ref.read(memoryProvider.notifier).upsert(MemoryPart(id: m?.id ?? newId(), title: title.trim(), content: content.trim()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final items = ref.watch(memoryProvider);
    final st = ref.watch(settingsProvider);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: _plainBar(p, 'الذاكرة'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: <Widget>[
          Container(
            decoration: cardDeco(p),
            margin: const EdgeInsets.only(bottom: 12),
            child: SwitchListTile(
              value: st.memoryOn,
              onChanged: (v) => ref.read(settingsProvider.notifier).set('memoryOn', v),
              activeColor: p.accent,
              title: Text('إرسال الذاكرة للنموذج', style: TextStyle(color: p.text, fontSize: 15)),
              subtitle: Text('معلومات ثابتة يتذكرها النموذج في كل محادثة', style: TextStyle(color: p.muted, fontSize: 12.5)),
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text('لا توجد عناصر. أضف معلومة يجب أن يتذكرها النموذج، مثل تفضيلاتك أو سياق عملك.', textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.6)),
            ),
          for (final m in items)
            _listCard(
              p,
              onTap: () => _edit(context, ref, m),
              child: Row(children: <Widget>[
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(m.title, style: TextStyle(color: p.text, fontSize: 15.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(m.content, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13, height: 1.5)),
                  ]),
                ),
                IconButton(
                  tooltip: 'حذف',
                  icon: Icon(Icons.delete_outline, color: p.muted),
                  onPressed: () async {
                    if (await confirmDialog(context, 'حذف', 'حذف "${m.title}"؟')) {
                      await ref.read(memoryProvider.notifier).remove(m.id);
                    }
                  },
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ------------------------------ المكتبة ------------------------------
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _addFiles(WidgetRef ref) async {
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
      if (res == null) return;
      for (final f in res.files) {
        Uint8List? b = f.bytes;
        if (b == null && f.path != null) b = await File(f.path!).readAsBytes();
        if (b == null) continue;
        await ref.read(libraryProvider.notifier).addBytes(f.name, b);
      }
    } catch (e) {
      toast('تعذر إضافة الملف: $e');
    }
  }

  Future<void> _addNote(BuildContext context, WidgetRef ref) async {
    final name = await askText(context, 'اسم الملاحظة', hint: 'مثلاً: ملاحظات المشروع');
    if (name == null || name.trim().isEmpty) return;
    if (!context.mounted) return;
    final text = await askText(context, 'النص', multiline: true);
    if (text == null || text.trim().isEmpty) return;
    final n = name.trim();
    await ref.read(libraryProvider.notifier).addBytes(n.contains('.') ? n : '$n.md', Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> _open(BuildContext context, LibraryItem it) async {
    if (!it.isText) {
      toast('${it.name} · ${_fmtSize(it.size)}');
      return;
    }
    final b = await LocalStorage.readRel(it.path);
    if (b == null) {
      toast('الملف غير متوفر');
      return;
    }
    final txt = clip(utf8.decode(b, allowMalformed: true), 20000);
    if (!context.mounted) return;
    showSheet<void>(
      context,
      (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const SheetHandle(),
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(it.name, style: TextStyle(color: pal(c).text, fontSize: 15, fontWeight: FontWeight.w600))),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Directionality(textDirection: TextDirection.ltr, child: SelectableText(txt, style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.5, color: pal(c).text))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  IconData _icon(LibraryItem it) {
    if (it.isImage) return Icons.image_outlined;
    if (it.isPdf) return Icons.picture_as_pdf_outlined;
    if (it.isText) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final items = ref.watch(libraryProvider);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: _plainBar(p, 'المكتبة', actions: <Widget>[
        IconButton(tooltip: 'ملاحظة نصية', icon: const Icon(Icons.note_add_outlined), onPressed: () => _addNote(context, ref)),
        IconButton(tooltip: 'إضافة ملفات', icon: const Icon(Icons.upload_file_outlined), onPressed: () => _addFiles(ref)),
      ]),
      body: items.isEmpty
          ? const EmptyHint(icon: Icons.library_books_outlined, text: 'المكتبة فارغة. أضف ملفات أو ملاحظات لتستخدمها في المشاريع.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: <Widget>[
                for (final it in items)
                  _listCard(
                    p,
                    onTap: () => _open(context, it),
                    child: Row(children: <Widget>[
                      IconBadge(_icon(it)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('${_fmtSize(it.size)} · ${it.time.year}/${it.time.month}/${it.time.day}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ]),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        icon: Icon(Icons.delete_outline, color: p.muted),
                        onPressed: () async {
                          if (await confirmDialog(context, 'حذف', 'حذف "${it.name}"؟')) {
                            await ref.read(libraryProvider.notifier).removeItem(it.id);
                          }
                        },
                      ),
                    ]),
                  ),
              ],
            ),
    );
  }
}

// ------------------------------ المشاريع ------------------------------
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  void _edit(BuildContext context, [Project? pr]) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProjectEditorScreen(project: pr)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final items = ref.watch(projectsProvider);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: _plainBar(p, 'المشاريع'),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('مشروع جديد'),
      ),
      body: items.isEmpty
          ? const EmptyHint(icon: Icons.folder_outlined, text: 'لا توجد مشاريع. المشروع يجمع تعليمات وملفات مكتبة تُرسل مع كل محادثة فيه.')
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: <Widget>[
                for (final pr in items)
                  _listCard(
                    p,
                    onTap: () => _edit(context, pr),
                    child: Row(children: <Widget>[
                      IconBadge(Icons.folder_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text(pr.name, style: TextStyle(color: p.text, fontSize: 15.5, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(pr.instructions.trim().isEmpty ? '${pr.knowledge.length} ملف معرفة' : clip(pr.instructions.replaceAll('\n', ' '), 60), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ]),
                      ),
                      IconButton(
                        tooltip: 'محادثة جديدة في المشروع',
                        icon: Icon(Icons.chat_bubble_outline, color: p.accent),
                        onPressed: () {
                          hub.newChat(projectId: pr.id);
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        },
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        icon: Icon(Icons.delete_outline, color: p.muted),
                        onPressed: () async {
                          if (await confirmDialog(context, 'حذف مشروع', 'حذف "${pr.name}"؟ المحادثات القديمة تبقى.')) {
                            await ref.read(projectsProvider.notifier).remove(pr.id);
                          }
                        },
                      ),
                    ]),
                  ),
              ],
            ),
    );
  }
}

class ProjectEditorScreen extends ConsumerStatefulWidget {
  final Project? project;
  const ProjectEditorScreen({super.key, this.project});

  @override
  ConsumerState<ProjectEditorScreen> createState() => _ProjectEditorScreenState();
}

class _ProjectEditorScreenState extends ConsumerState<ProjectEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _ins;
  late Set<String> _know;

  @override
  void initState() {
    super.initState();
    final pr = widget.project;
    _name = TextEditingController(text: pr?.name ?? '');
    _ins = TextEditingController(text: pr?.instructions ?? '');
    _know = Set<String>.of(pr?.knowledge ?? const <String>[]);
  }

  @override
  void dispose() {
    _name.dispose();
    _ins.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = _name.text.trim();
    if (n.isEmpty) {
      toast('أدخل اسماً للمشروع');
      return;
    }
    await ref.read(projectsProvider.notifier).upsert(Project(id: widget.project?.id ?? newId(), name: n, instructions: _ins.text.trim(), knowledge: _know.toList()));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final lib = ref.watch(libraryProvider);
    Widget pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: w);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: _plainBar(p, widget.project == null ? 'مشروع جديد' : 'تعديل مشروع', actions: <Widget>[
        TextButton(onPressed: _save, child: Text('حفظ', style: TextStyle(color: p.accent, fontSize: 15, fontWeight: FontWeight.w600))),
      ]),
      body: ListView(padding: const EdgeInsets.only(bottom: 40), children: <Widget>[
        const SectionLabel('الاسم'),
        pad(TextField(controller: _name, style: TextStyle(color: p.text), decoration: fieldDeco(context, hint: 'اسم المشروع'))),
        const SectionLabel('التعليمات'),
        pad(TextField(controller: _ins, minLines: 4, maxLines: 10, style: TextStyle(color: p.text), decoration: fieldDeco(context, hint: 'تُرسل للنموذج في كل محادثة داخل هذا المشروع'))),
        const SectionLabel('ملفات المعرفة من المكتبة'),
        pad(
          lib.isEmpty
              ? Text('المكتبة فارغة. أضف ملفات من شاشة المكتبة أولاً.', style: TextStyle(color: p.muted, fontSize: 13))
              : Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
                  for (final it in lib)
                    FilterChip(
                      label: Text(it.name, style: TextStyle(color: p.text, fontSize: 12.5)),
                      selected: _know.contains(it.id),
                      selectedColor: p.accent.withAlpha(60),
                      backgroundColor: p.surface,
                      side: BorderSide(color: p.border),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _know.add(it.id);
                        } else {
                          _know.remove(it.id);
                        }
                      }),
                    ),
                ]),
        ),
      ]),
    );
  }
}

// ------------------------------ ملفات الهاتف ------------------------------
class PhoneFilesScreen extends ConsumerStatefulWidget {
  const PhoneFilesScreen({super.key});

  @override
  ConsumerState<PhoneFilesScreen> createState() => _PhoneFilesScreenState();
}

class _PhoneFilesScreenState extends ConsumerState<PhoneFilesScreen> {
  String _path = PhoneStorage.root;
  late Future<List<FileSystemEntity>> _list;

  @override
  void initState() {
    super.initState();
    _list = PhoneStorage.listFiles(_path);
    PhoneStorage.requestPermissions().then((_) {
      if (mounted) _go(_path);
    });
  }

  void _go(String path) {
    setState(() {
      _path = path;
      _list = PhoneStorage.listFiles(path);
    });
  }

  String _name(FileSystemEntity e) {
    final i = e.path.lastIndexOf('/');
    return i < 0 ? e.path : e.path.substring(i + 1);
  }

  Future<void> _fileMenu(File f) async {
    final name = _name(f);
    await showSheet<void>(
      context,
      (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const SheetHandle(),
          SheetAction(
            icon: Icons.library_add_outlined,
            title: 'إضافة إلى المكتبة',
            subtitle: name,
            onTap: () async {
              Navigator.pop(c);
              try {
                final b = await f.readAsBytes();
                await ref.read(libraryProvider.notifier).addBytes(name, b);
                toast('أُضيف إلى المكتبة');
              } catch (e) {
                toast('تعذر القراءة: $e');
              }
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final atRoot = _path == PhoneStorage.root;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: _plainBar(p, 'ملفات الهاتف', actions: <Widget>[
        IconButton(tooltip: 'المجلد الأعلى', icon: const Icon(Icons.arrow_upward), onPressed: atRoot ? null : () => _go(Directory(_path).parent.path)),
      ]),
      body: Column(children: <Widget>[
        Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(Rd.control), border: Border.all(color: p.border)),
            child: Text(_path, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: p.codeText)),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<FileSystemEntity>>(
            future: _list,
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              final items = snap.data ?? <FileSystemEntity>[];
              if (items.isEmpty) return const EmptyHint(icon: Icons.folder_off_outlined, text: 'المجلد فارغ، أو الصلاحية غير ممنوحة. امنح صلاحية الملفات من الإعدادات > البيانات.');
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: items.length,
                itemBuilder: (c, i) {
                  final e = items[i];
                  final isDir = e is Directory;
                  return InkWell(
                    onTap: () {
                      if (e is Directory) {
                        _go(e.path);
                      } else if (e is File) {
                        _fileMenu(e);
                      }
                    },
                    child: SizedBox(
                      height: 48,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(children: <Widget>[
                          Icon(isDir ? Icons.folder : Icons.insert_drive_file_outlined, size: 22, color: isDir ? p.accent : p.muted),
                          const SizedBox(width: 14),
                          Expanded(child: Text(_name(e), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15.5))),
                        ]),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent, minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                ref.read(settingsProvider.notifier).set('workspaceRoot', _path);
                toast('تم تعيين مجلد المشروع');
              },
              icon: const Icon(Icons.folder_special_outlined),
              label: const Text('تعيين هذا المجلد كمجلد المشروع'),
            ),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------ التصدير ------------------------------
Future<void> showExportSheet(BuildContext context, String title, String content) {
  return showSheet<void>(
    context,
    (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        const SheetHandle(),
        SheetAction(
          icon: Icons.copy,
          title: 'نسخ كنص Markdown',
          onTap: () {
            Clipboard.setData(ClipboardData(text: content));
            Navigator.pop(c);
            toast('تم النسخ');
          },
        ),
        SheetAction(
          icon: Icons.save_alt,
          title: 'حفظ كملف في مجلد Download',
          onTap: () async {
            Navigator.pop(c);
            try {
              await PhoneStorage.requestPermissions();
              final dir = Directory('${PhoneStorage.root}/Download');
              if (!await dir.exists()) await dir.create(recursive: true);
              final f = File('${dir.path}/${safeFileName(title.isEmpty ? 'chat' : title)}.md');
              await f.writeAsString(content);
              toast('تم الحفظ: ${f.path}');
            } catch (e) {
              toast('تعذر الحفظ: $e');
            }
          },
        ),
      ]),
    ),
  );
}

Future<void> exportConversation(BuildContext context, dynamic session) async {
  final md = conversationToMarkdown(session.meta as ConvMeta, session.messages as List<ChatMessage>);
  final t = (session.meta as ConvMeta).title;
  await showExportSheet(context, t.isEmpty ? 'chat' : t, md);
}
