class ProjectScope {
  final String root;
  final String projectType;
  final List<String> allowedRoots;
  final List<String> ignorePatterns;
  final List<String> buildCommands;
  final List<String> testCommands;

  const ProjectScope({
    required this.root,
    this.projectType = 'generic',
    this.allowedRoots = const <String>[],
    this.ignorePatterns = const <String>[],
    this.buildCommands = const <String>[],
    this.testCommands = const <String>[],
  });

  bool containsPath(String path) {
    final cleaned = normalizeRoot(root);
    final toCheck = normalizePath(cleaned, path);
    return toCheck == cleaned || toCheck.startsWith('$cleaned/');
  }

  bool isAllowed(String path) {
    if (allowedRoots.isEmpty) return containsPath(path);
    for (final root in allowedRoots) {
      final r = normalizeRoot(root);
      final p = normalizePath(r, path);
      if (p == r || p.startsWith('$r/')) return true;
    }
    return false;
  }

  factory ProjectScope.fromAtlas(ProjectAtlas atlas) {
    final map = <String, List<String>>{
      'android': <String>['flutter test', 'flutter analyze', 'flutter build apk'],
      'web': <String>['npm install', 'npm run build', 'npm test'],
      'sdk': <String>['dart test', 'dart analyze', 'dart pub get'],
      'generic': <String>['git status --short --branch', 'ls', 'find . -maxdepth 2 -type f | head'],
    };
    final testMap = <String, List<String>>{
      'android': <String>['flutter test', 'flutter analyze'],
      'web': <String>['npm test', 'npm run build'],
      'sdk': <String>['dart test', 'dart analyze'],
      'generic': <String>['git status --short --branch'],
    };
    final type = atlas.projectType;
    return ProjectScope(
      root: atlas.root,
      projectType: type,
      allowedRoots: atlas.allowedRoots.isEmpty ? <String>[atlas.root] : atlas.allowedRoots,
      ignorePatterns: atlas.ignorePatterns,
      buildCommands: map[type] ?? map['generic']!,
      testCommands: testMap[type] ?? testMap['generic']!,
    );
  }
}

class ProjectRootPolicy {
  static const List<String> defaultDeniedRoots = <String>[
    '/proc',
    '/sys',
    '/dev',
    '/etc',
    '/var',
    '/tmp',
    '/root',
    '/home',
    '/opt',
    '/usr/local',
  ];

  static bool isDeniedRoot(String root) {
    final cleaned = normalizeRoot(root);
    for (final denied in defaultDeniedRoots) {
      if (cleaned == denied || cleaned.startsWith('$denied/')) return true;
    }
    return false;
  }

  static String sanitizeRoot(String raw) {
    final r = normalizeRoot(raw);
    if (r == '/') return '/storage/emulated/0';
    if (isDeniedRoot(r)) return '/storage/emulated/0';
    return r;
  }
}

class ProjectToolProfile {
  final ProjectAtlas atlas;
  final List<String> buildCommands;
  final List<String> testCommands;
  final List<String> readCommands;
  final List<String> writeCommands;

  const ProjectToolProfile({
    required this.atlas,
    required this.buildCommands,
    required this.testCommands,
    required this.readCommands,
    required this.writeCommands,
  });

  factory ProjectToolProfile.fromAtlas(ProjectAtlas atlas) {
    final scope = ProjectScope.fromAtlas(atlas);
    final read = <String>['ls', 'pwd', 'find', 'grep', 'rg', 'git', 'cat', 'head', 'tail', 'sed', 'awk'];
    final write = <String>['mkdir', 'cp', 'mv', 'touch', 'echo', 'printf', 'python', 'node', 'dart', 'flutter'];
    return ProjectToolProfile(
      atlas: atlas,
      buildCommands: scope.buildCommands,
      testCommands: scope.testCommands,
      readCommands: read,
      writeCommands: write,
    );
  }
}
