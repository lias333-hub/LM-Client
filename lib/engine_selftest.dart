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

    // ---- الاحتياط: خادم تجاهل البث (لا أحداث) لا يُعدّ مقطوعاً
    rec('no events is not a truncation', truncationError(kAnthropic, SseState()) == null, '');
  } catch (e) {
    rec('engine tests', false, '$e');
  }
  out('DONE fails=$fails total=$total');
}
