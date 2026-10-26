// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, unused_local_variable, avoid_print, deprecated_member_use, use_build_context_synchronously, prefer_const_constructors, prefer_const_literals_to_create_immutables, depend_on_referenced_packages, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, unnecessary_import
part of 'main.dart';

// ---------------------------------------------------------------------
//  Chat session: generation loop, tools loop, retry/heal, persistence.
//  Sessions live outside the widget tree, so a reply keeps streaming
//  even if you open another conversation.
// ---------------------------------------------------------------------
const String kSummarySystem =
    'You compress conversations. Write a dense summary of the conversation below so the work can continue without the original messages. '
    "Keep: the user's goals, constraints and preferences; decisions and conclusions; important facts, names, numbers, paths and identifiers; "
    'files read or changed and their current state; unfinished tasks and next steps. Drop pleasantries and anything already resolved. '
    'Use the same language as the conversation. No preamble. At most about 700 words.';

/// رسالة كتبها المستخدم أثناء عمل النموذج، تنتظر التسليم.
class QueuedMsg {
  final String id;
  final String text;
  final List<PendingAtt> atts;
  final String? quote;
  QueuedMsg({required this.id, required this.text, required this.atts, this.quote});
}

class ChatSession extends ChangeNotifier {
  ChatSession(this.meta, {bool existing = false})
      : loaded = !existing,
        persisted = existing;

  ConvMeta meta;
  bool loaded;
  bool persisted;
  final List<ChatMessage> messages = <ChatMessage>[];
  bool generating = false;
  String status = '';
  ChatMessage? streamingMsg;
  CancelToken? _cancel;
  final ValueNotifier<int> tick = ValueNotifier<int>(0);
  PreparedCall? lastCall;
  int _lastBump = 0;
  int _thinkStart = 0;
  int _sigSeen = 0;
  bool _titled = false;
  bool _titling = false;
  bool _busy = false;
  /// تُضبط عند حذف المحادثة: تمنع أي حفظ متأخر من إعادة إحيائها.
  bool deleted = false;
  /// أول رسالة داخل نافذة السياق. تتحرك دفعة واحدة (لا مع كل رسالة) كي يبقى مطلع الطلب ثابتاً فيعمل الكاش.
  String? _ctxStartId;

  /// حدّ قصّ داخل الدور الحالي: نتائج الأدوات في الرسائل قبل هذه الرسالة تُقصّ (ثابت بين الجولات كي يعمل الكاش).
  String? _trimBeforeId;
  /// عدد الرسائل القديمة المستبعدة من آخر طلب بسبب ميزانية السياق (للعرض فقط).
  int ctxDropped = 0;
  /// رسائل كُتبت أثناء التوليد: تُسلَّم بين جولات الأدوات، أو بعد انتهاء الرد كدور جديد.
  final List<QueuedMsg> queue = <QueuedMsg>[];
  /// كاشف الحلقات: بصمات آخر استدعاءات الأدوات (الاسم + الوسائط + النتيجة) في التشغيل الحالي.
  final List<int> _recentSigs = <int>[];
  bool _loopAbort = false;
  /// مجموع ما عالجه النموذج (دخل + خرج) في التشغيل الحالي، لميزانية المهمة.
  int _runTokens = 0;

  bool get isEmpty => messages.isEmpty;

  void refresh() => notifyListeners();

  void _bump({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (force || now - _lastBump > 60) {
      _lastBump = now;
      tick.value++;
    }
  }

  // ---- persistence -------------------------------------------------
  Future<void> load() async {
    if (loaded) return;
    final raw = await LocalStorage.load('chats', meta.id);
    messages.clear();
    if (raw != null) {
      try {
        for (final e in asList(jsonDecode(raw))) {
          messages.add(ChatMessage.fromJson(asMap(e)));
        }
      } catch (_) {}
    }
    for (final m in messages) {
      for (final c in m.toolCalls) {
        if (c.status == 'running' || c.status == 'pending') {
          c.status = 'error';
          c.isError = true;
          c.result ??= 'Interrupted';
        }
      }
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> persist() async {
    if (deleted || messages.isEmpty) return;
    meta.updatedAt = DateTime.now();
    final data = jsonEncode(messages.map((m) => m.toJson()).toList());
    await LocalStorage.save('chats', meta.id, data);
    if (deleted) return;
    await appContainer.read(convListProvider.notifier).upsert(meta);
    persisted = true;
  }

  // ---- user actions -------------------------------------------------
  Future<List<Attachment>> _storeAttachments(List<PendingAtt> pend) async {
    final lib = appContainer.read(libraryProvider.notifier);
    final out = <Attachment>[];
    for (final p in pend) {
      if (p.path != null) {
        out.add(Attachment(id: p.id, name: p.name, mime: p.mime, size: p.size, path: p.path));
        continue;
      }
      final b = p.bytes;
      if (b == null) continue;
      final it = await lib.addBytes(p.name, b, mime: p.mime);
      out.add(Attachment(id: it.id, name: it.name, mime: it.mime, size: it.size, path: it.path));
    }
    return out;
  }

  Future<void> send(String text, List<PendingAtt> pend, {String? quote}) async {
    if (generating || _busy) return;
    final t = text.trim();
    if (t.isEmpty && pend.isEmpty) return;
    _busy = true;
    try {
      final atts = await _storeAttachments(pend);
      final msg = ChatMessage(id: newId(), role: 'user', content: t, attachments: atts, quote: quote);
      messages.add(msg);
      if (meta.title.isEmpty) {
        final base = t.isNotEmpty ? t : (atts.isNotEmpty ? atts.first.name : 'محادثة جديدة');
        meta.title = clip(base.replaceAll(RegExp(r'\s+'), ' ').trim(), 42);
      }
      notifyListeners();
      await persist();
    } finally {
      _busy = false;
    }
    await _run();
  }

  /// يضيف رسالة إلى الطابور أثناء التوليد. يعيد false إن لم يكن هناك توليد جارٍ (أرسلها عادياً).
  bool enqueue(String text, List<PendingAtt> pend, {String? quote}) {
    if (!generating) return false;
    final t = text.trim();
    if (t.isEmpty && pend.isEmpty) return false;
    queue.add(QueuedMsg(id: newId(), text: t, atts: List<PendingAtt>.from(pend), quote: quote));
    notifyListeners();
    return true;
  }

  void removeQueued(String id) {
    queue.removeWhere((q) => q.id == id);
    notifyListeners();
  }

  /// يحوّل الطابور كله إلى رسالة مستخدم واحدة. inLoop=true: وصلت وسط حلقة الأدوات (نفس الدور).
  Future<void> _deliverQueue({required bool inLoop}) async {
    if (queue.isEmpty) return;
    final items = List<QueuedMsg>.from(queue);
    final texts = <String>[];
    final quotes = <String>[];
    final pend = <PendingAtt>[];
    for (final q in items) {
      if (q.text.isNotEmpty) texts.add(q.text);
      final qq = q.quote;
      if (qq != null && qq.isNotEmpty) quotes.add(qq);
      pend.addAll(q.atts);
    }
    // نخزّن المرفقات أولاً؛ إن فشل ذلك تبقى الرسائل في الطابور ولا تضيع.
    final atts = await _storeAttachments(pend);
    queue.removeWhere((q) => items.contains(q));
    messages.add(ChatMessage(
      id: newId(),
      role: 'user',
      content: texts.join('\n\n'),
      attachments: atts,
      quote: quotes.isEmpty ? null : quotes.join('\n\n'),
      injected: inLoop,
    ));
    notifyListeners();
    await persist();
  }

  /// بعد توقّف الحلقة (إيقاف من المستخدم أو خطأ) وفي الطابور رسائل. إيقاف المستخدم: تُسلَّم وتُشغَّل فوراً
  /// (هذا قصده من كتابتها). خطأ: تُسلَّم كرسائل فقط دون تشغيل تلقائي. يعيد true إن وجب المتابعة.
  Future<bool> _afterAbort() async {
    if (queue.isEmpty) return false;
    if (deleted) {
      queue.clear(); // محادثة محذوفة: لا نُشغّل شيئاً
      return false;
    }
    final byUser = _cancel?.isCancelled ?? false;
    await _deliverQueue(inLoop: false);
    if (!byUser) return false;
    _cancel = CancelToken();
    status = 'connecting';
    return true;
  }

  /// إعادة توليد الرد: يحذف دورة المساعد الأخيرة ثم يعيد الطلب.
  Future<void> regenerate() async {
    if (generating || messages.isEmpty) return;
    int u = -1;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == 'user') {
        u = i;
        break;
      }
    }
    if (u < 0) return;
    messages.removeRange(u + 1, messages.length);
    notifyListeners();
    await persist();
    await _run();
  }

  /// متابعة رد انقطع (حد الإخراج) أو فشل.
  Future<void> continueReply() async {
    if (generating) return;
    final last = messages.isNotEmpty ? messages.last : null;
    if (last != null && last.role == 'assistant' && last.error != null && last.content.trim().isEmpty && last.toolCalls.isEmpty) {
      messages.removeLast();
      notifyListeners();
      await _run();
      return;
    }
    await send('تابع من حيث توقفت تماماً.', <PendingAtt>[]);
  }

  Future<void> editAndResend(String id, String newText) async {
    if (generating) return;
    final i = messages.indexWhere((m) => m.id == id);
    if (i < 0) return;
    messages[i].content = newText.trim();
    if (i + 1 < messages.length) messages.removeRange(i + 1, messages.length);
    notifyListeners();
    await persist();
    await _run();
  }

  Future<void> updateContent(String id, String newText) async {
    final i = messages.indexWhere((m) => m.id == id);
    if (i < 0) return;
    messages[i].content = newText;
    notifyListeners();
    await persist();
  }

  Future<void> deleteMessages(Set<String> ids) async {
    messages.removeWhere((m) => ids.contains(m.id));
    notifyListeners();
    await persist();
  }

  Future<void> setExcluded(Set<String> ids, bool v) async {
    for (final m in messages) {
      if (ids.contains(m.id)) m.excluded = v;
    }
    notifyListeners();
    await persist();
  }

  void stop() {
    final c = _cancel;
    if (c != null && !c.isCancelled) c.cancel('stopped');
    BashRuntime.cancelAll();
  }

  Future<void> rename(String title) async {
    meta.title = title.trim().isEmpty ? meta.title : title.trim();
    notifyListeners();
    if (messages.isNotEmpty) {
      await persist();
    }
  }

  // ---- generation ----------------------------------------------------
  Future<void> _run() async {
    if (generating) return;
    generating = true;
    status = 'connecting';
    _cancel = CancelToken();
    notifyListeners();
    int rounds = 0;
    ReadLedger.newRun(meta.id);
    _recentSigs.clear();
    _loopAbort = false;
    _runTokens = 0;
    try {
      // تجاوزنا ميزانية السياق: نلخّص الأقدم بدل حذفه (طلب إضافي واحد). عند الفشل يعمل القصّ الاحتياطي.
      final cs = appContainer.read(settingsProvider);
      if (cs.autoCompact && _overBudget(cs)) {
        status = 'compacting';
        notifyListeners();
        final n = await compact(cs, manual: false);
        if (n > 0) {
          toast('لُخّصت $n رسالة قديمة لتوفير التوكنز');
        } else if (n < 0) {
          toast('تعذّر تلخيص السياق ($lastCompactError)؛ سيُحذف الأقدم بدلاً منه');
        }
      }
      while (true) {
        rounds++;
        final msg = ChatMessage(id: newId(), role: 'assistant');
        messages.add(msg);
        streamingMsg = msg;
        notifyListeners();
        final ok = await _streamRound(msg);
        streamingMsg = null;
        if (!ok) {
          if (msg.content.isEmpty && msg.thinking.isEmpty && msg.toolCalls.isEmpty && msg.error == null) {
            messages.remove(msg);
          }
          for (final c in msg.toolCalls) {
            if (c.result == null) {
              c.status = 'error';
              c.isError = true;
              c.result = 'Interrupted';
            }
          }
          if (await _afterAbort()) {
            rounds = 0;
            continue;
          }
          break;
        }
        _runTokens += msg.inTok + msg.outTok;
        if (msg.toolCalls.isEmpty) {
          // انتهى الرد وفي الطابور رسائل: تُرسل كدور جديد مباشرة.
          if (queue.isNotEmpty) {
            await _deliverQueue(inLoop: false);
            rounds = 0;
            continue;
          }
          break;
        }
        final int maxRounds = appContainer.read(settingsProvider).maxToolRounds;
        if (rounds >= maxRounds) {
          msg.error = 'تم إيقاف حلقة الأدوات بعد $maxRounds جولات. اكتب «تابع» لإكمال العمل.';
          for (final c in msg.toolCalls) {
            c.status = 'error';
            c.isError = true;
            c.result ??= 'Skipped: tool loop limit reached';
          }
          break;
        }
        await _execTools(msg);
        notifyListeners();
        await persist();
        if (_cancel?.isCancelled ?? false) {
          if (await _afterAbort()) {
            rounds = 0;
            continue;
          }
          break;
        }
        if (_loopAbort) {
          msg.error = 'توقف الـ Agent لأنه كرّر نفس الاستدعاء بنفس النتيجة عدة مرات. أعطه توجيهاً جديداً أو غيّر المقاربة.';
          break;
        }
        final budget = appContainer.read(settingsProvider).taskBudget;
        if (budget > 0 && _runTokens >= budget) {
          msg.error = 'بلغ التشغيل ميزانية التوكنز ($_runTokens من $budget). اكتب «تابع» للمتابعة أو ارفع الميزانية من الإعدادات.';
          break;
        }
        // رسائل كتبها المستخدم أثناء العمل: تصل النموذج الآن، بين جولتي الأدوات.
        if (queue.isNotEmpty) await _deliverQueue(inLoop: true);
      }
    } catch (e) {
      final m = ChatMessage(id: newId(), role: 'assistant', error: 'خطأ غير متوقع: $e');
      messages.add(m);
    } finally {
      generating = false;
      status = '';
      streamingMsg = null;
      _cancel = null;
      notifyListeners();
      _bump(force: true);
    }
    // ما تبقّى في الطابور (خطأ، أو بلوغ حد الجولات): يُسلَّم كرسائل دون تشغيل تلقائي.
    if (queue.isNotEmpty) {
      try {
        if (deleted) {
          queue.clear();
        } else {
          await _deliverQueue(inLoop: false);
        }
      } catch (_) {
        queue.clear();
      }
    }
    await persist();
    _maybeTitle();
  }

  bool _hasOutput(ChatMessage m) => m.content.isNotEmpty || m.thinking.isNotEmpty || m.toolCalls.isNotEmpty;

  /// يمسح ناتج جولة انقطعت (نص وتفكير وأدوات لم تُنفَّذ) ليعاد توليدها من الصفر.
  void _resetRoundOutput(ChatMessage m) {
    m.content = '';
    m.thinking = '';
    m.thinkSig = null;
    m.redacted.clear();
    m.toolCalls.clear();
    m.stopReason = null;
    m.thinkMs = 0;
    _thinkStart = 0;
    _sigSeen = 0;
  }

  Future<bool> _streamRound(ChatMessage msg) async {
    GenRequest req;
    try {
      req = await _buildRequest(msg);
    } catch (e) {
      msg.error = e is ApiException ? e.message : 'تعذر تجهيز الطلب: $e';
      return false;
    }
    msg.model = req.model;
    int attempt = 0;
    int heals = 0;
    int tooLong = 0;
    _thinkStart = 0;
    while (true) {
      try {
        final call = prepareCall(req);
        lastCall = call;
        _sigSeen = 0;
        status = 'connecting';
        notifyListeners();
        await for (final ev in executeCall(call, req, _cancel!)) {
          _apply(msg, ev);
          _bump();
        }
        _finishThink(msg);
        if (_cancel?.isCancelled ?? false) {
          msg.stopReason = 'cancelled';
          return false;
        }
        return _finalizeRound(msg);
      } catch (e) {
        if (isCancel(e) || (_cancel?.isCancelled ?? false)) {
          _finishThink(msg);
          msg.stopReason = 'cancelled';
          return false;
        }
        final ae = await toApiException(e);
        final bool partial = _hasOutput(msg);
        if (!partial && tooLong < 3 && isContextTooLong(ae)) {
          tooLong++;
          if (await _shrinkContext(tooLong)) {
            try {
              req = await _buildRequest(msg);
              toast('السياق أطول من نافذة الموديل: قُصّت نتائج الأدوات القديمة وأُعيدت المحاولة');
              continue;
            } catch (_) {}
          }
        }
        if (!partial && heals < 6 && req.tryHeal(ae)) {
          heals++;
          continue;
        }
        if (ae.retriable && attempt < 3) {
          attempt++;
          // انقطع الرد في منتصفه: نفرّغ ما وصل ونعيد الجولة كاملة (أدوات الجولة لم تُنفَّذ بعد، فالإعادة آمنة).
          if (partial) _resetRoundOutput(msg);
          status = 'retry:$attempt';
          notifyListeners();
          // يحترم Retry-After إن أرسله الخادم، وإلا تأخير متصاعد (4، 8، 16 ثانية). الانتظار قابل للإلغاء بزر الإيقاف.
          final ra = ae.retryAfter;
          final wait = ra != null ? clampInt(ra, 1, 60) : clampInt(2 << attempt, 2, 20);
          for (int i = 0; i < wait; i++) {
            if (_cancel?.isCancelled ?? false) break;
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          if (_cancel?.isCancelled ?? false) return false;
          continue;
        }
        _finishThink(msg);
        msg.error = isContextTooLong(ae) ? '${ae.message}\n\nالسياق أطول من نافذة الموديل حتى بعد القصّ والتلخيص. لخّص المحادثة من قائمتها أو ابدأ محادثة جديدة.' : ae.message;
        return false;
      }
    }
  }

  bool _finalizeRound(ChatMessage msg) {
    if (msg.content.trim().isEmpty && msg.toolCalls.isEmpty) {
      final sr = msg.stopReason ?? '';
      const blocked = <String>['SAFETY', 'RECITATION', 'BLOCKLIST', 'PROHIBITED_CONTENT', 'SPII', 'content_filter', 'refusal'];
      if (blocked.contains(sr)) {
        msg.error = 'الرد محجوب من المزوّد ($sr).';
      } else if (sr == 'max_tokens' || sr == 'length' || sr == 'MAX_TOKENS') {
        msg.error = 'انتهى الحد الأقصى للإخراج قبل ظهور أي نص (غالباً بسبب التفكير). ارفع "الحد الأقصى للإخراج" أو خفّض مستوى التفكير.';
      } else {
        msg.error = 'رد فارغ من النموذج${sr.isEmpty ? '' : ' (stop: $sr)'}.';
      }
      return false;
    }
    return true;
  }

  void _apply(ChatMessage msg, LlmEvent ev) {
    if (ev.thinking.isNotEmpty) {
      if (_thinkStart == 0) _thinkStart = DateTime.now().millisecondsSinceEpoch;
      msg.thinking += ev.thinking;
      status = 'thinking';
    }
    if (ev.text.isNotEmpty) {
      _finishThink(msg);
      msg.content += ev.text;
      status = 'writing';
    }
    final sig = ev.sig;
    if (sig != null && sig.isNotEmpty) {
      _sigSeen++;
      // رد واحد فيه أكثر من كتلة تفكير: لا نخزّن كتلاً متعددة، فنُسقط التوقيع
      // بدل إرسال توقيع لا يطابق النص المدموج (يرفضه الـ API).
      msg.thinkSig = _sigSeen == 1 ? sig : null;
    }
    final red = ev.redacted;
    if (red != null) msg.redacted.add(red);
    final call = ev.call;
    if (call != null) {
      _finishThink(msg);
      msg.toolCalls.add(call);
      status = 'writing';
    }
    final it = ev.inTok;
    if (it != null && it > 0) {
      msg.inTok = it;
      msg.tokExact = true;
    }
    final ct = ev.cacheTok;
    if (ct != null && ct >= 0 && (it != null && it > 0)) msg.cacheTok = ct;
    final ot = ev.outTok;
    if (ot != null && ot > 0) {
      msg.outTok = ot;
      msg.tokExact = true;
    }
    final st = ev.stop;
    if (st != null) msg.stopReason = st;
  }

  void _finishThink(ChatMessage msg) {
    if (_thinkStart != 0) {
      msg.thinkMs += DateTime.now().millisecondsSinceEpoch - _thinkStart;
      _thinkStart = 0;
    }
  }

  Future<void> _execTools(ChatMessage msg) async {
    final s = appContainer.read(settingsProvider);
    final agent = appContainer.read(agentsProvider.notifier).byId(appContainer.read(selectedAgentProvider));
    for (final c in msg.toolCalls) {
      if (_cancel?.isCancelled ?? false) {
        c.status = 'error';
        c.isError = true;
        c.result = 'Cancelled by the user';
        continue;
      }
      c.status = 'running';
      status = 'tool:${c.name}';
      notifyListeners();
      final out = await runTool(c, agent, s, convId: meta.id);
      var text = out.text;
      // كاشف الحلقات: نفس الاستدعاء بنفس النتيجة مراراً ⇒ تحذير للنموذج، ثم إيقاف.
      final sig = '${c.name}|${jsonEncode(c.args)}|${out.error}|${out.text.hashCode}'.hashCode;
      _recentSigs.add(sig);
      if (_recentSigs.length > 10) _recentSigs.removeAt(0);
      final rep = _recentSigs.where((x) => x == sig).length;
      if (rep >= 3) {
        text = '$text\n[WARNING: you have made this exact call $rep times with the same result. Change your approach or ask the user.]';
        if (rep >= 5) _loopAbort = true;
      }
      c.result = text;
      c.isError = out.error;
      c.status = out.error ? 'error' : 'done';
      notifyListeners();
    }
    status = 'connecting';
  }

  List<ChatMessage> _history(ChatMessage pending, AppSettings s) {
    var h = messages.where((m) => !identical(m, pending) && !m.excluded).toList();
    h = h.where((m) => !(m.role == 'assistant' && m.content.trim().isEmpty && m.toolCalls.isEmpty)).toList();
    if (s.contextLimit > 0 && h.length > s.contextLimit) {
      // نقصّ من البداية لكن نرجع للخلف حتى أقرب رسالة مستخدم، كي لا نفقد السؤال الحالي
      // (كل جولة أدوات هي رسالة مساعد مستقلة، فقد تتجاوز عدداً صغيراً من الرسائل).
      var st = h.length - s.contextLimit;
      while (st > 0 && h[st].role != 'user') {
        st--;
      }
      h = h.sublist(st);
    }
    final before = h.length;
    if (s.contextBudget > 0) h = _fitBudget(h, s);
    ctxDropped = before - h.length;
    while (h.isNotEmpty && h.first.role != 'user') {
      h.removeAt(0);
    }
    // طلب ينتهي بردّ مساعد نصي = prefill، ترفضه نماذج Claude الحديثة. (جولات الأدوات تبقى.)
    while (h.isNotEmpty && h.last.role == 'assistant' && h.last.toolCalls.isEmpty) {
      h.removeLast();
    }
    return h;
  }

  /// تقدير تقريبي لحجم الرسالة بالتوكنز (حرف ≈ 1/3 توكن، متحفّظ للعربية).
  int _estMsg(ChatMessage m, AppSettings s, bool old) {
    int n = m.content.length + 16;
    for (final a in m.attachments) {
      if (a.isImage) {
        n += 4500;
      } else if (a.isPdf) {
        n += 20000;
      } else {
        n += a.size < s.maxChars ? a.size : s.maxChars;
      }
    }
    for (final c in m.toolCalls) {
      n += jsonEncode(c.args).length;
      final r = c.result;
      if (r != null) n += (old && (s.trimOldResults || _trimBeforeId != null) && r.length > kTrimAt) ? kTrimKeep + 120 : r.length;
    }
    return (n / 3).ceil();
  }

  /// حدّ السياق بالتوكنز: عند التجاوز نقصّ أقدم الأدوار حتى نصف الميزانية، ثم نثبّت النافذة
  /// (لا ننزلق رسالة برسالة) كي يعمل الكاش. لا نقصّ أبداً الدور الحالي.
  List<ChatMessage> _fitBudget(List<ChatMessage> all, AppSettings s) {
    var h = all;
    final id = _ctxStartId;
    if (id != null) {
      final i = h.indexWhere((m) => m.id == id);
      if (i > 0) h = h.sublist(i);
      if (i < 0) _ctxStartId = null;
    }
    List<int> est = <int>[];
    int sum = 0;
    void measure() {
      est = <int>[];
      sum = 0;
      final f = _ffFor(h);
      for (int i = 0; i < h.length; i++) {
        final e = _estMsg(h[i], s, i < f);
        est.add(e);
        sum += e;
      }
    }

    measure();
    if (sum <= s.contextBudget) return h;
    // 1) داخل الدور الحالي: نقصّ نتائج الجولات القديمة (آخر 8 ثم 4 ثم 2 ثم 1 تبقى كاملة) قبل التفكير بحذف أدوار سابقة.
    for (final k in const <int>[8, 4, 2, 1]) {
      if (sum <= s.contextBudget) break;
      if (_advanceTrim(h, k)) measure();
    }
    if (sum <= s.contextBudget) return h;
    final target = s.contextBudget ~/ 2;
    int lastUser = 0;
    for (int i = 0; i < h.length; i++) {
      if (h[i].startsTurn) lastUser = i;
    }
    int st = 0;
    while (st < lastUser && sum > target) {
      sum -= est[st];
      st++;
    }
    while (st < lastUser && h[st].role != 'user') {
      st++;
    }
    if (st == 0) return h;
    h = h.sublist(st);
    _ctxStartId = h.first.id;
    return h;
  }

  /// أول فهرس تبقى منه نتائج الأدوات كاملة: الدور الحالي والذي قبله، أو حدّ القصّ داخل الدور الحالي إن وُجد.
  int _ffFor(List<ChatMessage> h) {
    int ff = fullResultsFrom(h);
    final id = _trimBeforeId;
    if (id != null) {
      final j = h.indexWhere((m) => m.id == id);
      if (j < 0) {
        _trimBeforeId = null;
      } else if (j > ff) {
        ff = j;
      }
    }
    return ff;
  }

  /// يقدّم حدّ القصّ داخل الدور الحالي بحيث تبقى آخر `keep` جولات أدوات كاملة. دفعة واحدة ثم يثبت الحدّ
  /// (لا ينزلق كل جولة) كي لا ينكسر الكاش في كل طلب. true = تقدّم الحدّ فعلاً.
  bool _advanceTrim(List<ChatMessage> h, int keep) {
    final b = trimBoundary(h, keep);
    if (b < 0 || b <= _ffFor(h)) return false;
    _trimBeforeId = h[b].id;
    // ما قُصّ لم يعد في السياق: نسمح بإعادة قراءته (حارس الكتابة فوق ملف لم يُقرأ كاملاً يبقى كما هو).
    ReadLedger.newRun(meta.id);
    return true;
  }

  /// إصلاح ذاتي لخطأ «السياق أطول من النافذة»: قصّ أشدّ، ثم تلخيص الأدوار السابقة. false = لا شيء بقي ليُقصّ.
  Future<bool> _shrinkContext(int step) async {
    final h = _included();
    if (step <= 1 && _advanceTrim(h, 3)) return true;
    if (step <= 2 && _advanceTrim(h, 1)) return true;
    status = 'compacting';
    notifyListeners();
    final n = await compact(appContainer.read(settingsProvider), manual: true);
    return n > 0;
  }

  // ---- ضغط السياق بالتلخيص ---------------------------------------------
  /// سبب آخر فشل في التلخيص (للعرض).
  String lastCompactError = '';

  /// الرسائل التي ستُرسل (بلا المستبعد والفارغ) قبل أي قصّ.
  List<ChatMessage> _included() {
    return messages.where((m) => !m.excluded && !(m.role == 'assistant' && m.content.trim().isEmpty && m.toolCalls.isEmpty)).toList();
  }

  bool _overBudget(AppSettings s) {
    if (s.contextBudget <= 0) return false;
    final h = _included();
    final ff = fullResultsFrom(h);
    int sum = 0;
    for (int i = 0; i < h.length; i++) {
      sum += _estMsg(h[i], s, i < ff);
    }
    return sum > s.contextBudget;
  }

  String _transcript(List<ChatMessage> part) {
    final b = StringBuffer();
    for (final m in part) {
      if (m.summary) {
        b.write('[Earlier summary]\n${clip(m.content, 8000)}\n\n');
      } else if (m.role == 'user') {
        final att = m.attachments.isEmpty ? '' : ' [attachments: ${m.attachments.map((a) => a.name).join(', ')}]';
        b.write('User$att: ${clip(m.content, 6000)}\n\n');
      } else {
        if (m.content.trim().isNotEmpty) b.write('Assistant: ${clip(m.content, 6000)}\n');
        for (final c in m.toolCalls) {
          b.write('  [tool ${c.name} ${clip(jsonEncode(c.args), 300)} -> ${clip((c.result ?? '').replaceAll('\n', ' '), 400)}]\n');
        }
        b.write('\n');
      }
    }
    return b.toString();
  }

  /// طلب واحد بلا أدوات مع الإصلاح الذاتي والمحاولة مرة ثانية. null = أُلغي. يرمي ApiException عند الفشل.
  Future<String?> _oneShot(GenRequest req, CancelToken cancel) async {
    final sb = StringBuffer();
    int heals = 0;
    int attempt = 0;
    while (true) {
      sb.clear();
      try {
        await for (final ev in executeCall(prepareCall(req), req, cancel)) {
          sb.write(ev.text);
        }
        return sb.toString();
      } catch (e) {
        if (isCancel(e)) return null;
        final ae = await toApiException(e);
        if (heals < 4 && req.tryHeal(ae)) {
          heals++;
          continue;
        }
        if (ae.retriable && attempt < 1) {
          attempt++;
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }
        throw ae;
      }
    }
  }

  /// يلخّص الأجزاء القديمة (يبقى الدور الحالي وذيل حديث)، يستبعدها من السياق ويضع الملخّص مكانها.
  /// يعيد عدد الرسائل الملخّصة: 0 = لا حاجة، -1 = فشل (السبب في lastCompactError).
  Future<int> compact(AppSettings s, {required bool manual}) async {
    lastCompactError = '';
    final h = _included();
    if (h.length < 3) return 0;
    final ff = fullResultsFrom(h);
    final est = <int>[];
    int total = 0;
    for (int i = 0; i < h.length; i++) {
      final e = _estMsg(h[i], s, i < ff);
      est.add(e);
      total += e;
    }
    final target = manual ? total ~/ 4 : (s.contextBudget > 0 ? s.contextBudget : 60000) ~/ 3;
    int lastTurn = 0;
    for (int i = 0; i < h.length; i++) {
      if (h[i].startsTurn) lastTurn = i;
    }
    // أبكر بداية دور يبقى بعدها ذيل ضمن الهدف؛ لا نتجاوز الدور الحالي أبداً.
    int st = lastTurn;
    int suf = 0;
    for (int i = h.length - 1; i >= 0; i--) {
      suf += est[i];
      if (i <= lastTurn && h[i].startsTurn && suf <= target) st = i;
    }
    int range = 0;
    for (int i = 0; i < st; i++) {
      range += est[i];
    }
    if (st <= 0 || range < 300) return 0;
    final part = h.sublist(0, st);
    final profile = appContainer.read(profilesProvider).selected;
    if (profile == null || profile.selectedModel.trim().isEmpty) {
      lastCompactError = 'لا يوجد بروفايل/موديل محدد';
      return -1;
    }
    final req = GenRequest(
      profile: profile,
      model: profile.selectedModel,
      system: kSummarySystem,
      msgs: <RMsg>[
        RMsg.user(<RPart>[RPart.text('Conversation to summarize:\n\n${_transcript(part)}')])
      ],
      tools: <ToolDef>[],
      maxTokens: 2000,
      cache: false,
    );
    String? out;
    try {
      out = await _oneShot(req, _cancel ?? CancelToken());
    } catch (e) {
      lastCompactError = e is ApiException ? e.message : '$e';
      return -1;
    }
    if (out == null) {
      lastCompactError = 'أُلغي';
      return -1;
    }
    final text = out.trim();
    if (text.isEmpty) {
      lastCompactError = 'رد فارغ من النموذج';
      return -1;
    }
    final at = messages.indexOf(h[st]);
    if (at < 0 || deleted) return -1;
    for (final m in part) {
      m.excluded = true;
    }
    messages.insert(at, ChatMessage(id: newId(), role: 'user', content: clip(text, 12000), summary: true));
    ctxDropped = 0;
    notifyListeners();
    await persist();
    return part.length;
  }

  /// ضغط يدوي من قائمة المحادثة.
  Future<void> compactNow() async {
    if (generating || _busy) return;
    final s = appContainer.read(settingsProvider);
    generating = true;
    status = 'compacting';
    _cancel = CancelToken();
    notifyListeners();
    int n = 0;
    try {
      n = await compact(s, manual: true);
    } finally {
      generating = false;
      status = '';
      _cancel = null;
      notifyListeners();
    }
    if (n > 0) {
      toast('لُخّصت $n رسالة قديمة وأُزيلت من السياق (تبقى ظاهرة في المحادثة)');
    } else if (n == 0) {
      toast('المحادثة قصيرة، لا حاجة للتلخيص');
    } else {
      toast('تعذّر التلخيص: $lastCompactError');
    }
    // رسائل كتبها المستخدم أثناء التلخيص: تُرسل الآن كدور جديد.
    if (queue.isNotEmpty && !deleted) {
      await _deliverQueue(inLoop: false);
      await _run();
    }
  }

  Future<GenRequest> _buildRequest(ChatMessage pending) async {
    final c = appContainer;
    final s = c.read(settingsProvider);
    final profile = c.read(profilesProvider).selected;
    if (profile == null) throw ApiException('لا يوجد بروفايل API. أضف بروفايل من الإعدادات أولاً.');
    if (profile.baseUrl.trim().isEmpty) throw ApiException('الرابط (Base URL) فارغ في بروفايل "${profile.name}".');
    if (profile.apiKey.trim().isEmpty && profile.kind != kOpenAI) {
      throw ApiException('مفتاح الـ API فارغ في بروفايل "${profile.name}".');
    }
    final model = profile.selectedModel.trim();
    if (model.isEmpty) throw ApiException('اختر موديلاً أولاً (من شريط الإدخال، أو اجلب الموديلات من الإعدادات).');
    final agent = c.read(agentsProvider.notifier).byId(c.read(selectedAgentProvider));
    final project = c.read(projectsProvider.notifier).byId(meta.projectId);
    final mem = c.read(memoryProvider);
    final lib = c.read(libraryProvider);
    final tools = availableTools(s, agent, hasLibrary: lib.isNotEmpty, hasMemory: mem.isNotEmpty, workspace: currentWorkspace());
    final system = await buildSystemPrompt(s: s, project: project, agent: agent, memory: mem, library: lib, tools: tools);
    final hist = _history(pending, s);
    if (hist.isEmpty) throw ApiException('لا توجد رسائل لإرسالها (كلها مستبعدة من السياق).');
    final msgs = await resolveMessages(hist, profile, s, minFullFrom: _ffFor(hist));
    return GenRequest(
      profile: profile,
      model: model,
      system: system,
      msgs: msgs,
      tools: tools,
      temperature: s.temperature,
      topP: s.topP,
      maxTokens: s.maxTokens,
      thinkLevel: s.thinkLevel,
      thinkMode: s.thinkMode,
      cache: s.promptCache,
    );
  }

  // ---- auto title ------------------------------------------------------
  void _maybeTitle() {
    final s = appContainer.read(settingsProvider);
    if (!s.autoTitle || _titled || _titling || deleted) return;
    int users = 0;
    for (final m in messages) {
      if (m.role == 'user') users++;
    }
    if (users != 1) return;
    _titling = true;
    _autoTitle().whenComplete(() => _titling = false);
  }

  Future<void> _autoTitle() async {
    try {
      final before = meta.title;
      final profile = appContainer.read(profilesProvider).selected;
      if (profile == null || profile.selectedModel.isEmpty) return;
      ChatMessage? u;
      ChatMessage? a;
      for (final m in messages) {
        if (m.role == 'user' && u == null) u = m;
        if (m.role == 'assistant' && a == null && m.content.isNotEmpty) a = m;
      }
      if (u == null || a == null) return;
      final req = GenRequest(
        profile: profile,
        model: profile.selectedModel,
        system: 'Write a very short title (max 6 words) for this conversation, in the same language as the user. Output only the title, with no quotes or punctuation at the end.',
        msgs: <RMsg>[
          RMsg.user(<RPart>[RPart.text('User: ${clip(u.content, 500)}\n\nAssistant: ${clip(a.content, 500)}')])
        ],
        tools: <ToolDef>[],
        maxTokens: 60,
        cache: false,
      );
      final sb = StringBuffer();
      int heals = 0;
      while (true) {
        sb.clear();
        try {
          await for (final ev in executeCall(prepareCall(req), req, CancelToken())) {
            sb.write(ev.text);
          }
          break;
        } catch (e) {
          if (isCancel(e)) return;
          final ae = await toApiException(e);
          if (heals < 3 && req.tryHeal(ae)) {
            heals++;
            continue;
          }
          return;
        }
      }
      final t = sb.toString().trim().replaceAll('"', '').split('\n').first.trim();
      // لا نكتب فوق عنوان غيّره المستخدم يدوياً أثناء التوليد، ولا نُحيي محادثة محذوفة.
      if (t.isNotEmpty && !deleted && meta.title == before) {
        meta.title = clip(t, 60);
        _titled = true;
        notifyListeners();
        await persist();
      }
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------
//  Session hub
// ---------------------------------------------------------------------
class SessionHub {
  final Map<String, ChatSession> _map = <String, ChatSession>{};
  late final ValueNotifier<ChatSession> current;

  SessionHub() {
    final s = ChatSession(ConvMeta(id: newId()));
    _map[s.meta.id] = s;
    current = ValueNotifier<ChatSession>(s);
  }

  ChatSession newChat({String? projectId}) {
    final cur = current.value;
    if (cur.isEmpty && !cur.generating) {
      cur.meta.projectId = projectId;
      cur.refresh();
      return cur;
    }
    final s = ChatSession(ConvMeta(id: newId(), projectId: projectId));
    _map[s.meta.id] = s;
    current.value = s;
    return s;
  }

  Future<void> open(String id) async {
    var s = _map[id];
    if (s == null) {
      final meta = appContainer.read(convListProvider.notifier).byId(id);
      if (meta == null) return;
      s = ChatSession(meta, existing: true);
      _map[id] = s;
    }
    current.value = s;
    await s.load();
  }

  Future<void> delete(String id) async {
    final s = _map.remove(id);
    if (s != null) {
      s.deleted = true;
      s.stop();
    }
    await LocalStorage.remove('chats', id);
    await CheckpointStore.purge(id);
    ReadLedger.forget(id);
    BashRuntime.forget(id);
    await appContainer.read(convListProvider.notifier).remove(id);
    if (current.value.meta.id == id) {
      // جلسة جديدة فعلاً (وليس إعادة استخدام الجلسة المحذوفة بمعرّفها القديم).
      final f = ChatSession(ConvMeta(id: newId()));
      _map[f.meta.id] = f;
      current.value = f;
    }
  }

  Future<void> updateMeta(ConvMeta m) async {
    await appContainer.read(convListProvider.notifier).upsert(m);
    final s = _map[m.id];
    if (s != null) s.refresh();
  }

  Future<void> persistCurrent() async {
    final s = current.value;
    if (s.messages.isNotEmpty) await s.persist();
  }
}

final SessionHub hub = SessionHub();

String conversationToMarkdown(ConvMeta meta, List<ChatMessage> msgs) {
  final b = StringBuffer('# ${meta.title.isEmpty ? 'محادثة' : meta.title}\n\n');
  b.write('*${fmtDate(meta.createdAt)}*\n\n');
  for (final m in msgs) {
    if (m.excluded) continue;
    b.write(m.role == 'user' ? '## المستخدم\n\n' : '## المساعد${m.model == null ? '' : ' (${m.model})'}\n\n');
    if (m.attachments.isNotEmpty) b.write('المرفقات: ${m.attachments.map((a) => a.name).join(', ')}\n\n');
    if (m.quote != null && m.quote!.isNotEmpty) b.write('${quoteBlock(m.quote!)}\n\n');
    if (m.thinking.trim().isNotEmpty) b.write('<details><summary>التفكير</summary>\n\n${m.thinking.trim()}\n\n</details>\n\n');
    for (final c in m.toolCalls) {
      b.write('- أداة `${c.name}` ${jsonEncode(c.args)}\n');
    }
    if (m.toolCalls.isNotEmpty) b.write('\n');
    if (m.content.isNotEmpty) b.write('${m.content}\n\n');
    if (m.error != null) b.write('> ⚠ ${m.error}\n\n');
  }
  return b.toString();
}

/// يحفظ نصاً في مجلد Download إن أمكن، وإلا في مجلد التطبيق. يعيد المسار.
Future<String> exportTextFile(String fileName, String content) async {
  final safe = safeFileName(fileName);
  try {
    if (Platform.isAndroid) {
      final ok = await PhoneStorage.requestPermissions();
      if (ok) {
        final d = Directory('${PhoneStorage.root}/Download');
        if (await d.exists()) {
          final f = File('${d.path}/$safe');
          await f.writeAsString(content, flush: true);
          return f.path;
        }
      }
    }
  } catch (_) {}
  final dir = await LocalStorage.folder('exports');
  final f = File('${dir.path}/$safe');
  await f.writeAsString(content, flush: true);
  return f.path;
}
