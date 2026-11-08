part of 'main.dart';

// =====================================================================
//  اختبار ذاتي للمحرّك (يُشغَّل في فحص المحاكي بالـ CI): محلّلات الـ stream تُغذّى بأسطر SSE جاهزة
//  لإثبات: (1) أخطاء الـ stream تُربط بحالة قابلة للإعادة، (2) الرد المقطوع لا يمرّ كأنه كامل.
//  لا شبكة ولا مفاتيح.
// =====================================================================

Future<void> runEngineSelfTest() async {
  int fails = 0;
  int total = 0;
  // ignore: avoid_print
  void out(String s) => print('LMPROBE|ENGINE $s');
  void rec(String name, bool ok, String detail) {
    total++;
    if (!ok) fails++;
    final String d = detail.replaceAll('\n', ' ⏎ ');
    out('${ok ? 'OK  ' : 'FAIL'} $name${d.isEmpty ? '' : ' :: ${d.length > 220 ? d.substring(0, 220) : d}'}');
  }

  Future<String> run(String kind, List<String> lines) async {
    final SseState st = SseState();
    final StringBuffer text = StringBuffer();
    int calls = 0;
    try {
      await for (final LlmEvent ev in parseStreamLines(kind, Stream<String>.fromIterable(lines), st)) {
        text.write(ev.text);
        if (ev.call != null) calls++;
      }
    } on ApiException catch (e) {
      return 'ERR status=${e.status} retriable=${e.retriable} net=${e.netError} calls=$calls text=$text';
    } catch (e) {
      return 'EXC $e';
    }
    return 'OK calls=$calls text=$text';
  }

  try {
    // ---- Anthropic
    final List<String> anOk = <String>[
      'event: message_start',
      'data: {"type":"message_start","message":{"usage":{"input_tokens":10}}}',
      'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
      'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}',
      'data: {"type":"content_block_stop","index":0}',
      'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}',
      'data: {"type":"message_stop"}',
    ];
    final String r1 = await run(kAnthropic, anOk);
    rec('anthropic complete stream', r1 == 'OK calls=0 text=Hello', r1);

    final String r2 = await run(kAnthropic, anOk.sublist(0, 4));
    rec('anthropic cut mid-text is an error', r2.startsWith('ERR') && r2.contains('retriable=true') && r2.contains('net=true') && r2.contains('text=Hello'), r2);

    final String r3 = await run(kAnthropic, <String>[
      'data: {"type":"message_start","message":{"usage":{"input_tokens":10}}}',
      'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tu1","name":"read_file"}}',
      'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"path\\":\\"a"}}',
    ]);
    rec('anthropic cut mid-tool_use is an error (no silent drop)', r3.startsWith('ERR') && r3.contains('retriable=true') && r3.contains('calls=0'), r3);

    final String r4 = await run(kAnthropic, <String>[
      'data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"tu1","name":"read_file"}}',
      'data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"path\\":\\"a.txt\\"}"}}',
      'data: {"type":"content_block_stop","index":0}',
      'data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":9}}',
      'data: {"type":"message_stop"}',
    ]);
    rec('anthropic tool_use complete', r4 == 'OK calls=1 text=', r4);

    final String r5 = await run(kAnthropic, <String>['data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}']);
    rec('anthropic in-stream overloaded -> 529 retriable', r5.contains('status=529') && r5.contains('retriable=true'), r5);
    final String r6 = await run(kAnthropic, <String>['data: {"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}']);
    rec('anthropic in-stream rate limit -> 429', r6.contains('status=429') && r6.contains('retriable=true'), r6);
    final String r7 = await run(kAnthropic, <String>['data: {"type":"error","error":{"type":"api_error","message":"boom"}}']);
    rec('anthropic in-stream api_error -> 500', r7.contains('status=500') && r7.contains('retriable=true'), r7);
    final String r8 = await run(kAnthropic, <String>['data: {"type":"error","error":{"type":"invalid_request_error","message":"bad"}}']);
    rec('anthropic invalid_request stays non-retriable', r8.contains('status=null') && r8.contains('retriable=false'), r8);

    // ---- OpenAI-compatible
    final String o1 = await run(kOpenAI, <String>[
      'data: {"choices":[{"delta":{"content":"Hi"}}]}',
      'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}',
      'data: [DONE]',
    ]);
    rec('openai complete stream', o1 == 'OK calls=0 text=Hi', o1);
    final String o2 = await run(kOpenAI, <String>['data: {"choices":[{"delta":{"content":"Hi"}}]}']);
    rec('openai text without end signal stays lenient (server variance)', o2 == 'OK calls=0 text=Hi', o2);
    final String o3 = await run(kOpenAI, <String>[
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"read_file","arguments":"{\\"path\\":"}}]}}]}',
    ]);
    rec('openai cut mid-tool_call is an error', o3.startsWith('ERR') && o3.contains('retriable=true'), o3);
    final String o4 = await run(kOpenAI, <String>[
      'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"read_file","arguments":"{\\"path\\":\\"a\\"}"}}]}}]}',
      'data: [DONE]',
    ]);
    rec('openai tool_call closed by [DONE] without finish_reason is accepted', o4 == 'OK calls=1 text=', o4);
    final String o5 = await run(kOpenAI, <String>['data: {"error":{"message":"busy","type":"server_error"}}']);
    rec('openai in-stream server_error -> 500', o5.contains('status=500') && o5.contains('retriable=true'), o5);
    final String o6 = await run(kOpenAI, <String>['data: {"error":{"message":"tpm","code":"rate_limit_exceeded"}}']);
    rec('openai in-stream rate_limit_exceeded -> 429', o6.contains('status=429'), o6);
    final String o7 = await run(kOpenAI, <String>['data: {"error":{"message":"no credit","type":"insufficient_quota","code":"insufficient_quota"}}']);
    rec('openai insufficient_quota stays non-retriable', o7.contains('retriable=false'), o7);

    // ---- Gemini
    final String g1 = await run(kGemini, <String>[
      'data: {"candidates":[{"content":{"parts":[{"text":"Hey"}]},"finishReason":"STOP"}]}',
    ]);
    rec('gemini complete stream', g1 == 'OK calls=0 text=Hey', g1);
    final String g2 = await run(kGemini, <String>['data: {"candidates":[{"content":{"parts":[{"text":"Hey"}]}}]}']);
    rec('gemini without finishReason is an error', g2.startsWith('ERR') && g2.contains('retriable=true'), g2);
    final String g3 = await run(kGemini, <String>['data: {"error":{"code":503,"status":"UNAVAILABLE","message":"overloaded"}}']);
    rec('gemini in-stream 503', g3.contains('status=503') && g3.contains('retriable=true'), g3);
    final String g4 = await run(kGemini, <String>['data: {"error":{"code":429,"status":"RESOURCE_EXHAUSTED","message":"quota"}}']);
    rec('gemini in-stream 429', g4.contains('status=429') && g4.contains('retriable=true'), g4);


    // ---- السياق
    rec(
      'too-long detection',
      isContextTooLong(ApiException('[400] prompt is too long: 215000 tokens > 200000 maximum', status: 400)) &&
          isContextTooLong(ApiException("This model's maximum context length is 128000 tokens", status: 400)) &&
          isContextTooLong(ApiException('The input token count (1100000) exceeds the maximum number of tokens allowed', status: 400)) &&
          !isContextTooLong(ApiException('max_tokens is too large: 200000', status: 400)) &&
          !isContextTooLong(ApiException('prompt is too long', status: 500)) &&
          !isContextTooLong(ApiException('[401] invalid api key', status: 401)),
      '',
    );
    final List<ChatMessage> h = <ChatMessage>[ChatMessage(id: 'u', role: 'user', content: 'go')];
    for (int i = 0; i < 12; i++) {
      h.add(ChatMessage(id: 'a$i', role: 'assistant', toolCalls: <ToolCall>[ToolCall(id: 't$i', name: 'read_file', result: 'x' * 5000)]));
    }
    rec('trim boundary inside the current turn', trimBoundary(h, 8) == 5 && trimBoundary(h, 1) == 12 && trimBoundary(h, 20) == -1, '${trimBoundary(h, 8)}/${trimBoundary(h, 1)}/${trimBoundary(h, 20)}');
    rec('old result is trimmed hard', trimResult('x' * 5000).length < 700, '${trimResult('x' * 5000).length}');

    // ---- الاستهلاك الفعلي كما يبلّغ المزوّد: دخل، كاش، خرج، تفكير (لا تقدير أبداً؛ غير المبلَّغ يبقى null)
    Future<String> usageOf(String kind, List<String> lines) async {
      int? ui;
      int? uo;
      int? uc;
      int? ut;
      try {
        await for (final LlmEvent ev in parseStreamLines(kind, Stream<String>.fromIterable(lines), SseState())) {
          if (ev.inTok != null) ui = ev.inTok;
          if (ev.outTok != null) uo = ev.outTok;
          if (ev.cacheTok != null) uc = ev.cacheTok;
          if (ev.thinkTok != null) ut = ev.thinkTok;
        }
      } catch (e) {
        return 'EXC $e';
      }
      return 'in=$ui out=$uo cache=$uc think=$ut';
    }

    final String u1 = await usageOf(kOpenAI, <String>[
      'data: {"choices":[{"delta":{"content":"Hi"}}]}',
      'data: {"choices":[],"usage":{"prompt_tokens":22707,"completion_tokens":2682,"prompt_tokens_details":{"cached_tokens":22528},"completion_tokens_details":{"reasoning_tokens":2400}}}',
      'data: [DONE]',
    ]);
    rec('usage openai-compatible: in, cached, out and reasoning tokens', u1 == 'in=22707 out=2682 cache=22528 think=2400', u1);
    final String u2 = await usageOf(kOpenAI, <String>[
      'data: {"choices":[{"delta":{"content":"Hi"}}]}',
      'data: {"choices":[],"usage":{"prompt_tokens":1000,"completion_tokens":50,"prompt_cache_hit_tokens":900}}',
      'data: [DONE]',
    ]);
    rec('usage deepseek style: cache hit field, reasoning not reported stays null (no guess)', u2 == 'in=1000 out=50 cache=900 think=null', u2);
    final String u3 = await usageOf(kAnthropic, <String>[
      'data: {"type":"message_start","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":90,"cache_creation_input_tokens":5}}}',
      'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
      'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}',
      'data: {"type":"content_block_stop","index":0}',
      'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":300,"output_tokens_details":{"thinking_tokens":250}}}',
      'data: {"type":"message_stop"}',
    ]);
    rec('usage anthropic: input includes cache read and write, thinking tokens from output_tokens_details', u3 == 'in=105 out=300 cache=90 think=250', u3);
    final String u4 = await usageOf(kAnthropic, <String>[
      'data: {"type":"message_start","message":{"usage":{"input_tokens":10}}}',
      'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
      'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}',
      'data: {"type":"content_block_stop","index":0}',
      'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":7}}',
      'data: {"type":"message_stop"}',
    ]);
    rec('usage anthropic without a thinking breakdown stays null', u4 == 'in=10 out=7 cache=0 think=null', u4);
    final String u5 = await usageOf(kGemini, <String>[
      'data: {"candidates":[{"content":{"parts":[{"text":"Hi"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":500,"candidatesTokenCount":40,"thoughtsTokenCount":160,"cachedContentTokenCount":300}}',
    ]);
    rec('usage gemini: thoughts counted inside output and reported separately', u5 == 'in=500 out=200 cache=300 think=160', u5);

    // ---- إخفاء الأسرار (المفاتيح تُبنى وقت التشغيل كي لا تظهر حرفياً في الشيفرة)
    final String kGoogle = 'AIza${'aB3dE' * 7}';
    final String kAnt = 'sk-ant-${'a1B2c3' * 6}';
    final String kGh = 'ghp_${'a1B2c' * 8}';
    final String kAq = 'AQ.${'Ab8RN6' * 8}';
    final String kJwt = 'eyJ${'abcde12345' * 2}.${'fghij67890' * 2}.${'klmno13579' * 2}';
    final String kPem = '-----BEGIN ${'RSA'} PRIVATE KEY-----\n${'MIIEowIBAAKC' * 6}\n-----END ${'RSA'} PRIVATE KEY-----';
    Redacted rd(String s, {bool h = false, List<String> known = const <String>[]}) => Redactor.clean(s, heuristics: h, known: known);
    Redacted r = rd('key=$kGoogle ok');
    rec('redact google key', r.count == 1 && !r.text.contains(kGoogle) && r.text.contains('ok'), r.text);
    r = rd('x $kAnt y');
    rec('redact anthropic-style key', r.count == 1 && !r.text.contains('a1B2c3a1B2c3'), r.text);
    r = rd('token $kGh');
    rec('redact github token', r.count == 1 && !r.text.contains(kGh), r.text);
    r = rd('GEMINI=$kAq');
    rec('redact google AQ. token', r.count == 1 && !r.text.contains('Ab8RN6Ab8RN6'), r.text);
    r = rd('jwt: $kJwt');
    rec('redact jwt', r.count == 1 && !r.text.contains('abcde12345'), r.text);
    r = rd('before\n$kPem\nafter');
    rec('redact private key block', r.count == 1 && r.text.contains('before') && r.text.contains('after') && !r.text.contains('MIIEowIBAAKC'), r.text);
    r = rd('curl -H "Authorization: Bearer ${'Zz9y8X7w' * 4}" https://x');
    rec('redact bearer header', r.count == 1 && !r.text.contains('Zz9y8X7wZz9y8X7w') && r.text.contains('Authorization: Bearer [REDACTED]'), r.text);
    final String tok = 'a1b2${'C3d4' * 4}';
    r = rd('export ANTHROPIC_AUTH_TOKEN="$tok"', h: true);
    rec('assignment heuristic keeps the name, hides the value', r.count == 1 && r.text.contains('ANTHROPIC_AUTH_TOKEN="[REDACTED]"') && !r.text.contains(tok), r.text);
    r = rd('export ANTHROPIC_AUTH_TOKEN="$tok"');
    rec('assignment heuristic is off by default', r.count == 0 && r.text.contains(tok), r.text);
    r = rd('{"apiKey": "${'k9Z8' * 5}", "name": "x"}', h: true);
    rec('json key heuristic', r.count == 1 && r.text.contains('"apiKey": "[REDACTED]"') && r.text.contains('"name": "x"'), r.text);
    final String code = 'final String password = widget.password;\nconst tokenizer = buildTokenizer(config);\nid 3f2a9c1e7b4d8a6f0e1c2b3a4d5e6f7a8b9c0d1e uuid 123e4567-e89b-12d3-a456-426614174000\ntask-force-alpha-bravo-charlie-delta-echo-foxtrot\nمرحباً بالعالم';
    r = rd(code, h: true);
    rec('no false positives on ordinary code and text', r.count == 0 && r.text == code, r.text);
    r = rd('my key is hunter2hunter2 ok', known: <String>['hunter2hunter2']);
    rec('app-known secret is matched literally', r.count == 1 && r.text == 'my key is [REDACTED:saved-secret] ok', r.text);
    final String viaBash = Redactor.forTool(kToolBash, <String, dynamic>{'command': 'cat ~/.bashrc'}, 'export OPENAI_API_KEY="$tok"\nalias ll="ls -l"');
    rec('bash output: hidden + note for the model', !viaBash.contains(tok) && viaBash.endsWith(Redactor.note) && viaBash.contains('alias ll="ls -l"'), viaBash);
    final String plain = Redactor.forTool(kToolBash, <String, dynamic>{'command': 'ls'}, 'a\nb\n');
    rec('clean output passes through untouched', plain == 'a\nb\n', plain);
    final String srcRead = Redactor.forTool(kToolReadFile, <String, dynamic>{'path': 'lib/main.dart'}, 'const API_KEY = "$tok";');
    rec('read_file of source keeps assignment text (no heuristics)', srcRead.contains(tok), srcRead);
    final String rcRead = Redactor.forTool(kToolReadFile, <String, dynamic>{'path': '/home/u/.bashrc'}, 'export API_KEY="$tok"');
    rec('read_file of a sensitive-named file hides assignments', !rcRead.contains(tok), rcRead);
    rec(
      'sensitive path detection',
      Redactor.sensitivePath('/home/u/.env') &&
          Redactor.sensitivePath('app/.env.local') &&
          Redactor.sensitivePath('~/.ssh/id_ed25519') &&
          Redactor.sensitivePath('certs/server.pem') &&
          !Redactor.sensitivePath('lib/secrets.dart') &&
          !Redactor.sensitivePath('lib/token_utils.dart') &&
          !Redactor.sensitivePath('README.md'),
      '',
    );

    // ---- الملخّص الحيّ (آخر جملة من التفكير، وصف الأداة، سطر السرد) وأرقام العرض
    rec('live summary: empty', liveSummary('') == '' && liveSummary('  \n ') == '', '');
    rec('live summary: last full sentence', liveSummary('Let me check git tracking. Then list models in one call.') == 'Then list models in one call.', liveSummary('Let me check git tracking. Then list models in one call.'));
    rec('live summary: a short tail joins the previous sentence', liveSummary('Check the proxy map first. Ok.') == 'Check the proxy map first. Ok.', liveSummary('Check the proxy map first. Ok.'));
    rec('live summary: last non-empty line, markdown stripped', liveSummary('first line\n\n**Plan** the next step carefully\n') == 'Plan the next step carefully', liveSummary('first line\n\n**Plan** the next step carefully\n'));
    final String longSum = liveSummary('w' * 300);
    rec('live summary: long text is clipped from the start', longSum.startsWith('…') && longSum.length == 141, '${longSum.length}');
    rec('live summary: arabic punctuation', liveSummary('فحصت الملف. ثم سأقرأ إعدادات الوسيط الآن؟') == 'ثم سأقرأ إعدادات الوسيط الآن؟', liveSummary('فحصت الملف. ثم سأقرأ إعدادات الوسيط الآن؟'));
    final ChatSession ls = ChatSession(ConvMeta(id: newId()));
    ls.messages.add(ChatMessage(id: 'u0', role: 'user', content: 'analyze'));
    ls.status = 'thinking';
    final String n0 = ls.liveNote;
    ls.messages.add(ChatMessage(
      id: 'lm',
      role: 'assistant',
      content: 'Checking the proxy config in one command.',
      toolCalls: <ToolCall>[ToolCall(id: 't1', name: 'bash', args: <String, dynamic>{'command': 'ls', 'description': 'Listing skills'}, status: 'done', result: 'x')],
    ));
    final String n1 = ls.liveNote;
    ls.status = 'tool:bash';
    ls.runningCall = ToolCall(id: 'lt', name: 'bash', args: <String, dynamic>{'command': 'cat map.ts | head', 'description': 'Reading the proxy map'}, status: 'running');
    final String n2 = ls.liveNote;
    ls.runningCall = ToolCall(id: 'lt2', name: 'read_file', args: <String, dynamic>{'path': '/a/b/session.dart'}, status: 'running');
    final String n3 = ls.liveNote;
    ls.status = 'writing';
    ls.streamingMsg = ChatMessage(id: 'lx', role: 'assistant', content: 'First. Now writing the report for you.');
    final String n4 = ls.liveNote;
    ls.streamingMsg = null;
    ls.status = 'thinking';
    ls.streamingMsg = ChatMessage(id: 'ly', role: 'assistant', thinking: 'SECRET-RAW-THINKING should never be shown. Another raw sentence here.');
    final String n5 = ls.liveNote;
    ls.streamingMsg = null;
    ls.status = '';
    final String n6 = ls.liveNote;
    rec(
      'live note: tool title / derived title / narration / last step while thinking (never the raw thinking) / idle',
      n0 == '' && n1 == 'Listing skills' && n2 == 'Reading the proxy map' && n3 == 'قراءة session.dart' && n4 == 'Now writing the report for you.' && n5 == 'Listing skills' && n6 == '',
      '$n0 | $n1 | $n2 | $n3 | $n4 | $n5 | $n6',
    );

    // ---- لوحة الملخّص: عناوين، خطوات، ترويسة مجمَّعة، وسيط description، بصمة الحلقات
    final List<ToolDef> raw = <ToolDef>[
      ToolDef(kToolReadFile, 'read', <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{'path': <String, dynamic>{'type': 'string'}}}),
      ToolDef(kToolBash, 'bash', <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{'command': <String, dynamic>{'type': 'string'}, 'description': <String, dynamic>{'type': 'string', 'description': 'own'}}}),
      ToolDef(kToolTodoWrite, 'todo', <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{'todos': <String, dynamic>{'type': 'array'}}}),
    ];
    final List<ToolDef> titled = withStepTitles(raw);
    rec(
      'tool schemas: optional description added to file tools only, own description kept, original not mutated',
      asMap(titled[0].schema['properties']).containsKey('description') && asStr(asMap(asMap(titled[1].schema['properties'])['description'])['description']) == 'own' && !asMap(titled[2].schema['properties']).containsKey('description') && !asMap(raw[0].schema['properties']).containsKey('description'),
      '',
    );
    rec(
      'loop signature ignores the step title',
      jsonEncode(argsForSig(<String, dynamic>{'path': 'a', 'description': 'x'})) == jsonEncode(argsForSig(<String, dynamic>{'path': 'a', 'description': 'y'})) && jsonEncode(argsForSig(<String, dynamic>{'path': 'a'})) == '{"path":"a"}',
      '',
    );
    final List<ChatMessage> sampleRun = <ChatMessage>[
      ChatMessage(id: 'a1', role: 'user', content: 'old question'),
      ChatMessage(id: 'a2', role: 'assistant', content: 'old answer'),
      ChatMessage(id: 'u1', role: 'user', content: 'do the work'),
      ChatMessage(id: 's1', role: 'assistant', content: '  Reading the\n   config first.  ', toolCalls: <ToolCall>[
        ToolCall(id: 'c1', name: 'read_file', args: <String, dynamic>{'path': 'lib/session.dart', 'offset': 655}, status: 'done', result: 'x'),
        ToolCall(id: 'c2', name: 'bash', args: <String, dynamic>{'command': 'ls -la\nwc -l', 'description': 'Listing the folder'}, status: 'done', result: 'x'),
      ]),
      ChatMessage(id: 's2', role: 'assistant', toolCalls: <ToolCall>[
        ToolCall(id: 'c3', name: 'edit_file', args: <String, dynamic>{'path': 'lib/a.dart', 'old_string': 'int a = 1;\nint b;', 'new_string': 'int a = 2;'}, status: 'done', result: 'ok'),
        ToolCall(id: 'c4', name: 'edit_file', args: <String, dynamic>{'path': 'lib/a.dart', 'edits': <dynamic>[<String, dynamic>{'old_string': 'x', 'new_string': 'y'}]}, status: 'done', result: 'ok'),
        ToolCall(id: 'c5', name: 'write_file', args: <String, dynamic>{'path': 'lib/b.dart', 'content': 'c'}, status: 'done', result: 'ok'),
        ToolCall(id: 'c6', name: 'fetch_url', args: <String, dynamic>{'url': 'https://docs.claude.com/en/docs/x'}, status: 'error', isError: true, result: 'blocked'),
        ToolCall(id: 'c7', name: 'search_files', args: <String, dynamic>{'pattern': 'liveNote', 'path': '/h/lib'}, status: 'running'),
      ]),
      ChatMessage(id: 's3', role: 'assistant', content: 'Final answer, not a step.'),
    ];
    final List<RunStep> st = buildRunSteps(sampleRun, live: true);
    final List<RunStep> stDead = buildRunSteps(sampleRun, live: false);
    rec(
      'run steps: only the last turn, narration then tools, final answer excluded',
      st.length == 8 && st[0].note && st[0].title == 'Reading the config first.' && !st[1].note && st.last.tool == 'search_files' && st.where((RunStep x) => x.note).length == 1,
      '${st.length} ${st.map((RunStep x) => x.title).join(' | ')}',
    );
    rec(
      'run step titles: derived, written by the model, and details',
      st[1].title == 'قراءة session.dart' && st[1].detail == 'lib/session.dart:655' && st[2].title == 'Listing the folder' && st[2].detail == 'ls -la' && st[3].title == 'تعديل a.dart' && st[5].title == 'كتابة b.dart' && st[6].title == 'فتح docs.claude.com' && st[7].title == 'بحث عن «liveNote»',
      '${st[1].title}/${st[1].detail}/${st[2].title}/${st[2].detail}/${st[3].title}/${st[5].title}/${st[6].title}/${st[7].title}',
    );
    rec(
      'run step status: done / failed / running while live, never stuck as running after the run',
      st[1].status == 'done' && st[6].failed && st[7].running && stDead[7].failed && st[3].minus == '- int a = 1;' && st[3].plus == '+ int a = 2;' && st[4].minus == '- x' && st[4].plus == '+ y' && st[1].minus == null,
      '${st[1].status} ${st[6].status} ${st[7].status} ${stDead[7].status} ${st[3].minus} ${st[3].plus}',
    );
    final String hd = runSummaryHeader(st);
    rec('run header counts distinct edited/written files and the other steps', hd == 'عُدّل ملف، وكُتب ملف، و4 خطوات أخرى', hd);
    RunStep pstep(int i) => RunStep(note: false, title: 't$i', tool: 'bash');
    RunStep ed(String f) => RunStep(note: false, title: 'e', tool: 'edit_file', file: f, edit: true);
    RunStep wr(String f) => RunStep(note: false, title: 'w', tool: 'write_file', file: f, write: true);
    final List<RunStep> big = <RunStep>[ed('a'), ed('b'), wr('c'), ...List<RunStep>.generate(31, pstep)];
    final List<String> hs = <String>[
      runSummaryHeader(big),
      runSummaryHeader(List<RunStep>.generate(12, pstep)),
      runSummaryHeader(List<RunStep>.generate(1, pstep)),
      runSummaryHeader(<RunStep>[ed('a'), ed('b'), ed('c'), pstep(0), pstep(1)]),
      runSummaryHeader(<RunStep>[ed('a'), pstep(0), pstep(1)]),
      runSummaryHeader(<RunStep>[for (int i = 0; i < 11; i++) ed('f$i')]),
      runSummaryHeader(<RunStep>[]),
    ];
    rec(
      'run header: Arabic dual and plural forms',
      hs[0] == 'عُدّل ملفان، وكُتب ملف، و31 خطوة أخرى' && hs[1] == '12 خطوة' && hs[2] == 'خطوة واحدة' && hs[3] == 'عُدّلت 3 ملفات، وخطوتان أخريان' && hs[4] == 'عُدّل ملف، وخطوتان أخريان' && hs[5] == 'عُدّل 11 ملفاً' && hs[6] == '',
      hs.join(' | '),
    );
    rec('display formats', fmtElapsed(const Duration(seconds: 251)) == '4:11' && fmtTokShort(22707) == '22.7k' && fmtTokShort(680000) == '680k' && fmtTokShort(999) == '999', '${fmtElapsed(const Duration(seconds: 251))} ${fmtTokShort(22707)} ${fmtTokShort(680000)}');

    // ---- v2.13.0: حدود التشغيل، الاستهلاك الفعلي، طيّ الجولات في الدردشة، وحقول الخطوة
    rec('thousands separators', fmtNum(612402) == '612,402' && fmtNum(0) == '0' && fmtNum(999) == '999' && fmtNum(1000) == '1,000' && fmtNum(22707) == '22,707' && fmtNum(1234567) == '1,234,567' && fmtNum(-1500) == '-1,500', '${fmtNum(612402)} ${fmtNum(1234567)} ${fmtNum(-1500)}');
    ChatMessage rm(String id, {String content = '', List<ToolCall>? calls, int inTok = 0, int cache = 0, int outTok = 0, int think = 0, String? error, String thinking = ''}) {
      return ChatMessage(id: id, role: 'assistant', content: content, toolCalls: calls, inTok: inTok, cacheTok: cache, outTok: outTok, thinkTok: think, error: error, thinking: thinking, model: 'm1');
    }

    ToolCall tcall(String id) => ToolCall(id: id, name: 'current_time', status: 'done', result: 'x');
    final List<ChatMessage> two = <ChatMessage>[
      ChatMessage(id: 'q1', role: 'user', content: 'first'),
      rm('r1', calls: <ToolCall>[tcall('t1')], inTok: 100, cache: 80, outTok: 10, think: 4, thinking: 'hmm'),
      rm('r2', calls: <ToolCall>[tcall('t2')], inTok: 120, cache: 100, outTok: 12),
      ChatMessage(id: 'inj', role: 'user', content: 'also this', injected: true),
      rm('r3', calls: <ToolCall>[tcall('t3')], inTok: 140, cache: 120, outTok: 14),
      rm('r4', content: 'done 1', inTok: 160, cache: 140, outTok: 20),
      ChatMessage(id: 'q2', role: 'user', content: 'second'),
      rm('r5', calls: <ToolCall>[tcall('t5')]),
      rm('r6', content: 'done 2', inTok: 50, outTok: 5),
    ];
    final RunSpan spLast = runSpanAt(two);
    final RunSpan spFirst = runSpanAt(two, 2);
    rec(
      'run spans: last run by default, the run containing a given message otherwise',
      spLast.start == 7 && spLast.end == 9 && spFirst.start == 1 && spFirst.end == 6 && runSpanAt(<ChatMessage>[]).start == 0,
      '${spLast.start}-${spLast.end} ${spFirst.start}-${spFirst.end}',
    );
    rec('run steps of an older run by index', buildRunSteps(two, at: 2).length == 3 && buildRunSteps(two).length == 1, '${buildRunSteps(two, at: 2).length} ${buildRunSteps(two).length}');
    final List<int> folds = List<int>.generate(two.length, (int i) => isFoldedRound(two, i) ? (isRunHeaderAt(two, i) ? 2 : 1) : 0);
    rec('chat folding: middle tool rounds fold, one header per run (an injected user message does not add another)', folds.join(',') == '0,2,1,0,1,0,0,2,0', folds.join(','));
    final List<ChatMessage> withErr = <ChatMessage>[
      ChatMessage(id: 'e0', role: 'user', content: 'go'),
      rm('e1', calls: <ToolCall>[tcall('t1')], error: 'boom'),
      rm('e2', content: 'after'),
    ];
    rec('chat folding: a round with an error stays visible', !isFoldedRound(withErr, 1), '');
    final RunUsage ru1 = runUsageAt(two, 2);
    final RunUsage ru2 = runUsageAt(two);
    rec(
      'run usage: exact sums, cache share, model; unreported requests counted not estimated',
      ru1.requests == 4 && ru1.input == 520 && ru1.cached == 440 && ru1.output == 56 && ru1.thinking == 4 && ru1.noUsage == 0 && ru1.thinkMissing == 0 && ru1.cachePct == 85 && ru1.model == 'm1' && ru2.requests == 2 && ru2.noUsage == 1 && ru2.input == 50 && ru2.output == 5 && ru2.cached == 0,
      '${ru1.requests}/${ru1.input}/${ru1.cached}/${ru1.output}/${ru1.thinking} ${ru2.requests}/${ru2.noUsage}/${ru2.input}',
    );
    final RunUsage ru3 = usageOfMessages(<ChatMessage>[rm('x', content: 'a', inTok: 10, outTok: 2, thinking: 'private thoughts')]);
    rec(
      'usage captions and notes: Arabic plurals, shortfall notes',
      usageCaption(ru1) == 'm1 · 4 طلبات · كاش 85%' && usageCaption(ru2) == 'm1 · طلبان · كاش 0%' && usageCaption(const RunUsage(requests: 11)) == '11 طلباً' && usageCaption(const RunUsage(requests: 1)) == 'طلب واحد' && usageNotes(ru1).isEmpty && usageNotes(ru2).length == 1 && ru3.thinkMissing == 1 && usageNotes(ru3).length == 1,
      '${usageCaption(ru1)} | ${usageCaption(ru2)} | ${usageNotes(ru2).join(' ')}',
    );
    rec(
      'run step carries the failure reason and the call itself',
      st[6].error == 'blocked' && st[6].call != null && st[6].call!.id == 'c6' && st[0].call == null && stDead[7].error == '' && st[1].error == '',
      '${st[6].error} ${st[6].call?.id} ${stDead[7].error}',
    );
    final ChatSession prev = previewSummarySession();
    final List<int> pf = List<int>.generate(prev.messages.length, (int i) => isFoldedRound(prev.messages, i) ? (isRunHeaderAt(prev.messages, i) ? 2 : 1) : 0);
    final String ph = runSummaryHeader(buildRunSteps(prev.messages));
    rec('preview sample builds the expected header and folds', ph == 'عُدّل ملف، و5 خطوات أخرى' && pf.join(',') == '0,2,1,1,1,0', '$ph ${pf.join(',')}');

    // ---- الاحتياط: خادم تجاهل البث (لا أحداث) لا يُعدّ مقطوعاً
    rec('no events is not a truncation', truncationError(kAnthropic, SseState()) == null, '');

    // ---- Gemini: «التفكير مُطفأ» يُترجم إلى thinkingLevel=minimal لنماذج Gemini 3 flash فقط (قياس CI: 0 توكن تفكير)
    Map<String, dynamic>? gcfg(String model, int level, {Set<String> heal = const <String>{}}) {
      final GenRequest gr = GenRequest(
        profile: const ApiProfile(id: 'gm', name: 'gm', kind: kGemini, baseUrl: 'https://generativelanguage.googleapis.com', apiKey: 'k', selectedModel: 'x'),
        model: model,
        system: '',
        msgs: <RMsg>[RMsg.user(const <RPart>[RPart.text('hi')])],
        tools: const <ToolDef>[],
        thinkLevel: level,
      );
      gr.heal.addAll(heal);
      final dynamic g = geminiBody(gr)['generationConfig'];
      return g is Map ? (g['thinkingConfig'] is Map ? Map<String, dynamic>.from(g['thinkingConfig'] as Map) : <String, dynamic>{}) : null;
    }

    final Map<String, dynamic>? t35 = gcfg('gemini-3.5-flash', 0);
    final Map<String, dynamic>? tLite = gcfg('models/gemini-3.1-flash-lite', 0);
    final Map<String, dynamic>? tPro = gcfg('gemini-3.1-pro', 0);
    final Map<String, dynamic>? t25 = gcfg('gemini-2.5-flash', 0);
    final Map<String, dynamic>? tMed = gcfg('gemini-3.5-flash', 2);
    final Map<String, dynamic>? tHeal = gcfg('gemini-3.5-flash', 0, heal: <String>{'nothink'});
    rec('gemini 3 flash with thinking off asks for thinkingLevel=minimal', t35 != null && t35['thinkingLevel'] == 'minimal' && tLite != null && tLite['thinkingLevel'] == 'minimal', '$t35 $tLite');
    rec('gemini pro, 2.5 and a healed request send no thinkingConfig when thinking is off', (tPro == null || tPro.isEmpty) && (t25 == null || t25.isEmpty) && (tHeal == null || tHeal.isEmpty), '$tPro $t25 $tHeal');
    rec('gemini 3 flash with thinking on keeps the chosen level and thoughts', tMed != null && tMed['thinkingLevel'] == 'medium' && tMed['includeThoughts'] == true, '$tMed');
    final GenRequest gh = GenRequest(
      profile: const ApiProfile(id: 'gm', name: 'gm', kind: kGemini, baseUrl: 'https://generativelanguage.googleapis.com', apiKey: 'k', selectedModel: 'x'),
      model: 'gemini-3.5-flash',
      system: '',
      msgs: <RMsg>[RMsg.user(const <RPart>[RPart.text('hi')])],
      tools: const <ToolDef>[],
    );
    final bool healed = gh.tryHeal(ApiException('Invalid thinking level for this model', status: 400));
    rec('a 400 that mentions thinking drops the thinking config even when thinking is off', healed && gh.heal.contains('nothink'), '${gh.heal}');
  } catch (e) {
    rec('engine tests', false, '$e');
  }
  out('DONE fails=$fails total=$total');
}
