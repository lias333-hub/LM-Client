part of 'main.dart';

// =====================================================================
//  أدوات التخطيط والتفاعل (v2.9.0): todo_write، ask_user_question، وضع التخطيط.
//  لا تغيّر أي واجهة موجودة: شاشتان جديدتان فقط (سؤال المستخدم، موافقة الخطة) تُفتحان كورقة سفلية.
//  الحالة تُستعاد من سجل المحادثة نفسه (نتائج الأدوات محفوظة)، فلا ملف إضافي ولا فقدان عند إعادة التشغيل.
//  وضع التخطيط يُفرض في runTool: أي أداة تعدّل شيئاً تُرفض حتى يوافق المستخدم على الخطة.
// =====================================================================

const String kToolTodoWrite = 'todo_write';
const String kToolAskUser = 'ask_user_question';
const String kToolEnterPlan = 'enter_plan_mode';
const String kToolExitPlan = 'exit_plan_mode';

const Set<String> kTodoStatuses = <String>{'pending', 'in_progress', 'completed'};

class TodoItem {
  final String content;
  final String activeForm;
  final String status;
  const TodoItem(this.content, this.activeForm, this.status);
}

class AskOption {
  final String label;
  final String description;
  const AskOption(this.label, this.description);
}

class AskQuestion {
  final String question;
  final String header;
  final bool multi;
  final List<AskOption> options;
  const AskQuestion(this.question, this.header, this.multi, this.options);
}

class AskAnswer {
  final List<String> picked;
  final String other;
  const AskAnswer(this.picked, this.other);
}

class PlanDecision {
  final bool approved;
  final String feedback;
  const PlanDecision(this.approved, [this.feedback = '']);
}

class PlanState {
  static final Map<String, List<TodoItem>> todos = <String, List<TodoItem>>{};
  static final Set<String> planMode = <String>{};

  /// خطّافات للاختبار الآلي فقط (لا يستطيع النموذج ولا أي إعداد ضبطها).
  static Future<List<AskAnswer>?> Function(List<AskQuestion> qs)? askHook;
  static Future<bool> Function()? enterHook;
  static Future<PlanDecision> Function(String plan)? planHook;

  static bool isPlanMode(String convId) => planMode.contains(convId);

  /// يستعيد وضع التخطيط وقائمة المهام من نتائج الأدوات المحفوظة في المحادثة.
  static void syncFromHistory(String convId, List<ChatMessage> msgs) {
    bool? plan;
    List<TodoItem>? list;
    for (int i = msgs.length - 1; i >= 0; i--) {
      if (plan != null && list != null) break;
      final ChatMessage m = msgs[i];
      if (m.role != 'assistant') continue;
      for (int j = m.toolCalls.length - 1; j >= 0; j--) {
        final ToolCall c = m.toolCalls[j];
        if (c.status != 'done' || c.isError) continue;
        if (plan == null && c.name == kToolEnterPlan) plan = true;
        if (plan == null && c.name == kToolExitPlan) plan = false;
        if (list == null && c.name == kToolTodoWrite) list = _lenientTodos(c.args['todos']);
      }
    }
    if (plan == true) {
      planMode.add(convId);
    } else {
      planMode.remove(convId);
    }
    if (list != null) {
      todos[convId] = list;
    } else {
      todos.remove(convId);
    }
  }
}

List<TodoItem> _lenientTodos(dynamic raw) {
  final List<TodoItem> out = <TodoItem>[];
  for (final dynamic e in asList(raw)) {
    final Map<String, dynamic> m = asMap(e);
    final String content = asStr(m['content']).trim();
    final String status = asStr(m['status']).trim();
    if (content.isEmpty || !kTodoStatuses.contains(status)) continue;
    final String active = asStr(m['activeForm']).trim();
    out.add(TodoItem(content, active.isEmpty ? content : active, status));
  }
  return out;
}

// ---------------------------------------------------------------------
//  تعريف الأدوات وقسم التعليمات
// ---------------------------------------------------------------------
List<ToolDef> planningToolDefs() {
  return <ToolDef>[
    ToolDef(
      kToolTodoWrite,
      'Create and update a task list for the current multi-step job, so the user can follow your progress and you do not lose track. Send the COMPLETE list every time (it replaces the previous one). Each item has content (imperative, e.g. "Run the tests"), activeForm (present continuous, e.g. "Running the tests") and status: pending, in_progress or completed. Keep exactly one item in_progress while you work and mark an item completed immediately after you finish it, not in a batch at the end. Use it for work with three or more steps; do not use it for a trivial one-step request.',
      _obj(<String, dynamic>{
        'todos': <String, dynamic>{
          'type': 'array',
          'description': 'The full todo list',
          'items': _obj(<String, dynamic>{
            'content': _pStr('What to do, imperative form'),
            'activeForm': _pStr('Same task in present continuous form, shown while it runs'),
            'status': <String, dynamic>{'type': 'string', 'enum': <String>['pending', 'in_progress', 'completed'], 'description': 'pending, in_progress or completed'},
          }, <String>['content', 'status']),
        },
      }, <String>['todos']),
    ),
    ToolDef(
      kToolAskUser,
      'Ask the user one to four multiple-choice questions when you are blocked on a decision only they can make (an ambiguous requirement, a real trade-off, a preference). Give 2-4 concrete options per question; the user can always type a different answer. Do not use it for things you can find out yourself with the tools, and do not ask for permission to continue. The reply comes back as the tool result.',
      _obj(<String, dynamic>{
        'questions': <String, dynamic>{
          'type': 'array',
          'description': '1 to 4 questions',
          'items': _obj(<String, dynamic>{
            'question': _pStr('The full question, ending with a question mark'),
            'header': _pStr('A very short label (max 12 characters) shown as a chip'),
            'multiSelect': _pBool('true when several options may be chosen'),
            'options': <String, dynamic>{
              'type': 'array',
              'description': '2 to 4 options',
              'items': _obj(<String, dynamic>{
                'label': _pStr('Short option text (1-5 words)'),
                'description': _pStr('One line saying what choosing it means'),
              }, <String>['label']),
            },
          }, <String>['question', 'options']),
        },
      }, <String>['questions']),
    ),
    ToolDef(
      kToolEnterPlan,
      'Switch to plan mode for a non-trivial change that has several possible approaches or touches many files. The user must agree. In plan mode you can only read and search (no file edits, no commands that change anything); explore, then call exit_plan_mode with your plan. Do not use it for small, obvious changes.',
      _obj(<String, dynamic>{}, <String>[]),
    ),
    ToolDef(
      kToolExitPlan,
      'Present your finished plan to the user for approval and leave plan mode. Write the whole plan in `plan` (Markdown: goal, the files you will change, the steps in order, how you will verify). The user may approve it or send it back with comments; only after approval may you edit files and run commands.',
      _obj(<String, dynamic>{'plan': _pStr('The complete plan in Markdown')}, <String>['plan']),
    ),
  ];
}

String planningPromptSection() {
  return 'Task tracking and questions: for work with three or more steps keep a todo list with $kToolTodoWrite (send the whole list each time, exactly one item in_progress, mark an item completed as soon as it is done); skip it for trivial requests. '
      'When you are blocked on a choice only the user can make, call $kToolAskUser with concrete options instead of guessing or asking in plain text; do not use it for things you can find out yourself. '
      'For a non-trivial change with several possible approaches, call $kToolEnterPlan, explore with read-only tools, then call $kToolExitPlan with a concise plan and wait for approval before changing anything.';
}

// ---------------------------------------------------------------------
//  وضع التخطيط: ما يُسمح به
// ---------------------------------------------------------------------
class PlanPolicy {
  static const Set<String> _ro = <String>{
    'ls', 'cat', 'head', 'tail', 'wc', 'grep', 'egrep', 'fgrep', 'rg', 'tree', 'stat', 'file', 'pwd', 'date', 'whoami', 'uname', 'which',
    'echo', 'du', 'df', 'find', 'git', 'sort', 'uniq', 'cut', 'tr', 'diff', 'basename', 'dirname', 'realpath', 'readlink', 'cd', 'id', 'ps', 'true',
  };
  static const Set<String> _gitRo = <String>{'status', 'log', 'diff', 'show', 'ls-files', 'rev-parse', 'blame', 'shortlog', 'describe', 'grep'};

  /// أمر قراءة فقط بلا تحويل مخرجات ولا استبدال أوامر ولا تسلسل بـ ; أو خلفية.
  static bool bashReadOnly(String cmd) {
    final String c = cmd.trim();
    if (c.isEmpty) return false;
    if (c.contains('>') || c.contains('`') || c.contains(';') || c.contains('\n') || c.contains(r'$(') || c.contains('<(') || c.contains('||')) return false;
    if (RegExp(r'(?<!&)&(?!&)').hasMatch(c)) return false;
    for (final String part in c.split(RegExp(r'&&|\|'))) {
      final List<String> t = part.trim().split(RegExp(r'\s+'));
      if (t.isEmpty || t.first.isEmpty || !_ro.contains(t.first)) return false;
      if (t.first == 'find' && t.any((String a) => a == '-delete' || a.startsWith('-exec') || a == '-ok' || a == '-okdir' || a.startsWith('-fprint') || a == '-fls')) return false;
      if (t.first == 'git') {
        String? sub;
        for (final String a in t.skip(1)) {
          if (a.startsWith('-')) continue;
          sub = a;
          break;
        }
        if (sub == null || !_gitRo.contains(sub)) return false;
      }
    }
    return true;
  }
}

/// نص الرفض إن كان استدعاء الأداة ممنوعاً في وضع التخطيط، وإلا null.
String? planModeBlock(String convId, ToolCall c) {
  if (convId.isEmpty || !PlanState.isPlanMode(convId)) return null;
  const String tail = ' Plan mode is active: you may only read and search until the user approves a plan. Finish exploring, then call exit_plan_mode with your plan.';
  switch (c.name) {
    case kToolWriteFile:
    case kToolEditFile:
    case kToolSaveMemory:
    case kToolShell:
    case kToolKillShell:
      return '${c.name} would change things.$tail';
    case kToolBash:
      final String cmd = asStr(c.args['command']);
      if (c.args['run_in_background'] == true || !PlanPolicy.bashReadOnly(cmd)) {
        return 'This bash command is not read-only.$tail';
      }
      return null;
  }
  return null;
}

// ---------------------------------------------------------------------
//  تنفيذ الأدوات
// ---------------------------------------------------------------------
ToolOutcome _toolTodoWrite(Map<String, dynamic> a, String convId) {
  final dynamic raw = a['todos'];
  if (raw is! List) throw const ToolError('todos must be an array of {content, status, activeForm}');
  if (raw.length > 50) throw const ToolError('Too many todos (max 50). Group related steps into one item.');
  final List<TodoItem> list = <TodoItem>[];
  for (int i = 0; i < raw.length; i++) {
    final dynamic e = raw[i];
    if (e is! Map) throw ToolError('todos[$i] must be an object with content and status');
    final String content = asStr(e['content']).trim();
    final String status = asStr(e['status']).trim();
    if (content.isEmpty) throw ToolError('todos[$i].content is empty');
    if (!kTodoStatuses.contains(status)) throw ToolError('todos[$i].status must be pending, in_progress or completed (got "$status")');
    final String active = asStr(e['activeForm']).trim();
    list.add(TodoItem(clip(content, 300), clip(active.isEmpty ? content : active, 300), status));
  }
  if (convId.isNotEmpty) PlanState.todos[convId] = list;
  int done = 0;
  int doing = 0;
  for (final TodoItem t in list) {
    if (t.status == 'completed') done++;
    if (t.status == 'in_progress') doing++;
  }
  final StringBuffer b = StringBuffer('Todo list updated ($done/${list.length} done).');
  for (final TodoItem t in list) {
    if (t.status == 'completed') {
      b.write('\n[x] ${t.content}');
    } else if (t.status == 'in_progress') {
      b.write('\n[>] ${t.activeForm}');
    } else {
      b.write('\n[ ] ${t.content}');
    }
  }
  if (list.isEmpty) {
    b.write('\n(empty)');
  } else if (done == list.length) {
    b.write('\nAll items are completed.');
  } else if (doing == 0) {
    b.write('\nNote: no item is in_progress. Mark the one you are working on as in_progress.');
  } else if (doing > 1) {
    b.write('\nNote: $doing items are in_progress. Keep exactly one in_progress at a time.');
  } else {
    b.write('\nContinue with the in_progress item; mark it completed right after you finish it.');
  }
  return ToolOutcome(b.toString(), false);
}

List<AskQuestion> _parseQuestions(dynamic raw) {
  if (raw is! List || raw.isEmpty) throw const ToolError('questions must be an array with 1 to 4 questions');
  if (raw.length > 4) throw const ToolError('At most 4 questions per call');
  final List<AskQuestion> out = <AskQuestion>[];
  for (int i = 0; i < raw.length; i++) {
    final Map<String, dynamic> m = asMap(raw[i]);
    final String q = asStr(m['question']).trim();
    if (q.isEmpty) throw ToolError('questions[$i].question is empty');
    final List<dynamic> opts = asList(m['options']);
    if (opts.length < 2 || opts.length > 4) throw ToolError('questions[$i] needs 2 to 4 options (the user can always type another answer)');
    final List<AskOption> os = <AskOption>[];
    for (int j = 0; j < opts.length; j++) {
      final Map<String, dynamic> o = asMap(opts[j]);
      final String label = asStr(o['label']).trim();
      if (label.isEmpty) throw ToolError('questions[$i].options[$j].label is empty');
      os.add(AskOption(clip(label, 80), clip(asStr(o['description']).trim(), 200)));
    }
    final String header = asStr(m['header']).trim();
    out.add(AskQuestion(clip(q, 400), clip(header, 12), m['multiSelect'] == true, os));
  }
  return out;
}

Future<ToolOutcome> _toolAskUser(Map<String, dynamic> a) async {
  final List<AskQuestion> qs = _parseQuestions(a['questions']);
  final Future<List<AskAnswer>?> Function(List<AskQuestion>)? hook = PlanState.askHook;
  if (hook == null && navKey.currentContext == null) {
    throw const ToolError('Cannot ask the user right now: no screen is available. Make a reasonable choice, say which one you made, and continue.');
  }
  final List<AskAnswer>? ans = hook != null ? await hook(qs) : await _showAskSheet(qs);
  if (ans == null || ans.length != qs.length) {
    return const ToolOutcome('The user dismissed the question without answering. Do not ask the same thing again right away: pick the most reasonable option and say which, or stop and wait for their next message.', true);
  }
  final StringBuffer b = StringBuffer('The user answered:');
  for (int i = 0; i < qs.length; i++) {
    final AskAnswer x = ans[i];
    final List<String> parts = <String>[...x.picked];
    final String other = x.other.trim();
    if (other.isNotEmpty) parts.add('(own answer) ${clip(other, 2000)}');
    b.write('\n- ${qs[i].question} => ${parts.isEmpty ? '(no answer)' : parts.join('; ')}');
  }
  return ToolOutcome(b.toString(), false);
}

Future<ToolOutcome> _toolEnterPlan(String convId) async {
  if (convId.isEmpty) throw const ToolError('Plan mode needs a conversation');
  if (PlanState.isPlanMode(convId)) throw const ToolError('Plan mode is already active. Explore, then call exit_plan_mode with your plan.');
  final Future<bool> Function()? hook = PlanState.enterHook;
  final bool ok = hook != null
      ? await hook()
      : await askConfirm('النموذج يقترح العمل بوضع التخطيط', 'سيقرأ ويبحث فقط دون تعديل أي ملف أو تنفيذ أمر يغيّر شيئاً، ثم يعرض عليك خطة لتوافق عليها قبل أي تعديل.', ok: 'موافقة', cancel: 'لا');
  if (!ok) {
    return const ToolOutcome('The user declined plan mode. Continue without it: proceed carefully with the task, or ask what they want.', true);
  }
  PlanState.planMode.add(convId);
  return const ToolOutcome('Plan mode is on. You may only read and search now (read_file, search_files, list_directory, outline_file, read-only bash such as ls, cat, grep, git status/log/diff). Explore the code, then call exit_plan_mode with the complete plan. Nothing can be edited until the user approves it.', false);
}

Future<ToolOutcome> _toolExitPlan(Map<String, dynamic> a, String convId) async {
  if (convId.isEmpty || !PlanState.isPlanMode(convId)) throw const ToolError('Plan mode is not active (call enter_plan_mode first).');
  final String plan = asStr(a['plan']).trim();
  if (plan.isEmpty) throw const ToolError('plan is required: write the complete plan in Markdown');
  if (plan.length > 30000) throw const ToolError('The plan is too long (max 30,000 characters). Make it shorter.');
  final Future<PlanDecision> Function(String)? hook = PlanState.planHook;
  final PlanDecision d = hook != null ? await hook(plan) : await _showPlanSheet(plan);
  if (!d.approved) {
    final String fb = d.feedback.trim();
    return ToolOutcome('The user did not approve the plan.${fb.isEmpty ? '' : ' Their comments: "${clip(fb, 3000)}".'} You are still in plan mode: revise the plan and call exit_plan_mode again, or ask a question with ask_user_question.', true);
  }
  PlanState.planMode.remove(convId);
  return const ToolOutcome('The user approved the plan. Plan mode is off: you may now edit files and run commands. Start with the first step and track progress with todo_write.', false);
}

// ---------------------------------------------------------------------
//  الواجهات (أوراق سفلية جديدة، لا تلمس الواجهات الموجودة)
// ---------------------------------------------------------------------
Future<List<AskAnswer>?> _showAskSheet(List<AskQuestion> qs) async {
  final BuildContext? ctx = navKey.currentContext;
  if (ctx == null) return null;
  return showModalBottomSheet<List<AskAnswer>>(
    context: ctx,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (BuildContext c) => AskUserSheet(questions: qs),
  );
}

Future<PlanDecision> _showPlanSheet(String plan) async {
  final BuildContext? ctx = navKey.currentContext;
  if (ctx == null) return const PlanDecision(false, 'No screen is available to show the plan to the user.');
  final PlanDecision? d = await showModalBottomSheet<PlanDecision>(
    context: ctx,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (BuildContext c) => PlanApprovalSheet(plan: plan),
  );
  return d ?? const PlanDecision(false);
}

class AskUserSheet extends StatefulWidget {
  final List<AskQuestion> questions;
  const AskUserSheet({super.key, required this.questions});
  @override
  State<AskUserSheet> createState() => _AskUserSheetState();
}

class _AskUserSheetState extends State<AskUserSheet> {
  late final List<Set<int>> _sel;
  late final List<TextEditingController> _other;

  @override
  void initState() {
    super.initState();
    _sel = List<Set<int>>.generate(widget.questions.length, (int i) => <int>{});
    _other = List<TextEditingController>.generate(widget.questions.length, (int i) => TextEditingController());
  }

  @override
  void dispose() {
    for (final TextEditingController c in _other) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _complete {
    for (int i = 0; i < widget.questions.length; i++) {
      if (_sel[i].isEmpty && _other[i].text.trim().isEmpty) return false;
    }
    return true;
  }

  void _toggle(int qi, int oi) {
    setState(() {
      final AskQuestion q = widget.questions[qi];
      if (q.multi) {
        if (!_sel[qi].add(oi)) _sel[qi].remove(oi);
      } else {
        _sel[qi]
          ..clear()
          ..add(oi);
        _other[qi].clear();
      }
    });
  }

  void _submit() {
    final List<AskAnswer> out = <AskAnswer>[];
    for (int i = 0; i < widget.questions.length; i++) {
      final List<int> idx = _sel[i].toList()..sort();
      out.add(AskAnswer(idx.map((int k) => widget.questions[i].options[k].label).toList(), _other[i].text.trim()));
    }
    Navigator.pop(context, out);
  }

  Widget _option(Pal p, int qi, int oi) {
    final AskQuestion q = widget.questions[qi];
    final AskOption o = q.options[oi];
    final bool on = _sel[qi].contains(oi);
    final IconData ic = q.multi ? (on ? Icons.check_box : Icons.check_box_outline_blank) : (on ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _toggle(qi, oi),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on ? p.accent.withAlpha(30) : p.codeBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? p.accent : p.border),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Icon(ic, size: 20, color: on ? p.accent : p.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(o.label, style: TextStyle(color: p.text, fontSize: 14.5, fontWeight: FontWeight.w600)),
              if (o.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                Text(o.description, style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _question(Pal p, int qi) {
    final AskQuestion q = widget.questions[qi];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      if (q.header.isNotEmpty)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: p.accent.withAlpha(30), borderRadius: BorderRadius.circular(99)),
            child: Text(q.header, style: TextStyle(color: p.accent, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      Text(q.question, style: TextStyle(color: p.text, fontSize: 15, height: 1.45, fontWeight: FontWeight.w500)),
      if (q.multi) Padding(padding: const EdgeInsets.only(top: 2), child: Text('يمكنك اختيار أكثر من إجابة', style: TextStyle(color: p.muted, fontSize: 12))),
      const SizedBox(height: 8),
      for (int oi = 0; oi < q.options.length; oi++) _option(p, qi, oi),
      TextField(
        controller: _other[qi],
        minLines: 1,
        maxLines: 4,
        onChanged: (String v) {
          setState(() {
            if (!q.multi && v.trim().isNotEmpty) _sel[qi].clear();
          });
        },
        decoration: fieldDeco(context, hint: 'أو اكتب إجابة أخرى…'),
      ),
      const SizedBox(height: 18),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    final double maxH = MediaQuery.of(context).size.height * 0.92;
    final double kb = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(color: p.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              const SheetHandle(),
              const SizedBox(height: 4),
              Row(children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: p.accent.withAlpha(36), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.help_outline, color: p.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Claude يسألك', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 14),
              for (int qi = 0; qi < widget.questions.length; qi++) _question(p, qi),
              FilledButton(
                onPressed: _complete ? _submit : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('إرسال الإجابة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 4),
              TextButton(onPressed: () => Navigator.pop(context), child: Text('تخطّي', style: TextStyle(color: p.muted, fontSize: 14))),
            ]),
          ),
        ),
      ),
    );
  }
}

class PlanApprovalSheet extends StatelessWidget {
  final String plan;
  const PlanApprovalSheet({super.key, required this.plan});

  Future<void> _comment(BuildContext context) async {
    final String? r = await askText(context, 'ملاحظاتك على الخطة', hint: 'تصل إلى Claude ليعدّل الخطة', multiline: true);
    if (r == null) return;
    if (context.mounted) Navigator.pop(context, PlanDecision(false, r.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final Pal p = pal(context);
    final double maxH = MediaQuery.of(context).size.height * 0.92;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(color: p.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            const SheetHandle(),
            const SizedBox(height: 4),
            Row(children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: p.accent.withAlpha(36), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.checklist, color: p.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('خطة Claude للتنفيذ', style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                decoration: BoxDecoration(color: p.codeBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(child: SelectableText(plan, style: TextStyle(color: p.text, fontSize: 13.5, height: 1.55))),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context, const PlanDecision(true)),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('موافقة وابدأ التنفيذ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _comment(context),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: const Text('تعديل الخطة (اكتب ملاحظاتك)', style: TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.pop(context, const PlanDecision(false)), child: Text('رفض', style: TextStyle(color: p.danger, fontSize: 14))),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
//  اختبار ذاتي (يُشغَّل في فحص المحاكي بالـ CI)
// ---------------------------------------------------------------------
Future<void> runPlanningSelfTest() async {
  int fails = 0;
  int total = 0;
  // ignore: avoid_print
  void out(String s) => print('LMPROBE|PLAN $s');
  void rec(String name, bool ok, String detail) {
    total++;
    if (!ok) fails++;
    final String d = detail.replaceAll('\n', ' ⏎ ');
    out('${ok ? 'OK  ' : 'FAIL'} $name${d.isEmpty ? '' : ' :: ${d.length > 220 ? d.substring(0, 220) : d}'}');
  }

  Future<String> err(Future<ToolOutcome> Function() f) async {
    try {
      final ToolOutcome o = await f();
      return o.error ? 'ERR ${o.text}' : 'OK ${o.text}';
    } on ToolError catch (e) {
      return 'ERR ${e.message}';
    } catch (e) {
      return 'EXC $e';
    }
  }

  try {
    // ---- todo_write
    Map<String, dynamic> t(String c, String s) => <String, dynamic>{'content': c, 'activeForm': '$c...', 'status': s};
    final String r1 = await err(() async => _toolTodoWrite(<String, dynamic>{'todos': <dynamic>[t('A', 'completed'), t('B', 'in_progress'), t('C', 'pending')]}, 'pt1'));
    rec('todo_write renders checklist', r1.startsWith('OK Todo list updated (1/3 done).') && r1.contains('[x] A') && r1.contains('[>] B...') && r1.contains('[ ] C') && r1.contains('Continue with'), r1);
    rec('todo_write stores per conversation', (PlanState.todos['pt1'] ?? <TodoItem>[]).length == 3, '');
    final String r2 = await err(() async => _toolTodoWrite(<String, dynamic>{'todos': <dynamic>[t('A', 'doing')]}, 'pt1'));
    rec('todo_write rejects an unknown status', r2.startsWith('ERR') && r2.contains('status must be'), r2);
    final String r3 = await err(() async => _toolTodoWrite(<String, dynamic>{'todos': 'x'}, 'pt1'));
    rec('todo_write rejects a non-array', r3.startsWith('ERR'), r3);
    final String r4 = await err(() async => _toolTodoWrite(<String, dynamic>{'todos': List<dynamic>.generate(51, (int i) => t('T$i', 'pending'))}, 'pt1'));
    rec('todo_write caps the list at 50', r4.startsWith('ERR') && r4.contains('max 50'), r4);
    final String r5 = await err(() async => _toolTodoWrite(<String, dynamic>{'todos': <dynamic>[t('A', 'in_progress'), t('B', 'in_progress')]}, 'pt1'));
    rec('todo_write warns about two in_progress', r5.startsWith('OK') && r5.contains('2 items are in_progress'), r5);
    final String r6 = await err(() async => _toolTodoWrite(<String, dynamic>{'todos': <dynamic>[t('A', 'completed')]}, 'pt1'));
    rec('todo_write notes completion', r6.contains('All items are completed.'), r6);

    // ---- ask_user_question: التحقق من المدخلات
    Map<String, dynamic> q(int nOpts) => <String, dynamic>{
          'question': 'Which one?',
          'header': 'A very long header here',
          'options': List<dynamic>.generate(nOpts, (int i) => <String, dynamic>{'label': 'Opt$i', 'description': 'd$i'}),
        };
    final String a1 = await err(() => _toolAskUser(<String, dynamic>{'questions': <dynamic>[]}));
    rec('ask rejects an empty question list', a1.startsWith('ERR'), a1);
    final String a2 = await err(() => _toolAskUser(<String, dynamic>{'questions': <dynamic>[q(1)]}));
    rec('ask needs at least 2 options', a2.startsWith('ERR') && a2.contains('2 to 4'), a2);
    final String a3 = await err(() => _toolAskUser(<String, dynamic>{'questions': List<dynamic>.generate(5, (int i) => q(2))}));
    rec('ask caps at 4 questions', a3.startsWith('ERR') && a3.contains('At most 4'), a3);
    PlanState.askHook = (List<AskQuestion> qs) async => <AskAnswer>[
          const AskAnswer(<String>['Opt1'], ''),
          const AskAnswer(<String>['Opt0', 'Opt1'], 'extra'),
        ];
    final String a4 = await err(() => _toolAskUser(<String, dynamic>{
          'questions': <dynamic>[q(2), <String, dynamic>{...q(3), 'multiSelect': true}],
        }));
    rec('ask returns the answers to the model', a4.startsWith('OK The user answered:') && a4.contains('Which one? => Opt1') && a4.contains('Opt0; Opt1; (own answer) extra'), a4);
    PlanState.askHook = (List<AskQuestion> qs) async => null;
    final String a5 = await err(() => _toolAskUser(<String, dynamic>{'questions': <dynamic>[q(2)]}));
    rec('ask: dismissal is reported as an error', a5.startsWith('ERR') && a5.contains('dismissed'), a5);
    PlanState.askHook = null;

    // ---- وضع التخطيط: الاستعادة من السجل
    ToolCall done(String id, String name, Map<String, dynamic> args, {bool error = false}) => ToolCall(id: id, name: name, args: args, result: 'x', status: error ? 'error' : 'done', isError: error);
    ChatMessage am(List<ToolCall> cs) => ChatMessage(id: newId(), role: 'assistant', toolCalls: cs);
    final List<ChatMessage> h1 = <ChatMessage>[
      ChatMessage(id: 'u', role: 'user', content: 'go'),
      am(<ToolCall>[done('1', kToolEnterPlan, <String, dynamic>{})]),
      am(<ToolCall>[done('2', kToolTodoWrite, <String, dynamic>{'todos': <dynamic>[t('A', 'pending')]})]),
    ];
    PlanState.syncFromHistory('ph1', h1);
    rec('plan mode restored from history', PlanState.isPlanMode('ph1') && (PlanState.todos['ph1'] ?? <TodoItem>[]).length == 1, '');
    final List<ChatMessage> h2 = <ChatMessage>[...h1, am(<ToolCall>[done('3', kToolExitPlan, <String, dynamic>{'plan': 'p'})])];
    PlanState.syncFromHistory('ph1', h2);
    rec('a successful exit_plan_mode ends plan mode', !PlanState.isPlanMode('ph1'), '');
    final List<ChatMessage> h3 = <ChatMessage>[...h1, am(<ToolCall>[done('4', kToolExitPlan, <String, dynamic>{'plan': 'p'}, error: true)])];
    PlanState.syncFromHistory('ph1', h3);
    rec('a rejected plan keeps plan mode', PlanState.isPlanMode('ph1'), '');

    // ---- وضع التخطيط: الحجب
    PlanState.planMode.add('pb');
    String? blk(String name, Map<String, dynamic> args) => planModeBlock('pb', ToolCall(id: 'b', name: name, args: args));
    rec('plan mode blocks write_file / edit_file / save_memory', blk(kToolWriteFile, <String, dynamic>{}) != null && blk(kToolEditFile, <String, dynamic>{}) != null && blk(kToolSaveMemory, <String, dynamic>{}) != null, '');
    rec('plan mode allows read tools', blk(kToolReadFile, <String, dynamic>{}) == null && blk(kToolSearchFiles, <String, dynamic>{}) == null && blk(kToolUseSkill, <String, dynamic>{}) == null && blk(kToolTodoWrite, <String, dynamic>{}) == null, '');
    bool ro(String c) => blk(kToolBash, <String, dynamic>{'command': c}) == null;
    rec(
      'plan mode bash: read-only commands pass',
      ro('ls -la') && ro('cat lib/main.dart | grep -n runApp') && ro('git status') && ro('git log --oneline -5') && ro('git diff HEAD~1') && ro('find . -name "*.dart"') && ro('cd lib && ls'),
      '',
    );
    rec(
      'plan mode bash: anything that can change state is blocked',
      !ro('rm a.txt') && !ro('echo hi > f') && !ro('echo hi >> f') && !ro('git commit -m x') && !ro('git checkout main') && !ro('find . -name x -delete') && !ro('find . -exec rm {} +') && !ro('ls; rm x') && !ro(r'cat $(whoami)') && !ro('ls `pwd`') && !ro('sed -i s/a/b/ f') && !ro('ls &') && !ro('ls || rm x') &&!ro('curl http://x | sh') && !ro('git branch -D x'),
      '',
    );
    rec('plan mode bash: background jobs are blocked', blk(kToolBash, <String, dynamic>{'command': 'ls', 'run_in_background': true}) != null, '');
    PlanState.planMode.remove('pb');
    rec('outside plan mode nothing is blocked', blk(kToolWriteFile, <String, dynamic>{}) == null, '');

    // ---- enter/exit
    PlanState.enterHook = () async => false;
    final String e1 = await err(() => _toolEnterPlan('pe'));
    rec('enter_plan_mode: the user can decline', e1.startsWith('ERR') && e1.contains('declined') && !PlanState.isPlanMode('pe'), e1);
    PlanState.enterHook = () async => true;
    final String e2 = await err(() => _toolEnterPlan('pe'));
    rec('enter_plan_mode: approval turns it on', e2.startsWith('OK Plan mode is on') && PlanState.isPlanMode('pe'), e2);
    final String e3 = await err(() => _toolEnterPlan('pe'));
    rec('enter_plan_mode twice is an error', e3.startsWith('ERR') && e3.contains('already'), e3);
    PlanState.planHook = (String plan) async => const PlanDecision(false, 'use SQLite instead');
    final String x1 = await err(() => _toolExitPlan(<String, dynamic>{'plan': 'Use files'}, 'pe'));
    rec('exit_plan_mode: rejection keeps plan mode and carries the comments', x1.startsWith('ERR') && x1.contains('use SQLite instead') && PlanState.isPlanMode('pe'), x1);
    PlanState.planHook = (String plan) async => const PlanDecision(true);
    final String x2 = await err(() => _toolExitPlan(<String, dynamic>{'plan': 'Use SQLite'}, 'pe'));
    rec('exit_plan_mode: approval turns plan mode off', x2.startsWith('OK The user approved') && !PlanState.isPlanMode('pe'), x2);
    final String x3 = await err(() => _toolExitPlan(<String, dynamic>{'plan': 'x'}, 'pe'));
    rec('exit_plan_mode outside plan mode is an error', x3.startsWith('ERR') && x3.contains('not active'), x3);
    PlanState.enterHook = null;
    PlanState.planHook = null;
    PlanState.planMode.remove('pe');

    // ---- التعريفات والتعليمات
    final List<ToolDef> defs = planningToolDefs();
    rec('four tool definitions', defs.length == 4 && defs.map((ToolDef d) => d.name).toSet().containsAll(<String>[kToolTodoWrite, kToolAskUser, kToolEnterPlan, kToolExitPlan]), defs.map((ToolDef d) => d.name).join(','));
    rec('definitions are valid JSON', () {
      try {
        jsonEncode(defs.map((ToolDef d) => d.schema).toList());
        return true;
      } catch (_) {
        return false;
      }
    }(), '');
    final SettingsNotifier st = appContainer.read(settingsProvider.notifier);
    st.set('tools', true);
    final List<ToolDef> avail = availableTools(appContainer.read(settingsProvider), null, hasLibrary: false, hasMemory: false);
    rec('tools are exposed by availableTools', avail.any((ToolDef d) => d.name == kToolTodoWrite) && avail.any((ToolDef d) => d.name == kToolAskUser) && avail.any((ToolDef d) => d.name == kToolExitPlan), avail.map((ToolDef d) => d.name).join(','));
    final String sp = await buildSystemPrompt(s: appContainer.read(settingsProvider), project: null, agent: null, memory: <MemoryPart>[], library: <LibraryItem>[], tools: avail);
    rec('system prompt mentions the planning tools', sp.contains(kToolTodoWrite) && sp.contains(kToolAskUser) && sp.contains(kToolEnterPlan), '');
  } catch (e) {
    rec('planning tests', false, '$e');
  }
  out('DONE fails=$fails total=$total');
}
