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
- `packages/lm_termux`: plugin أندرويد (Kotlin) لـ Termux RUN_COMMAND. لا يعتمد على `.github`. (موجود في نسخة Claude A الأحدث؛ غير موجود بعد في `terminal-plus`.)
- `compat.dart`: بقايا stubs. عند Claude A ما بقي فيه ما زال فارغاً عمداً (`showInspector`, `CheckpointsSheet`, `searchChats`). في `terminal-plus` نُقلت الثلاثة إلى `restored.dart` بتنفيذ حقيقي وأُزيلت من `compat.dart` (انظر "مفتوح").

ملفات أضافها Claude B (بيئات التنفيذ):
- `workspace.dart`: `WorkspaceConfig` (و`WorkspaceConfig.local()` = "هذا الهاتف"، معرّفه الثابت `'local'` ولا يُخزَّن في القائمة)، `SshExec` كواجهة تنفيذ واحدة (`run/startJob/readJob/killJob/probe`) تتفرع على `isLocal`، `BashRuntime` (cwd لكل محادثة)، `BashPolicy` و`approveBash` (الموافقات؛ تمر عبر `requestInlineApproval` حين يكون وضع Terminal ظاهراً)، `runUserCommandInWorkspace` لأوامر `!`. أدوات النموذج: `bash`, `bash_output`, `kill_shell`، وتظهر فقط عند اختيار بيئة (`availableTools(..., workspace)`)، وحينها تختفي `run_shell` الخاصة بـ Termux.
- `local_exec.dart`: `LocalExec` يشغّل `/system/bin/sh` داخل التطبيق (HOME = `<app support>/lmhome`)، يقتل شجرة العمليات عبر /proc، ويدير المهام الخلفية بملفات سجل. بدون git أو npm أو أي أداة غير موجودة في نظام أندرويد.
- `exec_probe.dart`: شاشة "اختبار التنفيذ" (7 فحوص، منها هل يسمح أندرويد بتشغيل ملفات كتبها التطبيق في مجلده، W^X). تُفتح من قائمة شاشة "بيئات التنفيذ". نتيجتها تقرر إن كانت طرفية محلية حقيقية ممكنة.
- `workspace_ui.dart`: `showWorkspacePicker`، `WorkspacesScreen`، `WorkspaceEditor` (إضافة بيئة SSH)، `BashApprovalSheet`، و`SshTerminalScreen` (طرفية SSH؛ سُمّيت هكذا لتفادي التعارض مع `TerminalScreen` الخاصة بـ Termux).
- `restored.dart`: `CheckpointsSheet`, `showInspector`, `searchChats`, `redactJson`, `maskKey`, `describeRequest` بتنفيذ حقيقي (مأخوذة من v2.3.0).
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
- (2026-10-25) لا وكلاء فرعيين (حد الاستخدام). التحقق من الترجمة عبر GitHub Actions لأن لا Dart SDK محلياً: دفع الفرع ثم قراءة `ci-logs/latest/2_analyze.txt` و`3_build.txt`.

## قواعد التنسيق بين النسختين (مقترحة من Claude B، بانتظار موافقة المستخدم)
- كل نسخة على فرعها، والدمج بـ 3-way merge، ولا يُنسخ ملف كامل فوق ملف الأخرى (يضيع عمل أحدهما بصمت).
- ملكية مقترحة لتفادي تكرار العمل: Claude A = الواجهة (`terminal_chat`, `messages`, `settings`, `data_screens`, `ui_kit`, ثيمات `core`). Claude B = المحرك (`workspace*`, `local_exec`, `exec_probe`, `tools`, `session`, `llm`). الملفات المشتركة (`main.dart`, `models`, `store`) تعديلات صغيرة وتُسجَّل هنا.
- لا يُكتب سطر في السجل قبل أن يمر `flutter analyze` والبناء على CI بلا أخطاء، ويُذكر رقم التشغيل. ويُكتب بوضوح "لم يُختبر على جهاز" إن لم يجرّبه المستخدم.
- قبل أي دمج: ترسل نسخة A الأحدث كاملة (`lib` + `packages` + `pubspec.yaml` + workflow).

## سجل التغييرات
- 2026-10-25 (Claude A): إصلاح البناء الأول، الـ Agents، Terminal عبر Termux، وضع Terminal، نظام التصميم، فهرس الإعدادات، شاشات البيانات، التنسيق الغني، ثيم Terminal الأسود.
- 2026-10-25 (Claude B): فرع `terminal-plus` (v2.5.1) فوق Terminal: بيئات التنفيذ (SSH + هذا الهاتف)، أدوات bash للنموذج، موافقات bash داخل السجل، `/env`، شاشة اختبار التنفيذ، وإعادة CheckpointsSheet/showInspector/searchChats بتنفيذ حقيقي. جديدة: workspace.dart, local_exec.dart, exec_probe.dart, workspace_ui.dart, restored.dart. معدّلة: main.dart, core.dart (الإصدار), models.dart, store.dart, tools.dart, session.dart, messages.dart, settings.dart, agents.dart, terminal_chat.dart, compat.dart, pubspec.yaml, build.yml. CI: analyze بلا أخطاء، APK 26.5MB (run 40147377820). لم يُختبر على جهاز بعد.

## مفتوح
- أمر `/env` (حُلّ توثيقه): أضافه Claude B. التعريف في `terminal_chat.dart` (`_kCmds` و`case '/env'`) ويفتح `showWorkspacePicker` في `workspace_ui.dart`. مدخلان آخران: Settings ← "بيئات التنفيذ"، وقائمة منتقي الـ Agent ("بيئة التنفيذ (Bash)"). "هذا الهاتف" يشغّل `sh` الخاص بأندرويد بدون git أو npm؛ لهما Termux فقط. "إنشاء بيئة جديدة" = `WorkspaceEditor` (SSH: مضيف ومنفذ ومستخدم ومفتاح ed25519 يُولَّد داخل التطبيق، مع تثبيت بصمة الخادم عند أول اتصال).
- **دمج نسخة A الأحدث أولاً**: `terminal-plus` مبني على Terminal الأقدم ولا يحوي `packages/lm_termux`. لا عمل جديد على الواجهة أو الجسر قبل الدمج.
- **تعارض متوقع عند الدمج**: إن كانت `compat.dart` عند A ما زالت تعرّف `showInspector` و`CheckpointsSheet` و`searchChats` فسيحدث تعريف مكرر وينكسر البناء. الحل: تُؤخذ `compat.dart` الخاصة بـ A بعد حذف هذه الثلاثة، وتبقى `restored.dart`. قرار A بإبقائها فارغة "عمداً" يحتاج تأكيداً: عناصر القوائم في `chat_page.dart` تستدعيها (السطران 314 و324) وكانت لا تفعل شيئاً.
- **جسر Termux في CI**: workflow الحالي لا ينسخ `MainActivity.kt`. ملاحظة A أن plugin لا يعتمد على `.github` تعني أن نسخته الأحدث تحل ذلك؛ يُؤكَّد بعد الدمج.
- **اختبار الجهاز**: شاشة اختبار التنفيذ ومسارات bash المحلية والموافقات لم تُجرَّب على هاتف. القرار بين طرفية محلية حقيقية (PTY) وSSH فقط ينتظر نتيجتها.
- تنفيذ المشاريع على نمط Claude، وفهرس الذاكرة عند الطلب، وتحديد الأسطر بدل الكلمات.
