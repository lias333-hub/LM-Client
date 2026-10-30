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
    ls.status = 'thinking';
    ls.streamingMsg = ChatMessage(id: 'lx', role: 'assistant', thinking: 'First. Now checking the bashrc file for tokens.');
    final String n1 = ls.liveNote;
    ls.streamingMsg = null;
    ls.status = 'tool:bash';
    ls.runningCall = ToolCall(id: 'lt', name: 'bash', args: <String, dynamic>{'command': 'ls', 'description': 'Listing skills'});
    final String n2 = ls.liveNote;
    ls.messages.add(ChatMessage(id: 'lm', role: 'assistant', content: 'Checking the proxy config in one command.'));
    ls.runningCall = ToolCall(id: 'lt2', name: 'bash', args: <String, dynamic>{'command': 'ls'});
    final String n3 = ls.liveNote;
    ls.status = '';
    final String n4 = ls.liveNote;
    rec('live note: thinking / tool description / narration / idle', n1 == 'Now checking the bashrc file for tokens.' && n2 == 'Listing skills' && n3 == 'Checking the proxy config in one command.' && n4 == '', '$n1 | $n2 | $n3 | $n4');
    rec('display formats', fmtElapsed(const Duration(seconds: 251)) == '4:11' && fmtTokShort(22707) == '22.7k' && fmtTokShort(680000) == '680k' && fmtTokShort(999) == '999', '${fmtElapsed(const Duration(seconds: 251))} ${fmtTokShort(22707)} ${fmtTokShort(680000)}');

    // ---- الاحتياط: خادم تجاهل البث (لا أحداث) لا يُعدّ مقطوعاً
    rec('no events is not a truncation', truncationError(kAnthropic, SseState()) == null, '');
  } catch (e) {
    rec('engine tests', false, '$e');
  }
  out('DONE fails=$fails total=$total');
}
