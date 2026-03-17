enum SyncTrigger {
  startup,
  manual,
}

enum SyncAction {
  upload,
  downloadMerge,
  none,
}

enum SyncStateType {
  idle,
  syncing,
  ok,
  error,
}

class SyncRunResult {
  final SyncAction action;
  final String message;
  final bool success;

  const SyncRunResult({
    required this.action,
    required this.message,
    required this.success,
  });
}

class SyncStatus {
  final bool showButton;
  final bool isEnabled;
  final bool autoSyncEnabled;
  final SyncStateType state;
  final String? lastError;
  final DateTime? lastSuccessAt;
  final SyncAction? lastAction;

  const SyncStatus({
    required this.showButton,
    required this.isEnabled,
    required this.autoSyncEnabled,
    required this.state,
    this.lastError,
    this.lastSuccessAt,
    this.lastAction,
  });

  const SyncStatus.initial()
      : showButton = false,
        isEnabled = false,
        autoSyncEnabled = false,
        state = SyncStateType.idle,
        lastError = null,
        lastSuccessAt = null,
        lastAction = null;

  SyncStatus copyWith({
    bool? showButton,
    bool? isEnabled,
    bool? autoSyncEnabled,
    SyncStateType? state,
    String? lastError,
    DateTime? lastSuccessAt,
    SyncAction? lastAction,
    bool clearError = false,
  }) {
    return SyncStatus(
      showButton: showButton ?? this.showButton,
      isEnabled: isEnabled ?? this.isEnabled,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      state: state ?? this.state,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      lastAction: lastAction ?? this.lastAction,
    );
  }
}
