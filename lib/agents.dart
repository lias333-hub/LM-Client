part of 'main.dart';

// ---------------------------------------------------------------------
// Agents: يحدد ما تستطيع الأدوات فعله (قراءة / كتابة / ويب) وأي مجلدات.
// بدون Agent مختار لا تصل أدوات الملفات إلى النموذج.
// ---------------------------------------------------------------------

String _agentSummary(Agent a) {
  final perms = <String>[];
  if (a.canRead) perms.add('قراءة');
  if (a.canWrite) perms.add('كتابة');
  if (a.canExecute) perms.add('ويب');
  if (a.canShell) perms.add('Terminal');
  if (perms.isEmpty) perms.add('بدون صلاحيات');
  final folders = a.allowedPaths.where((e) => e.trim().isNotEmpty).length;
  perms.add(folders == 0 ? 'كل التخزين المشترك' : '$folders مجلد');
  return perms.join(' · ');
}

void _openAgents(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AgentsScreen()));
}

Future<void> showAgentPicker(BuildContext context) {
  return showSheet<void>(context, (c) {
    return Consumer(builder: (ctx, ref, _) {
      final p = pal(ctx);
      final agents = ref.watch(agentsProvider);
      final selected = ref.watch(selectedAgentProvider);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const SheetHandle(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  SheetAction(
                    icon: selected == null ? Icons.check_circle : Icons.circle_outlined,
                    title: 'بدون Agent',
                    subtitle: 'محادثة فقط، بدون أدوات الملفات',
                    onTap: () {
                      ref.read(selectedAgentProvider.notifier).choose(null);
                      Navigator.pop(c);
                    },
                  ),
                  for (final a in agents)
                    SheetAction(
                      icon: selected == a.id ? Icons.check_circle : Icons.circle_outlined,
                      title: a.name.isEmpty ? 'Agent' : a.name,
                      subtitle: _agentSummary(a),
                      onTap: () {
                        ref.read(selectedAgentProvider.notifier).choose(a.id);
                        Navigator.pop(c);
                      },
                    ),
                  Divider(height: 1, color: p.border),
                  SheetAction(
                    icon: Icons.terminal,
                    title: 'بيئة التنفيذ (Bash)',
                    subtitle: ref.watch(selectedWorkspaceProvider) == null ? 'غير مفعّلة' : 'مفعّلة',
                    onTap: () {
                      Navigator.pop(c);
                      showWorkspacePicker(context);
                    },
                  ),
                  SheetAction(
                    icon: Icons.tune,
                    title: 'إدارة الـ Agents',
                    onTap: () {
                      Navigator.pop(c);
                      _openAgents(context);
                    },
                  ),
                ],
              ),
            ),
          ]),
        ),
      );
    });
  });
}

class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});

  void _edit(BuildContext context, [Agent? a]) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AgentEditorScreen(agent: a)));
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Agent a, bool isSelected) async {
    final ok = await confirmDialog(context, 'حذف Agent', 'حذف "${a.name}"؟');
    if (!ok) return;
    if (isSelected) await ref.read(selectedAgentProvider.notifier).choose(null);
    await ref.read(agentsProvider.notifier).remove(a.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = pal(context);
    final agents = ref.watch(agentsProvider);
    final selected = ref.watch(selectedAgentProvider);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: p.text),
        title: Text('Agents', style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w600)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Agent جديد'),
      ),
      body: agents.isEmpty
          ? const EmptyHint(icon: Icons.smart_toy_outlined, text: 'لا يوجد Agents بعد. أنشئ واحداً لتفعيل أدوات الملفات.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              itemCount: agents.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'الـ Agent يحدد ما تستطيع الأدوات فعله: قراءة، كتابة، وصول للويب، وأي مجلدات مسموحة. اختر واحداً ليعمل في المحادثة.',
                      style: TextStyle(color: p.muted, fontSize: 13, height: 1.5),
                    ),
                  );
                }
                final a = agents[i - 1];
                final on = a.id == selected;
                return _AgentCard(
                  agent: a,
                  active: on,
                  onTap: () => _edit(context, a),
                  onToggle: () => ref.read(selectedAgentProvider.notifier).choose(on ? null : a.id),
                  onDelete: () => _delete(context, ref, a, on),
                );
              },
            ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final Agent agent;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  const _AgentCard({required this.agent, required this.active, required this.onTap, required this.onToggle, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        decoration: cardDeco(p, selected: active),
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(children: <Widget>[
          Icon(Icons.smart_toy_outlined, color: active ? p.accent : p.muted, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(agent.name.isEmpty ? 'Agent' : agent.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.text, fontSize: 15.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(_agentSummary(agent), style: TextStyle(color: p.muted, fontSize: 12.5)),
            ]),
          ),
          IconButton(
            tooltip: active ? 'إلغاء التفعيل' : 'تفعيل',
            icon: Icon(active ? Icons.check_circle : Icons.circle_outlined, color: active ? p.accent : p.muted),
            onPressed: onToggle,
          ),
          IconButton(tooltip: 'حذف', icon: Icon(Icons.delete_outline, color: p.muted), onPressed: onDelete),
        ]),
      ),
    );
  }
}

class AgentEditorScreen extends ConsumerStatefulWidget {
  final Agent? agent;
  const AgentEditorScreen({super.key, this.agent});

  @override
  ConsumerState<AgentEditorScreen> createState() => _AgentEditorScreenState();
}

class _AgentEditorScreenState extends ConsumerState<AgentEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _prompt;
  late bool _read;
  late bool _write;
  late bool _exec;
  late bool _shell;
  late List<String> _paths;

  @override
  void initState() {
    super.initState();
    final a = widget.agent;
    _name = TextEditingController(text: a?.name ?? '');
    _prompt = TextEditingController(text: a?.systemPrompt ?? '');
    _read = a?.canRead ?? true;
    _write = a?.canWrite ?? false;
    _exec = a?.canExecute ?? false;
    _shell = a?.canShell ?? false;
    _paths = List<String>.of(a?.allowedPaths ?? const <String>[]);
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    await PhoneStorage.requestPermissions();
    try {
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null || dir.trim().isEmpty) return;
      if (!_paths.contains(dir)) setState(() => _paths.add(dir));
    } catch (e) {
      toast('تعذر اختيار المجلد: $e');
    }
  }

  Future<void> _typePath() async {
    final t = await askText(context, 'مسار مجلد', hint: 'مثلاً: Download/project');
    if (t == null || t.trim().isEmpty) return;
    final v = t.trim();
    if (!_paths.contains(v)) setState(() => _paths.add(v));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast('أدخل اسماً للـ Agent');
      return;
    }
    final a = Agent(
      id: widget.agent?.id ?? newId(),
      name: name,
      systemPrompt: _prompt.text.trim(),
      allowedPaths: List<String>.of(_paths),
      canRead: _read,
      canWrite: _write,
      canExecute: _exec,
      canShell: _shell,
    );
    await ref.read(agentsProvider.notifier).upsert(a);
    if (widget.agent == null && ref.read(selectedAgentProvider) == null) {
      await ref.read(selectedAgentProvider.notifier).choose(a.id);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _pad(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: w);

  Widget _switchTile(Pal p, IconData icon, String title, String sub, bool v, ValueChanged<bool> on) {
    return SwitchListTile(
      value: v,
      onChanged: on,
      activeColor: p.accent,
      secondary: Icon(icon, color: p.muted),
      title: Text(title, style: TextStyle(color: p.text, fontSize: 15)),
      subtitle: Text(sub, style: TextStyle(color: p.muted, fontSize: 12.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: p.text),
        title: Text(widget.agent == null ? 'Agent جديد' : 'تعديل Agent', style: TextStyle(color: p.text, fontSize: 18, fontWeight: FontWeight.w600)),
        actions: <Widget>[
          TextButton(onPressed: _save, child: Text('حفظ', style: TextStyle(color: p.accent, fontSize: 15, fontWeight: FontWeight.w600))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: <Widget>[
          const SectionLabel('الاسم'),
          _pad(TextField(controller: _name, style: TextStyle(color: p.text), decoration: fieldDeco(context, hint: 'مثلاً: مساعد المشروع'))),
          const SectionLabel('التعليمات (اختياري)'),
          _pad(TextField(
            controller: _prompt,
            minLines: 3,
            maxLines: 6,
            style: TextStyle(color: p.text),
            decoration: fieldDeco(context, hint: 'كيف يتصرف هذا الـ Agent؟ تُضاف إلى تعليمات النظام.'),
          )),
          const SectionLabel('الصلاحيات'),
          _pad(Container(
            decoration: cardDeco(p),
            clipBehavior: Clip.antiAlias,
            child: Column(children: <Widget>[
              _switchTile(p, Icons.folder_open_outlined, 'قراءة الملفات', 'عرض المجلدات وقراءة وبحث الملفات', _read, (v) {
                setState(() {
                  _read = v;
                  if (!v) _write = false;
                });
              }),
              Divider(height: 1, color: p.border),
              _switchTile(p, Icons.edit_outlined, 'الكتابة والتعديل', 'إنشاء الملفات وتعديلها (مع طلب موافقتك)', _write, (v) {
                setState(() {
                  _write = v;
                  if (v) _read = true;
                });
              }),
              Divider(height: 1, color: p.border),
              _switchTile(p, Icons.public, 'الوصول للويب', 'جلب صفحات الإنترنت (fetch_url)', _exec, (v) => setState(() => _exec = v)),
              Divider(height: 1, color: p.border),
              _switchTile(p, Icons.terminal, 'تنفيذ أوامر (Termux)', 'يتطلب ربط Termux. كل أمر يطلب موافقتك', _shell, (v) => setState(() => _shell = v)),
            ]),
          )),
          const SectionLabel('المجلدات المسموحة'),
          _pad(Container(
            decoration: cardDeco(p),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              if (_paths.isEmpty)
                Text('بدون مجلدات محددة = كل التخزين المشترك. حدّد مجلداً لتقييد الوصول.', style: TextStyle(color: p.muted, fontSize: 13, height: 1.5))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final path in _paths)
                      InputChip(
                        label: Text(path, style: TextStyle(color: p.text, fontSize: 12.5)),
                        backgroundColor: p.surfaceHi,
                        side: BorderSide(color: p.border),
                        onDeleted: () => setState(() => _paths.remove(path)),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              Row(children: <Widget>[
                TextButton.icon(onPressed: _pickFolder, icon: const Icon(Icons.create_new_folder_outlined, size: 20), label: const Text('اختيار مجلد')),
                TextButton.icon(onPressed: _typePath, icon: const Icon(Icons.keyboard_outlined, size: 20), label: const Text('كتابة مسار')),
              ]),
            ]),
          )),
        ],
      ),
    );
  }
}

/// منتقي المزوّد والموديل (يُستدعى من خانة الكتابة ومن /model).
Future<void> showModelPicker(BuildContext context, [Object? profile]) {
  return showSheet<void>(context, (c) {
    return Consumer(builder: (ctx, ref, _) {
      final ps = ref.watch(profilesProvider);
      final cur = ps.selected;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const SheetHandle(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  if (ps.list.length > 1) ...<Widget>[
                    const SectionLabel('المزوّد'),
                    for (final pr in ps.list)
                      SheetAction(
                        icon: (cur != null && pr.id == cur.id) ? Icons.check_circle : Icons.circle_outlined,
                        title: pr.name,
                        subtitle: pr.selectedModel,
                        onTap: () => ref.read(profilesProvider.notifier).select(pr.id),
                      ),
                  ],
                  const SectionLabel('الموديل'),
                  if (cur == null || cur.models.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('لا توجد موديلات. أضفها من الإعدادات > مزوّدو الـ API.', style: TextStyle(color: pal(ctx).muted, fontSize: 13.5)),
                    )
                  else
                    for (final m in cur.models)
                      SheetAction(
                        icon: m == cur.selectedModel ? Icons.check_circle : Icons.circle_outlined,
                        title: m,
                        onTap: () {
                          ref.read(profilesProvider.notifier).setModel(m);
                          Navigator.pop(c);
                        },
                      ),
                ],
              ),
            ),
          ]),
        ),
      );
    });
  });
}
