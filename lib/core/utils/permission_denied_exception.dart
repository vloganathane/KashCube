/// Thrown when an app user attempts an action they don't have permission for.
class PermissionDeniedException implements Exception {
  const PermissionDeniedException(this.module, this.action);

  final String module;
  final String action;

  @override
  String toString() => 'PermissionDeniedException: cannot $action in module "$module"';
}
