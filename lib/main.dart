import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const ProviderScope(child: LMClientApp()));
}

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

// حفظ محلي لكل شي - Offline First
class LocalStorage {
  static Future<Directory> getDir() async {
    final d = await getApplicationDocumentsDirectory();
    final lm = Directory("${d.path}/LMClient");
    if (!await lm.exists()) await lm.create(recursive: true);
    return lm;
  }
  static Future<void> save(String folder, String name, String data) async {
    final dir = await getDir();
    final f = Directory("${dir.path}/$folder");
    if (!await f.exists()) await f.create(recursive: true);
    await File("${f.path}/$name.json").writeAsString(data);
  }
  static Future<String?> load(String folder, String name) async {
    final dir = await getDir();
    final file = File("${dir.path}/$folder/$name.json");
    if (await file.exists()) return await file.readAsString();
    return null;
  }
}

class LMClientApp extends ConsumerWidget {
  const LMClientApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final lightTheme = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFAF9F5),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFFCC785C),
        surface: Color(0xFFFFFFFF),
        surfaceVariant: Color(0xFFF0EEE6),
        background: Color(0xFFFAF9F5),
                onSurface: Color(0xFF2D2D2D),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFFAF9F5), elevation: 0, foregroundColor: Color(0xFF2D2D2D)),
    );
    final darkTheme = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF191919),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFE8A082),
        surface: Color(0xFF2A2A2A),
        surfaceVariant: Color(0xFF2F2F2F),
        background: Color(0xFF191919),
        onSurface: Color(0xFFE8E8E8),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF191919), elevation: 0),
    );
    return MaterialApp(
      title: 'LMClient',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: mode,
      home: const HomeScreen(),
    );
  }
}
// Models + حساب التوكنز
int estimateTokens(String t) => (t.length / 4).ceil();

class ChatMessage {
  final String id;
  final String role;
  final String content;
  final List<String> fileNames;
  final DateTime time;
  final bool excluded;
  ChatMessage({required this.id, required this.role, required this.content, this.fileNames = const [], required this.time, this.excluded = false});
  Map<String,dynamic> toJson() => {"id":id,"role":role,"content":content,"fileNames":fileNames,"time":time.toIso8601String(),"excluded":excluded};
  factory ChatMessage.fromJson(Map<String,dynamic> j) => ChatMessage(id:j["id"], role:j["role"], content:j["content"], fileNames:List<String>.from(j["fileNames"]??[]), time:DateTime.parse(j["time"]), excluded:j["excluded"]??false);
  ChatMessage copyWith({bool? excluded}) => ChatMessage(id:id, role:role, content:content, fileNames:fileNames, time:time, excluded: excluded??this.excluded);
}

class Project {
  final String id;
  final String name;
  final String instructions;
  Project({required this.id, required this.name, this.instructions = ""});
  Map<String,dynamic> toJson() => {"id":id,"name":name,"instructions":instructions};
  factory Project.fromJson(Map<String,dynamic> j) => Project(id:j["id"], name:j["name"], instructions:j["instructions"]??"");
}

class MemoryPart {
  final String id;
  final String title;
  final String content;
  MemoryPart({required this.id, required this.title, required this.content});
  Map<String,dynamic> toJson() => {"id":id,"title":title,"content":content};
  factory MemoryPart.fromJson(Map<String,dynamic> j) => MemoryPart(id:j["id"], title:j["title"], content:j["content"]);
}
// Agent - مع صلاحيات كاملة انت بتحددها
class Agent {
  final String id;
  final String name;
  final String systemPrompt;
  final List<String> allowedPaths;
  final bool canRead;
  final bool canWrite;
  final bool canExecute;
  Agent({required this.id, required this.name, required this.systemPrompt, this.allowedPaths = const [], this.canRead = true, this.canWrite = false, this.canExecute = false});
  Map<String,dynamic> toJson() => {"id":id,"name":name,"systemPrompt":systemPrompt,"allowedPaths":allowedPaths,"canRead":canRead,"canWrite":canWrite,"canExecute":canExecute};
  factory Agent.fromJson(Map<String,dynamic> j) => Agent(id:j["id"], name:j["name"], systemPrompt:j["systemPrompt"]??"", allowedPaths:List<String>.from(j["allowedPaths"]??[]), canRead:j["canRead"]??true, canWrite:j["canWrite"]??false, canExecute:j["canExecute"]??false);
}
class LibraryItem {
  final String id;
  final String name;
  final int size;
  final DateTime time;
  LibraryItem({required this.id, required this.name, required this.size, required this.time});
}
// Providers - بدون حدود + ذاكرة مقسمة عابرة + حفظ محلي
final apiBaseUrlProvider = StateProvider<String>((ref) => "https://cleanapis.com");
final apiKeyProvider = StateProvider<String>((ref) => "");
final modelsProvider = StateProvider<List<String>>((ref) => []);
final selectedModelProvider = StateProvider<String>((ref) => "");
final messagesProvider = StateProvider<List<ChatMessage>>((ref) => []);
final projectsProvider = StateProvider<List<Project>>((ref) => []);
final memoryPartsProvider = StateProvider<List<MemoryPart>>((ref) => []);
final libraryProvider = StateProvider<List<LibraryItem>>((ref) => []);
final agentsProvider = StateProvider<List<Agent>>((ref) => []);
final selectedAgentProvider = StateProvider<Agent?>((ref) => null);
final thinkingProvider = StateProvider<String>((ref) => "");
final lastContextProvider = StateProvider<String>((ref) => "");
final lastTokensProvider = StateProvider<Map<String,int>>((ref) => {"input":0,"output":0});
// حفظ الـ API والجلسات بشكل دائم
Future<void> loadSavedData(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString("api_baseUrl");
  final savedKey = prefs.getString("api_key");
  final savedModel = prefs.getString("api_model");
  if (savedUrl != null) ref.read(apiBaseUrlProvider.notifier).state = savedUrl;
  if (savedKey != null) ref.read(apiKeyProvider.notifier).state = savedKey;
  if (savedModel != null) ref.read(selectedModelProvider.notifier).state = savedModel;
  // تحميل المحادثات المحفوظة
  final chatsJson = await LocalStorage.load("chats", "current");
  if (chatsJson != null) {
    try {
      final list = (jsonDecode(chatsJson) as List).map((e) => ChatMessage.fromJson(e)).toList();
      ref.read(messagesProvider.notifier).state = list;
    } catch (_) {}
  }
}
Future<void> saveApi(String url, String key, String model) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString("api_baseUrl", url);
  await prefs.setString("api_key", key);
  await prefs.setString("api_model", model);
}
// Universal API - بدون حدود Input/Output + تصليح cleanapis.com
class UniversalApi {
  final Dio dio = Dio();
  String fixUrl(String url) {
    url = url.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (url.endsWith('/v1')) url = url.substring(0, url.length - 3);
    return url;
  }
  Future<List<String>> fetchModels(String baseUrl, String apiKey) async {
    final base = fixUrl(baseUrl);
    final res = await dio.get("$base/v1/models",
      options: Options(headers: {"Authorization": "Bearer $apiKey"}));
    return (res.data['data'] as List).map((e) => e['id'].toString()).toList();
  }
  Stream<String> chatStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<ChatMessage> history,
    required String prompt,
  }) async* {
    final base = fixUrl(baseUrl);
    // بدون حدود - نرسل كل الرسائل غير المستبعدة كاملة
    final messages = [
      ...history.where((m) => !m.excluded).map((m) => {"role": m.role, "content": m.content}),
      {"role": "user", "content": prompt}
    ];
    // لا نرسل max_tokens نهائيا - الموديل يحدد حده
    final res = await dio.post("$base/v1/chat/completions",
      data: {"model": model, "messages": messages, "stream": true},
      options: Options(headers: {"Authorization": "Bearer $apiKey"}, responseType: ResponseType.stream));
    await for (var chunk in res.data.stream) {
      final lines = utf8.decode(chunk).split("\n");
      for (var line in lines) {
        if (line.startsWith("data: ") && !line.contains("[DONE]")) {
          try {
            final j = jsonDecode(line.substring(6));
            final d = j['choices'][0]['delta']['content'];
            if (d != null) yield d.toString();
          } catch (_) {}
        }
      }
    }
  }
}
final universalApiProvider = Provider((ref) => UniversalApi());
// HomeScreen + الوضع الليلي
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends ConsumerState<HomeScreen> {
  int idx = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(() => loadSavedData(ref));
  }
  @override
  Widget build(BuildContext context) {
    final screens = [const ChatScreen(), const ProjectsScreen(), const LibraryScreen(), const MemoryScreen(), const AgentsScreen(), const SettingsScreen()];
    final titles = ["LMClient", "Projects", "المكتبة", "الذاكرة", "Agents", "الإعدادات"];
    final models = ref.watch(modelsProvider);
    final selected = ref.watch(selectedModelProvider);
    return Scaffold(
      appBar: AppBar(
        leading: Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu), onPressed: () => Scaffold.of(ctx).openDrawer())),
        title: models.isEmpty ? Text(titles[idx]) : DropdownButton<String>(value: selected.isEmpty ? null : selected, hint: const Text("اختر الموديل"), underline: const SizedBox(), items: models.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 14)))).toList(), onChanged: (v) => ref.read(selectedModelProvider.notifier).state = v!),
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.edit_square), tooltip: "محادثة جديدة", onPressed: () { ref.read(messagesProvider.notifier).state = []; ref.read(lastContextProvider.notifier).state = ""; setState(() => idx = 0); })],
      ),
      drawer: Drawer(
        child: ListView(padding: EdgeInsets.zero, children: [
          DrawerHeader(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceVariant), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [Text("LMClient", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Text("Claude Clone - بدون حدود")])),
          ListTile(leading: const Icon(Icons.add), title: const Text("محادثة جديدة"), onTap: () { ref.read(messagesProvider.notifier).state = []; Navigator.pop(context); setState(() => idx = 0); }),
          const Divider(),
          ListTile(leading: const Icon(Icons.chat), title: const Text("الشات"), selected: idx==0, onTap: () { Navigator.pop(context); setState(() => idx=0); }),
          ListTile(leading: const Icon(Icons.folder), title: const Text("Projects"), selected: idx==1, onTap: () { Navigator.pop(context); setState(() => idx=1); }),
          ListTile(leading: const Icon(Icons.library_books), title: const Text("المكتبة"), selected: idx==2, onTap: () { Navigator.pop(context); setState(() => idx=2); }),
          ListTile(leading: const Icon(Icons.memory), title: const Text("الذاكرة"), selected: idx==3, onTap: () { Navigator.pop(context); setState(() => idx=3); }),
          ListTile(leading: const Icon(Icons.smart_toy), title: const Text("Agents"), selected: idx==4, onTap: () { Navigator.pop(context); setState(() => idx=4); }),
          ListTile(leading: const Icon(Icons.settings), title: const Text("الإعدادات"), selected: idx==5, onTap: () { Navigator.pop(context); setState(() => idx=5); }),
        ]),
      ),
      body: screens[idx],
    );
  }
}
// شاشة الذاكرة المقسمة العابرة - النموذج يقسمها ويستدعي أي جزء
class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mem = ref.watch(memoryPartsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("الذاكرة المقسمة")),
      body: mem.isEmpty
          ? const Center(child: Text("لا يوجد ذاكرة\nاضغط + لإضافة جزء جديد"))
          : ListView.builder(
              itemCount: mem.length,
              itemBuilder: (c, i) => Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: const Icon(Icons.memory),
                  title: Text(mem[i].title),
                  subtitle: Text(mem[i].content, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () async {
                      final l = [...mem]..removeAt(i);
                      ref.read(memoryPartsProvider.notifier).state = l;
                      await LocalStorage.save("memory", "parts", jsonEncode(l.map((e) => e.toJson()).toList()));
                    },
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addMemory(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
  void _addMemory(BuildContext ctx, WidgetRef ref) {
    final t = TextEditingController();
    final c = TextEditingController();
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text("إضافة جزء للذاكرة"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: t, decoration: const InputDecoration(labelText: "العنوان", hintText: "مثال: تفضيلات اللغة")),
        const SizedBox(height: 8),
        TextField(controller: c, decoration: const InputDecoration(labelText: "المحتوى", hintText: "مثال: أفضل الرد بالعربي"), maxLines: 3),
      ]),
      actions: [TextButton(onPressed: () async {
        if (t.text.isNotEmpty && c.text.isNotEmpty) {
          final part = MemoryPart(id: const Uuid().v4(), title: t.text, content: c.text);
          final l = [...ref.read(memoryPartsProvider), part];
          ref.read(memoryPartsProvider.notifier).state = l;
          await LocalStorage.save("memory", "parts", jsonEncode(l.map((e) => e.toJson()).toList()));
          Navigator.pop(ctx);
        }
      }, child: const Text("حفظ"))],
    ));
  }
}
// المكتبة - كل المرفقات مصنفة + بحث + إعادة استخدام
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("المكتبة")),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: "ابحث في المكتبة...", border: OutlineInputBorder()),
            onChanged: (v) {},
          ),
        ),
        Expanded(
          child: lib.isEmpty
              ? const Center(child: Text("المكتبة فارغة\nارفع ملفات من الشات وستظهر هنا"))
              : ListView.builder(
                  itemCount: lib.length,
                  itemBuilder: (c, i) => ListTile(
                    leading: const Icon(Icons.insert_drive_file),
                    title: Text(lib[i].name),
                    subtitle: Text("${lib[i].size} bytes - ${lib[i].time.day}/${lib[i].time.month}"),
                    trailing: IconButton(icon: const Icon(Icons.share), onPressed: () {}),
                  ),
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
          if (res != null) {
            final items = res.files.map((f) => LibraryItem(id: const Uuid().v4(), name: f.name, size: f.size, time: DateTime.now())).toList();
            ref.read(libraryProvider.notifier).state = [...lib, ...items];
            await LocalStorage.save("library", "items", jsonEncode([...lib, ...items].map((e) => {"id":e.id,"name":e.name,"size":e.size,"time":e.time.toIso8601String()}).toList()));
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
// Projects مثل Claude مع Knowledge
class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Projects - مثل Claude")),
      body: projects.isEmpty
          ? const Center(child: Text("لا يوجد Projects\nاضغط + لإنشاء مشروع"))
          : ListView.builder(
              itemCount: projects.length,
              itemBuilder: (c, i) => Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: const Icon(Icons.folder_special),
                  title: Text(projects[i].name),
                  subtitle: Text(projects[i].instructions.isEmpty ? "بدون تعليمات" : projects[i].instructions),
                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ChatScreen(project: projects[i]))),
                  trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () async {
                    final l = [...projects]..removeAt(i);
                    ref.read(projectsProvider.notifier).state = l;
                    await LocalStorage.save("projects", "list", jsonEncode(l.map((e) => e.toJson()).toList()));
                  }),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addProject(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
  void _addProject(BuildContext ctx, WidgetRef ref) {
    final n = TextEditingController();
    final ins = TextEditingController();
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text("مشروع جديد"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(labelText: "اسم المشروع")),
        TextField(controller: ins, decoration: const InputDecoration(labelText: "تعليمات المشروع - Knowledge")),
      ]),
      actions: [TextButton(onPressed: () async {
        if (n.text.isNotEmpty) {
          final p = Project(id: const Uuid().v4(), name: n.text, instructions: ins.text);
          final l = [...ref.read(projectsProvider), p];
          ref.read(projectsProvider.notifier).state = l;
          await LocalStorage.save("projects", "list", jsonEncode(l.map((e) => e.toJson()).toList()));
          Navigator.pop(ctx);
        }
      }, child: const Text("إنشاء"))],
    ));
  }
}
// AgentsScreen - تحكم كامل بالتطبيقات والملفات اللي يوصلها النموذج
class AgentsScreen extends ConsumerWidget {
  const AgentsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentsProvider);
    final selected = ref.watch(selectedAgentProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("Agents")),
      body: agents.isEmpty
          ? const Center(child: Text("لا يوجد Agents\nاضغط + لإنشاء Agent"))
          : ListView.builder(
              itemCount: agents.length,
              itemBuilder: (c, i) {
                final a = agents[i];
                final isSel = selected?.id == a.id;
                return Card(
                  margin: const EdgeInsets.all(8),
                  color: isSel ? Colors.indigo.shade50 : null,
                  child: ListTile(
                    leading: Icon(Icons.smart_toy, color: isSel ? Colors.indigo : null),
                    title: Text(a.name),
                    subtitle: Text("${a.systemPrompt}\nصلاحيات: ${a.canRead ? 'قراءة ' : ''}${a.canWrite ? 'كتابة ' : ''}${a.canExecute ? 'تنفيذ' : ''}\nمسارات: ${a.allowedPaths.isEmpty ? 'الكل' : a.allowedPaths.join(', ')}", maxLines: 3),
                    isThreeLine: true,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: Icon(isSel ? Icons.check_circle : Icons.circle_outlined, color: Colors.indigo), onPressed: () => ref.read(selectedAgentProvider.notifier).state = a),
                      IconButton(icon: const Icon(Icons.delete), onPressed: () async {
                        final l = [...agents]..removeAt(i);
                        ref.read(agentsProvider.notifier).state = l;
                        if (isSel) ref.read(selectedAgentProvider.notifier).state = null;
                        await LocalStorage.save("agents", "list", jsonEncode(l.map((e) => e.toJson()).toList()));
                      }),
                    ]),
                    onTap: () => ref.read(selectedAgentProvider.notifier).state = a,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addAgent(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }
  void _addAgent(BuildContext ctx, WidgetRef ref) {
    final n = TextEditingController();
    final p = TextEditingController();
    final paths = TextEditingController();
    bool canRead = true;
    bool canWrite = false;
    bool canExecute = false;
    showDialog(context: ctx, builder: (_) => StatefulBuilder(builder: (c, setSt) => AlertDialog(
      title: const Text("Agent جديد"),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: n, decoration: const InputDecoration(labelText: "اسم الـ Agent")),
        const SizedBox(height: 8),
        TextField(controller: p, decoration: const InputDecoration(labelText: "System Prompt"), maxLines: 3),
        const SizedBox(height: 8),
        TextField(controller: paths, decoration: const InputDecoration(labelText: "المسارات المسموحة (مفصولة ب ,)", hintText: "مثال: /DCIM, /Documents")),
        SwitchListTile(title: const Text("قراءة"), value: canRead, onChanged: (v) => setSt(() => canRead = v)),
        SwitchListTile(title: const Text("كتابة / إنشاء"), value: canWrite, onChanged: (v) => setSt(() => canWrite = v)),
        SwitchListTile(title: const Text("تنفيذ مهام"), value: canExecute, onChanged: (v) => setSt(() => canExecute = v)),
      ])),
      actions: [TextButton(onPressed: () async {
        if (n.text.isNotEmpty) {
          final list = paths.text.isEmpty ? <String>[] : paths.text.split(',').map((e) => e.trim()).toList();
          final a = Agent(id: const Uuid().v4(), name: n.text, systemPrompt: p.text, allowedPaths: list, canRead: canRead, canWrite: canWrite, canExecute: canExecute);
          final l = [...ref.read(agentsProvider), a];
          ref.read(agentsProvider.notifier).state = l;
          await LocalStorage.save("agents", "list", jsonEncode(l.map((e) => e.toJson()).toList()));
          Navigator.pop(ctx);
        }
      }, child: const Text("إنشاء"))],
    )));
  }
}
// SettingsScreen - Universal API + الوضع الليلي + Drive
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final apiKey = ref.watch(apiKeyProvider);
    final models = ref.watch(modelsProvider);
    final selected = ref.watch(selectedModelProvider);
    final mode = ref.watch(themeModeProvider);
    final baseCtrl = TextEditingController(text: baseUrl);
    final keyCtrl = TextEditingController(text: apiKey);
    return Scaffold(
      appBar: AppBar(title: const Text("الإعدادات")),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text("المظهر", style: TextStyle(fontWeight: FontWeight.bold)),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.light, label: Text("فاتح"), icon: Icon(Icons.light_mode)),
            ButtonSegment(value: ThemeMode.dark, label: Text("داكن"), icon: Icon(Icons.dark_mode)),
            ButtonSegment(value: ThemeMode.system, label: Text("تلقائي"), icon: Icon(Icons.auto_mode)),
          ],
          selected: {mode},
          onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).state = s.first,
        ),
        const Divider(height: 32),
        const Text("Universal API", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(controller: baseCtrl, decoration: const InputDecoration(labelText: "Base URL", hintText: "https://cleanapis.com", border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(controller: keyCtrl, decoration: const InputDecoration(labelText: "API Key", border: OutlineInputBorder()), obscureText: true),
        const SizedBox(height: 12),
                FilledButton(
          onPressed: () async {
            ref.read(apiBaseUrlProvider.notifier).state = baseCtrl.text;
            ref.read(apiKeyProvider.notifier).state = keyCtrl.text;
            try {
              final list = await ref.read(universalApiProvider).fetchModels(baseCtrl.text, keyCtrl.text);
              ref.read(modelsProvider.notifier).state = list;
              if (list.isNotEmpty) ref.read(selectedModelProvider.notifier).state = list.first;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("تم جلب ${list.length} موديل")));
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
            }
          },
          child: const Text("Fetch Models - جلب الموديلات"),
        ),
        const SizedBox(height: 16),
        if (models.isNotEmpty)
          DropdownButton<String>(
            value: selected.isEmpty ? null : selected,
            hint: const Text("اختر الموديل"),
            isExpanded: true,
            items: models.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) => ref.read(selectedModelProvider.notifier).state = v!,
          ),
        const Divider(height: 32),
        const Text("Drive والصلاحيات", style: TextStyle(fontWeight: FontWeight.bold)),
        ListTile(
          leading: const Icon(Icons.cloud),
          title: const Text("ربط Google Drive"),
          trailing: FilledButton(onPressed: () {}, child: const Text("ربط")),
        ),
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: const Text("صلاحيات الملفات"),
          trailing: IconButton(icon: const Icon(Icons.settings), onPressed: () async { await openAppSettings(); }),
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.backup),
          title: const Text("تصدير نسخة احتياطية"),
          onTap: () async {
            final dir = await LocalStorage.getDir();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("المجلد: ${dir.path}")));
          },
        ),
      ]),
    );
  }
}
// ChatScreen - بدون حدود + الذاكرة المقسمة + حالة التفكير Live + حفظ محلي
class ChatScreen extends ConsumerStatefulWidget {
  final Project? project;
  const ChatScreen({super.key, this.project});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController ctrl = TextEditingController();
  final ScrollController scroll = ScrollController();
  final SpeechToText stt = SpeechToText();
  final FlutterTts tts = FlutterTts();
  bool isLoading = false;
  bool isListening = false;
  String streamingText = "";
  List<PlatformFile> attached = [];
  Set<String> selectedIds = {};
  bool selectionMode = false;

  Future<void> pickFiles() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true);
    if (res != null) setState(() => attached = res.files);
  }
    Future<void> send() async {
    if (ctrl.text.trim().isEmpty && attached.isEmpty) return;
    String fileText = "";
    for (var f in attached) {
      fileText += "\n[File: ${f.name} - ${f.size} bytes]\n";
      if (f.bytes != null) {
        try {
          String content = utf8.decode(f.bytes!, allowMalformed: true);
          if (content.length > 8000) content = content.substring(0, 8000) + "\n...[truncated]";
          fileText += content;
        } catch (_) {
          fileText += "(binary file)";
        }
      }
    }
    final prompt = ctrl.text + fileText;
    final userMsg = ChatMessage(id: const Uuid().v4(), role: "user", content: ctrl.text, fileNames: attached.map((e) => e.name).toList(), time: DateTime.now());
    setState(() { isLoading = true; streamingText = ""; });
    ref.read(thinkingProvider.notifier).state = "Thinking...";
    final updated = [...ref.read(messagesProvider), userMsg];
    ref.read(messagesProvider.notifier).state = updated;
    await LocalStorage.save("chats", "current", jsonEncode(updated.map((e) => e.toJson()).toList()));
    if (attached.isNotEmpty) {
      final items = attached.map((f) => LibraryItem(id: const Uuid().v4(), name: f.name, size: f.size, time: DateTime.now())).toList();
      final lib = [...ref.read(libraryProvider), ...items];
      ref.read(libraryProvider.notifier).state = lib;
      await LocalStorage.save("library", "items", jsonEncode(lib.map((e) => {"id":e.id,"name":e.name,"size":e.size,"time":e.time.toIso8601String()}).toList()));
    }
    ctrl.clear();
    setState(() => attached = []);
    try {
      final baseUrl = ref.read(apiBaseUrlProvider);
      final apiKey = ref.read(apiKeyProvider);
      final model = ref.read(selectedModelProvider);
      final mem = ref.read(memoryPartsProvider);
      final agent = ref.read(selectedAgentProvider);
      final lib = ref.read(libraryProvider);
      String sysPrompt = "[LMClient System - Claude Clone]\nNo client Input/Output limits, only model limit. Context is full history without truncation, max_tokens not sent.\nMemory parts: ${mem.isEmpty ? "none" : mem.map((m) => "${m.title}: ${m.content}").join(" | ")}\nProject: ${widget.project?.instructions ?? "none"}\nLibrary: ${lib.isEmpty ? "empty" : lib.map((e) => e.name).join(", ")} - you can request via [SEARCH_LIBRARY: query]\nAgent: ${agent?.name ?? "none"} allowed:${agent?.allowedPaths.join(",")} canRead:${agent?.canRead} canWrite:${agent?.canWrite} canExecute:${agent?.canExecute}\nYou can save memory via [SAVE_MEMORY: title|content] and create/edit files if allowed.\n";
      String fullPrompt = sysPrompt + "\nUser: " + prompt;
      final ctx = [...ref.read(messagesProvider).where((m) => !m.excluded).map((m) => "[${m.role.toUpperCase()}] ${m.content}"), "[USER] $fullPrompt"].join("\n\n");
      ref.read(lastContextProvider.notifier).state = ctx;
      ref.read(lastTokensProvider.notifier).state = {"input": estimateTokens(ctx), "output": 0};
      ref.read(thinkingProvider.notifier).state = "Working...";
      String full = "";
            await for (final chunk in ref.read(universalApiProvider).chatStream(
        baseUrl: baseUrl, apiKey: apiKey, model: model,
        history: ref.read(messagesProvider).length > 1 ? ref.read(messagesProvider).sublist(0, ref.read(messagesProvider).length - 1) : [],
        prompt: fullPrompt)) {
        full += chunk;
        setState(() => streamingText = full);
        ref.read(lastTokensProvider.notifier).state = {"input": estimateTokens(ctx), "output": estimateTokens(full)};
        ref.read(thinkingProvider.notifier).state = "Writing...";
      }
      final botMsg = ChatMessage(id: const Uuid().v4(), role: "assistant", content: full, time: DateTime.now());
      final finalList = [...ref.read(messagesProvider), botMsg];
      ref.read(messagesProvider.notifier).state = finalList;
      await LocalStorage.save("chats", "current", jsonEncode(finalList.map((e) => e.toJson()).toList()));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e")));
    } finally {
      setState(() { isLoading = false; streamingText = ""; });
      ref.read(thinkingProvider.notifier).state = "";
    }
  }
    @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(messagesProvider);
    final thinking = ref.watch(thinkingProvider);
    final tokens = ref.watch(lastTokensProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project?.name ?? "LMClient"),
        actions: [
          IconButton(icon: const Icon(Icons.visibility), tooltip: "عرض السياق", onPressed: () => showContextViewer(context, ref)),
          IconButton(icon: Icon(selectionMode ? Icons.close : Icons.checklist), onPressed: () => setState(() { selectionMode = !selectionMode; selectedIds.clear(); })),
          if (selectionMode && selectedIds.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete), onPressed: () => deleteSelected()),
        ],
      ),
      body: Column(children: [
        if (thinking.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: Row(children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text(thinking, style: const TextStyle(fontSize: 13)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Text("~${tokens["input"]} in / ~${tokens["output"]} out", style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const Spacer(),
            Text("${msgs.where((m) => !m.excluded).length}/${msgs.length} في السياق", style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
                Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(12),
            itemCount: msgs.length + (streamingText.isNotEmpty ? 1 : 0),
            itemBuilder: (c, i) {
              if (i < msgs.length) return MessageBubble(msg: msgs[i], tts: tts, selectionMode: selectionMode, selected: selectedIds.contains(msgs[i].id), onSelect: () => toggleSelect(msgs[i].id));
              return MessageBubble(
                msg: ChatMessage(id: "stream", role: "assistant", content: streamingText, time: DateTime.now()),
                tts: tts, selectionMode: false, selected: false, onSelect: () {},
              );
            },
          ),
        ),
        if (attached.isNotEmpty)
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: attached.map((f) => Chip(label: Text(f.name), onDeleted: () => setState(() => attached.remove(f)))).toList(),
            ),
          ),
                Container(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.attach_file), onPressed: pickFiles),
            Expanded(
              child: TextField(
                controller: ctrl,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                cursorColor: Colors.blue,
                cursorWidth: 2,
                showCursor: true,
                enableInteractiveSelection: true,
                decoration: InputDecoration(
                  hintText: "اكتب رسالة...",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
                        const SizedBox(width: 4),
            IconButton(
              icon: Icon(isListening ? Icons.mic_off : Icons.mic),
              onPressed: toggleListen,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_left),
              onPressed: () => moveCursor(-1),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_right),
              onPressed: () => moveCursor(1),
            ),
            FilledButton(
              onPressed: isLoading ? null : send,
              child: isLoading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
            ),
          ]),
        ),
      ]),
    );
  }
    void moveCursor(int d) {
    final p = ctrl.selection.baseOffset;
    if (p < 0) return;
    final n = (p + d).clamp(0, ctrl.text.length);
    ctrl.selection = TextSelection.collapsed(offset: n);
  }

  Future<void> toggleListen() async {
    if (isListening) {
      await stt.stop();
      setState(() => isListening = false);
    } else {
      bool ok = await stt.initialize();
      if (ok) {
        setState(() => isListening = true);
        stt.listen(onResult: (r) => setState(() => ctrl.text = r.recognizedWords));
      }
    }
  }

  void toggleSelect(String id) {
    setState(() {
      if (selectedIds.contains(id)) selectedIds.remove(id);
      else selectedIds.add(id);
    });
  }

  Future<void> deleteSelected() async {
    final ids = Set<String>.from(selectedIds);
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("حذف المحدد"),
      content: Text("تم تحديد ${ids.length} رسالة"),
      actions: [
        TextButton(onPressed: () async {
          final list = ref.read(messagesProvider).where((m) => !ids.contains(m.id)).toList();
          ref.read(messagesProvider.notifier).state = list;
          await LocalStorage.save("chats", "current", jsonEncode(list.map((e) => e.toJson()).toList()));
          setState(() { selectedIds.clear(); selectionMode = false; });
          Navigator.pop(context);
        }, child: const Text("حذف نهائي")),
        TextButton(onPressed: () async {
          final list = ref.read(messagesProvider).map((m) => ids.contains(m.id) ? m.copyWith(excluded: true) : m).toList();
          ref.read(messagesProvider.notifier).state = list;
          await LocalStorage.save("chats", "current", jsonEncode(list.map((e) => e.toJson()).toList()));
          setState(() { selectedIds.clear(); selectionMode = false; });
          Navigator.pop(context);
        }, child: const Text("استبعاد من السياق")),
      ],
    ));
  }
    void showContextViewer(BuildContext ctx, WidgetRef ref) {
    final ctxText = ref.read(lastContextProvider);
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text("ما يراه النموذج بالحرف"),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: SingleChildScrollView(child: SelectableText(ctxText.isEmpty ? "لا يوجد سياق بعد" : ctxText)),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إغلاق"))],
    ));
  }

  @override
  void dispose() {
    ctrl.dispose();
    scroll.dispose();
    super.dispose();
  }
}
// MessageBubble - Markdown + عداد التوكنز + تحديد نص محسن + Artifacts
class MessageBubble extends ConsumerWidget {
  final ChatMessage msg;
  final FlutterTts tts;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onSelect;
  const MessageBubble({super.key, required this.msg, required this.tts, required this.selectionMode, required this.selected, required this.onSelect});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = msg.role == "user";
    final tokens = estimateTokens(msg.content);
    return GestureDetector(
      onLongPress: onSelect,
      child: Container(
        decoration: BoxDecoration(
          border: selected ? Border.all(color: Colors.indigo, width: 2) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Opacity(
            opacity: msg.excluded ? 0.4 : 1.0,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? Colors.indigo : Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (msg.fileNames.isNotEmpty)
                  Wrap(spacing: 4, children: msg.fileNames.map((n) => Chip(label: Text(n, style: const TextStyle(fontSize: 11)))).toList()),
                isUser
                    ? SelectableText(msg.content, style: const TextStyle(color: Colors.white))
                    : MarkdownBody(data: msg.content, selectable: true),
                const SizedBox(height: 6),
                                Row(children: [
                  Text("~$tokens tok", style: TextStyle(fontSize: 10, color: isUser ? Colors.white70 : Colors.black54)),
                  const SizedBox(width: 6),
                  Text("${msg.time.hour}:${msg.time.minute.toString().padLeft(2,'0')}", style: TextStyle(fontSize: 10, color: isUser ? Colors.white70 : Colors.black54)),
                  const Spacer(),
                  if (!isUser) IconButton(icon: const Icon(Icons.volume_up, size: 18), onPressed: () => tts.speak(msg.content)),
                  IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () {}),
                  if (!isUser) IconButton(icon: const Icon(Icons.bookmark_add, size: 18), onPressed: () async {
                    final part = MemoryPart(id: const Uuid().v4(), title: "من الشات ${DateTime.now().day}/${DateTime.now().month}", content: msg.content);
                    final l = [...ref.read(memoryPartsProvider), part];
                    ref.read(memoryPartsProvider.notifier).state = l;
                    await LocalStorage.save("memory", "parts", jsonEncode(l.map((e) => e.toJson()).toList()));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم الحفظ في الذاكرة المقسمة")));
                  }),
                                                  ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
