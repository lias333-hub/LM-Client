part of 'main.dart';

// =====================================================================
//  واجهات البيئة: شاشة الموافقة على الأمر، قائمة البيئات، إعداد الاتصال، الطرفية
// =====================================================================

// ---------------------------------------------------------------------
//  Approval sheet
// ---------------------------------------------------------------------
class BashApprovalSheet extends StatefulWidget {
  final WorkspaceConfig ws;
  final String cwd;
  final String command;
  final String description;
  const BashApprovalSheet({super.key, required this.ws, required this.cwd, required this.command, required this.description});
  @override
  State<BashApprovalSheet> createState() => _BashApprovalSheetState();
}

class _BashApprovalSheetState extends State<BashApprovalSheet> {
  late String _cmd;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _cmd = widget.command;
  }

  void _done(bool allow, {String prefix = '', String reason = ''}) {
    Navigator.pop(context, BashDecision(allow: allow, command: _cmd, prefix: prefix, reason: reason));
  }

  Future<void> _edit() async {
    final String? r = await askText(context, 'تعديل الأمر', initial: _cmd, multiline: true);
    if (r != null && r.trim().isNotEmpty) {
      setState(() {
        _cmd = r;
        _edited = true;
      });
    }
  }

  Future<void> _denyWithReason() async {
    final String? r = await askText(context, 'سبب الرفض (اختياري)', hint: 'يصل إلى Claude ليعدّل خطته');
    if (r == null) return;
    _done(false, reason: r.trim());
  }

  Widget _tag(Pal p, String t) {
    final bool danger = t == 'خطر' || t == 'يلمس بيانات التطبيق الخاصة';
    final Color c = danger ? p.danger : p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withAlpha(28), borderRadius: BorderRadius.circular(99)),
      child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w500)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    final bool local = widget.ws.isLocal;
    final bool priv = local && LocalExec.touchesPrivate(_cmd);
    final List<String> tags = BashPolicy.riskTags(_cmd, local: local);
    final bool danger = BashPolicy.isDangerous(_cmd) || priv;
    final String? prefix = priv ? null : BashPolicy.prefixFor(_cmd);
    final double maxH = MediaQuery.of(context).size.height * 0.9;
    final ButtonStyle big = FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)));
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(color: p.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetHandle(),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.accent.withAlpha(36), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.terminal, color: p.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('يريد Claude تشغيل أمر', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('${widget.ws.name} · ${widget.cwd.isEmpty ? '~' : widget.cwd}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 11.5, fontFamily: 'monospace')),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: danger ? p.danger : p.border)),
              child: Column(children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: SelectableText('\$ ' + _cmd, style: TextStyle(color: p.codeText, fontSize: 13, height: 1.5, fontFamily: 'monospace')),
                    ),
                  ),
                ),
                Divider(height: 1, color: p.border),
                Row(children: [
                  Expanded(child: TextButton.icon(onPressed: _edit, icon: Icon(Icons.edit_outlined, size: 16, color: p.muted), label: Text('تعديل الأمر', style: TextStyle(color: p.text, fontSize: 13)))),
                  Container(width: 1, height: 24, color: p.border),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _cmd));
                        toast('تم النسخ');
                      },
                      icon: Icon(Icons.copy, size: 15, color: p.muted),
                      label: Text('نسخ', style: TextStyle(color: p.text, fontSize: 13)),
                    ),
                  ),
                ]),
              ]),
            ),
            if (tags.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: tags.map((String t) => _tag(p, t)).toList()),
            ],
            if (widget.description.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text('وصف Claude: ${widget.description}', style: TextStyle(color: p.muted, fontSize: 13, height: 1.5)),
            ],
            if (danger) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                  priv && !BashPolicy.isDangerous(_cmd)
                      ? 'هذا الأمر يشير إلى مجلدات التطبيق الخاصة (فيها مفاتيح API المحفوظة). تأكد أنك تريد ذلك.'
                      : 'هذا الأمر قد يحذف أو يغيّر أشياء لا يمكن التراجع عنها. راجعه جيداً.',
                  style: TextStyle(color: p.danger, fontSize: 13, height: 1.5)),
            ],
            const SizedBox(height: 14),
            FilledButton(onPressed: () => _done(true), style: big, child: Text(_edited ? 'السماح بالأمر المعدّل' : 'السماح مرة واحدة', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
            if (prefix != null) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _done(true, prefix: prefix),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('السماح لـ «$prefix» في هذه المحادثة', style: const TextStyle(fontSize: 14)),
              ),
            ],
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: TextButton(onPressed: () => _done(false), child: Text('رفض', style: TextStyle(color: p.danger, fontSize: 14)))),
              Expanded(child: TextButton(onPressed: _denyWithReason, child: Text('رفض مع سبب', style: TextStyle(color: p.danger, fontSize: 14)))),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Workspaces list
// ---------------------------------------------------------------------
class WorkspacesScreen extends ConsumerWidget {
  const WorkspacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Pal p = pal(context);
    final List<WorkspaceConfig> list = ref.watch(workspacesProvider);
    final String? sel = ref.watch(selectedWorkspaceProvider);
    final AppSettings s = ref.watch(settingsProvider);
    final bool auto = s.bashApproval == 'auto';
    return Scaffold(
      appBar: AppBar(title: const Text('بيئات التنفيذ')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => pushScreen(const WorkspaceEditor()),
        icon: const Icon(Icons.add),
        label: const Text('بيئة جديدة'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 110),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(12)),
            child: Text(
              'البيئة تعطي Claude طرفية. «هذا الهاتف» مدمجة في التطبيق (sh النظام، بدون git/python/node). وللأدوات الكاملة (git، اختبارات، بناء، بايثون…) أضف Termux أو أي خادم عبر SSH. اختر بيئة واحدة لتفعيلها، وكل أمر يطلب موافقتك.',
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.5),
            ),
          ),
          const SectionLabel('الموافقة على الأوامر'),
          SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'ask', label: Text('اسأل عن كل أمر')),
              ButtonSegment<String>(value: 'auto', label: Text('تلقائي')),
            ],
            selected: <String>{auto ? 'auto' : 'ask'},
            onSelectionChanged: (Set<String> v) => ref.read(settingsProvider.notifier).set('bashApproval', v.first),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              auto
                  ? 'تُنفَّذ الأوامر دون سؤال عدا الخطرة (rm -r، sudo، git push --force…). هذه القائمة تنبيه وليست حماية كاملة، فاستعمل هذا الوضع في بيئة تحتمل الخطأ.'
                  : 'يظهر لك كل أمر قبل تنفيذه، ويمكنك تعديله أو السماح لبادئة محددة (مثل git status) لبقية المحادثة.',
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.5),
            ),
          ),
          const SectionLabel('البيئات'),
          _localWorkspaceCard(p, ref, sel == kLocalWorkspaceId),
          if (list.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 24), child: EmptyHint(icon: Icons.terminal, text: 'لا توجد بيئات SSH.\nأضف Termux أو خادماً للأدوات الكاملة.')),
          ...list.map((WorkspaceConfig w) {
            final bool on = sel == w.id;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? p.accent : p.border)),
              child: ListTile(
                onTap: () => ref.read(selectedWorkspaceProvider.notifier).choose(on ? null : w.id),
                leading: Icon(on ? Icons.check_circle : Icons.circle_outlined, color: on ? p.accent : p.muted),
                title: Text(w.name, style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: Directionality(textDirection: TextDirection.ltr, child: Text(w.address, style: TextStyle(color: p.muted, fontSize: 12, fontFamily: 'monospace'))),
                trailing: PopupMenuButton<String>(
                  onSelected: (String v) async {
                    if (v == 'terminal') {
                      pushScreen(TerminalScreen(ws: w));
                    } else if (v == 'edit') {
                      pushScreen(WorkspaceEditor(existing: w));
                    } else if (v == 'delete') {
                      final bool ok = await askConfirm('حذف البيئة؟', 'سيُحذف الاتصال "${w.name}" من التطبيق (لا يُمسّ الخادم).', ok: 'حذف');
                      if (!ok) return;
                      SshPool.drop(w.id);
                      if (ref.read(selectedWorkspaceProvider) == w.id) await ref.read(selectedWorkspaceProvider.notifier).choose(null);
                      await ref.read(workspacesProvider.notifier).remove(w.id);
                    }
                  },
                  itemBuilder: (BuildContext c) => const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(value: 'terminal', child: Text('فتح الطرفية')),
                    PopupMenuItem<String>(value: 'edit', child: Text('تعديل')),
                    PopupMenuItem<String>(value: 'delete', child: Text('حذف')),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

Widget _localWorkspaceCard(Pal p, WidgetRef ref, bool on) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? p.accent : p.border)),
    child: ListTile(
      onTap: () => ref.read(selectedWorkspaceProvider.notifier).choose(on ? null : kLocalWorkspaceId),
      leading: Icon(on ? Icons.check_circle : Icons.circle_outlined, color: on ? p.accent : p.muted),
      title: Row(children: <Widget>[
        Flexible(child: Text('هذا الهاتف', style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: p.accent.withAlpha(30), borderRadius: BorderRadius.circular(99)),
          child: Text('مدمج', style: TextStyle(color: p.accent, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('بدون أي تطبيق آخر · sh + toybox فقط (لا git ولا python ولا node). يعمل بصلاحيات التطبيق، فراجع كل أمر قبل الموافقة.', style: TextStyle(color: p.muted, fontSize: 12, height: 1.45)),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (String v) {
          if (v == 'probe') pushScreen(const ExecProbeScreen());
        },
        itemBuilder: (BuildContext c) => const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(value: 'probe', child: Text('اختبار التنفيذ والطرفية')),
        ],
      ),
    ),
  );
}

/// اختيار سريع للبيئة من شريط المحادثة (مع قائمة الـ Agents).
Future<void> showWorkspacePicker(BuildContext context) {
  return showSheet<void>(context, (BuildContext c) {
    return Consumer(builder: (BuildContext c, WidgetRef ref, Widget? _) {
      final List<WorkspaceConfig> list = ref.watch(workspacesProvider);
      final String? sel = ref.watch(selectedWorkspaceProvider);
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const SheetHandle(),
          SheetAction(
            icon: sel == null ? Icons.check_circle : Icons.circle_outlined,
            title: 'بدون بيئة تنفيذ',
            subtitle: 'لا أوامر bash',
            onTap: () {
              ref.read(selectedWorkspaceProvider.notifier).choose(null);
              Navigator.pop(c);
            },
          ),
          SheetAction(
            icon: sel == kLocalWorkspaceId ? Icons.check_circle : Icons.circle_outlined,
            title: 'هذا الهاتف (مدمج)',
            subtitle: 'sh النظام · بدون git/python/node',
            onTap: () {
              ref.read(selectedWorkspaceProvider.notifier).choose(kLocalWorkspaceId);
              Navigator.pop(c);
            },
          ),
          ...list.map((WorkspaceConfig w) => SheetAction(
                icon: sel == w.id ? Icons.check_circle : Icons.circle_outlined,
                title: w.name,
                subtitle: w.address,
                onTap: () {
                  ref.read(selectedWorkspaceProvider.notifier).choose(w.id);
                  Navigator.pop(c);
                },
              )),
          SheetAction(
            icon: Icons.add,
            title: 'إدارة البيئات',
            onTap: () {
              Navigator.pop(c);
              pushScreen(const WorkspacesScreen());
            },
          ),
          const SizedBox(height: 8),
        ]),
      );
    });
  });
}

// ---------------------------------------------------------------------
//  Connect / edit
// ---------------------------------------------------------------------
class WorkspaceEditor extends ConsumerStatefulWidget {
  final WorkspaceConfig? existing;
  const WorkspaceEditor({super.key, this.existing});
  @override
  ConsumerState<WorkspaceEditor> createState() => _WorkspaceEditorState();
}

class _WorkspaceEditorState extends ConsumerState<WorkspaceEditor> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _dir;
  late final TextEditingController _pass;
  late bool _termux;
  String _key = '';
  String _fp = '';
  bool _testing = false;
  String _result = '';
  bool _resultOk = false;

  @override
  void initState() {
    super.initState();
    final WorkspaceConfig? w = widget.existing;
    _termux = w == null ? true : w.isTermux;
    _name = TextEditingController(text: w == null ? 'termux' : w.name);
    _host = TextEditingController(text: w == null ? '127.0.0.1' : w.host);
    _port = TextEditingController(text: w == null ? '8022' : '${w.port}');
    _user = TextEditingController(text: w == null ? '' : w.user);
    _dir = TextEditingController(text: w == null ? '' : w.startDir);
    _pass = TextEditingController(text: w == null ? '' : w.password);
    _key = w == null ? '' : w.keyPem;
    _fp = w == null ? '' : w.hostFp;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _dir.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _setKind(bool termux) {
    setState(() {
      _termux = termux;
      _fp = '';
      if (termux) {
        _host.text = '127.0.0.1';
        _port.text = '8022';
        if (_name.text.trim().isEmpty || _name.text.trim() == 'server') _name.text = 'termux';
      } else {
        if (_host.text.trim() == '127.0.0.1') _host.text = '';
        _port.text = '22';
        if (_name.text.trim() == 'termux') _name.text = 'server';
      }
    });
  }

  WorkspaceConfig _cfg() {
    final String id = widget.existing == null ? newId() : widget.existing!.id;
    return WorkspaceConfig(
      id: id,
      name: _name.text.trim().isEmpty ? 'بيئة' : _name.text.trim(),
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? 22,
      user: _user.text.trim(),
      keyPem: _key,
      password: _pass.text,
      startDir: _dir.text.trim(),
      hostFp: _fp,
      isTermux: _termux,
    );
  }

  String? _problem() {
    if (_host.text.trim().isEmpty) return 'اكتب عنوان الخادم.';
    if (_user.text.trim().isEmpty) return _termux ? 'اكتب اسم المستخدم (الأمر whoami في Termux).' : 'اكتب اسم المستخدم.';
    if (_key.trim().isEmpty && _pass.text.isEmpty) return 'أنشئ مفتاحاً أو اكتب كلمة مرور.';
    return null;
  }

  void _genKey() {
    final GeneratedKey g = SshKeys.generate('lmclient');
    setState(() {
      _key = g.pem;
      _result = '';
    });
  }

  String _pub() => _key.trim().isEmpty ? '' : SshKeys.publicLineOf(_key, 'lmclient');

  String _termuxScript() {
    return 'pkg install -y openssh\nmkdir -p ~/.ssh\necho \'${_pub()}\' >> ~/.ssh/authorized_keys\nchmod 600 ~/.ssh/authorized_keys\nsshd\nwhoami';
  }

  Future<void> _test() async {
    final String? pr = _problem();
    if (pr != null) {
      setState(() {
        _result = pr;
        _resultOk = false;
      });
      return;
    }
    setState(() {
      _testing = true;
      _result = '';
    });
    final Stopwatch sw = Stopwatch()..start();
    String out = '';
    bool ok = false;
    try {
      final String r = await SshExec.probe(_cfg(), onFingerprint: (String fp) => _fp = fp).timeout(const Duration(seconds: 45));
      ok = r.contains('user:');
      out = ok ? 'الاتصال ناجح · ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} ث\n${r.trim()}' : 'اتصل لكن الاستجابة غير متوقعة:\n${r.trim()}';
    } catch (e) {
      out = sshErrorText(e);
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = out;
      _resultOk = ok;
    });
  }

  Future<void> _save() async {
    final String? pr = _problem();
    if (pr != null) {
      toast(pr);
      return;
    }
    final WorkspaceConfig c = _cfg();
    SshPool.drop(c.id);
    await ref.read(workspacesProvider.notifier).upsert(c);
    if (ref.read(selectedWorkspaceProvider) == null) await ref.read(selectedWorkspaceProvider.notifier).choose(c.id);
    if (mounted) Navigator.pop(context);
  }

  Widget _field(Pal p, String label, TextEditingController c, {bool mono = true, bool obscure = false, TextInputType? type, void Function(String)? onChanged, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(label, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: c,
            obscureText: obscure,
            keyboardType: type,
            onChanged: onChanged,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: p.text, fontSize: 14, fontFamily: mono ? 'monospace' : null),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              filled: true,
              fillColor: p.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: p.border)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _kindCard(Pal p, String title, String sub, IconData icon, bool on, VoidCallback tap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: on ? p.accent.withAlpha(30) : p.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? p.accent : p.border, width: on ? 1.5 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Row(children: <Widget>[
              Icon(icon, size: 18, color: on ? p.accent : p.text),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: on ? p.accent : p.text, fontSize: 14, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            Text(sub, style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    final String pub = _pub();
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'ربط بيئة تنفيذ' : 'تعديل البيئة')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          Row(children: <Widget>[
            _kindCard(p, 'Termux', 'على هذا الهاتف نفسه، بلا خادم', Icons.smartphone, _termux, () => _setKind(true)),
            const SizedBox(width: 10),
            _kindCard(p, 'خادم SSH', 'جهاز يعمل دائماً أو VPS', Icons.dns_outlined, !_termux, () => _setKind(false)),
          ]),
          const SizedBox(height: 16),
          if (_termux)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.surfaceHi, borderRadius: BorderRadius.circular(12)),
              child: Text(
                'ثبّت Termux من F-Droid (نسخة متجر Play قديمة ومعطّلة). افتحه ونفّذ الأوامر التي تظهر بعد إنشاء المفتاح أدناه مرة واحدة، ثم اكتب في الحقل المستخدم ناتج الأمر whoami. ملاحظة: قد يوقف أندرويد عمليات Termux الخلفية إذا قيّد توفير الطاقة، فاستثنِه من تحسين البطارية.',
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.5),
              ),
            ),
          const SizedBox(height: 14),
          _field(p, 'الاسم', _name, mono: false),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(flex: 2, child: _field(p, 'العنوان', _host, type: TextInputType.url, onChanged: (String _) => _fp = '')),
            const SizedBox(width: 10),
            Expanded(child: _field(p, 'المنفذ', _port, type: TextInputType.number, onChanged: (String _) => _fp = '')),
          ]),
          _field(p, 'المستخدم', _user, hint: _termux ? 'u0_a123' : 'ubuntu'),
          _field(p, 'مجلد البداية (اختياري)', _dir, hint: '~/projects'),
          const SectionLabel('الدخول'),
          if (pub.isEmpty)
            OutlinedButton.icon(
              onPressed: _genKey,
              icon: const Icon(Icons.key, size: 18),
              label: const Text('إنشاء مفتاح ed25519 داخل التطبيق'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            )
          else ...<Widget>[
            Container(
              decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
              child: Column(children: <Widget>[
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(_termux ? _termuxScript() : pub, style: TextStyle(color: p.codeText, fontSize: 11.5, height: 1.5, fontFamily: 'monospace')),
                  ),
                ),
                Divider(height: 1, color: p.border),
                Row(children: <Widget>[
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _termux ? _termuxScript() : pub));
                        toast(_termux ? 'نُسخت أوامر Termux' : 'نُسخ المفتاح العام');
                      },
                      icon: Icon(Icons.copy, size: 15, color: p.muted),
                      label: Text(_termux ? 'نسخ أوامر Termux' : 'نسخ المفتاح العام', style: TextStyle(color: p.text, fontSize: 13)),
                    ),
                  ),
                  Container(width: 1, height: 24, color: p.border),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _genKey,
                      icon: Icon(Icons.refresh, size: 16, color: p.muted),
                      label: Text('مفتاح جديد', style: TextStyle(color: p.text, fontSize: 13)),
                    ),
                  ),
                ]),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                _termux ? 'المفتاح الخاص يبقى داخل التطبيق ولا يغادر الهاتف.' : 'ألصق المفتاح العام في ~/.ssh/authorized_keys على الخادم. المفتاح الخاص يبقى داخل التطبيق.',
                style: TextStyle(color: p.muted, fontSize: 12, height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _field(p, 'أو كلمة مرور (أقل أماناً، اختياري)', _pass, obscure: true),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bolt, size: 18),
            label: Text(_testing ? 'جارٍ الاختبار…' : 'اختبار الاتصال'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
          if (_result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_resultOk ? p.success : p.danger).withAlpha(26),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: (_resultOk ? p.success : p.danger).withAlpha(90)),
              ),
              child: Directionality(
                textDirection: _resultOk ? TextDirection.ltr : Directionality.of(context),
                child: Text(_result, style: TextStyle(color: p.text, fontSize: 12.5, height: 1.5, fontFamily: _resultOk ? 'monospace' : null)),
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('حفظ البيئة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  Terminal
// ---------------------------------------------------------------------
class TerminalScreen extends StatefulWidget {
  final WorkspaceConfig ws;
  const TerminalScreen({super.key, required this.ws});
  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final xt.Terminal _term = xt.Terminal(maxLines: 5000);
  final xt.TerminalController _ctl = xt.TerminalController();
  ssh.SSHSession? _sess;
  StreamSubscription<String>? _subOut;
  StreamSubscription<String>? _subErr;
  String _status = 'connecting';
  String _error = '';
  bool _ctrl = false;
  bool _alt = false;

  @override
  void initState() {
    super.initState();
    _term.onOutput = _onTermOutput;
    _term.onResize = (int w, int h, int pw, int ph) {
      final ssh.SSHSession? s = _sess;
      if (s != null) {
        try {
          s.resizeTerminal(w, h, pw, ph);
        } catch (_) {}
      }
    };
    _connect();
  }

  @override
  void dispose() {
    _subOut?.cancel();
    _subErr?.cancel();
    final ssh.SSHSession? s = _sess;
    if (s != null) {
      try {
        s.close();
      } catch (_) {}
    }
    _ctl.dispose();
    super.dispose();
  }

  void _send(String data) {
    final ssh.SSHSession? s = _sess;
    if (s == null) return;
    try {
      s.write(Uint8List.fromList(utf8.encode(data)));
    } catch (_) {}
  }

  void _onTermOutput(String data) {
    String d = data;
    if (_ctrl && d.length == 1) {
      final int c = d.codeUnitAt(0);
      if (c >= 0x61 && c <= 0x7a) {
        d = String.fromCharCode(c - 0x60);
      } else if (c >= 0x41 && c <= 0x5a) {
        d = String.fromCharCode(c - 0x40);
      }
      setState(() => _ctrl = false);
    }
    if (_alt && d.length == 1) {
      d = '\x1b' + d;
      setState(() => _alt = false);
    }
    _send(d);
  }

  Future<void> _connect() async {
    setState(() {
      _status = 'connecting';
      _error = '';
    });
    try {
      final ssh.SSHClient c = await SshPool.get(widget.ws);
      final ssh.SSHSession s = await c.shell(pty: ssh.SSHPtyConfig(width: _term.viewWidth, height: _term.viewHeight));
      if (!mounted) {
        s.close();
        return;
      }
      _sess = s;
      _subOut = const Utf8Decoder(allowMalformed: true).bind(s.stdout).listen((String d) => _term.write(d));
      _subErr = const Utf8Decoder(allowMalformed: true).bind(s.stderr).listen((String d) => _term.write(d));
      s.done.then((_) {
        if (mounted) setState(() => _status = 'closed');
      }, onError: (Object e) {
        if (mounted) setState(() => _status = 'closed');
      });
      setState(() => _status = 'ready');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'error';
        _error = sshErrorText(e);
      });
    }
  }

  void _key(xt.TerminalKey k) {
    _term.keyInput(k, ctrl: _ctrl, alt: _alt);
    if (_ctrl || _alt) {
      setState(() {
        _ctrl = false;
        _alt = false;
      });
    }
  }

  Widget _qk(String label, VoidCallback onTap, {bool active = false}) {
    final Pal p = pal(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: active ? p.accent.withAlpha(60) : p.surfaceHi,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              height: 40,
              child: Center(child: Text(label, style: TextStyle(color: active ? p.accent : p.text, fontSize: 12.5, fontFamily: 'monospace'))),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(widget.ws.name, style: const TextStyle(fontSize: 16)),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: _status == 'ready' ? p.success : (_status == 'connecting' ? p.muted : p.danger))),
              const SizedBox(width: 6),
              Text(widget.ws.address, style: TextStyle(color: p.muted, fontSize: 11, fontFamily: 'monospace')),
            ]),
          ),
        ]),
        actions: <Widget>[
          IconButton(
            tooltip: 'إعادة الاتصال',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _subOut?.cancel();
              _subErr?.cancel();
              final ssh.SSHSession? s = _sess;
              if (s != null) {
                try {
                  s.close();
                } catch (_) {}
              }
              _sess = null;
              _connect();
            },
          ),
        ],
      ),
      body: Column(children: <Widget>[
        Expanded(
          child: _status == 'error'
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error, textAlign: TextAlign.center, style: TextStyle(color: p.danger, fontSize: 14, height: 1.6))))
              : xt.TerminalView(_term, controller: _ctl, autofocus: true, padding: const EdgeInsets.all(6), textStyle: const xt.TerminalStyle(fontSize: 13)),
        ),
        if (_status == 'closed')
          Container(
            width: double.infinity,
            color: p.surfaceHi,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(child: Text('انتهت الجلسة. اضغط تحديث لجلسة جديدة.', style: TextStyle(color: p.muted, fontSize: 12.5))),
          ),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            color: p.bg,
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Row(children: <Widget>[
                  _qk('Esc', () => _key(xt.TerminalKey.escape)),
                  _qk('/', () => _term.textInput('/')),
                  _qk('-', () => _term.textInput('-')),
                  _qk('Home', () => _key(xt.TerminalKey.home)),
                  _qk('↑', () => _key(xt.TerminalKey.arrowUp)),
                  _qk('End', () => _key(xt.TerminalKey.end)),
                  _qk('PgUp', () => _key(xt.TerminalKey.pageUp)),
                ]),
                Row(children: <Widget>[
                  _qk('Tab', () => _key(xt.TerminalKey.tab)),
                  _qk('Ctrl', () => setState(() => _ctrl = !_ctrl), active: _ctrl),
                  _qk('Alt', () => setState(() => _alt = !_alt), active: _alt),
                  _qk('←', () => _key(xt.TerminalKey.arrowLeft)),
                  _qk('↓', () => _key(xt.TerminalKey.arrowDown)),
                  _qk('→', () => _key(xt.TerminalKey.arrowRight)),
                  _qk('PgDn', () => _key(xt.TerminalKey.pageDown)),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
