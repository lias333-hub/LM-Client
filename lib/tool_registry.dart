part of 'main.dart';

/// Tool registry for a professional coding assistant.
/// This contains the capability surface for project work, file operations,
/// search, memory, web access, visualization, and safe device actions.
/// The app does not expose the Claude name or branding; it exposes the features.

enum ToolCategory {
  workspace,
  shell,
  search,
  memory,
  artifact,
  documents,
  device,
  integration,
  project,
}

enum ToolPermission {
  none,
  workspace,
  project,
  network,
  device,
  userConsent,
}

class ToolSpec {
  final String name;
  final String description;
  final ToolCategory category;
  final ToolPermission permission;
  final bool safeByDefault;
  final List<String> tags;

  const ToolSpec({
    required this.name,
    required this.description,
    required this.category,
    required this.permission,
    this.safeByDefault = true,
    this.tags = const <String>[],
  });
}

class ToolSecurityPolicy {
  final bool allowProjectFiles;
  final bool allowNetwork;
  final bool allowDeviceTools;
  final bool requireUserConfirmationForWrite;

  const ToolSecurityPolicy({
    this.allowProjectFiles = true,
    this.allowNetwork = false,
    this.allowDeviceTools = false,
    this.requireUserConfirmationForWrite = true,
  });

  static const ToolSecurityPolicy defaultPolicy = ToolSecurityPolicy(
    allowProjectFiles: true,
    allowNetwork: false,
    allowDeviceTools: false,
    requireUserConfirmationForWrite: true,
  );

  bool allows(ToolSpec spec) {
    if (spec.permission == ToolPermission.none) return true;
    if (spec.permission == ToolPermission.workspace && !allowProjectFiles) return false;
    if (spec.permission == ToolPermission.project && !allowProjectFiles) return false;
    if (spec.permission == ToolPermission.network && !allowNetwork) return false;
    if (spec.permission == ToolPermission.device && !allowDeviceTools) return false;
    if (spec.permission == ToolPermission.userConsent) return true;
    return true;
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
      name: 'render_html',
      description: 'Render a simple HTML/CSS page or UI mockup for review and preview.',
      category: ToolCategory.artifact,
      permission: ToolPermission.workspace,
      safeByDefault: true,
      tags: <String>['visual', 'preview', 'prototype'],
    ),
    ToolSpec(
      name: 'render_chart',
      description: 'Render a chart, graph, or data visualization preview.',
      category: ToolCategory.artifact,
      permission: ToolPermission.workspace,
      safeByDefault: true,
      tags: <String>['visual', 'chart'],
    ),
    ToolSpec(
      name: 'render_mockup',
      description: 'Render a UI mockup or design composition as a shareable preview.',
      category: ToolCategory.artifact,
      permission: ToolPermission.workspace,
      safeByDefault: true,
      tags: <String>['visual', 'design'],
    ),
    ToolSpec(
      name: 'create_doc',
      description: 'Create or initialize a document or structured note within the app.',
      category: ToolCategory.documents,
      permission: ToolPermission.workspace,
      safeByDefault: false,
      tags: <String>['docs', 'notes'],
    ),
    ToolSpec(
      name: 'read_doc',
      description: 'Read a document or note.',
      category: ToolCategory.documents,
      permission: ToolPermission.workspace,
      safeByDefault: true,
      tags: <String>['docs', 'read'],
    ),
    ToolSpec(
      name: 'update_doc',
      description: 'Update a document or note content.',
      category: ToolCategory.documents,
      permission: ToolPermission.workspace,
      safeByDefault: false,
      tags: <String>['docs', 'write'],
    ),
    ToolSpec(
      name: 'export_doc',
      description: 'Export a document to a supported format like markdown, HTML, or PDF.',
      category: ToolCategory.documents,
      permission: ToolPermission.workspace,
      safeByDefault: false,
      tags: <String>['docs', 'export'],
    ),
    ToolSpec(
      name: 'get_time',
      description: 'Read the current local date and time for scheduling and context.',
      category: ToolCategory.device,
      permission: ToolPermission.device,
      safeByDefault: true,
      tags: <String>['device', 'time'],
    ),
    ToolSpec(
      name: 'get_location',
      description: 'Read the current user location only with explicit user approval.',
      category: ToolCategory.device,
      permission: ToolPermission.userConsent,
      safeByDefault: false,
      tags: <String>['device', 'location'],
    ),
    ToolSpec(
      name: 'create_alarm',
      description: 'Set a local alarm from the app.',
      category: ToolCategory.device,
      permission: ToolPermission.userConsent,
      safeByDefault: false,
      tags: <String>['device', 'alarm'],
    ),
    ToolSpec(
      name: 'create_timer',
      description: 'Create a timer or reminder.',
      category: ToolCategory.device,
      permission: ToolPermission.userConsent,
      safeByDefault: false,
      tags: <String>['device', 'timer'],
    ),
    ToolSpec(
      name: 'search_calendar',
      description: 'Search existing calendar events and appointments.',
      category: ToolCategory.device,
      permission: ToolPermission.userConsent,
      safeByDefault: true,
      tags: <String>['device', 'calendar'],
    ),
    ToolSpec(
      name: 'create_event',
      description: 'Create or schedule a calendar event with explicit approval.',
      category: ToolCategory.device,
      permission: ToolPermission.userConsent,
      safeByDefault: false,
      tags: <String>['device', 'calendar'],
    ),
    ToolSpec(
      name: 'compose_message',
      description: 'Draft a message, email, or summary for user review.',
      category: ToolCategory.integration,
      permission: ToolPermission.userConsent,
      safeByDefault: true,
      tags: <String>['compose', 'message'],
    ),
    ToolSpec(
      name: 'ask_user_choice',
      description: 'Ask the user a multiple-choice question when a decision requires confirmation.',
      category: ToolCategory.integration,
      permission: ToolPermission.userConsent,
      safeByDefault: true,
      tags: <String>['interaction', 'question'],
    ),
    ToolSpec(
      name: 'suggest_connectors',
      description: 'Suggest relevant external connectors or integrations that fit the task.',
      category: ToolCategory.integration,
      permission: ToolPermission.workspace,
      safeByDefault: true,
      tags: <String>['connector', 'integration'],
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
        allowList.addAll(<String>['list_dir', 'read_file', 'outline_file', 'search_files', 'create_file', 'edit_file', 'write_file', 'shell_exec', 'git_status', 'git_diff', 'run_build', 'run_test', 'read_memory', 'write_memory', 'render_html', 'render_mockup']);
        break;
      case 'web':
        allowList.addAll(<String>['list_dir', 'read_file', 'outline_file', 'search_files', 'create_file', 'edit_file', 'write_file', 'shell_exec', 'git_status', 'git_diff', 'run_build', 'run_test', 'web_search', 'web_fetch', 'read_memory', 'write_memory', 'render_html', 'render_chart']);
        break;
      case 'sdk':
        allowList.addAll(<String>['list_dir', 'read_file', 'outline_file', 'search_files', 'create_file', 'edit_file', 'write_file', 'shell_exec', 'git_status', 'git_diff', 'run_build', 'run_test', 'web_search', 'web_fetch', 'read_memory', 'write_memory']);
        break;
      default:
        allowList.addAll(<String>['list_dir', 'read_file', 'outline_file', 'search_files', 'create_file', 'edit_file', 'write_file', 'shell_exec', 'git_status', 'git_diff', 'read_memory', 'write_memory', 'render_html']);
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
