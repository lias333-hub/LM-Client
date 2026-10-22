part of 'main.dart';

class ToolPolicy {
  static final Set<String> dangerousShellPatterns = <String>{
    'rm -rf /',
    'rm -rf /tmp',
    'chmod 777',
    'sudo ',
    'git clean -fd',
    'git checkout -- .',
    'mkfs',
    'dd if=',
    'mount ',
    'umount ',
    'su ',
    'pkill ',
    'kill -9',
    'ssh ',
    'scp ',
    'curl http://localhost',
    'curl https://localhost',
    'reset --hard',
  };

  static bool requiresApproval(String toolName) {
    final writeTools = <String>{
      'create_file',
      'edit_file',
      'write_file',
      'delete_file',
      'shell_exec',
      'run_build',
      'run_test',
      'create_doc',
      'update_doc',
      'delete_memory',
      'write_memory',
      'append_memory',
    };
    return writeTools.contains(toolName);
  }

  static bool isAllowedForProject(String projectType, String toolName) {
    final type = projectType.trim().toLowerCase();
    final allowList = <String>{};

    switch (type) {
      case 'android':
      case 'web':
      case 'sdk':
        allowList.addAll(<String>{
          'list_dir',
          'read_file',
          'outline_file',
          'search_files',
          'create_file',
          'edit_file',
          'write_file',
          'shell_exec',
          'git_status',
          'git_diff',
          'run_build',
          'run_test',
          'read_memory',
          'write_memory',
          'append_memory',
          'close_task',
        });
        break;
      default:
        allowList.addAll(<String>{
          'list_dir',
          'read_file',
          'outline_file',
          'search_files',
          'create_file',
          'edit_file',
          'write_file',
          'shell_exec',
          'git_status',
          'git_diff',
          'read_memory',
          'write_memory',
          'append_memory',
          'close_task',
        });
        break;
    }

    return allowList.contains(toolName);
  }

  static bool isDangerousCommand(String command) {
    final normalized = command.toLowerCase();
    for (final pattern in dangerousShellPatterns) {
      if (normalized.contains(pattern.toLowerCase())) return true;
    }
    return false;
  }

  static bool isAllowedRoot(String root, String path) {
    final cleanRoot = ProjectExecutor.normalizeRoot(root);
    final cleanPath = ProjectExecutor.normalizePath(cleanRoot, path);
    return cleanPath == cleanRoot || cleanPath.startsWith('$cleanRoot/');
  }
}

class ToolRegistry {
  static const List<ToolSpec> core = <ToolSpec>[
    ToolSpec(
      name: 'list_dir',
      description: 'List files and folders for a project or workspace root.',
      category: ToolCategory.workspace,
      permission: ToolPermission.workspace,
      safeByDefault: true,
      tags: <String>['filesystem', 'workspace'],
    ),
    ToolSpec(
      name: 'read_file',
      description: 'Read a text file or a narrow file range.',
      category: ToolCategory.workspace,
      permission: ToolPermission.workspace,
      safeByDefault: true,
      tags: <String>['filesystem', 'read'],
    ),
    ToolSpec(
      name: 'outline_file',
      description: 'Summarize a file structure, headings, and important definitions.',
      category: ToolCategory.workspace,
      permission: ToolPermission.workspace,
      safeByDefault: true,
      tags: <String>['filesystem', 'read', 'navigation'],
    ),
    ToolSpec(
      name: 'search_files',
      description: 'Search inside files or filenames for a pattern under a project root.',
      category: ToolCategory.search,
      permission: ToolPermission.workspace,
      safeByDefault: true,
      tags: <String>['search', 'workspace'],
    ),
    ToolSpec(
      name: 'create_file',
      description: 'Create a new file within the selected project root.',
      category: ToolCategory.workspace,
      permission: ToolPermission.project,
      safeByDefault: false,
      tags: <String>['write', 'create'],
    ),
    ToolSpec(
      name: 'edit_file',
      description: 'Replace a specific snippet in an existing file.',
      category: ToolCategory.workspace,
      permission: ToolPermission.project,
      safeByDefault: false,
      tags: <String>['write', 'patch'],
    ),
    ToolSpec(
      name: 'write_file',
      description: 'Create or overwrite a file as a full content replacement.',
      category: ToolCategory.workspace,
      permission: ToolPermission.project,
      safeByDefault: false,
      tags: <String>['write', 'overwrite'],
    ),
    ToolSpec(
      name: 'delete_file',
      description: 'Delete an existing file or empty folder within the project scope.',
      category: ToolCategory.workspace,
      permission: ToolPermission.project,
      safeByDefault: false,
      tags: <String>['write', 'delete'],
    ),
    ToolSpec(
      name: 'shell_exec',
      description: 'Run a safe, scoped shell command inside the active project root.',
      category: ToolCategory.shell,
      permission: ToolPermission.project,
      safeByDefault: false,
      tags: <String>['shell', 'exec', 'project'],
    ),
    ToolSpec(
      name: 'git_status',
      description: 'Check repository status and current branch state.',
      category: ToolCategory.shell,
      permission: ToolPermission.project,
      safeByDefault: true,
      tags: <String>['git', 'status'],
    ),
    ToolSpec(
      name: 'git_diff',
      description: 'Inspect the repository diff for a file or the whole project.',
      category: ToolCategory.shell,
      permission: ToolPermission.project,
      safeByDefault: true,
      tags: <String>['git', 'diff'],
    ),
    ToolSpec(
      name: 'run_build',
      description: 'Run the minimal project build or compile step for verification.',
      category: ToolCategory.shell,
      permission: ToolPermission.project,
      safeByDefault: false,
      tags: <String>['build', 'verify'],
    ),
    ToolSpec(
      name: 'run_test',
      description: 'Run the closest relevant tests for the active feature or project area.',
      category: ToolCategory.shell,
      permission: ToolPermission.project,
      safeByDefault: false,
      tags: <String>['test', 'verify'],
    ),
    ToolSpec(
      name: 'web_search',
      description: 'Search the public web for updated API docs, examples, or references.',
      category: ToolCategory.search,
      permission: ToolPermission.network,
      safeByDefault: true,
      tags: <String>['network', 'docs'],
    ),
    ToolSpec(
      name: 'web_fetch',
      description: 'Fetch and summarize a public URL for code, docs, or reference material.',
      category: ToolCategory.search,
      permission: ToolPermission.network,
      safeByDefault: true,
      tags: <String>['network', 'fetch'],
    ),
    ToolSpec(
      name: 'read_memory',
      description: 'Read a saved fact or durable preference from memory.',
      category: ToolCategory.memory,
      permission: ToolPermission.workspace,
      safeByDefault: true,
      tags: <String>['memory', 'context'],
    ),
    ToolSpec(
      name: 'write_memory',
      description: 'Store a durable fact or project-specific memory item.',
      category: ToolCategory.memory,
      permission: ToolPermission.workspace,
      safeByDefault: false,
      tags: <String>['memory', 'persist'],
    ),
    ToolSpec(
      name: 'append_memory',
      description: 'Add new context to an existing memory entry.',
      category: ToolCategory.memory,
      permission: ToolPermission.workspace,
      safeByDefault: false,
      tags: <String>['memory', 'update'],
    ),
    ToolSpec(
      name: 'delete_memory',
      description: 'Remove a stored memory item.',
      category: ToolCategory.memory,
      permission: ToolPermission.workspace,
      safeByDefault: false,
      tags: <String>['memory', 'delete'],
    ),
    ToolSpec(
      name: 'close_task',
      description: 'Finish the current task after the work is verified and the summary is ready.',
      category: ToolCategory.project,
      permission: ToolPermission.project,
      safeByDefault: true,
      tags: <String>['task', 'done'],
    ),
  ];

  static List<ToolSpec> forPolicy(ToolSecurityPolicy policy) {
    return core.where((spec) => policy.allows(spec)).toList();
  }

  static List<ToolSpec> forProjectType(String projectType, {ToolSecurityPolicy policy = ToolSecurityPolicy.defaultPolicy}) {
    final type = projectType.trim().toLowerCase();
    final allowList = <String>{};

    switch (type) {
      case 'android':
      case 'web':
      case 'sdk':
        allowList.addAll(<String>{
          'list_dir',
          'read_file',
          'outline_file',
          'search_files',
          'create_file',
          'edit_file',
          'write_file',
          'shell_exec',
          'git_status',
          'git_diff',
          'run_build',
          'run_test',
          'read_memory',
          'write_memory',
          'append_memory',
          'close_task',
        });
        break;
      default:
        allowList.addAll(<String>{
          'list_dir',
          'read_file',
          'outline_file',
          'search_files',
          'create_file',
          'edit_file',
          'write_file',
          'shell_exec',
          'git_status',
          'git_diff',
          'read_memory',
          'write_memory',
          'append_memory',
          'close_task',
        });
        break;
    }

    return core.where((spec) => allowList.contains(spec.name) && policy.allows(spec)).toList();
  }

  static List<String> namesForProjectType(String projectType, {ToolSecurityPolicy policy = ToolSecurityPolicy.defaultPolicy}) {
    return forProjectType(projectType, policy: policy).map((spec) => spec.name).toList();
  }

  static ToolSpec? byName(String name) {
    for (final spec in core) {
      if (spec.name == name) return spec;
    }
    return null;
  }
}

class ToolUsageLog {
  final String tool;
  final String category;
  final String timestamp;
  final bool success;
  final String summary;

  const ToolUsageLog({
    required this.tool,
    required this.category,
    required this.timestamp,
    required this.success,
    required this.summary,
  });
}

class ToolRuntime {
  final ToolSecurityPolicy policy;

  const ToolRuntime({this.policy = ToolSecurityPolicy.defaultPolicy});

  List<ToolSpec> allowedForProject(String projectType) {
    return ToolRegistry.forProjectType(projectType, policy: policy);
  }

  bool isAllowed(String toolName, {String projectType = 'generic'}) {
    final spec = ToolRegistry.byName(toolName);
    if (spec == null) return false;
    if (!policy.allows(spec)) return false;
    final allowed = ToolRegistry.forProjectType(projectType, policy: policy);
    return allowed.any((item) => item.name == toolName);
  }
}
