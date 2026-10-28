part of 'main.dart';

// =====================================================================
//  اختبار شامل لحلقة الـ Agent بنموذج وهمي (يُشغَّل في فحص المحاكي بالـ CI، لا شبكة ولا مفاتيح):
//  خادم HTTP محلي داخل التطبيق يتكلم بروتوكول Anthropic (SSE) بسيناريوهات مبرمجة، و`ChatSession` الحقيقية
//  تتحدث معه. يثبت سلوك الجلسة الفعلي: حلقة الأدوات، إعادة الجولة المقطوعة، أخطاء الـ stream،
//  قصّ السياق داخل الدور، والإصلاح الذاتي لخطأ prompt-too-long.
// =====================================================================

class _MockReply {
  final int status;
  final String body;
  final bool sse;
  const _MockReply(this.status, this.body, {this.sse = true});
}

class _MockLlm {
  HttpServer? _server;
  final List<String> bodies = <String>[];
  Future<_MockReply> Function(int n, String body) handler = (int n, String b) async => const _MockReply(500, 'no handler', sse: false);

  Future<void> start() async {
    final HttpServer srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = srv;
    srv.listen((HttpRequest req) async {
      try {
        final String body = await utf8.decodeStream(req);
        bodies.add(body);
        final _MockReply r = await handler(bodies.length, body);
        req.response.statusCode = r.status;
        req.response.headers.contentType = r.sse ? ContentType('text', 'event-stream') : ContentType('application', 'json');
        req.response.write(r.body);
        await req.response.close();
      } catch (_) {
        try {
          await req.response.close();
        } catch (_) {}
      }
    });
  }

  int get port => _server?.port ?? 0;

  Future<void> stop() async {
    final HttpServer? s = _server;
    if (s != null) await s.close(force: true);
  }
}

String _sseOf(List<Map<String, dynamic>> evs) => evs.map((Map<String, dynamic> e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n').join();

List<Map<String, dynamic>> _anText(String t, {bool end = true}) => <Map<String, dynamic>>[
      <String, dynamic>{'type': 'message_start', 'message': <String, dynamic>{'usage': <String, dynamic>{'input_tokens': 120}}},
      <String, dynamic>{'type': 'content_block_start', 'index': 0, 'content_block': <String, dynamic>{'type': 'text', 'text': ''}},
      <String, dynamic>{'type': 'content_block_delta', 'index': 0, 'delta': <String, dynamic>{'type': 'text_delta', 'text': t}},
      if (end) <String, dynamic>{'type': 'content_block_stop', 'index': 0},
      if (end) <String, dynamic>{'type': 'message_delta', 'delta': <String, dynamic>{'stop_reason': 'end_turn'}, 'usage': <String, dynamic>{'output_tokens': 7}},
      if (end) <String, dynamic>{'type': 'message_stop'},
    ];

List<Map<String, dynamic>> _anTool(String id, String name, String json, {bool end = true}) => <Map<String, dynamic>>[
      <String, dynamic>{'type': 'message_start', 'message': <String, dynamic>{'usage': <String, dynamic>{'input_tokens': 120}}},
      <String, dynamic>{'type': 'content_block_start', 'index': 0, 'content_block': <String, dynamic>{'type': 'tool_use', 'id': id, 'name': name, 'input': <String, dynamic>{}}},
      <String, dynamic>{'type': 'content_block_delta', 'index': 0, 'delta': <String, dynamic>{'type': 'input_json_delta', 'partial_json': json}},
      if (end) <String, dynamic>{'type': 'content_block_stop', 'index': 0},
      if (end) <String, dynamic>{'type': 'message_delta', 'delta': <String, dynamic>{'stop_reason': 'tool_use'}, 'usage': <String, dynamic>{'output_tokens': 9}},
      if (end) <String, dynamic>{'type': 'message_stop'},
    ];

ChatSession _seededSession(int rounds, int chars) {
  final ChatSession s = ChatSession(ConvMeta(id: newId()));
  s.messages.add(ChatMessage(id: newId(), role: 'user', content: 'work on it'));
  for (int i = 0; i < rounds; i++) {
    s.messages.add(ChatMessage(
      id: newId(),
      role: 'assistant',
      toolCalls: <ToolCall>[ToolCall(id: 'tc$i', name: 'current_time', args: <String, dynamic>{}, result: 'R$i-${'x' * chars}', status: 'done')],
    ));
  }
  return s;
}

Future<void> runAgentE2E() async {
  int fails = 0;
  int total = 0;
  // ignore: avoid_print
  void out(String s) => print('LMPROBE|E2E $s');
  void rec(String name, bool ok, String detail) {
    total++;
    if (!ok) fails++;
    final String d = detail.replaceAll('\n', ' ⏎ ');
    out('${ok ? 'OK  ' : 'FAIL'} $name${d.isEmpty ? '' : ' :: ${d.length > 240 ? d.substring(0, 240) : d}'}');
  }

  final _MockLlm mock = _MockLlm();
  try {
    await mock.start();
    final SettingsNotifier st = appContainer.read(settingsProvider.notifier);
    st.set('tools', true);
    st.set('includeDate', true);
    st.set('autoTitle', false);
    st.set('autoCompact', false);
    st.set('contextBudget', 60000);
    await appContainer.read(profilesProvider.notifier).upsert(
          ApiProfile(id: 'e2e-mock', name: 'mock', kind: kAnthropic, baseUrl: 'http://127.0.0.1:${mock.port}', apiKey: 'k', selectedModel: 'mock-model'),
          select: true,
        );
    out('mock server on 127.0.0.1:${mock.port}');

    // ---- 1) حلقة أدوات كاملة: أداة ثم رد نهائي
    mock.bodies.clear();
    mock.handler = (int n, String body) async {
      if (n == 1) return _MockReply(200, _sseOf(_anTool('tu1', 'current_time', '{}')));
      return _MockReply(200, _sseOf(_anText('DONE-1')));
    };
    final ChatSession s1 = ChatSession(ConvMeta(id: newId()));
    await s1.send('what time is it', <PendingAtt>[]).timeout(const Duration(seconds: 60));
    final bool s1ok = s1.messages.length == 3 &&
        s1.messages[1].toolCalls.length == 1 &&
        !s1.messages[1].toolCalls[0].isError &&
        (s1.messages[1].toolCalls[0].result ?? '').isNotEmpty &&
        s1.messages[2].content == 'DONE-1' &&
        mock.bodies.length == 2 &&
        mock.bodies[1].contains('tool_result');
    rec('tool loop: tool call, result sent back, final answer', s1ok, 'msgs=${s1.messages.length} reqs=${mock.bodies.length} last=${s1.messages.last.content} err=${s1.messages.last.error}');

    // ---- 2) رد مقطوع في منتصف النص: يُفرَّغ الجزئي وتُعاد الجولة (لا «par» + «OK-2»)
    mock.bodies.clear();
    mock.handler = (int n, String body) async {
      if (n == 1) return _MockReply(200, _sseOf(_anText('par', end: false)));
      return _MockReply(200, _sseOf(_anText('OK-2')));
    };
    final ChatSession s2 = ChatSession(ConvMeta(id: newId()));
    await s2.send('hello', <PendingAtt>[]).timeout(const Duration(seconds: 90));
    rec('truncated text stream is retried from scratch', s2.messages.last.content == 'OK-2' && s2.messages.last.error == null && mock.bodies.length == 2,
        'content=${s2.messages.last.content} err=${s2.messages.last.error} reqs=${mock.bodies.length}');

    // ---- 3) استدعاء أداة مقطوع: لا يضيع بصمت، يُعاد
    mock.bodies.clear();
    mock.handler = (int n, String body) async {
      if (n == 1) return _MockReply(200, _sseOf(_anTool('tu9', 'current_time', '{', end: false)));
      return _MockReply(200, _sseOf(_anText('OK-3')));
    };
    final ChatSession s3 = ChatSession(ConvMeta(id: newId()));
    await s3.send('hello', <PendingAtt>[]).timeout(const Duration(seconds: 90));
    rec('truncated tool call is retried (no silent drop)', s3.messages.last.content == 'OK-3' && s3.messages.last.toolCalls.isEmpty && mock.bodies.length == 2,
        'content=${s3.messages.last.content} calls=${s3.messages.last.toolCalls.length} reqs=${mock.bodies.length}');

    // ---- 4) overloaded داخل الـ stream (HTTP 200): تُعاد المحاولة
    mock.bodies.clear();
    mock.handler = (int n, String body) async {
      if (n == 1) return _MockReply(200, _sseOf(<Map<String, dynamic>>[<String, dynamic>{'type': 'error', 'error': <String, dynamic>{'type': 'overloaded_error', 'message': 'Overloaded'}}]));
      return _MockReply(200, _sseOf(_anText('OK-4')));
    };
    final ChatSession s4 = ChatSession(ConvMeta(id: newId()));
    await s4.send('hello', <PendingAtt>[]).timeout(const Duration(seconds: 90));
    rec('in-stream overloaded is retried', s4.messages.last.content == 'OK-4' && s4.messages.last.error == null && mock.bodies.length == 2,
        'content=${s4.messages.last.content} err=${s4.messages.last.error} reqs=${mock.bodies.length}');

    // ---- 5) قصّ السياق داخل الدور الحالي (استباقي): 12 جولة × 20000 حرف تتجاوز الميزانية
    mock.bodies.clear();
    mock.handler = (int n, String body) async => _MockReply(200, _sseOf(_anText('OK-5')));
    final ChatSession s5 = _seededSession(12, 20000);
    await s5._run().timeout(const Duration(seconds: 60));
    final int b5 = mock.bodies.isEmpty ? 0 : mock.bodies[0].length;
    rec('in-turn trimming keeps the request under the budget', mock.bodies.length == 1 && b5 > 100000 && b5 < 200000 && mock.bodies[0].contains('old tool output trimmed') && s5.messages.last.content == 'OK-5',
        'reqs=${mock.bodies.length} bytes=$b5 (untrimmed would be about 240000) last=${s5.messages.last.content}');

    // ---- 6) إصلاح ذاتي لخطأ prompt-too-long (الميزانية معطّلة): نقصّ ونعيد
    st.set('contextBudget', 0);
    mock.bodies.clear();
    mock.handler = (int n, String body) async {
      if (n == 1) {
        return _MockReply(400, jsonEncode(<String, dynamic>{'type': 'error', 'error': <String, dynamic>{'type': 'invalid_request_error', 'message': 'prompt is too long: 250000 tokens > 200000 maximum'}}), sse: false);
      }
      return _MockReply(200, _sseOf(_anText('OK-6')));
    };
    final ChatSession s6 = _seededSession(12, 20000);
    await s6._run().timeout(const Duration(seconds: 60));
    final int a6 = mock.bodies.isNotEmpty ? mock.bodies[0].length : 0;
    final int c6 = mock.bodies.length > 1 ? mock.bodies[1].length : 0;
    rec('prompt-too-long self-heal: trim and retry', mock.bodies.length == 2 && c6 > 0 && c6 < a6 ~/ 2 && s6.messages.last.content == 'OK-6' && s6.messages.last.error == null,
        'reqs=${mock.bodies.length} first=$a6 second=$c6 last=${s6.messages.last.content} err=${s6.messages.last.error}');

    // ---- 7) أدوات التخطيط والتفاعل داخل الحلقة الحقيقية: مهام ← سؤال ← وضع التخطيط (كتابة مرفوضة) ← خطة مرفوضة ← خطة مقبولة
    mock.bodies.clear();
    mock.handler = (int n, String body) async {
      switch (n) {
        case 1:
          return _MockReply(200, _sseOf(_anTool('p1', kToolTodoWrite, '{"todos":[{"content":"Read code","activeForm":"Reading code","status":"in_progress"},{"content":"Write fix","activeForm":"Writing fix","status":"pending"}]}')));
        case 2:
          return _MockReply(200, _sseOf(_anTool('p2', kToolAskUser, '{"questions":[{"question":"Which storage?","header":"Storage","options":[{"label":"SQLite","description":"local db"},{"label":"Files"}]}]}')));
        case 3:
          return _MockReply(200, _sseOf(_anTool('p3', kToolEnterPlan, '{}')));
        case 4:
          return _MockReply(200, _sseOf(_anTool('p4', kToolWriteFile, '{"path":"a.txt","content":"x"}')));
        case 5:
          return _MockReply(200, _sseOf(_anTool('p5', kToolExitPlan, '{"plan":"1. Use files"}')));
        case 6:
          return _MockReply(200, _sseOf(_anTool('p6', kToolExitPlan, '{"plan":"1. Use SQLite"}')));
        default:
          return _MockReply(200, _sseOf(_anText('DONE-7')));
      }
    };
    int planCalls = 0;
    PlanState.askHook = (List<AskQuestion> qs) async => <AskAnswer>[const AskAnswer(<String>['SQLite'], '')];
    PlanState.enterHook = () async => true;
    PlanState.planHook = (String plan) async {
      planCalls++;
      return planCalls == 1 ? const PlanDecision(false, 'use SQLite instead') : const PlanDecision(true);
    };
    try {
      final ChatSession s7 = ChatSession(ConvMeta(id: newId()));
      await s7.send('fix it', <PendingAtt>[]).timeout(const Duration(seconds: 90));
      final List<ToolCall> cs = <ToolCall>[for (final ChatMessage m in s7.messages) ...m.toolCalls];
      String res(int i) => i < cs.length ? (cs[i].result ?? '') : '';
      bool err(int i) => i < cs.length && cs[i].isError;
      final bool ok7 = cs.length == 6 &&
          s7.messages.last.content == 'DONE-7' &&
          mock.bodies.length == 7 &&
          !err(0) && res(0).contains('Todo list updated (0/2 done).') &&
          !err(1) && res(1).contains('SQLite') &&
          !err(2) && res(2).contains('Plan mode is on') &&
          err(3) && res(3).contains('Plan mode is active') &&
          err(4) && res(4).contains('use SQLite instead') &&
          !err(5) && res(5).contains('approved') &&
          !PlanState.isPlanMode(s7.meta.id) &&
          (PlanState.todos[s7.meta.id] ?? <TodoItem>[]).length == 2;
      rec('planning tools in the real loop (todo, ask, plan mode blocks writes, plan rejected then approved)', ok7,
          'calls=${cs.length} reqs=${mock.bodies.length} last=${s7.messages.last.content} r=${<String>[for (int i = 0; i < cs.length; i++) '${err(i) ? 'E' : 'o'}:${clip(res(i), 40)}'].join(' | ')}');
    } finally {
      PlanState.askHook = null;
      PlanState.enterHook = null;
      PlanState.planHook = null;
    }
  } catch (e) {
    rec('e2e harness', false, '$e');
  } finally {
    await mock.stop();
  }
  out('DONE fails=$fails total=$total');
}
