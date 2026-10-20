// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, unused_local_variable, avoid_print, deprecated_member_use, use_build_context_synchronously, prefer_const_constructors, prefer_const_literals_to_create_immutables, depend_on_referenced_packages, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, unnecessary_import
part of 'main.dart';

// =====================================================================
//  UI — App shell
// =====================================================================
class LMClientApp extends ConsumerWidget {
  const LMClientApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final mode = s.themeMode == 1 ? ThemeMode.light : (s.themeMode == 2 ? ThemeMode.dark : ThemeMode.system);
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      scaffoldMessengerKey: messengerKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      builder: (context, child) => Directionality(
        textDirection: s.rtl ? TextDirection.rtl : TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const ChatPage(),
    );
  }
}

String greeting() {
  final h = DateTime.now().hour;
  if (h >= 5 && h < 12) return 'صباح الخير';
  if (h >= 12 && h < 18) return 'طاب يومك';
  return 'مساء الخير';
}

void pushScreen(Widget w) {
  final nav = navKey.currentState;
  if (nav == null) return;
  nav.push(MaterialPageRoute<void>(builder: (_) => w));
}

// =====================================================================
//  Chat page
// =====================================================================
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});
  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scroll = ScrollController();
  bool _stick = true;
  bool _showDown = false;
  bool _selecting = false;
  final Set<String> _selected = <String>{};
  ChatSession? _attached;
  int _lastCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!appContainer.read(bootProvider)) bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attached?.tick.removeListener(_onTick);
    _attached?.removeListener(_onSessionChange);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.inactive) {
      hub.persistCurrent();
    }
  }

  void _attach(ChatSession s) {
    if (identical(_attached, s)) return;
    _attached?.tick.removeListener(_onTick);
    _attached?.removeListener(_onSessionChange);
    _attached = s;
    s.tick.addListener(_onTick);
    s.addListener(_onSessionChange);
    _stick = true;
    _showDown = false;
    _lastCount = s.messages.length;
    _selecting = false;
    _selected.clear();
    _settleBottom();
  }

  void _onTick() {
    if (_stick) _jumpBottom();
  }

  void _onSessionChange() {
    final n = _attached?.messages.length ?? 0;
    if (n != _lastCount) {
      _lastCount = n;
      if (_stick) _settleBottom();
    }
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _settleBottom() {
    _jumpBottom();
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (mounted && _stick) _jumpBottom();
    });
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (mounted && _stick) _jumpBottom();
    });
  }

  void _onSent() {
    _stick = true;
    _settleBottom();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n.depth != 0) return false;
    final dist = n.metrics.maxScrollExtent - n.metrics.pixels;
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      _stick = dist < 100;
    } else if (n is ScrollEndNotification && dist < 40) {
      _stick = true;
    }
    final down = dist > 320;
    if (down != _showDown) setState(() => _showDown = down);
    return false;
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _enterSelect(String id) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(id);
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final boot = ref.watch(bootProvider);
    final ps = ref.watch(profilesProvider);
    final projects = ref.watch(projectsProvider);
    return ValueListenableBuilder<ChatSession>(
      valueListenable: hub.current,
      builder: (context, session, _) {
        _attach(session);
        return AnimatedBuilder(
          animation: session,
          builder: (context, _) => _scaffold(context, session, boot, ps, projects),
        );
      },
    );
  }

  Widget _scaffold(BuildContext context, ChatSession session, bool boot, ProfilesState ps, List<Project> projects) {
    final p = pal(context);
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      appBar: _selecting ? _selectionBar(context, session, p) : _normalBar(context, session, p, projects),
      body: Column(children: [
        Expanded(child: _body(context, session, p, boot)),
        Composer(session: session, onSent: _onSent),
      ]),
    );
  }

  PreferredSizeWidget _selectionBar(BuildContext context, ChatSession session, Pal p) {
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelect),
      title: Text('${_selected.length} محددة', style: const TextStyle(fontSize: 16)),
      actions: [
        IconButton(
          icon: const Icon(Icons.visibility_off_outlined),
          tooltip: 'استبعاد من السياق',
          onPressed: () async {
            await session.setExcluded(Set<String>.from(_selected), true);
            _exitSelect();
          },
        ),
        IconButton(
          icon: const Icon(Icons.visibility_outlined),
          tooltip: 'إرجاع إلى السياق',
          onPressed: () async {
            await session.setExcluded(Set<String>.from(_selected), false);
            _exitSelect();
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'حذف',
          onPressed: () async {
            final ok = await confirmDialog(context, 'حذف الرسائل', 'سيتم حذف ${_selected.length} رسالة نهائياً. للإبقاء عليها دون إرسالها للنموذج استخدم "استبعاد من السياق".');
            if (!ok) return;
            await session.deleteMessages(Set<String>.from(_selected));
            _exitSelect();
          },
        ),
      ],
    );
  }

  PreferredSizeWidget _normalBar(BuildContext context, ChatSession session, Pal p, List<Project> projects) {
    String? projectName;
    for (final pr in projects) {
      if (pr.id == session.meta.projectId) projectName = pr.name;
    }
    final title = session.meta.title.isEmpty ? kAppName : session.meta.title;
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
      title: GestureDetector(
        onTap: () => _rename(context, session),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text)),
            if (projectName != null) Text(projectName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: p.muted)),
          ],
        ),
      ),
      actions: [
        IconButton(icon: const Icon(Icons.edit_square), tooltip: 'محادثة جديدة', onPressed: () => hub.newChat()),
        PopupMenuButton<String>(
          color: p.surface,
          surfaceTintColor: Colors.transparent,
          icon: const Icon(Icons.more_vert),
          onSelected: (v) => _menu(context, session, v),
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            _menuItem('inspect', Icons.data_object, 'عرض الطلب الأخير', p),
            _menuItem('compact', Icons.compress, 'تلخيص السياق الآن', p),
            _menuItem('changes', Icons.history, 'تعديلات الملفات (تراجع)', p),
            _menuItem('select', Icons.checklist, 'تحديد رسائل', p),
            _menuItem('rename', Icons.drive_file_rename_outline, 'إعادة تسمية', p),
            _menuItem('export', Icons.ios_share, 'تصدير المحادثة', p),
            _menuItem('delete', Icons.delete_outline, 'حذف المحادثة', p),
          ],
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String v, IconData i, String t, Pal p) {
    return PopupMenuItem<String>(
      value: v,
      child: Row(children: [Icon(i, size: 20, color: p.muted), const SizedBox(width: 12), Text(t, style: TextStyle(color: p.text, fontSize: 14.5))]),
    );
  }

  Future<void> _menu(BuildContext context, ChatSession session, String v) async {
    switch (v) {
      case 'inspect':
        showInspector(context, session);
        break;
      case 'compact':
        if (session.generating) {
          toast('انتظر انتهاء الرد الحالي');
        } else {
          await session.compactNow();
        }
        break;
      case 'changes':
        showSheet<void>(context, (c) => CheckpointsSheet(convId: session.meta.id));
        break;
      case 'select':
        if (session.messages.isNotEmpty) _enterSelect(session.messages.last.id);
        break;
      case 'rename':
        await _rename(context, session);
        break;
      case 'export':
        exportConversation(context, session);
        break;
      case 'delete':
        if (session.messages.isEmpty) {
          toast('المحادثة فارغة');
          break;
        }
        final ok = await confirmDialog(context, 'حذف المحادثة', 'سيتم حذف "${session.meta.title}" نهائياً.');
        if (ok) await hub.delete(session.meta.id);
        break;
    }
  }

  Future<void> _rename(BuildContext context, ChatSession session) async {
    final t = await askText(context, 'اسم المحادثة', initial: session.meta.title);
    if (t != null && t.trim().isNotEmpty) await session.rename(t);
  }

  Widget _body(BuildContext context, ChatSession session, Pal p, bool boot) {
    if (!session.loaded) {
      return Center(child: CircularProgressIndicator(strokeWidth: 2, color: p.accent));
    }
    final msgs = session.messages;
    if (msgs.isEmpty) return EmptyState(boot: boot);
    return Stack(children: [
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
          itemCount: msgs.length,
          itemBuilder: (c, i) {
            final m = msgs[i];
            final last = i == msgs.length - 1;
            final showActions = last || msgs[i + 1].role == 'user';
            return MessageView(
              key: ValueKey<String>(m.id),
              session: session,
              msg: m,
              isLast: last,
              showActions: showActions,
              selecting: _selecting,
              selected: _selected.contains(m.id),
              onTapSelect: () => _toggle(m.id),
              onEnterSelect: () => _enterSelect(m.id),
            );
          },
        ),
      ),
      if (_showDown)
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: p.surface,
              shape: CircleBorder(side: BorderSide(color: p.border)),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  _stick = true;
                  _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                },
                child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.arrow_downward, size: 20, color: p.text)),
              ),
            ),
          ),
        ),
    ]);
  }
}

// =====================================================================
//  Empty state
// =====================================================================
class EmptyState extends ConsumerWidget {
  final bool boot;
  const EmptyState({super.key, required this.boot});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final ps = ref.watch(profilesProvider);
    final pr = ps.selected;
    Widget info;
    if (!boot) {
      info = const SizedBox.shrink();
    } else if (pr == null) {
      info = _card(
        context,
        p,
        'أضف مزوّد API لتبدأ: Anthropic أو OpenAI أو Gemini أو أي خادم متوافق مع OpenAI.',
        'إضافة بروفايل',
        () => openProfileEditor(context, null),
      );
    } else if (pr.selectedModel.isEmpty) {
      info = _card(context, p, 'اختر الموديل الذي تريد التحدث معه (أو اجلب القائمة من الخادم).', 'اختيار موديل', () => showModelPicker(context));
    } else {
      info = Text('${pr.name} · ${pr.selectedModel}', textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 13.5));
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome, color: p.accent, size: 30),
          const SizedBox(height: 14),
          Text(greeting(), style: TextStyle(fontFamily: 'serif', fontFamilyFallback: const <String>['Noto Serif', 'Georgia'], fontSize: 32, color: p.text)),
          const SizedBox(height: 12),
          info,
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, Pal p, String text, String btn, VoidCallback onTap) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.border)),
      child: Column(children: [
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 14, height: 1.5)),
        const SizedBox(height: 12),
        FilledButton(onPressed: onTap, child: Text(btn)),
      ]),
    );
  }
}

// =====================================================================
//  Attachment tile (image thumbnail or file chip)
// =====================================================================
class AttachTile extends StatefulWidget {
  final String name;
  final String mime;
  final Uint8List? bytes;
  final String? path;
  final VoidCallback? onRemove;
  const AttachTile({super.key, required this.name, required this.mime, this.bytes, this.path, this.onRemove});
  @override
  State<AttachTile> createState() => _AttachTileState();
}

class _AttachTileState extends State<AttachTile> {
  Future<Uint8List?>? _fut;

  @override
  void initState() {
    super.initState();
    if (widget.mime.startsWith('image/') && widget.bytes == null && widget.path != null) {
      _fut = LocalStorage.readRel(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final isImg = widget.mime.startsWith('image/');
    Widget core;
    if (isImg) {
      Widget img;
      if (widget.bytes != null) {
        img = Image.memory(widget.bytes!, fit: BoxFit.cover, cacheWidth: 240, gaplessPlayback: true);
      } else if (_fut != null) {
        img = FutureBuilder<Uint8List?>(
          future: _fut,
          builder: (c, snap) {
            final d = snap.data;
            if (d == null) return Icon(Icons.image_outlined, color: p.muted);
            return Image.memory(d, fit: BoxFit.cover, cacheWidth: 240, gaplessPlayback: true);
          },
        );
      } else {
        img = Icon(Icons.image_outlined, color: p.muted);
      }
      core = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(width: 60, height: 60, color: p.surfaceHi, child: img),
      );
    } else {
      core = Container(
        height: 44,
        padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 12, 0),
        decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(12)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(widget.mime == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.description_outlined, size: 18, color: p.muted),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: p.text)),
          ),
        ]),
      );
    }
    if (widget.onRemove == null) return core;
    return Stack(clipBehavior: Clip.none, children: [
      core,
      PositionedDirectional(
        top: -6,
        end: -6,
        child: GestureDetector(
          onTap: widget.onRemove,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: p.text, shape: BoxShape.circle),
            child: Icon(Icons.close, size: 13, color: p.bg),
          ),
        ),
      ),
    ]);
  }
}

// =====================================================================
//  Composer
// =====================================================================
class Composer extends ConsumerStatefulWidget {
  final ChatSession session;
  final VoidCallback onSent;
  const Composer({super.key, required this.session, required this.onSent});
  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  final SpeechToText _stt = SpeechToText();
  bool _listening = false;
  String _sttBase = '';
  bool _hasText = false;
  TextDirection? _dir;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onText);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onText);
    _ctrl.dispose();
    _focus.dispose();
    try {
      _stt.cancel();
    } catch (_) {}
    super.dispose();
  }

  void _onText() {
    final has = _ctrl.text.trim().isNotEmpty;
    final d = detectDir(_ctrl.text);
    if (has != _hasText || d != _dir) {
      setState(() {
        _hasText = has;
        _dir = d;
      });
    }
  }

  Future<void> _send() async {
    final session = widget.session;
    final pend = ref.read(pendingProvider);
    final text = _ctrl.text;
    if (text.trim().isEmpty && pend.isEmpty) return;
    final quote = ref.read(quoteProvider);
    if (_listening) {
      try {
        await _stt.stop();
      } catch (_) {}
      _listening = false;
    }
    _ctrl.clear();
    ref.read(pendingProvider.notifier).clear();
    ref.read(quoteProvider.notifier).set(null);
    widget.onSent();
    // أثناء توليد الرد: تُضاف إلى الطابور وتصل النموذج بين جولات الأدوات (أو بعد انتهاء ردّه).
    if (session.generating && session.enqueue(text, pend, quote: quote)) return;
    await session.send(text, pend, quote: quote);
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      try {
        await _stt.stop();
      } catch (_) {}
      if (mounted) setState(() => _listening = false);
      return;
    }
    bool ok = false;
    try {
      ok = await _stt.initialize(
        onError: (e) {
          if (mounted) setState(() => _listening = false);
        },
        onStatus: (st) {
          if ((st == 'done' || st == 'notListening') && mounted) setState(() => _listening = false);
        },
      );
    } catch (_) {}
    if (!ok) {
      toast('التعرف على الصوت غير متاح. تحقق من إذن الميكروفون.');
      return;
    }
    _sttBase = _ctrl.text;
    if (_sttBase.isNotEmpty && !_sttBase.endsWith(' ')) _sttBase += ' ';
    setState(() => _listening = true);
    final loc = ref.read(settingsProvider).sttLocale;
    _stt.listen(
      onResult: (r) {
        if (!mounted) return;
        _ctrl.text = _sttBase + r.recognizedWords;
        _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
      },
      localeId: loc.isEmpty ? null : loc,
    );
  }

  void _moveCursor(int d) {
    final pos = _ctrl.selection.baseOffset;
    if (pos < 0) return;
    _ctrl.selection = TextSelection.collapsed(offset: clampInt(pos + d, 0, _ctrl.text.length));
  }

  Future<void> _pick({bool images = false}) async {
    final list = await pickAttachments(images: images);
    for (final a in list) {
      ref.read(pendingProvider.notifier).add(a);
    }
  }

  Future<void> _pickFromLibrary() async {
    final lib = ref.read(libraryProvider);
    if (lib.isEmpty) {
      toast('المكتبة فارغة');
      return;
    }
    final chosen = <String>{};
    await showSheet<void>(context, (c) {
      final p = pal(c);
      return StatefulBuilder(builder: (c, setSt) {
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(children: [
                Expanded(child: Text('اختر من المكتبة', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600))),
                FilledButton(
                  onPressed: chosen.isEmpty
                      ? null
                      : () {
                          for (final it in lib) {
                            if (chosen.contains(it.id) && it.path != null) {
                              ref.read(pendingProvider.notifier).add(PendingAtt(id: newId(), name: it.name, mime: it.mime, size: it.size, path: it.path));
                            }
                          }
                          Navigator.pop(c);
                        },
                  child: Text('إرفاق (${chosen.length})'),
                ),
              ]),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: lib
                    .where((e) => e.path != null)
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

  void _openPlus() {
    showSheet<void>(context, (c) {
      return Consumer(builder: (c, ref2, _) {
        final p = pal(c);
        final s = ref2.watch(settingsProvider);
        final agents = ref2.watch(agentsProvider);
        final selId = ref2.watch(selectedAgentProvider);
        String agentName = 'بدون';
        for (final a in agents) {
          if (a.id == selId) agentName = a.name;
        }
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SheetHandle(),
              SheetAction(
                icon: Icons.attach_file,
                title: 'إرفاق ملف',
                onTap: () {
                  Navigator.pop(c);
                  _pick();
                },
              ),
              SheetAction(
                icon: Icons.image_outlined,
                title: 'إرفاق صورة',
                onTap: () {
                  Navigator.pop(c);
                  _pick(images: true);
                },
              ),
              SheetAction(
                icon: Icons.library_books_outlined,
                title: 'من المكتبة',
                onTap: () {
                  Navigator.pop(c);
                  _pickFromLibrary();
                },
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Text('مستوى التفكير', style: TextStyle(color: p.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegPicker<int>(
                  values: const <int>[0, 1, 2, 3],
                  labels: const <String>['إيقاف', 'منخفض', 'متوسط', 'عالٍ'],
                  value: s.thinkLevel,
                  onChanged: (v) => ref2.read(settingsProvider.notifier).set('thinkLevel', v),
                ),
              ),
              SwitchListTile(
                value: s.tools,
                onChanged: (v) => ref2.read(settingsProvider.notifier).set('tools', v),
                title: Text('الأدوات (ذاكرة، مكتبة، ملفات)', style: TextStyle(color: p.text, fontSize: 14.5)),
                subtitle: Text('تسمح للنموذج باستدعاء الأدوات تلقائياً', style: TextStyle(color: p.muted, fontSize: 12)),
                dense: true,
              ),
              SheetAction(
                icon: Icons.smart_toy_outlined,
                title: 'Agent',
                subtitle: agentName,
                onTap: () {
                  Navigator.pop(c);
                  showAgentPicker(context);
                },
              ),
              const SizedBox(height: 8),
            ]),
          ),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final session = widget.session;
    final pend = ref.watch(pendingProvider);
    final quote = ref.watch(quoteProvider);
    final s = ref.watch(settingsProvider);
    final agents = ref.watch(agentsProvider);
    final selAgent = ref.watch(selectedAgentProvider);
    String? agentName;
    for (final a in agents) {
      if (a.id == selAgent) agentName = a.name;
    }
    final generating = session.generating;
    final hasInput = _hasText || pend.isNotEmpty;
    final canSend = generating || hasInput;
    // أثناء التوليد: إن كُتب شيء يصير الزر الرئيسي "إرسال إلى الطابور" ويظهر زر إيقاف منفصل.
    final queueMode = generating && hasInput;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 2, 10, 10),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: p.border),
          boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withAlpha(16), blurRadius: 14, offset: const Offset(0, 3))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (quote != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 4, 6),
              decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.reply, size: 16, color: p.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(clip(quote.replaceAll('\n', ' '), 140), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12.5))),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  icon: Icon(Icons.close, color: p.muted),
                  onPressed: () => ref.read(quoteProvider.notifier).set(null),
                ),
              ]),
            ),
          if (session.queue.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 6),
              decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('بالانتظار — تصل النموذج بعد الجولة الحالية (الإيقاف يرسلها فوراً)', style: TextStyle(color: p.muted, fontSize: 11.5)),
                for (final q in session.queue)
                  Row(children: [
                    Icon(Icons.schedule, size: 15, color: p.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        q.text.isEmpty ? 'مرفقات (${q.atts.length})' : clip(q.text.replaceAll('\n', ' '), 120),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.text, fontSize: 13.5),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      tooltip: 'إزالة من الطابور',
                      icon: Icon(Icons.close, color: p.muted),
                      onPressed: () => session.removeQueued(q.id),
                    ),
                  ]),
              ]),
            ),
          if (pend.isNotEmpty)
            SizedBox(
              height: 74,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                itemCount: pend.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (c, i) => AttachTile(
                  key: ValueKey<String>(pend[i].id),
                  name: pend[i].name,
                  mime: pend[i].mime,
                  bytes: pend[i].bytes,
                  path: pend[i].path,
                  onRemove: () => ref.read(pendingProvider.notifier).removeId(pend[i].id),
                ),
              ),
            ),
          Directionality(
            textDirection: _dir ?? (s.rtl ? TextDirection.rtl : TextDirection.ltr),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              minLines: 1,
              maxLines: 7,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textAlign: TextAlign.start,
              style: TextStyle(fontSize: 16, color: p.text, height: 1.4),
              cursorColor: p.accent,
              decoration: InputDecoration(
                hintText: 'اكتب رسالتك…',
                hintStyle: TextStyle(color: p.muted.withAlpha(190)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 8),
            child: Row(children: [
              GestureDetector(
                onTap: _openPlus,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.border)),
                  child: Icon(Icons.add, size: 20, color: p.muted),
                ),
              ),
              const SizedBox(width: 6),
              if (agentName != null) _chip(p, Icons.smart_toy_outlined, agentName, () => showAgentPicker(context)),
              if (s.thinkLevel > 0) _chip(p, Icons.psychology_outlined, 'تفكير', _openPlus),
              const Spacer(),
              _modelChip(context, p),
              if (s.cursorBtns) ...[
                IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.chevron_left, color: p.muted), onPressed: () => _moveCursor(-1)),
                IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.chevron_right, color: p.muted), onPressed: () => _moveCursor(1)),
              ],
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? p.accent : p.muted),
                onPressed: _toggleMic,
              ),
              const SizedBox(width: 2),
              if (queueMode) ...[
                GestureDetector(
                  onTap: session.stop,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.border)),
                    child: Icon(Icons.stop_rounded, size: 21, color: p.muted),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              GestureDetector(
                onTap: (generating && !queueMode) ? session.stop : (canSend ? _send : null),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: canSend ? p.accent : p.surfaceHi, shape: BoxShape.circle),
                  child: Icon((generating && !queueMode) ? Icons.stop_rounded : Icons.arrow_upward_rounded, size: 21, color: canSend ? p.onAccent : p.muted),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chip(Pal p, IconData i, String t, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 15, color: p.accent),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 70),
              child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: p.text)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _modelChip(BuildContext ctx, Pal p) {
    final ps = ref.watch(profilesProvider);
    final pr = ps.selected;
    final label = pr == null ? 'إضافة مزوّد' : (pr.selectedModel.isEmpty ? 'اختر موديل' : pr.selectedModel);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => pr == null ? openProfileEditor(ctx, null) : showModelPicker(ctx),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 170),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 13))),
          Icon(Icons.expand_more, size: 16, color: p.muted),
        ]),
      ),
    );
  }
}

/// أداة اختيار مقسّمة (بديل SegmentedButton موحّد الشكل).
class SegPicker<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T value;
  final ValueChanged<T> onChanged;
  const SegPicker({super.key, required this.values, required this.labels, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: List<Widget>.generate(values.length, (i) {
          final sel = values[i] == value;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(values[i]),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(color: sel ? p.surface : Colors.transparent, borderRadius: BorderRadius.circular(10)),
                child: Center(
                  child: Text(labels[i], style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w600 : FontWeight.w400, color: sel ? p.text : p.muted)),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

Future<void> showAgentPicker(BuildContext context) {
  return showSheet<void>(context, (c) {
    return Consumer(builder: (c, ref, _) {
      final p = pal(c);
      final agents = ref.watch(agentsProvider);
      final sel = ref.watch(selectedAgentProvider);
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SheetHandle(),
          SheetAction(
            icon: sel == null ? Icons.check_circle : Icons.circle_outlined,
            title: 'بدون Agent',
            subtitle: 'لا وصول لملفات الهاتف',
            onTap: () {
              ref.read(selectedAgentProvider.notifier).choose(null);
              Navigator.pop(c);
            },
          ),
          ...agents.map((a) => SheetAction(
                icon: sel == a.id ? Icons.check_circle : Icons.circle_outlined,
                title: a.name,
                subtitle: '${a.canRead ? 'قراءة ' : ''}${a.canWrite ? 'كتابة ' : ''}${a.canExecute ? 'ويب' : ''}',
                onTap: () {
                  ref.read(selectedAgentProvider.notifier).choose(a.id);
                  Navigator.pop(c);
                },
              )),
          SheetAction(
            icon: Icons.add,
            title: 'إدارة الـ Agents',
            onTap: () {
              Navigator.pop(c);
              pushScreen(const AgentsScreen());
            },
          ),
          const SizedBox(height: 8),
        ]),
      );
    });
  });
}

// =====================================================================
//  Model picker
// =====================================================================
Future<void> showModelPicker(BuildContext context) {
  return showSheet<void>(context, (c) => const ModelPickerSheet());
}

class ModelPickerSheet extends ConsumerStatefulWidget {
  const ModelPickerSheet({super.key});
  @override
  ConsumerState<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends ConsumerState<ModelPickerSheet> {
  String _q = '';
  bool _loading = false;

  Future<void> _refresh(ApiProfile pr) async {
    setState(() => _loading = true);
    try {
      final list = await listModels(pr);
      final cur = pr.selectedModel;
      final keep = list.contains(cur) ? cur : (list.isNotEmpty && cur.isEmpty ? list.first : cur);
      await ref.read(profilesProvider.notifier).upsert(pr.copyWith(models: list, selectedModel: keep));
      toast('تم جلب ${list.length} موديل');
    } catch (e) {
      toast('فشل جلب الموديلات: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _manual(ApiProfile pr) async {
    final t = await askText(context, 'اسم الموديل (Model ID)', hint: 'مثال: claude-sonnet-4-5');
    if (t == null || t.trim().isEmpty) return;
    final m = t.trim();
    final models = pr.models.contains(m) ? pr.models : <String>[m, ...pr.models];
    await ref.read(profilesProvider.notifier).upsert(pr.copyWith(models: models, selectedModel: m), select: true);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final ps = ref.watch(profilesProvider);
    final pr = ps.selected;
    final q = _q.trim().toLowerCase();
    final models = pr == null ? <String>[] : pr.models.where((m) => q.isEmpty || m.toLowerCase().contains(q)).toList();
    return FractionallySizedBox(
      heightFactor: 0.82,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHandle(),
          if (ps.list.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: ps.list
                    .map((x) => Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(x.name),
                            selected: x.id == ps.selectedId,
                            selectedColor: p.accent,
                            backgroundColor: p.surfaceHi,
                            side: BorderSide.none,
                            labelStyle: TextStyle(color: x.id == ps.selectedId ? p.onAccent : p.text, fontSize: 13),
                            onSelected: (_) => ref.read(profilesProvider.notifier).select(x.id),
                          ),
                        ))
                    .toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Row(children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: fieldDeco(context, hint: 'بحث في الموديلات…', prefix: Icon(Icons.search, size: 20, color: p.muted)),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'جلب الموديلات من الخادم',
                onPressed: (pr == null || _loading) ? null : () => _refresh(pr),
                icon: _loading
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.accent))
                    : Icon(Icons.refresh, color: p.muted),
              ),
            ]),
          ),
          if (pr != null)
            SheetAction(icon: Icons.add, title: 'إدخال اسم موديل يدوياً', subtitle: 'إذا كان الخادم لا يدعم قائمة الموديلات', onTap: () => _manual(pr)),
          const Divider(),
          Expanded(
            child: pr == null
                ? Center(child: Text('لا يوجد بروفايل', style: TextStyle(color: p.muted)))
                : (models.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(pr.models.isEmpty ? 'لا توجد موديلات محفوظة.\nاضغط تحديث لجلبها أو أدخل الاسم يدوياً.' : 'لا نتائج', textAlign: TextAlign.center, style: TextStyle(color: p.muted, height: 1.5)),
                        ),
                      )
                    : ListView.builder(
                        itemCount: models.length,
                        itemBuilder: (c, i) {
                          final m = models[i];
                          final sel = m == pr.selectedModel;
                          return ListTile(
                            dense: true,
                            title: Text(m, style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
                            trailing: sel ? Icon(Icons.check, color: p.accent, size: 20) : null,
                            onTap: () async {
                              await ref.read(profilesProvider.notifier).upsert(pr.copyWith(selectedModel: m), select: true);
                              if (mounted) Navigator.pop(context);
                            },
                          );
                        },
                      )),
          ),
        ]),
      ),
    );
  }
}

// =====================================================================
//  Request inspector ("what the model sees, verbatim")
// =====================================================================
dynamic redactJson(dynamic v, [String key = '']) {
  if (v is Map) {
    final out = <String, dynamic>{};
    v.forEach((k, val) {
      out[k.toString()] = redactJson(val, k.toString());
    });
    return out;
  }
  if (v is List) return v.map((e) => redactJson(e, key)).toList();
  if (v is String && v.length > 400 && (key == 'data' || key == 'file_data' || v.startsWith('data:'))) {
    return '<${v.length} chars base64>';
  }
  return v;
}

String maskKey(String v) => v.length <= 10 ? '••••' : '${v.substring(0, 6)}••••${v.substring(v.length - 3)}';

String describeRequest(ChatSession session) {
  final c = session.lastCall;
  if (c == null) return 'لم يُرسل أي طلب في هذه المحادثة بعد.';
  final b = StringBuffer();
  b.writeln('POST ${c.url}');
  c.headers.forEach((k, v) {
    final low = k.toLowerCase();
    final masked = (low.contains('key') || low == 'authorization') ? maskKey(v) : v;
    b.writeln('$k: $masked');
  });
  b.writeln();
  b.writeln(const JsonEncoder.withIndent('  ').convert(redactJson(c.body)));
  return b.toString();
}

/// قائمة تعديلات الملفات التي أجراها النموذج في هذه المحادثة، مع زر تراجع لكل تعديل.
class CheckpointsSheet extends StatefulWidget {
  final String convId;
  const CheckpointsSheet({super.key, required this.convId});
  @override
  State<CheckpointsSheet> createState() => _CheckpointsSheetState();
}

class _CheckpointsSheetState extends State<CheckpointsSheet> {
  List<Checkpoint>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await CheckpointStore.list(widget.convId);
    if (mounted) setState(() => _items = l.reversed.toList());
  }

  Future<void> _undo(Checkpoint c) async {
    final changed = await CheckpointStore.changedSince(c);
    final name = c.path.split('/').last;
    final what = c.existed ? 'سيُستعاد "$name" كما كان قبل التعديل.' : 'سيُحذف "$name" (أنشأه النموذج).';
    final warn = changed ? '\n\nتنبيه: الملف تغيّر بعد هذا التعديل، وسيضيع ما تغيّر.' : '';
    if (!mounted) return;
    final ok = await confirmDialog(context, 'التراجع عن تعديل', '$what$warn', ok: 'تراجع');
    if (!ok) return;
    String msg;
    try {
      msg = await CheckpointStore.undo(c);
    } catch (e) {
      msg = 'تعذّر التراجع: $e';
    }
    toast(msg);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final items = _items;
    Widget body;
    if (items == null) {
      body = Center(child: CircularProgressIndicator(strokeWidth: 2, color: p.accent));
    } else if (items.isEmpty) {
      body = Center(child: Text('لا توجد تعديلات ملفات بعد', style: TextStyle(color: p.muted)));
    } else {
      body = ListView.builder(
        itemCount: items.length,
        itemBuilder: (c, i) {
          final it = items[i];
          final parts = it.path.split('/');
          final dir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '';
          return ListTile(
            leading: Icon(it.existed ? Icons.edit_outlined : Icons.add_circle_outline, color: p.muted, size: 22),
            title: Text(parts.last, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15)),
            subtitle: Text('${toolLabel(it.tool)} · ${fmtClock(it.time)}${dir.isEmpty ? '' : ' · $dir'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
            trailing: it.undone
                ? Text('تم التراجع', style: TextStyle(color: p.muted, fontSize: 12.5))
                : TextButton(onPressed: () => _undo(it), child: Text('تراجع', style: TextStyle(color: p.accent))),
          );
        },
      );
    }
    return FractionallySizedBox(
      heightFactor: 0.7,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('تعديلات الملفات في هذه المحادثة', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: body),
      ]),
    );
  }
}

void showInspector(BuildContext context, ChatSession session) {
  final text = describeRequest(session);
  int inTok = 0;
  int outTok = 0;
  bool exact = false;
  int cacheTok = 0;
  for (final m in session.messages.reversed) {
    if (m.role == 'assistant' && (m.inTok > 0 || m.outTok > 0)) {
      inTok = m.inTok;
      outTok = m.outTok;
      cacheTok = m.cacheTok;
      exact = m.tokExact;
      break;
    }
  }
  int excluded = 0;
  int est = 0;
  for (final m in session.messages) {
    if (m.excluded) {
      excluded++;
    } else {
      est += estimateTokens(m.content);
    }
  }
  showSheet<void>(context, (c) {
    final p = pal(c);
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetHandle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(children: [
            Expanded(child: Text('ما يراه النموذج بالحرف', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600))),
            IconButton(
              tooltip: 'نسخ',
              icon: Icon(Icons.copy_rounded, size: 20, color: p.muted),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                toast('تم النسخ');
              },
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '${session.messages.length} رسالة${excluded > 0 ? ' ($excluded مستبعدة)' : ''} · ${exact ? '' : '~'}$inTok دخل${cacheTok > 0 ? ' (⚡$cacheTok من الكاش)' : ''} / ${exact ? '' : '~'}$outTok خرج · تقدير النصوص ~$est${session.ctxDropped > 0 ? ' · ${session.ctxDropped} رسالة قديمة خارج السياق' : ''}',
            style: TextStyle(color: p.muted, fontSize: 12.5),
          ),
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(text, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.45, color: p.text)),
            ),
          ),
        ),
      ]),
    );
  });
}

void exportConversation(BuildContext context, ChatSession session) {
  if (session.messages.isEmpty) {
    toast('المحادثة فارغة');
    return;
  }
  showExportSheet(context, session.meta.title.isEmpty ? 'chat' : session.meta.title, conversationToMarkdown(session.meta, session.messages));
}
