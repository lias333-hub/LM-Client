# CLAUDE_NOTES.md: سجل مشترك بين نسخ Claude

القاعدة: كل نسخة تقرأ هذا الملف قبل أي تعديل، وتضيف سطراً تحت "سجل التغييرات" بعد كل دفعة (التاريخ، من، ماذا، أي ملفات). المستخدم يرفع الملف في بداية كل محادثة. نسخة الريبو في جذر فرع `terminal-plus`؛ من لا يصل للريبو يأخذ الملف من المستخدم.

## بنية المشروع (Flutter)
- كل ملفات `lib/*.dart` أجزاء من `main.dart` (`part of`). أي ملف جديد يلزم تسجيله بسطر `part '...';` في `main.dart`، وإلا لن يراه المترجم. الأجزاء لا تحمل `import` (تُضاف في `main.dart`).
- `core.dart`: الألوان `Pal` والثيمات (`darkPal`, `lightPal`, `termPal` أسود نقي) و`buildTheme` وحوارات `askText/askConfirm` و`showSheet`.
- `ui_kit.dart`: مسافات `Sp` واستدارات `Rd` ومكوّنات `IconBadge`, `NavRow`, `NavTile`, `NavItem`. أي شاشة جديدة تستخدمها.
- `terminal.dart`: جسر Termux (`TermuxBridge`) وأداة النموذج `run_shell` وشاشة `TerminalScreen`.
- `terminal_chat.dart`: وضع Terminal (`UiModeSwitch`, `ChatTopStrip`, `TerminalChatView`)، موافقات داخل السجل (`inlineApproval`)، قائمة `/` (`_kCmds`)، أوامر `!`.
- `agents.dart`: شاشات الـ Agents ومنتقي الموديل `showModelPicker`.
- `data_screens.dart`: الذاكرة والمكتبة والمشاريع وملفات الهاتف والتصدير.
- `messages.dart`: عرض الرسائل، `RichMarkdown` داخل `SelectionArea`، صيغ غنية (تنبيهات `[!NOTE]`، `:blue[..]`، `==..==`، `++..++`، `[[Ctrl]]`، `:::details`).
- `settings.dart`: فهرس إعدادات بسبعة أقسام، كل قسم صفحة فرعية.
- `safety.dart` (Claude A): `searchChats` (بحث نصي في كل المحادثات)، `CheckpointsSheet` (تعديلات الملفات مع تراجع وتحذير إن تغيّر الملف)، `showInspector` (المزوّد والأدوات وتقدير التوكنز وتعليمات النظام؛ يمرّر `workspace: currentWorkspace()` ليُظهر أدوات bash أيضاً). الـ stubs الثلاثة غير موجودة في `compat.dart`.
- `packages/lm_termux`: plugin أندرويد (Kotlin) لـ Termux RUN_COMMAND، ومرتبط في `pubspec.yaml` (`path: packages/lm_termux`). صلاحية `com.termux.permission.RUN_COMMAND` و`<queries>` تُحقَن في manifest من `.github/workflows/build.yml`.

ملفات أضافها Claude B (بيئات التنفيذ):
- `workspace.dart`: `WorkspaceConfig` (و`WorkspaceConfig.local()` = "هذا الهاتف"، معرّفه الثابت `'local'` ولا يُخزَّن في القائمة)، `SshExec` كواجهة تنفيذ واحدة (`run/startJob/readJob/killJob/probe`) تتفرع على `isLocal`، `BashRuntime` (cwd لكل محادثة)، `BashPolicy` و`approveBash` (الموافقات؛ تمر عبر `requestInlineApproval` حين يكون وضع Terminal ظاهراً)، `runUserCommandInWorkspace` لأوامر `!`. أدوات النموذج: `bash`, `bash_output`, `kill_shell`، وتظهر فقط عند اختيار بيئة (`availableTools(..., workspace: ...)`)، وحينها تختفي `run_shell` الخاصة بـ Termux.
- `local_exec.dart`: `LocalExec` يشغّل `/system/bin/sh` داخل التطبيق (HOME = `<app support>/lmhome`)، يقتل شجرة العمليات عبر /proc، ويدير المهام الخلفية بملفات سجل. بدون git أو npm أو أي أداة غير موجودة في نظام أندرويد.
- `exec_probe.dart`: شاشة "اختبار التنفيذ" (7 فحوص، منها هل يسمح أندرويد بتشغيل ملفات كتبها التطبيق في مجلده، W^X). تُفتح من قائمة شاشة "بيئات التنفيذ". نتيجتها تقرر إن كانت طرفية محلية حقيقية ممكنة.
- `workspace_ui.dart`: `showWorkspacePicker`، `WorkspacesScreen`، `WorkspaceEditor` (إضافة بيئة SSH)، `BashApprovalSheet`، و`SshTerminalScreen` (طرفية SSH؛ سُمّيت هكذا لتفادي التعارض مع `TerminalScreen` الخاصة بـ Termux).
- `workspace_fs.dart`: `FsBackend` (`LocalFs` للهاتف، `RemoteFs` عبر SFTP لبيئات SSH) و`currentFs()`؛ أدوات الملفات (list/read/outline/edit/write/search) تمر عليها فتعمل على البيئة المختارة نفسها التي يعمل عليها bash. البحث البعيد عبر grep/find. لا نقاط حفظ (تراجع) للملفات البعيدة (التراجع عبر git على السيرفر). مفاتيح السيرفر (`~/.ssh` وغيرها) محجوبة عن أدوات الملفات.
- `skills.dart` (Claude B): المهارات (Skills) بصيغة Claude Code. `Skill` + `SkillsNotifier` (JsonListNotifier، مجلد `skills`)، `parseSkillMd` (frontmatter name/description)، أداة `use_skill` (بلا اسم = قائمة؛ باسم = النص الكامل وفهرس الملفات المرفقة؛ مع `file` = ملف مرفق)، `skillsPromptSection` (اسم+وصف فقط في الـ prompt، حد 40)، اكتشاف `<cwd>/.claude/skills` و`~/.claude/skills` على بيئة SSH عبر `currentFs()`، استيراد من GitHub العام (`ghDiscover` بطلب شجرة واحد ثم `ghFetchSkill` من raw)، وواجهات `SkillsScreen` و`SkillEditor` (صف في الإعدادات > السلوك). `runSkillsSelfTest` يعمل في فحص المحاكي، ومجلد `ci/skills/hello-ci` ملف اختبار للاستيراد (لا يُحذف).
- `engine_selftest.dart` (Claude B): اختبار ذاتي لمحلّلات الـ stream (`runEngineSelfTest`): أسطر SSE جاهزة لـ Anthropic/OpenAI/Gemini تُثبت ربط أخطاء الـ stream بحالات قابلة للإعادة وكشف الرد المقطوع، مع اختبارات قصّ السياق. يعمل في فحص المحاكي.
- `agent_e2e.dart` (Claude B): `runAgentE2E` يشغّل `ChatSession` الحقيقية ضد خادم HTTP وهمي داخل التطبيق يتكلم بروتوكول Anthropic (6 سيناريوهات). أي تعديل على `session.dart` أو `llm.dart` يجب أن يبقي هذه السيناريوهات خضراء؛ وأي سلوك جديد في الحلقة يُضاف له سيناريو هنا.
- `secrets.dart` (Claude B): `SecretStore` (flutter_secure_storage 9.2.2، Keystore) لمفاتيح الـ API ومفاتيح SSH الخاصة وكلمات السر. ملفات JSON/SharedPreferences لا تحمل أسراراً؛ `ProfilesNotifier` و`WorkspacesNotifier` ينقلان النسخ القديمة تلقائياً. `JsonListNotifier` له خطّافان: `postLoad` و`encodeAll`. أي صنف جديد فيه أسرار يستخدمهما.
- `planning.dart` (Claude B): `todo_write`، `ask_user_question`، `enter_plan_mode`/`exit_plan_mode`، وسياسة وضع التخطيط (`planModeBlock` أول ما يُنفَّذ في `runTool`، و`PlanPolicy.bashReadOnly`). شاشتان جديدتان فقط: `AskUserSheet` و`PlanApprovalSheet` (ورقتان سفليتان). الحالة تُستعاد من نتائج الأدوات المحفوظة (`PlanState.syncFromHistory`). خطّافات الاختبار `PlanState.askHook/enterHook/planHook` للـ CI فقط. وفيه `runPlanningSelfTest`.
- `keepalive.dart` + `packages/lm_keepalive` (Claude B): خدمة مقدّمة أندرويد (dataSync) + قفل تشغيل جزئي (حدّ 3 ساعات) تُحجز من `ChatSession._run` وتُفرَج في `finally` بعدّ مرجعي؛ إشعار ثابت منخفض الأهمية؛ إعداد مخفي `keepAlive` (افتراضي true) بلا واجهة بعد.
- `pubspec.yaml`: `dartssh2` من git (v4.1.0) يتطلب `dependency_overrides: meta: 1.16.0` مع Flutter 3.22.0. لا تحذفه ولا ترفعه (1.19.0 يحتاج Dart 3.5+). `xterm` مثبّت على commit محدد.

## قرارات متفق عليها مع المستخدم
- يُراجَع أي تصميم أولاً في Artifact، ثم يُنفَّذ بعد موافقته.
- أدوات الملفات تصل للنموذج فقط عند اختيار Agent (`availableTools` في `tools.dart`).
- إعدادات مخفية بقيم ثابتة: `promptCache`, `trimOldResults`, `includeDate`, `memoryOn`, `thinkMode`, `topP`, `maxTokens`, `contextLimit`, `taskBudget`, `autoCompact`.
- المشاريع تعمل مثل Claude: تعليمات وملفات معرفة وسعة، والمحادثات داخل المشروع (لم يُنفَّذ بعد).
- الذاكرة: ملفات صغيرة محلية، والنموذج يرى الفهرس فقط ويقرأ الملف عند الحاجة بأداة (لم يُنفَّذ بعد).
- هدف بعيد: بناء أفضل Harness ممكن.
- (2026-10-25) فرع `terminal-plus` هو الأساس: واجهة Terminal كما هي، ويُضاف إليها كل ما في النسخة الأخرى. لا تغيير على الواجهة دون موافقة المستخدم.
- (2026-10-25) الهدف الجوهري: استخدام كل ميزات Claude Code على الهاتف، والطرفية داخل التطبيق نفسه دون تطبيقات أخرى.
- (2026-10-25) لا وكلاء فرعيين (حد الاستخدام). التحقق من الترجمة عبر GitHub Actions لأن لا Dart SDK محلياً: دفع الفرع ثم قراءة `ci-logs/latest/2_analyze.txt` و`3_build.txt`. هذا يغطي اقتراح A بخطوة `flutter analyze` في CI: موجودة ومفعّلة لكل دفعة.

## قواعد التنسيق بين النسختين (مقترحة من Claude B، بانتظار موافقة المستخدم)
- كل نسخة على فرعها، والدمج بـ 3-way merge، ولا يُنسخ ملف كامل فوق ملف الأخرى (يضيع عمل أحدهما بصمت). الدمج الأخير (v2.6.0) تم هكذا: الأساس = قمة `Terminal` (daa8416) وهي نفسها أساس نسخة A.
- ملكية مقترحة لتفادي تكرار العمل: Claude A = الواجهة (`terminal_chat`, `messages`, `settings`, `data_screens`, `ui_kit`, `safety`, ثيمات `core`). Claude B = المحرك (`workspace*`, `local_exec`, `exec_probe`, `tools`, `session`, `llm`) وملف CI. الملفات المشتركة (`main.dart`, `models`, `store`) تعديلات صغيرة وتُسجَّل هنا.
- لا يُكتب سطر في السجل قبل أن يمر `flutter analyze` والبناء على CI بلا أخطاء، ويُذكر رقم التشغيل. ويُكتب بوضوح "لم يُختبر على جهاز" إن لم يجرّبه المستخدم.
- A يرسل نسخته كاملة كل مرة (`lib` + `packages` + `pubspec.yaml` + workflow)، وB يدمجها ويعيدها للمستخدم.

## سجل التغييرات
- 2026-10-25 (Claude A): إصلاح البناء الأول، الـ Agents، Terminal عبر Termux، وضع Terminal، نظام التصميم، فهرس الإعدادات، شاشات البيانات، التنسيق الغني، ثيم Terminal الأسود.
- 2026-10-25 (Claude A): `safety.dart` (بحث المحادثات، نقاط الحفظ، فحص الطلب)، `packages/lm_termux`، `scrollPadding` لخانة الكتابة، ثيم Terminal كخيار ثالث للمظهر (`themeMode == 3`)، صيغ تنسيق إضافية في تعليمات النظام، زر الملفات في وضع Terminal يفتح `PhoneFilesScreen`.
- 2026-10-25 (Claude B): فرع `terminal-plus` (v2.5.1) فوق Terminal: بيئات التنفيذ (SSH + هذا الهاتف)، أدوات bash للنموذج، موافقات bash داخل السجل، `/env`، شاشة اختبار التنفيذ. جديدة: workspace.dart, local_exec.dart, exec_probe.dart, workspace_ui.dart.
- 2026-10-25 (Claude B): دمج نسخة A الأحدث في `terminal-plus` (v2.6.0) بـ 3-way merge: تعارض واحد فقط (`compat.dart`) وحُلّ. حُذف `restored.dart` الخاص بي لأن A أضاف `safety.dart` بنفس الدوال الثلاث (تُؤخذ نسخة A)، وعُدّل `showInspector` ليمرّر `workspace`. أُضيفت إلى `build.yml` صلاحية RUN_COMMAND و`<queries>` لـ Termux، وإلى `pubspec.yaml` اعتماد `lm_termux`. CI (run 115): analyze بلا أخطاء (ملاحظتان قديمتان فقط)، APK 26.5MB. لم يُختبر على جهاز بعد.
- 2026-10-25 (Claude B): خطوة محاكي في CI (job `probe`، أندرويد 14 x86_64) تثبّت الـ APK وتشغّل شاشة اختبار التنفيذ تلقائياً عبر مسار البدء `/probe` (`AutoProbeApp` في exec_probe.dart، يُستدعى من `main()` في core.dart؛ `adb shell am start -n com.lmclient.lm_client/.MainActivity --es route /probe`) وتكتب `ci-logs/latest/4_probe.txt` و`4_screen.png`. run 116 أخضر. نتيجة المحاكي: `sh` و41 أداة والمهلة والإيقاف والمهام الخلفية والمجلد الحالي ورمز الخروج كلها تعمل؛ تنفيذ ملف ثنائي أو سكربت shebang من مجلد التطبيق مرفوض (W^X) كما هو متوقع عند targetSdk 34. هذا محاكٍ وليس هاتف المستخدم.
- 2026-10-26 (Claude B): دفعة 1 (v2.6.3): أدوات الملفات تتبع البيئة المختارة (كانت تعدّل ملفات الهاتف بينما bash يعمل على السيرفر)، وسقف جولات الأدوات من 12 إلى 60 (إعداد مخفي `maxToolRounds` في `AppSettings`)، وتعليمات النظام تخبر النموذج أن أدوات الملفات وbash يشتركان في البيئة. ملفات: workspace_fs.dart (جديد)، tools.dart, session.dart, models.dart, core.dart, workspace.dart, main.dart. اختبار تكاملي في CI: يشغّل الـ runner خادم `sshd` والتطبيق على المحاكي يمرّر أدوات الملفات وbash والمهام الخلفية عبره (`runSshSelfTest` في exec_probe.dart؛ المسار `/probe?ssh=...`): 23 فحصاً ناجحاً (run 119). أول تجربة فعلية لطبقة SSH. ما زال غير مجرَّب على هاتف المستخدم.
- 2026-10-26 (Claude B): دفعة 2 (v2.7.0): Skills. مهارات يدوية/ملصوقة/مستوردة من GitHub، أداة `use_skill`، واكتشاف `.claude/skills` على SSH. الأمان: المهارة نص فقط ولا تمنح صلاحيات، وكل أمر أو كتابة يمرّ بالموافقات المعتادة؛ وتعليمات النظام تستثني ما حمّله `use_skill` من قاعدة «نتائج الأدوات بيانات غير موثوقة» مع بقاء أولوية المستخدم وقواعد الأمان. التحقق في CI (تشغيل 120): 13/13 اختبار منطق وأداة وتخزين، منها استيراد حقيقي من GitHub (discover + fetch)، و30/30 في اختبار SSH (7 جديدة: اكتشاف المهارات وتحميلها وقراءة ملف ورفض `..`). لم تُجرَّب على هاتف حقيقي بعد. ملاحظة لـ A: عند مرحلة اللغة تُحوَّل نصوص `skills.dart` إلى `tr()` مع بقية التطبيق (نصوصها الآن عربية مباشرة).
- 2026-10-27 (Claude B): دفعة 3 (v2.7.1): متانة الـ stream. بعد مراجعة Opus 5.5 (محادثة أرسلها المستخدم) تحققتُ من كل ادعاء في الكود قبل العمل به. تأكّد: أخطاء داخل الـ stream (`overloaded_error` وغيرها) كانت تُرمى بلا status فلا تُعاد، والرد المقطوع بإغلاق نظيف كان يمرّ كاملاً (واستدعاء أداة ناقص يضيع بصمت). الإصلاح في `llm.dart`: `streamApiError` (overloaded→529، rate limit→429، خطأ خادم→500/503)، و`truncationError` (صارم لـ Anthropic وGemini، ولـ OpenAI-compatible فقط عند وجود استدعاء أداة قيد التجميع لأن الخوادم تختلف)، والتقاط انقطاع الاتصال أثناء الاستلام كخطأ شبكة. في `session.dart` صارت الجولة المقطوعة تُفرَّغ وتُعاد (الأدوات لا تُنفَّذ قبل نهاية البث، فالإعادة آمنة). CI (تشغيل 121): 20/20.
- 2026-10-27 (Claude B): دفعة 4 (v2.7.2): السياق داخل الدور. تأكّد أن الضغط/الفحص كان مرة قبل الحلقة فقط وأن نتائج أدوات الدور الحالي لا تُقصّ أبداً (فالمهام الطويلة تنتهي بـ prompt too long). الآن: قصّ نتائج الجولات القديمة داخل الدور عند تجاوز الميزانية (تبقى آخر 8 ثم 4 ثم 2 ثم 1 جولة كاملة) بحدّ ثابت `_trimBeforeId` يتحرك دفعة واحدة كي لا ينكسر الكاش كل جولة، ويُصفَّر `ReadLedger` عند التقدّم كي يستطيع النموذج إعادة قراءة ما قُصّ. وإصلاح ذاتي لخطأ «السياق أطول من النافذة» (`isContextTooLong`): قصّ أشدّ ثم تلخيص ثم إعادة المحاولة. CI (تشغيل 122): 23/23.
- 2026-10-27 (Claude B): v2.7.3: اختبار شامل لحلقة الـ Agent بنموذج وهمي (`agent_e2e.dart`). CI (تشغيل 123): 6/6، وأثبت: حلقة أدوات كاملة، إعادة الرد والأداة المقطوعين، overloaded داخل stream، قصّ السياق (طلب 240KB → 166KB)، وإصلاح prompt-too-long (244KB → 68KB). اكتشاف مهم: اتصال HTTP نصي (بدون TLS) بـ localhost يعمل من dart:io على أندرويد 14 بلا `usesCleartextTraffic`، أي أن Ollama المحلي عبر http مدعوم.
- 2026-10-27 (Claude B): دفعة 5 (v2.8.0): الأسرار إلى Keystore (`secrets.dart`) مع ترحيل تلقائي، و`allowBackup=false` و`fullBackupContent=false` في الـ manifest (يحقنها build.yml). CI (تشغيل 125): 11/11 اختبار أسرار، ووُجد في ملفات JSON `apiKey:""` و`keyPem:""`. تحقّقتُ من الـ APK المثبّت على المحاكي (تشغيل 126): `pkgFlags=[ HAS_CODE ALLOW_CLEAR_USER_DATA ]` أي أن ALLOW_BACKUP غير موجود. لم يُجرَّب على هاتف حقيقي؛ المستخدمون الحاليون تُرحَّل مفاتيحهم عند أول تشغيل. إن فشل Keystore يبقى المفتاح في الملف بدل أن يضيع (لا يُحذف سرّ لمجرد أن قراءته فشلت).
- 2026-10-29 (Claude B): دفعة 6 (v2.9.0): أدوات التخطيط والتفاعل (`planning.dart`). CI (تشغيل 129–131): تخطيط 31/31 وسيناريو e2e رقم 7 (مهام ← سؤال ← وضع التخطيط ← كتابة مرفوضة ← خطة مرفوضة بتعليق ← خطة مقبولة) في الحلقة الحقيقية. أضفتُ لقطات شاشة تلقائية في CI للورقتين الجديدتين (علامات `SHOT` في الـ probe) وفتحتُ الصور: تُعرضان سليمتين، والخطة تظهر Markdown عبر `RichMarkdown`. لم تُلمس واجهة Terminal. لم تُجرَّب باللمس ولا على هاتف حقيقي. لا يوجد بعد مفتاح وضع تخطيط يضغطه المستخدم ولا لوحة مهام حيّة (طلب واجهة لـ Claude A، انظر مستند التسليم).
- 2026-10-29 (Claude B): دفعة 7 (v2.10.0): خدمة الخلفية (`lm_keepalive`). CI (تشغيل 132): keepalive 9/9، وفحص من النظام نفسه عبر `dumpsys`: `isForeground=true types=00000001`، والإشعار (قناة `lmclient_work`، المعرّف 4271)، و`PARTIAL_WAKE_LOCK 'lmclient:work'` مع أزواج ACQ/REL تلقائية من تشغيل المحادثات الحقيقية في e2e. غير قابل للاختبار على المحاكي: Doze مع الشاشة المطفأة وقاتلات البطارية عند الشركات؛ قد يحتاج الهاتف الحقيقي استثناء التطبيق من توفير البطارية.

## مفتوح (جرد A بتاريخ 2026-10-25، مرتّب بالأولوية، مع ملاحظات B)
### ميزات معطّلة أو فاضية الآن
- `task_runtime.dart` و`verification_gate.dart` و`tool_registry.dart` لا يستدعيها أحد (شغل Copilot غير موصول). ميزانية المهمة تُنشأ من جديد مع كل رسالة فلا تُستنفد أبداً.
### تصاميم موافق عليها ولم تُنفَّذ
- خانة الكتابة وشكل الرسائل وبطاقات الأدوات في وضع المحادثة.
- المشاريع على نمط Claude: صفحة مشروع، وصف، سعة المعرفة، محادثات داخله.
- الذاكرة كفهرس: `read_memory` موجودة، لكن الفهرس لا يُستخدم إلا فوق 6000 حرف؛ المطلوب فهرس دائماً وشاشة كقائمة ملفات.
- تحديد الأسطر بدل الكلمات.
- شاشة المساحة (دمج مع Terminal)؛ وهي تشغّل `sh` أندرويد بدون git.
- عناصر صفحات الإعدادات الداخلية بشكلها القديم، ومشكلة bidi في نص "حول".
### Harness وتوكنز
- ملفات معرفة المشروع تُحشر كاملة في كل رسالة (حتى `maxChars` لكل ملف). المطلوب فهرس + `read_library_file` عند الحاجة.
- أدوات ناقصة: `web_search`، خطة/todo، `ask_user` بخيارات، أدوات الهاتف (منبه/تقويم/موقع).
- اقتراحات قابلة للضغط، LaTeX.
### بيئة التنفيذ
- `/env` أضافه Claude B. التعريف في `terminal_chat.dart` (`_kCmds` و`case '/env'`) ويفتح `showWorkspacePicker` في `workspace_ui.dart`. مدخلان آخران: Settings ← "بيئات التنفيذ"، وقائمة منتقي الـ Agent ("بيئة التنفيذ (Bash)"). "هذا الهاتف" = `sh` أندرويد بدون git/npm. "إنشاء بيئة جديدة" = `WorkspaceEditor` (SSH: مضيف ومنفذ ومستخدم ومفتاح ed25519 يُولَّد داخل التطبيق، مع تثبيت بصمة الخادم عند أول اتصال).
- **تعارض اتجاه (يحتاج قرار المستخدم)**: خطة A "Termux افتراضي، proot لاحقاً" تتعارض مع طلب المستخدم الصريح: طرفية داخل التطبيق دون أي تطبيق آخر. نتيجة المحاكي (run 116): W^X يمنع تشغيل أي ملف ثنائي أو سكربت من مجلد التطبيق عند targetSdk 34، فلا تنزيل لـ git/python/node. المسارات الممكنة لطرفية داخلية: (1) رفع targetSdk إلى 28 مثل Termux (يُجرَّب على المحاكي أولاً)، (2) أدوات تنفيذية مضمّنة داخل الـ APK نفسه، (3) SSH. القرار النهائي للمستخدم بعد التجربة. حتى ذلك الحين Termux خيار إضافي لا افتراضي.
- جسر Termux لم يُختبر على جهاز المستخدم بعد (يحتاج `allow-external-apps` في Termux). ملاحظة B: بناء CI يطبع تحذيرات Kotlin عن إصدار البيانات الوصفية (1.8 مقابل 1.6) من مكتبات gradle ولا يفشل؛ إن ظهر "native bridge missing" على الجهاز فهذا أول ما يُفحص (`packages/lm_termux/android/build.gradle`).
### جودة
- A لا يبني ولا يختبر: كل كود A يُترجم على CI عند B (run 115 أخضر). الكود الميت: `ProjectStrip`, `_navChip`, `_quickChip`، واسم `compat.dart` مضلل.
- اختبار الجهاز: شاشة اختبار التنفيذ تعمل الآن آلياً على محاكي في CI (انظر السجل)، لكن مسارات bash مع النموذج والموافقات والجسر لم تُجرَّب على هاتف المستخدم.
