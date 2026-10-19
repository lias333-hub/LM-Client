// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, unused_local_variable, avoid_print, deprecated_member_use, use_build_context_synchronously, prefer_const_constructors, prefer_const_literals_to_create_immutables, depend_on_referenced_packages, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, unnecessary_import
part of 'main.dart';

// ---------------------------------------------------------------------
//  LLM layer: native adapters for OpenAI-compatible / Anthropic / Gemini
// ---------------------------------------------------------------------
const List<String> kEffort = <String>['low', 'medium', 'high'];
const List<int> kBudgets = <int>[2048, 8192, 16384];
const List<int> kGeminiBudgets = <int>[1024, 8192, 24576];

int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
int? toInt(dynamic v) => v is num ? v.toInt() : null;

class ApiException implements Exception {
  final int? status;
  final String message;
  final String body;
  final bool netError;
  ApiException(this.message, {this.status, this.body = '', this.netError = false});
  bool get retriable {
    final s = status;
    if (s == null) return netError;
    return s == 408 || s == 409 || s == 429 || (s >= 500 && s <= 599);
  }

  @override
  String toString() => message;
}

class ToolDef {
  final String name;
  final String description;
  final Map<String, dynamic> schema;
  const ToolDef(this.name, this.description, this.schema);
}

/// جزء من محتوى رسالة بعد تحميل المرفقات (نص / صورة / PDF).
class RPart {
  final String kind; // text | image | pdf
  final String text;
  final String mime;
  final String b64;
  final String name;
  const RPart.text(this.text)
      : kind = 'text',
        mime = '',
        b64 = '',
        name = '';
  const RPart.image(this.mime, this.b64)
      : kind = 'image',
        text = '',
        name = '';
  const RPart.pdf(this.name, this.b64)
      : kind = 'pdf',
        text = '',
        mime = 'application/pdf';
}

/// رسالة جاهزة للإرسال (مستقلة عن المزوّد).
class RMsg {
  final String role;
  final List<RPart> parts; // للمستخدم
  final String text; // للمساعد
  final List<ToolCall> calls;
  final String thinking;
  final String? thinkSig;
  final List<String> redacted;
  RMsg.user(this.parts)
      : role = 'user',
        text = '',
        calls = const <ToolCall>[],
        thinking = '',
        thinkSig = null,
        redacted = const <String>[];
  RMsg.assistant({required this.text, this.calls = const <ToolCall>[], this.thinking = '', this.thinkSig, this.redacted = const <String>[]})
      : role = 'assistant',
        parts = const <RPart>[];
}

double claudeVersion(String id) {
  final s = id.toLowerCase();
  final m = RegExp(r'claude-(?:opus|sonnet|haiku|fable|mythos)-(\d+)(?:-(\d{1,2}))?(?!\d)').firstMatch(s);
  if (m != null) {
    final major = int.parse(m.group(1)!);
    final minor = m.group(2) == null ? 0 : int.parse(m.group(2)!);
    return major + minor / 10.0;
  }
  final o = RegExp(r'claude-(\d+)(?:-(\d{1,2}))?-(?:opus|sonnet|haiku)').firstMatch(s);
  if (o != null) {
    final major = int.parse(o.group(1)!);
    final minor = o.group(2) == null ? 0 : int.parse(o.group(2)!);
    return major + minor / 10.0;
  }
  return 0;
}

class GenRequest {
  final ApiProfile profile;
  final String model;
  final String system;
  final List<RMsg> msgs;
  final List<ToolDef> tools;
  final double temperature;
  final double topP;
  final int maxTokens;
  final int thinkLevel;
  final int thinkMode;
  /// Anthropic فقط: وضع علامات cache_control على الـ system وآخر رسالة. (OpenAI وGemini يخزّنان تلقائياً.)
  final bool cache;
  final Set<String> heal = <String>{};
  int capTokens = 0;
  // وضع التفكير الذي فرضه الإصلاح الذاتي. يُقلب مرة واحدة فقط لتفادي حلقة لا نهائية.
  String forcedMode = '';
  bool _modeFlipped = false;

  GenRequest({
    required this.profile,
    required this.model,
    required this.system,
    required this.msgs,
    required this.tools,
    this.temperature = -1,
    this.topP = -1,
    this.maxTokens = 0,
    this.thinkLevel = 0,
    this.thinkMode = 0,
    this.cache = true,
  });

  /// off | adaptive | budget   (Anthropic فقط)
  String anthropicMode() {
    if (thinkLevel <= 0 || heal.contains('nothink')) return 'off';
    if (forcedMode.isNotEmpty) return forcedMode;
    if (thinkMode == 1) return 'adaptive';
    if (thinkMode == 2) return 'budget';
    return claudeVersion(model) >= 4.6 ? 'adaptive' : 'budget';
  }

  bool _add(String f) {
    if (heal.contains(f)) return false;
    heal.add(f);
    return true;
  }

  /// إصلاح ذاتي: يقرأ رسالة الخطأ ويعدّل الطلب ثم يطلب إعادة المحاولة. يعيد true إن تغيّر شيء.
  bool tryHeal(ApiException e) {
    if (e.status != 400 && e.status != 422) return false;
    final t = ('${e.message} ${e.body}').toLowerCase();
    final k = profile.kind;
    if (k == kAnthropic) {
      // خادم متوافق مع Anthropic لا يعرف cache_control: نعيد الطلب بدونه.
      if (cache && t.contains('cache_control') && _add('nocache')) return true;
      final m = RegExp(r'max_tokens:\s*\d+\s*>\s*(\d+)').firstMatch(t);
      if (m != null) {
        final n = int.parse(m.group(1)!);
        if (capTokens != n) {
          capTokens = n;
          heal.add('cap:$n');
          return true;
        }
      }
      if (t.contains('thinking.type') || t.contains('adaptive') || t.contains('budget_tokens')) {
        final cur = anthropicMode();
        if (!_modeFlipped && (cur == 'adaptive' || cur == 'budget')) {
          _modeFlipped = true;
          forcedMode = cur == 'adaptive' ? 'budget' : 'adaptive';
          heal.add('mode:$forcedMode');
          return true;
        }
      }
      if (t.contains('effort') && _add('noeffort')) return true;
      if (t.contains('top_p') && _add('notopp')) return true;
      if (t.contains('temperature') && _add('notemp')) return true;
      if (t.contains('thinking') && thinkLevel > 0 && _add('nothink')) return true;
      return false;
    }
    if (k == kGemini) {
      if ((t.contains('thought_signature') || t.contains('thoughtsignature')) && _add('dummysig')) return true;
      if (t.contains('thinking') && thinkLevel > 0 && _add('nothink')) return true;
      return false;
    }
    if (t.contains('max_completion_tokens') && _add('maxcomp')) return true;
    if (t.contains('stream_options') && _add('nostreamopt')) return true;
    if (t.contains('temperature') && _add('notemp')) return true;
    if (t.contains('top_p') && _add('notopp')) return true;
    if ((t.contains('reasoning') || t.contains('thinking')) && thinkLevel > 0 && _add('nothink')) return true;
    return false;
  }
}

class LlmEvent {
  final String text;
  final String thinking;
  final String? sig;
  final String? redacted;
  final String? stop;
  final ToolCall? call;
  final int? inTok;
  final int? outTok;
  final int? cacheTok;
  const LlmEvent({this.text = '', this.thinking = '', this.sig, this.redacted, this.stop, this.call, this.inTok, this.outTok, this.cacheTok});
}

class PreparedCall {
  final Uri url;
  final Map<String, String> headers;
  final Map<String, dynamic> body;
  PreparedCall(this.url, this.headers, this.body);
}

// ---------------------------------------------------------------------
//  URLs & headers
// ---------------------------------------------------------------------
String _trimSlash(String s) {
  var r = s.trim();
  while (r.endsWith('/')) {
    r = r.substring(0, r.length - 1);
  }
  return r;
}

String _normBase(String b) {
  var r = _trimSlash(b);
  if (!r.contains('://')) r = 'https://$r';
  return r;
}

String _pathOf(String b) {
  final u = Uri.tryParse(b);
  return u == null ? '' : _trimSlash(u.path);
}

String openAiRoot(String base) {
  var b = _normBase(base);
  if (b.endsWith('/chat/completions')) b = b.substring(0, b.length - '/chat/completions'.length);
  if (_pathOf(b).isEmpty) b = '$b/v1';
  return b;
}

String anthropicRoot(String base) {
  var b = _normBase(base);
  if (b.endsWith('/messages')) b = b.substring(0, b.length - '/messages'.length);
  if (!RegExp(r'/v\d+$').hasMatch(b)) b = '$b/v1';
  return b;
}

String geminiRoot(String base) {
  var b = _normBase(base);
  if (!RegExp(r'/v\d+(beta|alpha)?\d*$').hasMatch(b)) b = '$b/v1beta';
  return b;
}

Map<String, String> buildHeaders(ApiProfile p) {
  final h = <String, String>{};
  final k = p.apiKey.trim();
  if (p.kind == kAnthropic) {
    if (k.isNotEmpty) h['x-api-key'] = k;
    h['anthropic-version'] = '2023-06-01';
  } else if (p.kind == kGemini) {
    if (k.isNotEmpty) h['x-goog-api-key'] = k;
  } else if (k.isNotEmpty) {
    h['Authorization'] = 'Bearer $k';
  }
  for (final line in p.headers.split('\n')) {
    final i = line.indexOf(':');
    if (i <= 0) continue;
    final name = line.substring(0, i).trim();
    final val = line.substring(i + 1).trim();
    if (name.isNotEmpty) h[name] = val;
  }
  return h;
}

// ---------------------------------------------------------------------
//  Request bodies
// ---------------------------------------------------------------------
Map<String, dynamic> openAiBody(GenRequest r) {
  final msgs = <Map<String, dynamic>>[];
  if (r.system.trim().isNotEmpty) msgs.add(<String, dynamic>{'role': 'system', 'content': r.system});
  for (final m in r.msgs) {
    if (m.role == 'user') {
      bool onlyText = true;
      for (final p in m.parts) {
        if (p.kind != 'text') onlyText = false;
      }
      if (onlyText) {
        msgs.add(<String, dynamic>{'role': 'user', 'content': m.parts.map((p) => p.text).join('\n\n')});
      } else {
        final c = <Map<String, dynamic>>[];
        for (final p in m.parts) {
          if (p.kind == 'text') {
            c.add(<String, dynamic>{'type': 'text', 'text': p.text});
          } else if (p.kind == 'image') {
            c.add(<String, dynamic>{
              'type': 'image_url',
              'image_url': <String, dynamic>{'url': 'data:${p.mime};base64,${p.b64}'}
            });
          } else if (p.kind == 'pdf') {
            c.add(<String, dynamic>{
              'type': 'file',
              'file': <String, dynamic>{'filename': p.name, 'file_data': 'data:application/pdf;base64,${p.b64}'}
            });
          }
        }
        msgs.add(<String, dynamic>{'role': 'user', 'content': c});
      }
    } else {
      final am = <String, dynamic>{'role': 'assistant', 'content': m.text};
      if (m.calls.isNotEmpty) {
        am['tool_calls'] = m.calls
            .map((c) => <String, dynamic>{
                  'id': c.id,
                  'type': 'function',
                  'function': <String, dynamic>{'name': c.name, 'arguments': jsonEncode(c.args)}
                })
            .toList();
      }
      msgs.add(am);
      for (final c in m.calls) {
        msgs.add(<String, dynamic>{'role': 'tool', 'tool_call_id': c.id, 'content': c.result ?? 'Tool execution was interrupted.'});
      }
    }
  }
  final body = <String, dynamic>{'model': r.model, 'messages': msgs, 'stream': true};
  if (r.profile.streamUsage && !r.heal.contains('nostreamopt')) {
    body['stream_options'] = <String, dynamic>{'include_usage': true};
  }
  if (r.temperature >= 0 && !r.heal.contains('notemp')) body['temperature'] = r.temperature;
  if (r.topP >= 0 && !r.heal.contains('notopp')) body['top_p'] = r.topP;
  if (r.maxTokens > 0) body[r.heal.contains('maxcomp') ? 'max_completion_tokens' : 'max_tokens'] = r.maxTokens;
  if (r.thinkLevel > 0 && !r.heal.contains('nothink')) {
    body['reasoning_effort'] = kEffort[clampInt(r.thinkLevel, 1, 3) - 1];
  }
  if (r.tools.isNotEmpty) {
    body['tools'] = r.tools
        .map((t) => <String, dynamic>{
              'type': 'function',
              'function': <String, dynamic>{'name': t.name, 'description': t.description, 'parameters': t.schema}
            })
        .toList();
  }
  return body;
}

List<Map<String, dynamic>> anthropicMessages(GenRequest r, bool passThinking) {
  final out = <Map<String, dynamic>>[];
  for (final m in r.msgs) {
    if (m.role == 'user') {
      final content = <Map<String, dynamic>>[];
      for (final p in m.parts) {
        if (p.kind == 'image') {
          content.add(<String, dynamic>{
            'type': 'image',
            'source': <String, dynamic>{'type': 'base64', 'media_type': p.mime, 'data': p.b64}
          });
        } else if (p.kind == 'pdf') {
          content.add(<String, dynamic>{
            'type': 'document',
            'source': <String, dynamic>{'type': 'base64', 'media_type': 'application/pdf', 'data': p.b64}
          });
        } else if (p.text.trim().isNotEmpty) {
          content.add(<String, dynamic>{'type': 'text', 'text': p.text});
        }
      }
      if (content.isEmpty) content.add(<String, dynamic>{'type': 'text', 'text': '.'});
      if (out.isNotEmpty && out.last['role'] == 'user') {
        // رسالة محقونة بعد نتائج الأدوات: ندمجها في نفس الدور (نتائج الأدوات أولاً ثم النص).
        (out.last['content'] as List<Map<String, dynamic>>).addAll(content);
      } else {
        out.add(<String, dynamic>{'role': 'user', 'content': content});
      }
    } else {
      final content = <Map<String, dynamic>>[];
      final sig = m.thinkSig;
      if (passThinking && sig != null && sig.isNotEmpty) {
        content.add(<String, dynamic>{'type': 'thinking', 'thinking': m.thinking, 'signature': sig});
      }
      if (passThinking) {
        for (final d in m.redacted) {
          content.add(<String, dynamic>{'type': 'redacted_thinking', 'data': d});
        }
      }
      if (m.text.trim().isNotEmpty) content.add(<String, dynamic>{'type': 'text', 'text': m.text});
      for (final c in m.calls) {
        content.add(<String, dynamic>{'type': 'tool_use', 'id': c.id, 'name': c.name, 'input': c.args});
      }
      if (content.isEmpty) continue;
      out.add(<String, dynamic>{'role': 'assistant', 'content': content});
      if (m.calls.isNotEmpty) {
        final results = <Map<String, dynamic>>[];
        for (final c in m.calls) {
          final res = <String, dynamic>{
            'type': 'tool_result',
            'tool_use_id': c.id,
            'content': c.result ?? 'Tool execution was interrupted.',
          };
          if (c.isError || c.result == null) res['is_error'] = true;
          results.add(res);
        }
        out.add(<String, dynamic>{'role': 'user', 'content': results});
      }
    }
  }
  return out;
}

Map<String, dynamic> anthropicBody(GenRequest r) {
  final mode = r.anthropicMode();
  int maxTok = r.maxTokens > 0 ? r.maxTokens : 8192;
  if (r.capTokens > 0 && maxTok > r.capTokens) maxTok = r.capTokens;
  final useCache = r.cache && !r.heal.contains('nocache');
  // التوثيق: "pass them back unmodified, particularly during tool use" (في الوضعين budget وadaptive).
  final msgs = anthropicMessages(r, mode != 'off');
  if (useCache && msgs.isNotEmpty) {
    // علامة على آخر كتلة: كل ما قبلها (الأدوات + system + المحادثة) يُقرأ من الكاش في الطلب التالي.
    final lc = msgs.last['content'];
    if (lc is List && lc.isNotEmpty) {
      final lb = lc.last;
      if (lb is Map<String, dynamic>) lb['cache_control'] = <String, dynamic>{'type': 'ephemeral'};
    }
  }
  final body = <String, dynamic>{
    'model': r.model,
    'max_tokens': maxTok,
    'stream': true,
    'messages': msgs,
  };
  if (r.system.trim().isNotEmpty) {
    if (useCache) {
      // علامة على الـ system تغطي الأدوات أيضاً (الترتيب: tools ← system ← messages).
      body['system'] = <Map<String, dynamic>>[
        <String, dynamic>{'type': 'text', 'text': r.system, 'cache_control': <String, dynamic>{'type': 'ephemeral'}}
      ];
    } else {
      body['system'] = r.system;
    }
  }
  final lv = clampInt(r.thinkLevel, 1, 3);
  if (mode == 'adaptive') {
    body['thinking'] = <String, dynamic>{'type': 'adaptive'};
    if (!r.heal.contains('noeffort')) body['output_config'] = <String, dynamic>{'effort': kEffort[lv - 1]};
  } else if (mode == 'budget') {
    final budget = kBudgets[lv - 1];
    int mt = maxTok;
    if (mt <= budget) mt = budget + 4096;
    if (r.capTokens > 0 && mt > r.capTokens) mt = r.capTokens;
    if (mt > budget) {
      body['thinking'] = <String, dynamic>{'type': 'enabled', 'budget_tokens': budget};
      body['max_tokens'] = mt;
    }
  }
  final thinkingOn = body.containsKey('thinking');
  if (!thinkingOn) {
    if (r.temperature >= 0 && !r.heal.contains('notemp')) {
      body['temperature'] = r.temperature;
    } else if (r.topP >= 0 && r.temperature < 0 && !r.heal.contains('notopp')) {
      body['top_p'] = r.topP;
    }
  }
  if (r.tools.isNotEmpty) {
    body['tools'] = r.tools
        .map((t) => <String, dynamic>{'name': t.name, 'description': t.description, 'input_schema': t.schema})
        .toList();
  }
  return body;
}

dynamic geminiSchema(dynamic v) {
  if (v is Map) {
    final out = <String, dynamic>{};
    v.forEach((k, val) {
      final key = k.toString();
      if (key == 'additionalProperties') return;
      if (key == 'type' && val is String) {
        out[key] = val.toUpperCase();
      } else {
        out[key] = geminiSchema(val);
      }
    });
    return out;
  }
  if (v is List) return v.map((e) => geminiSchema(e)).toList();
  return v;
}

Map<String, dynamic> geminiBody(GenRequest r) {
  final contents = <Map<String, dynamic>>[];
  void push(String role, List<Map<String, dynamic>> parts) {
    if (parts.isEmpty) return;
    if (contents.isNotEmpty && contents.last['role'] == role) {
      (contents.last['parts'] as List).addAll(parts);
    } else {
      contents.add(<String, dynamic>{'role': role, 'parts': parts});
    }
  }

  for (final m in r.msgs) {
    if (m.role == 'user') {
      final parts = <Map<String, dynamic>>[];
      for (final p in m.parts) {
        if (p.kind == 'image') {
          parts.add(<String, dynamic>{
            'inlineData': <String, dynamic>{'mimeType': p.mime, 'data': p.b64}
          });
        } else if (p.kind == 'pdf') {
          parts.add(<String, dynamic>{
            'inlineData': <String, dynamic>{'mimeType': 'application/pdf', 'data': p.b64}
          });
        } else if (p.text.trim().isNotEmpty) {
          parts.add(<String, dynamic>{'text': p.text});
        }
      }
      if (parts.isEmpty) parts.add(<String, dynamic>{'text': '.'});
      push('user', parts);
    } else {
      final parts = <Map<String, dynamic>>[];
      if (m.text.trim().isNotEmpty) parts.add(<String, dynamic>{'text': m.text});
      for (final c in m.calls) {
        final part = <String, dynamic>{
          'functionCall': <String, dynamic>{'name': c.name, 'args': c.args}
        };
        if (c.sig != null && c.sig!.isNotEmpty) {
          part['thoughtSignature'] = c.sig;
        } else if (r.heal.contains('dummysig')) {
          part['thoughtSignature'] = 'skip_thought_signature_validator';
        }
        parts.add(part);
      }
      push('model', parts);
      if (m.calls.isNotEmpty) {
        final rs = <Map<String, dynamic>>[];
        for (final c in m.calls) {
          final resp = c.isError ? <String, dynamic>{'error': c.result ?? 'error'} : <String, dynamic>{'result': c.result ?? 'Tool execution was interrupted.'};
          rs.add(<String, dynamic>{
            'functionResponse': <String, dynamic>{'name': c.name, 'response': resp}
          });
        }
        push('user', rs);
      }
    }
  }
  final body = <String, dynamic>{'contents': contents};
  if (r.system.trim().isNotEmpty) {
    body['systemInstruction'] = <String, dynamic>{
      'parts': <Map<String, dynamic>>[
        <String, dynamic>{'text': r.system}
      ]
    };
  }
  final gc = <String, dynamic>{};
  if (r.temperature >= 0) gc['temperature'] = r.temperature;
  if (r.topP >= 0) gc['topP'] = r.topP;
  if (r.maxTokens > 0) gc['maxOutputTokens'] = r.maxTokens;
  if (r.thinkLevel > 0 && !r.heal.contains('nothink')) {
    final lv = clampInt(r.thinkLevel, 1, 3);
    final ml = r.model.toLowerCase();
    if (ml.contains('gemini-3')) {
      gc['thinkingConfig'] = <String, dynamic>{'thinkingLevel': kEffort[lv - 1], 'includeThoughts': true};
    } else if (ml.contains('gemini-2.5') || ml.contains('thinking')) {
      gc['thinkingConfig'] = <String, dynamic>{'thinkingBudget': kGeminiBudgets[lv - 1], 'includeThoughts': true};
    }
  }
  if (gc.isNotEmpty) body['generationConfig'] = gc;
  if (r.tools.isNotEmpty) {
    body['tools'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'functionDeclarations': r.tools.map((t) {
          final d = <String, dynamic>{'name': t.name, 'description': t.description};
          // Gemini يرفض OBJECT بلا properties: الأداة بلا وسائط تُرسل دون parameters.
          final props = t.schema['properties'];
          if (props is Map && props.isNotEmpty) d['parameters'] = geminiSchema(t.schema);
          return d;
        }).toList()
      }
    ];
  }
  return body;
}

PreparedCall prepareCall(GenRequest r) {
  final p = r.profile;
  final headers = buildHeaders(p);
  if (p.kind == kAnthropic) {
    return PreparedCall(Uri.parse('${anthropicRoot(p.baseUrl)}/messages'), headers, anthropicBody(r));
  }
  if (p.kind == kGemini) {
    final m = r.model.startsWith('models/') ? r.model.substring(7) : r.model;
    return PreparedCall(Uri.parse('${geminiRoot(p.baseUrl)}/models/$m:streamGenerateContent?alt=sse'), headers, geminiBody(r));
  }
  return PreparedCall(Uri.parse('${openAiRoot(p.baseUrl)}/chat/completions'), headers, openAiBody(r));
}

// ---------------------------------------------------------------------
//  Errors
// ---------------------------------------------------------------------
String errMsg(dynamic e) {
  if (e is Map) {
    final m = e['message'];
    final t = e['type'] ?? e['status'] ?? e['code'];
    if (m is String && m.isNotEmpty) return t == null ? m : '$m ($t)';
    return jsonEncode(e);
  }
  if (e is String) return e;
  return e.toString();
}

String extractErrorText(String body) {
  final b = body.trim();
  if (b.isEmpty) return '';
  try {
    dynamic j = jsonDecode(b);
    if (j is List && j.isNotEmpty) j = j.first;
    if (j is Map) {
      if (j['error'] != null) return errMsg(j['error']);
      if (j['message'] is String) return j['message'] as String;
      if (j['detail'] is String) return j['detail'] as String;
      if (j['detail'] != null) return jsonEncode(j['detail']);
    }
  } catch (_) {}
  return clip(b, 800);
}

Future<ApiException> toApiException(Object e) async {
  if (e is ApiException) return e;
  if (e is DioException) {
    final r = e.response;
    if (r != null) {
      String body = '';
      final d = r.data;
      try {
        if (d is ResponseBody) {
          final bytes = <int>[];
          await for (final c in d.stream) {
            bytes.addAll(c);
          }
          body = utf8.decode(bytes, allowMalformed: true);
        } else if (d is String) {
          body = d;
        } else if (d != null) {
          body = jsonEncode(d);
        }
      } catch (_) {}
      var msg = extractErrorText(body);
      final code = r.statusCode;
      if (msg.isEmpty) msg = e.message ?? 'خطأ غير معروف';
      if (code == 401 || code == 403) msg = '$msg — تحقق من مفتاح الـ API والصلاحيات';
      if (code == 404) msg = '$msg — تحقق من الرابط (Base URL) واسم الموديل';
      return ApiException(code == null ? msg : '[$code] ${clip(msg, 1200)}', status: code, body: body);
    }
    String why;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        why = 'انتهت مهلة الاتصال بالخادم';
        break;
      case DioExceptionType.sendTimeout:
        why = 'انتهت مهلة إرسال الطلب';
        break;
      case DioExceptionType.receiveTimeout:
        why = 'انتهت مهلة انتظار الرد';
        break;
      case DioExceptionType.badCertificate:
        why = 'شهادة SSL غير موثوقة';
        break;
      case DioExceptionType.connectionError:
        why = 'تعذر الاتصال (تحقق من الإنترنت والرابط)';
        break;
      default:
        why = 'خطأ في الشبكة';
    }
    final detail = e.error == null ? '' : ' — ${clip(e.error.toString(), 200)}';
    return ApiException('$why$detail', netError: true);
  }
  return ApiException(e.toString());
}

bool isCancel(Object e) => e is DioException && e.type == DioExceptionType.cancel;

// ---------------------------------------------------------------------
//  SSE parsing
// ---------------------------------------------------------------------
class SseState {
  int events = 0;
  final List<String> raw = <String>[];
}

Stream<Map<String, dynamic>> sseJson(Stream<String> lines, SseState st) async* {
  await for (final line in lines) {
    if (line.isEmpty) continue;
    if (line.startsWith('data:')) {
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      if (payload == '[DONE]') return;
      dynamic j;
      try {
        j = jsonDecode(payload);
      } catch (_) {
        continue;
      }
      if (j is Map) {
        st.events++;
        yield Map<String, dynamic>.from(j);
      }
    } else if (line.startsWith('event:') || line.startsWith(':') || line.startsWith('id:') || line.startsWith('retry:')) {
      continue;
    } else {
      if (st.raw.length < 400) st.raw.add(line);
    }
  }
}

Map<String, dynamic> decodeArgs(String s) {
  final t = s.trim();
  if (t.isEmpty) return <String, dynamic>{};
  try {
    final v = jsonDecode(t);
    if (v is Map) return Map<String, dynamic>.from(v);
  } catch (_) {}
  return <String, dynamic>{'_raw': t};
}

class SplitOut {
  final String text;
  final String thinking;
  const SplitOut(this.text, this.thinking);
}

/// يفصل <think>…</think> داخل النص (بعض الخوادم المحلية والوسيطة تدمج التفكير في الرد).
class ThinkSplitter {
  bool inThink = false;
  String _buf = '';

  SplitOut feed(String s) {
    _buf += s;
    final text = StringBuffer();
    final think = StringBuffer();
    while (true) {
      final tag = inThink ? '</think>' : '<think>';
      final i = _buf.indexOf(tag);
      if (i >= 0) {
        if (inThink) {
          think.write(_buf.substring(0, i));
        } else {
          text.write(_buf.substring(0, i));
        }
        _buf = _buf.substring(i + tag.length);
        inThink = !inThink;
        continue;
      }
      int keep = 0;
      final maxK = (tag.length - 1) < _buf.length ? (tag.length - 1) : _buf.length;
      for (int k = maxK; k > 0; k--) {
        if (_buf.endsWith(tag.substring(0, k))) {
          keep = k;
          break;
        }
      }
      final out = _buf.substring(0, _buf.length - keep);
      if (inThink) {
        think.write(out);
      } else {
        text.write(out);
      }
      _buf = _buf.substring(_buf.length - keep);
      break;
    }
    return SplitOut(text.toString(), think.toString());
  }

  SplitOut flush() {
    final out = inThink ? SplitOut('', _buf) : SplitOut(_buf, '');
    _buf = '';
    return out;
  }
}

class _TcAcc {
  String id = '';
  String name = '';
  final StringBuffer args = StringBuffer();
}

Stream<LlmEvent> parseOpenAi(Stream<Map<String, dynamic>> events) async* {
  final acc = <int, _TcAcc>{};
  int lastIdx = 0;
  int nextIdx = 0;
  final splitter = ThinkSplitter();
  String? stop;
  await for (final j in events) {
    if (j['error'] != null) throw ApiException(errMsg(j['error']));
    final usage = j['usage'];
    if (usage is Map) {
      // التوكنز المخزّنة: OpenAI تضعها في prompt_tokens_details، وDeepSeek في prompt_cache_hit_tokens.
      final cached = toInt(asMap(usage['prompt_tokens_details'])['cached_tokens']) ?? toInt(usage['prompt_cache_hit_tokens']);
      yield LlmEvent(inTok: toInt(usage['prompt_tokens']), outTok: toInt(usage['completion_tokens']), cacheTok: cached);
    }
    final choices = j['choices'];
    if (choices is! List || choices.isEmpty) continue;
    final c = asMap(choices[0]);
    final d = asMap(c['delta'] ?? c['message']);
    String thinking = '';
    final rc = d['reasoning_content'] ?? d['reasoning'];
    if (rc is String) thinking = rc;
    String text = '';
    final content = d['content'];
    if (content is String) text = content;
    if (text.isNotEmpty) {
      final sp = splitter.feed(text);
      text = sp.text;
      thinking += sp.thinking;
    }
    if (text.isNotEmpty || thinking.isNotEmpty) yield LlmEvent(text: text, thinking: thinking);
    final tcs = d['tool_calls'];
    if (tcs is List) {
      for (final raw in tcs) {
        final tc = asMap(raw);
        int idx;
        final iv = toInt(tc['index']);
        if (iv != null) {
          idx = iv;
        } else if (tc['id'] is String && (tc['id'] as String).isNotEmpty) {
          idx = nextIdx;
        } else {
          idx = lastIdx;
        }
        lastIdx = idx;
        if (idx >= nextIdx) nextIdx = idx + 1;
        final a = acc.putIfAbsent(idx, () => _TcAcc());
        if (tc['id'] is String && (tc['id'] as String).isNotEmpty) a.id = tc['id'] as String;
        final fn = asMap(tc['function']);
        if (fn['name'] is String && (fn['name'] as String).isNotEmpty) a.name = fn['name'] as String;
        final ar = fn['arguments'];
        if (ar is String) {
          a.args.write(ar);
        } else if (ar is Map) {
          a.args.write(jsonEncode(ar));
        }
      }
    }
    final fr = c['finish_reason'];
    if (fr is String && fr.isNotEmpty) stop = fr;
  }
  final tail = splitter.flush();
  if (tail.text.isNotEmpty || tail.thinking.isNotEmpty) yield LlmEvent(text: tail.text, thinking: tail.thinking);
  final keys = acc.keys.toList()..sort();
  for (final k in keys) {
    final a = acc[k]!;
    if (a.name.isEmpty) continue;
    yield LlmEvent(call: ToolCall(id: a.id.isEmpty ? newId() : a.id, name: a.name, args: decodeArgs(a.args.toString()), rawArgs: a.args.toString()));
  }
  if (stop != null) yield LlmEvent(stop: stop);
}

class _Blk {
  final String type;
  final String id;
  final String name;
  final StringBuffer buf = StringBuffer();
  _Blk(this.type, this.id, this.name);
}

Stream<LlmEvent> parseAnthropic(Stream<Map<String, dynamic>> events) async* {
  final blocks = <int, _Blk>{};
  await for (final j in events) {
    final type = j['type'];
    if (type == 'error') throw ApiException(errMsg(j['error'] ?? j));
    if (type == 'message_start') {
      final u = asMap(asMap(j['message'])['usage']);
      final read = toInt(u['cache_read_input_tokens']) ?? 0;
      final total = (toInt(u['input_tokens']) ?? 0) + read + (toInt(u['cache_creation_input_tokens']) ?? 0);
      yield LlmEvent(inTok: total, cacheTok: read);
    } else if (type == 'content_block_start') {
      final idx = toInt(j['index']) ?? 0;
      final cb = asMap(j['content_block']);
      final bt = asStr(cb['type']);
      blocks[idx] = _Blk(bt, asStr(cb['id']), asStr(cb['name']));
      if (bt == 'redacted_thinking') {
        yield LlmEvent(redacted: asStr(cb['data']));
      } else if (bt == 'text' && cb['text'] is String && (cb['text'] as String).isNotEmpty) {
        yield LlmEvent(text: cb['text'] as String);
      }
    } else if (type == 'content_block_delta') {
      final idx = toInt(j['index']) ?? 0;
      final delta = asMap(j['delta']);
      final dt = delta['type'];
      if (dt == 'text_delta') {
        yield LlmEvent(text: asStr(delta['text']));
      } else if (dt == 'thinking_delta') {
        yield LlmEvent(thinking: asStr(delta['thinking']));
      } else if (dt == 'signature_delta') {
        yield LlmEvent(sig: asStr(delta['signature']));
      } else if (dt == 'input_json_delta') {
        final b = blocks[idx];
        if (b != null) b.buf.write(asStr(delta['partial_json']));
      }
    } else if (type == 'content_block_stop') {
      final idx = toInt(j['index']) ?? 0;
      final b = blocks[idx];
      if (b != null && b.type == 'tool_use') {
        yield LlmEvent(call: ToolCall(id: b.id.isEmpty ? newId() : b.id, name: b.name, args: decodeArgs(b.buf.toString()), rawArgs: b.buf.toString()));
      }
      blocks.remove(idx);
    } else if (type == 'message_delta') {
      final delta = asMap(j['delta']);
      final u = asMap(j['usage']);
      final sr = delta['stop_reason'];
      yield LlmEvent(stop: sr is String ? sr : null, outTok: toInt(u['output_tokens']));
    }
  }
}

/// رد Anthropic غير متدفق (احتياط إذا تجاهل الخادم stream:true).
Stream<LlmEvent> anthropicFull(Map<String, dynamic> j) async* {
  final u = asMap(j['usage']);
  final read = toInt(u['cache_read_input_tokens']) ?? 0;
  yield LlmEvent(
      inTok: (toInt(u['input_tokens']) ?? 0) + read + (toInt(u['cache_creation_input_tokens']) ?? 0),
      outTok: toInt(u['output_tokens']),
      cacheTok: read);
  for (final raw in asList(j['content'])) {
    final b = asMap(raw);
    final t = b['type'];
    if (t == 'text') {
      yield LlmEvent(text: asStr(b['text']));
    } else if (t == 'thinking') {
      yield LlmEvent(thinking: asStr(b['thinking']), sig: asStr(b['signature']));
    } else if (t == 'redacted_thinking') {
      yield LlmEvent(redacted: asStr(b['data']));
    } else if (t == 'tool_use') {
      yield LlmEvent(call: ToolCall(id: asStr(b['id'], newId()), name: asStr(b['name']), args: asMap(b['input'])));
    }
  }
  final sr = j['stop_reason'];
  if (sr is String) yield LlmEvent(stop: sr);
}

Stream<LlmEvent> parseGemini(Stream<Map<String, dynamic>> events) async* {
  await for (final j in events) {
    if (j['error'] != null) throw ApiException(errMsg(j['error']));
    final pf = asMap(j['promptFeedback']);
    final br = pf['blockReason'];
    if (br is String && br.isNotEmpty) throw ApiException('حجب Gemini الطلب: $br');
    final um = j['usageMetadata'];
    if (um is Map) {
      yield LlmEvent(
        inTok: toInt(um['promptTokenCount']),
        outTok: (toInt(um['candidatesTokenCount']) ?? 0) + (toInt(um['thoughtsTokenCount']) ?? 0),
        cacheTok: toInt(um['cachedContentTokenCount']),
      );
    }
    final cands = j['candidates'];
    if (cands is! List || cands.isEmpty) continue;
    final c = asMap(cands[0]);
    final parts = asList(asMap(c['content'])['parts']);
    for (final raw in parts) {
      final p = asMap(raw);
      if (p['functionCall'] is Map) {
        final fc = asMap(p['functionCall']);
        yield LlmEvent(
          call: ToolCall(
            id: newId(),
            name: asStr(fc['name']),
            args: asMap(fc['args']),
            sig: p['thoughtSignature'] is String ? p['thoughtSignature'] as String : null,
          ),
        );
      } else if (p['text'] is String) {
        final t = p['text'] as String;
        if (p['thought'] == true) {
          yield LlmEvent(thinking: t);
        } else if (t.isNotEmpty) {
          yield LlmEvent(text: t);
        }
      }
    }
    final fr = c['finishReason'];
    if (fr is String && fr.isNotEmpty) yield LlmEvent(stop: fr);
  }
}

// ---------------------------------------------------------------------
//  Execute a prepared call and stream LlmEvents
// ---------------------------------------------------------------------
Stream<LlmEvent> executeCall(PreparedCall call, GenRequest r, CancelToken ct) async* {
  Response<ResponseBody> res;
  try {
    final headers = <String, dynamic>{...call.headers, 'Accept': 'text/event-stream'};
    res = await httpClient.post<ResponseBody>(
      call.url.toString(),
      data: call.body,
      cancelToken: ct,
      options: Options(headers: headers, responseType: ResponseType.stream, contentType: 'application/json'),
    );
  } catch (e) {
    if (isCancel(e)) rethrow;
    throw await toApiException(e);
  }
  final rb = res.data;
  if (rb == null) throw ApiException('رد فارغ من الخادم');
  final lines = rb.stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
  final st = SseState();
  final events = sseJson(lines, st);
  final kind = r.profile.kind;
  if (kind == kAnthropic) {
    yield* parseAnthropic(events);
  } else if (kind == kGemini) {
    yield* parseGemini(events);
  } else {
    yield* parseOpenAi(events);
  }
  // الخادم تجاهل البث وأرجع JSON كاملاً (أو خطأً بحالة 200)
  if (st.events == 0 && st.raw.isNotEmpty) {
    final body = st.raw.join('\n');
    dynamic j;
    try {
      j = jsonDecode(body);
    } catch (_) {
      throw ApiException('الخادم لم يرجع بثاً صالحاً: ${clip(body, 500)}');
    }
    if (j is List && j.isNotEmpty) j = j.first;
    if (j is Map) {
      final m = Map<String, dynamic>.from(j);
      if (m['error'] != null) throw ApiException(errMsg(m['error']));
      if (kind == kAnthropic) {
        yield* anthropicFull(m);
      } else if (kind == kGemini) {
        yield* parseGemini(Stream<Map<String, dynamic>>.value(m));
      } else {
        yield* parseOpenAi(Stream<Map<String, dynamic>>.value(m));
      }
    }
  }
}

// ---------------------------------------------------------------------
//  Models listing / connection test
// ---------------------------------------------------------------------
dynamic _jsonOf(dynamic d) {
  if (d is String) {
    try {
      return jsonDecode(d);
    } catch (_) {
      return null;
    }
  }
  return d;
}

Future<List<String>> listModels(ApiProfile p) async {
  final headers = buildHeaders(p);
  final out = <String>[];
  try {
    if (p.kind == kGemini) {
      String? token;
      int pages = 0;
      do {
        final url = '${geminiRoot(p.baseUrl)}/models?pageSize=1000${token == null ? '' : '&pageToken=$token'}';
        final r = await httpClient.get<dynamic>(url, options: Options(headers: headers));
        final j = asMap(_jsonOf(r.data));
        for (final m in asList(j['models'])) {
          final mm = asMap(m);
          final methods = asList(mm['supportedGenerationMethods']);
          if (methods.isNotEmpty && !methods.contains('generateContent')) continue;
          var name = asStr(mm['name']);
          if (name.startsWith('models/')) name = name.substring(7);
          if (name.isNotEmpty) out.add(name);
        }
        final nt = j['nextPageToken'];
        token = (nt is String && nt.isNotEmpty) ? nt : null;
        pages++;
      } while (token != null && pages < 6);
    } else if (p.kind == kAnthropic) {
      final r = await httpClient.get<dynamic>('${anthropicRoot(p.baseUrl)}/models?limit=1000', options: Options(headers: headers));
      final j = asMap(_jsonOf(r.data));
      for (final m in asList(j['data'])) {
        final id = asStr(asMap(m)['id']);
        if (id.isNotEmpty) out.add(id);
      }
    } else {
      final r = await httpClient.get<dynamic>('${openAiRoot(p.baseUrl)}/models', options: Options(headers: headers));
      final j = _jsonOf(r.data);
      List<dynamic> items = <dynamic>[];
      if (j is Map) {
        items = asList(j['data']);
        if (items.isEmpty) items = asList(j['models']);
      } else if (j is List) {
        items = j;
      }
      for (final m in items) {
        if (m is String) {
          out.add(m);
        } else {
          final mm = asMap(m);
          final id = asStr(mm['id'] ?? mm['name']);
          if (id.isNotEmpty) out.add(id);
        }
      }
    }
  } catch (e) {
    throw await toApiException(e);
  }
  final set = out.toSet().toList();
  set.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return set;
}
