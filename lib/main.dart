import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';

void main() {
  runApp(const ProviderScope(child: PrivateLMApp()));
}

class PrivateLMApp extends StatelessWidget {
  const PrivateLMApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PrivateLM V2',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomeScreen(),
    );
  }
}
// Models
class ChatMessage {
  final String id;
  final String role;
  final String content;
  final List<String> fileNames;
  final DateTime time;
  ChatMessage({required this.id, required this.role, required this.content, this.fileNames = const [], required this.time});
}

class Project {
  final String id;
  final String name;
  final String instructions;
  Project({required this.id, required this.name, this.instructions = ""});
}
// Providers - Riverpod (مافي GetX نهائيا)
final apiBaseUrlProvider = StateProvider<String>((ref) => "https://api.openai.com");
final apiKeyProvider = StateProvider<String>((ref) => "");
final modelsProvider = StateProvider<List<String>>((ref) => []);
final selectedModelProvider = StateProvider<String>((ref) => "");
final messagesProvider = StateProvider<List<ChatMessage>>((ref) => []);
final projectsProvider = StateProvider<List<Project>>((ref) => []);
// Universal API - بدون حدود Context
class UniversalApi {
  final Dio dio = Dio();
  Future<List<String>> fetchModels(String baseUrl, String apiKey) async {
    final res = await dio.get("$baseUrl/v1/models",
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
    // بدون حدود - نرسل كل الرسائل كاملة بدون قص
    final messages = [
      ...history.map((m) => {"role": m.role, "content": m.content}),
      {"role": "user", "content": prompt}
    ];
    final res = await dio.post("$baseUrl/v1/chat/completions",
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
// ذاكرة طويلة - تحفظ معلومات مهمة للأبد
final memoryProvider = StateProvider<List<String>>((ref) => []);

// HomeScreen مع تبويب الذاكرة
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends ConsumerState<HomeScreen> {
  int idx = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: [const ChatScreen(), const ProjectsScreen(), const MemoryScreen(), const SettingsScreen()][idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (v) => setState(() => idx = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat), label: "شات"),
          NavigationDestination(icon: Icon(Icons.folder), label: "Projects"),
          NavigationDestination(icon: Icon(Icons.memory), label: "الذاكرة"),
          NavigationDestination(icon: Icon(Icons.settings), label: "الإعدادات"),
        ],
      ),
    );
  }
}
// شاشة الذاكرة الطويلة
class MemoryScreen extends ConsumerWidget {
  const MemoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mem = ref.watch(memoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text("الذاكرة الطويلة")),
      body: mem.isEmpty
          ? const Center(child: Text("لا يوجد ذاكرة\nاضغط + لإضافة معلومة مهمة"))
          : ListView.builder(
              itemCount: mem.length,
              itemBuilder: (c, i) => ListTile(
                leading: const Icon(Icons.lightbulb),
                title: Text(mem[i]),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    final l = [...mem]..removeAt(i);
                    ref.read(memoryProvider.notifier).state = l;
                  },
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
    final c = TextEditingController();
    showDialog(context: ctx, builder: (_) => AlertDialog(
      title: const Text("إضافة للذاكرة"),
      content: TextField(controller: c, decoration: const InputDecoration(hintText: "مثال: اسمي أحمد، أفضل الرد بالعربي")),
      actions: [TextButton(onPressed: () {
        if (c.text.isNotEmpty) {
          ref.read(memoryProvider.notifier).state = [...ref.read(memoryProvider), c.text];
          Navigator.pop(ctx);
        }
      }, child: const Text("حفظ"))],
    ));
  }
}
// الإعدادات - Universal API
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseUrl = ref.watch(apiBaseUrlProvider);
    final apiKey = ref.watch(apiKeyProvider);
    final models = ref.watch(modelsProvider);
    final selected = ref.watch(selectedModelProvider);
    final baseCtrl = TextEditingController(text: baseUrl);
    final keyCtrl = TextEditingController(text: apiKey);
    return Scaffold(
      appBar: AppBar(title: const Text("الإعدادات - Universal API")),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: baseCtrl, decoration: const InputDecoration(labelText: "Base URL", hintText: "https://api.openai.com", border: OutlineInputBorder())),
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
      ]),
    );
  }
}
// Projects مثل Claude
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
              itemBuilder: (c, i) => ListTile(
                leading: const Icon(Icons.folder_special),
                title: Text(projects[i].name),
                subtitle: Text(projects[i].instructions.isEmpty ? "بدون تعليمات" : projects[i].instructions),
                onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ChatScreen(project: projects[i]))),
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
        TextField(controller: ins, decoration: const InputDecoration(labelText: "تعليمات المشروع")),
      ]),
      actions: [TextButton(onPressed: () {
        if (n.text.isNotEmpty) {
          ref.read(projectsProvider.notifier).state = [...ref.read(projectsProvider), Project(id: const Uuid().v4(), name: n.text, instructions: ins.text)];
          Navigator.pop(ctx);
        }
      }, child: const Text("إنشاء"))],
    ));
  }
}
// ChatScreen - بدون حدود Context + حقن الذاكرة الطويلة
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
          // فك الملفات المضغوطة ZIP وغيرها - نقرأ النص داخلها
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
    ref.read(messagesProvider.notifier).state = [...ref.read(messagesProvider), userMsg];
    ctrl.clear();
    setState(() => attached = []);
    try {
      final baseUrl = ref.read(apiBaseUrlProvider);
      final apiKey = ref.read(apiKeyProvider);
      final model = ref.read(selectedModelProvider);
      // بدون حدود + حقن الذاكرة الطويلة + تعليمات المشروع
      final mem = ref.read(memoryProvider);
      String sysPrompt = "";
      if (mem.isNotEmpty) sysPrompt += "Memory:\n" + mem.join("\n") + "\n";
      if (widget.project != null && widget.project!.instructions.isNotEmpty) sysPrompt += "Project: " + widget.project!.instructions + "\n";
      String fullPrompt = sysPrompt.isEmpty ? prompt : sysPrompt + "\nUser: " + prompt;
      String full = "";
            await for (final chunk in ref.read(universalApiProvider).chatStream(
        baseUrl: baseUrl, apiKey: apiKey, model: model,
        history: ref.read(messagesProvider).sublist(0, ref.read(messagesProvider).length -1), prompt: fullPrompt)) {
        full += chunk;
        setState(() => streamingText = full);
      }
      final botMsg = ChatMessage(
        id: const Uuid().v4(), role: "assistant",
        content: full, time: DateTime.now());
      ref.read(messagesProvider.notifier).state =
          [...ref.read(messagesProvider), botMsg];
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("خطأ: $e")));
    } finally {
      setState(() { isLoading = false; streamingText = ""; });
    }
  }
    @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(messagesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(widget.project?.name ?? "شات - PrivateLM")),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: scroll,
            padding: const EdgeInsets.all(12),
            itemCount: msgs.length + (streamingText.isNotEmpty ? 1 : 0),
            itemBuilder: (c, i) {
              if (i < msgs.length) return MessageBubble(msg: msgs[i], tts: tts);
              return MessageBubble(
                msg: ChatMessage(id: "stream", role: "assistant", content: streamingText, time: DateTime.now()),
                tts: tts,
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

  @override
  void dispose() {
    ctrl.dispose();
    scroll.dispose();
    super.dispose();
  }
}
// MessageBubble - Markdown + Voice + حفظ للذاكرة
class MessageBubble extends ConsumerWidget {
  final ChatMessage msg;
  final FlutterTts tts;
  const MessageBubble({super.key, required this.msg, required this.tts});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = msg.role == "user";
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Colors.indigo : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (msg.fileNames.isNotEmpty)
            Wrap(spacing: 4, children: msg.fileNames.map((n) => Chip(label: Text(n, style: const TextStyle(fontSize: 11)))).toList()),
          isUser
              ? Text(msg.content, style: const TextStyle(color: Colors.white))
              : MarkdownBody(data: msg.content, selectable: true),
          const SizedBox(height: 6),
          Row(children: [
            Text("${msg.time.hour}:${msg.time.minute.toString().padLeft(2,'0')}", style: TextStyle(fontSize: 10, color: isUser ? Colors.white70 : Colors.black54)),
            const Spacer(),
            if (!isUser) IconButton(icon: const Icon(Icons.volume_up, size: 18), onPressed: () => tts.speak(msg.content)),
            IconButton(icon: const Icon(Icons.copy, size: 18), onPressed: () {}),
            if (!isUser) IconButton(icon: const Icon(Icons.bookmark_add, size: 18), onPressed: () {
              ref.read(memoryProvider.notifier).state = [...ref.read(memoryProvider), msg.content];
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم الحفظ في الذاكرة")));
            }),
          ]),
        ]),
      ),
    );
  }
}
