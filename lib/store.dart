// ignore_for_file: curly_braces_in_flow_control_structures, unused_element, unused_local_variable, avoid_print, deprecated_member_use, use_build_context_synchronously, prefer_const_constructors, prefer_const_literals_to_create_immutables, depend_on_referenced_packages, prefer_interpolation_to_compose_strings, unnecessary_brace_in_string_interps, unnecessary_import
part of 'main.dart';

// ---------------------------------------------------------------------
//  Local storage (offline-first, atomic writes, same layout as v1)
// ---------------------------------------------------------------------
class LocalStorage {
  static Directory? _root;
  static final Map<String, Future<void>> _q = <String, Future<void>>{};

  static Future<Directory> getDir() async {
    final cached = _root;
    if (cached != null) return cached;
    final d = await getApplicationDocumentsDirectory();
    final lm = Directory('${d.path}/LMClient');
    if (!await lm.exists()) await lm.create(recursive: true);
    _root = lm;
    return lm;
  }

  static Future<Directory> folder(String name) async {
    final dir = await getDir();
    final f = Directory('${dir.path}/$name');
    if (!await f.exists()) await f.create(recursive: true);
    return f;
  }

  static Future<void> _write(String folderName, String name, String data) async {
    final f = await folder(folderName);
    final target = File('${f.path}/$name.json');
    final tmp = File('${f.path}/$name.json.tmp');
    await tmp.writeAsString(data, flush: true);
    await tmp.rename(target.path);
  }

  /// كتابة JSON بشكل ذري ومتسلسل لكل ملف (لا تتداخل الكتابات ولا يتلف الملف عند الانقطاع).
  static Future<void> save(String folderName, String name, String data) {
    final key = '$folderName/$name';
    final prev = _q[key] ?? Future<void>.value();
    final Future<void> next = prev.then((_) => _write(folderName, name, data)).catchError((Object e) {
      debugPrint('save failed $key: $e');
    });
    _q[key] = next;
    return next;
  }

  static Future<String?> load(String folderName, String name) async {
    try {
      final dir = await getDir();
      final file = File('${dir.path}/$folderName/$name.json');
      if (await file.exists()) return await file.readAsString();
    } catch (_) {}
    return null;
  }

  /// الحذف يمرّ عبر نفس طابور الكتابة حتى لا تتجاوز كتابةٌ معلّقة الحذفَ فتُعيد الملف.
  static Future<void> remove(String folderName, String name) {
    final key = '$folderName/$name';
    final prev = _q[key] ?? Future<void>.value();
    final Future<void> next = prev.then((_) async {
      try {
        final dir = await getDir();
        final file = File('${dir.path}/$folderName/$name.json');
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }).catchError((Object e) {
      debugPrint('remove failed $key: $e');
    });
    _q[key] = next;
    return next;
  }

  /// يحفظ ملفاً ثنائياً ويعيد مساره النسبي (نسبة إلى مجلد LMClient).
  static Future<String> saveBytes(String folderName, String fileName, Uint8List bytes) async {
    final f = await folder(folderName);
    final file = File('${f.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return '$folderName/$fileName';
  }

  static Future<File> absFile(String rel) async {
    final dir = await getDir();
    return File('${dir.path}/$rel');
  }

  static Future<Uint8List?> readRel(String? rel) async {
    if (rel == null || rel.isEmpty) return null;
    try {
      final f = await absFile(rel);
      if (await f.exists()) return await f.readAsBytes();
    } catch (_) {}
    return null;
  }

  static Future<void> removeRel(String? rel) async {
    if (rel == null || rel.isEmpty) return;
    try {
      final f = await absFile(rel);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------
//  Access to the real phone storage (used by Agents & the files screen)
// ---------------------------------------------------------------------
class PhoneStorage {
  static const String root = '/storage/emulated/0';

  static Future<bool> requestPermissions() async {
    try {
      final s1 = await Permission.storage.request();
      final s2 = await Permission.manageExternalStorage.request();
      return s1.isGranted || s2.isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<List<FileSystemEntity>> listFiles(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return <FileSystemEntity>[];
    final out = <FileSystemEntity>[];
    try {
      await for (final e in dir.list(followLinks: false)) {
        out.add(e);
      }
    } catch (_) {}
    out.sort((a, b) {
      final ad = a is Directory ? 0 : 1;
      final bd = b is Directory ? 0 : 1;
      if (ad != bd) return ad - bd;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
    return out;
  }
}

// ---------------------------------------------------------------------
//  Riverpod notifiers (Notifier API: works with riverpod 2.x and 3.x)
// ---------------------------------------------------------------------
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => const AppSettings(<String, dynamic>{});

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('settings_v2');
    if (raw != null) {
      try {
        state = AppSettings(asMap(jsonDecode(raw)));
      } catch (_) {}
    }
  }

  void set(String k, dynamic v) {
    state = state.set(k, v);
    _save();
  }

  void replaceAll(Map<String, dynamic> m) {
    state = AppSettings(Map<String, dynamic>.from(m));
    _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('settings_v2', jsonEncode(state.m));
    } catch (_) {}
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

abstract class JsonListNotifier<T> extends Notifier<List<T>> {
  String get folderName;
  String get fileName;
  T decode(Map<String, dynamic> j);
  Map<String, dynamic> encode(T t);
  String idOf(T t);

  @override
  List<T> build() => <T>[];

  Future<void> load() async {
    final raw = await LocalStorage.load(folderName, fileName);
    if (raw == null) return;
    try {
      final out = <T>[];
      for (final e in asList(jsonDecode(raw))) {
        out.add(decode(asMap(e)));
      }
      state = out;
    } catch (_) {}
  }

  Future<void> _persist() => LocalStorage.save(folderName, fileName, jsonEncode(state.map((e) => encode(e)).toList()));

  Future<void> setAll(List<T> l) async {
    state = l;
    await _persist();
  }

  Future<void> upsert(T t) async {
    final id = idOf(t);
    final l = <T>[...state];
    final i = l.indexWhere((e) => idOf(e) == id);
    if (i >= 0) {
      l[i] = t;
    } else {
      l.add(t);
    }
    state = l;
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((e) => idOf(e) != id).toList();
    await _persist();
  }

  T? byId(String? id) {
    if (id == null) return null;
    for (final e in state) {
      if (idOf(e) == id) return e;
    }
    return null;
  }
}

class ProjectsNotifier extends JsonListNotifier<Project> {
  @override
  String get folderName => 'projects';
  @override
  String get fileName => 'list';
  @override
  Project decode(Map<String, dynamic> j) => Project.fromJson(j);
  @override
  Map<String, dynamic> encode(Project t) => t.toJson();
  @override
  String idOf(Project t) => t.id;
}

class MemoryNotifier extends JsonListNotifier<MemoryPart> {
  @override
  String get folderName => 'memory';
  @override
  String get fileName => 'parts';
  @override
  MemoryPart decode(Map<String, dynamic> j) => MemoryPart.fromJson(j);
  @override
  Map<String, dynamic> encode(MemoryPart t) => t.toJson();
  @override
  String idOf(MemoryPart t) => t.id;
}

class AgentsNotifier extends JsonListNotifier<Agent> {
  @override
  String get folderName => 'agents';
  @override
  String get fileName => 'list';
  @override
  Agent decode(Map<String, dynamic> j) => Agent.fromJson(j);
  @override
  Map<String, dynamic> encode(Agent t) => t.toJson();
  @override
  String idOf(Agent t) => t.id;
}

class ConvListNotifier extends JsonListNotifier<ConvMeta> {
  @override
  String get folderName => 'chats';
  @override
  String get fileName => '_index';
  @override
  ConvMeta decode(Map<String, dynamic> j) => ConvMeta.fromJson(j);
  @override
  Map<String, dynamic> encode(ConvMeta t) => t.toJson();
  @override
  String idOf(ConvMeta t) => t.id;
}

class LibraryNotifier extends JsonListNotifier<LibraryItem> {
  @override
  String get folderName => 'library';
  @override
  String get fileName => 'items';
  @override
  LibraryItem decode(Map<String, dynamic> j) => LibraryItem.fromJson(j);
  @override
  Map<String, dynamic> encode(LibraryItem t) => t.toJson();
  @override
  String idOf(LibraryItem t) => t.id;

  Future<LibraryItem> addBytes(String name, Uint8List bytes, {String? mime}) async {
    final id = newId();
    final rel = await LocalStorage.saveBytes('library_files', '${id}_${safeFileName(name)}', bytes);
    final item = LibraryItem(id: id, name: name, size: bytes.length, mime: mime ?? mimeFromName(name), time: DateTime.now(), path: rel);
    await upsert(item);
    return item;
  }

  Future<void> removeItem(String id) async {
    final it = byId(id);
    if (it != null) await LocalStorage.removeRel(it.path);
    await remove(id);
  }
}

final projectsProvider = NotifierProvider<ProjectsNotifier, List<Project>>(ProjectsNotifier.new);
final memoryProvider = NotifierProvider<MemoryNotifier, List<MemoryPart>>(MemoryNotifier.new);
final agentsProvider = NotifierProvider<AgentsNotifier, List<Agent>>(AgentsNotifier.new);
final convListProvider = NotifierProvider<ConvListNotifier, List<ConvMeta>>(ConvListNotifier.new);
final libraryProvider = NotifierProvider<LibraryNotifier, List<LibraryItem>>(LibraryNotifier.new);

class ProfilesState {
  final List<ApiProfile> list;
  final String? selectedId;
  const ProfilesState(this.list, this.selectedId);
  ApiProfile? get selected {
    for (final p in list) {
      if (p.id == selectedId) return p;
    }
    return null;
  }
}

class ProfilesNotifier extends Notifier<ProfilesState> {
  @override
  ProfilesState build() => const ProfilesState(<ApiProfile>[], null);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('profiles');
    final selId = p.getString('selected_profile');
    if (raw == null) return;
    try {
      final l = <ApiProfile>[];
      for (final e in asList(jsonDecode(raw))) {
        l.add(ApiProfile.fromJson(asMap(e)));
      }
      String? sel = selId;
      if (sel == null || !l.any((e) => e.id == sel)) sel = l.isEmpty ? null : l.first.id;
      state = ProfilesState(l, sel);
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('profiles', jsonEncode(state.list.map((e) => e.toJson()).toList()));
      final s = state.selectedId;
      if (s != null) {
        await p.setString('selected_profile', s);
      } else {
        await p.remove('selected_profile');
      }
    } catch (_) {}
  }

  Future<void> upsert(ApiProfile pr, {bool select = false}) async {
    final l = <ApiProfile>[...state.list];
    final i = l.indexWhere((e) => e.id == pr.id);
    if (i >= 0) {
      l[i] = pr;
    } else {
      l.add(pr);
    }
    String? sel = state.selectedId;
    if (select || sel == null) sel = pr.id;
    state = ProfilesState(l, sel);
    await _save();
  }

  Future<void> remove(String id) async {
    final l = state.list.where((e) => e.id != id).toList();
    String? sel = state.selectedId;
    if (sel == id) sel = l.isEmpty ? null : l.first.id;
    state = ProfilesState(l, sel);
    await _save();
  }

  Future<void> select(String id) async {
    state = ProfilesState(state.list, id);
    await _save();
  }

  Future<void> setModel(String model) async {
    final cur = state.selected;
    if (cur == null) return;
    await upsert(cur.copyWith(selectedModel: model));
  }

  Future<void> replaceAll(List<ApiProfile> l, String? sel) async {
    state = ProfilesState(l, sel);
    await _save();
  }
}

final profilesProvider = NotifierProvider<ProfilesNotifier, ProfilesState>(ProfilesNotifier.new);

class SelectedAgentNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = p.getString('selected_agent');
    } catch (_) {}
  }

  Future<void> choose(String? id) async {
    state = id;
    try {
      final p = await SharedPreferences.getInstance();
      if (id == null) {
        await p.remove('selected_agent');
      } else {
        await p.setString('selected_agent', id);
      }
    } catch (_) {}
  }
}

final selectedAgentProvider = NotifierProvider<SelectedAgentNotifier, String?>(SelectedAgentNotifier.new);

class PendingNotifier extends Notifier<List<PendingAtt>> {
  @override
  List<PendingAtt> build() => <PendingAtt>[];
  void add(PendingAtt a) => state = <PendingAtt>[...state, a];
  void removeId(String id) => state = state.where((e) => e.id != id).toList();
  void clear() => state = <PendingAtt>[];
}

final pendingProvider = NotifierProvider<PendingNotifier, List<PendingAtt>>(PendingNotifier.new);

class BootNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void done() => state = true;
}

final bootProvider = NotifierProvider<BootNotifier, bool>(BootNotifier.new);

/// نص الرد الجاري اقتباسه (Reply) في الـ composer.
class QuoteNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? q) => state = q;
}

final quoteProvider = NotifierProvider<QuoteNotifier, String?>(QuoteNotifier.new);

// ---------------------------------------------------------------------
//  Bootstrap: load everything at startup (v1 saved data but never loaded it)
// ---------------------------------------------------------------------
Future<void> bootstrap() async {
  final c = appContainer;
  try {
    await c.read(settingsProvider.notifier).load();
    await c.read(profilesProvider.notifier).load();
    await c.read(projectsProvider.notifier).load();
    await c.read(memoryProvider.notifier).load();
    await c.read(agentsProvider.notifier).load();
    await c.read(workspacesProvider.notifier).load();
    await c.read(selectedWorkspaceProvider.notifier).load();
    await c.read(skillsProvider.notifier).load();
    await c.read(libraryProvider.notifier).load();
    await c.read(convListProvider.notifier).load();
    await c.read(selectedAgentProvider.notifier).load();
    try {
      await migrateLegacy();
    } catch (e) {
      debugPrint('migrate failed: $e');
    }
    await PathGuard.init();
  } catch (e) {
    debugPrint('bootstrap failed: $e');
  } finally {
    // حتى لو فشل شيء، لا نترك شاشة البداية معلّقة.
    c.read(bootProvider.notifier).done();
  }
}

Future<void> migrateLegacy() async {
  final prefs = await SharedPreferences.getInstance();
  final profiles = appContainer.read(profilesProvider);
  if (profiles.list.isEmpty) {
    final url = prefs.getString('api_baseUrl');
    final key = prefs.getString('api_key');
    if (url != null && url.trim().isNotEmpty) {
      await appContainer.read(profilesProvider.notifier).upsert(
            ApiProfile(
              id: newId(),
              name: 'الافتراضي',
              kind: kOpenAI,
              baseUrl: url,
              apiKey: key ?? '',
              selectedModel: prefs.getString('api_model') ?? '',
            ),
            select: true,
          );
    }
  }
  if (prefs.getBool('migrated_current') != true) {
    final raw = await LocalStorage.load('chats', 'current');
    final convs = appContainer.read(convListProvider);
    if (raw != null && convs.isEmpty) {
      try {
        final l = asList(jsonDecode(raw));
        if (l.isNotEmpty) {
          final meta = ConvMeta(id: newId(), title: 'المحادثة السابقة');
          await LocalStorage.save('chats', meta.id, raw);
          await appContainer.read(convListProvider.notifier).upsert(meta);
        }
      } catch (_) {}
    }
    await prefs.setBool('migrated_current', true);
  }
}
