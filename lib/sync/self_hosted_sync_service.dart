import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tier_monitor/db/app_database.dart';
import 'package:tier_monitor/sync/self_hosted_sync_models.dart';

class SelfHostedSyncService {
  SelfHostedSyncService._();

  static final SelfHostedSyncService instance = SelfHostedSyncService._();

  static const String enabledKey = 'selfhosted_enabled';
  static const String autoSyncEnabledKey = 'selfhosted_auto_sync_enabled';
  static const String baseUrlKey = 'selfhosted_base_url';
  static const String apiTokenKey = 'selfhosted_api_token';
  static const String deviceNameKey = 'selfhosted_device_name';
  static const String lastUploadKey = 'selfhosted_last_upload_at';
  static const String lastDownloadKey = 'selfhosted_last_download_at';
  static const String mergeSymptomsKey = 'selfhosted_merge_symptoms';
  static const String mergeMedicationsKey = 'selfhosted_merge_medications';
  static const String mergeWidgetsKey = 'selfhosted_merge_widgets';
  static const String mergeBuchtenKey = 'selfhosted_merge_buchten';
  static const String syncErrorKey = 'selfhosted_last_sync_error';
  static const String syncSuccessKey = 'selfhosted_last_sync_success_at';
  static const String syncLastActionKey = 'selfhosted_last_sync_action';

  final ValueNotifier<SyncStatus> status = ValueNotifier(const SyncStatus.initial());

  bool _initialized = false;
  Future<SyncRunResult>? _inFlight;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await refreshConfig();
  }

  Future<void> refreshConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(enabledKey) ?? false;
    final autoEnabled = prefs.getBool(autoSyncEnabledKey) ?? false;
    final error = prefs.getString(syncErrorKey);
    final successRaw = prefs.getString(syncSuccessKey);
    final actionRaw = prefs.getString(syncLastActionKey);
    status.value = status.value.copyWith(
      isEnabled: enabled,
      autoSyncEnabled: autoEnabled,
      showButton: enabled && autoEnabled,
      lastError: error,
      lastSuccessAt: _parseComparableTimestamp(successRaw),
      lastAction: _parseAction(actionRaw),
    );
  }

  Future<SyncRunResult> runStartupSyncCheck() async {
    await initialize();
    final current = status.value;
    if (!current.isEnabled || !current.autoSyncEnabled) {
      return const SyncRunResult(
        action: SyncAction.none,
        message: 'Automatische Synchronisierung ist deaktiviert.',
        success: false,
      );
    }
    return syncNow(trigger: SyncTrigger.startup);
  }

  Future<SyncRunResult> syncNow({required SyncTrigger trigger}) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _syncNowInternal(trigger: trigger);
    _inFlight = future;
    return future.whenComplete(() {
      _inFlight = null;
    });
  }

  Future<SyncRunResult> _syncNowInternal({required SyncTrigger trigger}) async {
    await initialize();
    await refreshConfig();

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(enabledKey) ?? false;
    final autoEnabled = prefs.getBool(autoSyncEnabledKey) ?? false;
    final normalized = _normalizeBaseUrl(prefs.getString(baseUrlKey) ?? '');
    if (!enabled || !autoEnabled) {
      final message = trigger == SyncTrigger.startup
          ? 'Sync ist deaktiviert.'
          : 'Sync ist nicht aktiv.';
      return SyncRunResult(
        action: SyncAction.none,
        message: message,
        success: false,
      );
    }
    if (normalized == null) {
      await _setError('Server-Adresse fehlt.');
      return const SyncRunResult(
        action: SyncAction.none,
        message: 'Server-Adresse fehlt.',
        success: false,
      );
    }

    status.value = status.value.copyWith(state: SyncStateType.syncing);

    try {
      final local = await _loadLocalSummary();
      final server = await _loadServerSummary(
        normalized,
        prefs.getString(apiTokenKey) ?? '',
      );

      final decision = _decideAction(
        localOverall: local.overallLastEditAt,
        serverOverall: server.overallLastEditAt,
      );

      if (decision == SyncAction.none) {
        await _setSuccess(SyncAction.none);
        return const SyncRunResult(
          action: SyncAction.none,
          message: 'Keine neuen Änderungen.',
          success: true,
        );
      }

      if (decision == SyncAction.upload) {
        await _uploadData(
          normalized: normalized,
          apiToken: prefs.getString(apiTokenKey) ?? '',
          deviceName: prefs.getString(deviceNameKey) ?? '',
        );
        await _setSuccess(SyncAction.upload);
        return const SyncRunResult(
          action: SyncAction.upload,
          message: 'Upload abgeschlossen.',
          success: true,
        );
      }

      await _downloadMergeData(
        normalized: normalized,
        apiToken: prefs.getString(apiTokenKey) ?? '',
      );
      await _setSuccess(SyncAction.downloadMerge);
      return const SyncRunResult(
        action: SyncAction.downloadMerge,
        message: 'Download (Merge) abgeschlossen.',
        success: true,
      );
    } catch (error) {
      final msg = _friendlySyncErrorMessage(error);
      await _setError(msg);
      return SyncRunResult(
        action: SyncAction.none,
        message: msg,
        success: false,
      );
    }
  }

  Future<void> _setError(String error) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(syncErrorKey, error);
    status.value = status.value.copyWith(
      state: SyncStateType.error,
      lastError: error,
    );
  }

  Future<void> _setSuccess(SyncAction action) async {
    final now = DateTime.now().toIso8601String();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(syncErrorKey);
    await prefs.setString(syncSuccessKey, now);
    await prefs.setString(syncLastActionKey, _actionToString(action));
    status.value = status.value.copyWith(
      state: SyncStateType.ok,
      lastSuccessAt: _parseComparableTimestamp(now),
      lastAction: action,
      clearError: true,
    );
  }

  String _friendlySyncErrorMessage(Object error) {
    if (error is SocketException) {
      return 'Keine Verbindung zum lokalen Netzwerk.';
    }

    final raw = error.toString().toLowerCase();
    if (raw.contains('timed out') ||
        raw.contains('timeout') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection refused') ||
        raw.contains('network is unreachable')) {
      return 'Keine Verbindung zum lokalen Netzwerk.';
    }

    return 'Synchronisierung fehlgeschlagen.';
  }

  String _actionToString(SyncAction action) {
    switch (action) {
      case SyncAction.upload:
        return 'upload';
      case SyncAction.downloadMerge:
        return 'download_merge';
      case SyncAction.none:
        return 'none';
    }
  }

  SyncAction? _parseAction(String? raw) {
    switch (raw) {
      case 'upload':
        return SyncAction.upload;
      case 'download_merge':
        return SyncAction.downloadMerge;
      case 'none':
        return SyncAction.none;
      default:
        return null;
    }
  }

  SyncAction _decideAction({
    required String? localOverall,
    required String? serverOverall,
  }) {
    final local = _parseComparableTimestamp(localOverall);
    final server = _parseComparableTimestamp(serverOverall);

    if (local == null && server == null) return SyncAction.none;
    if (local != null && server == null) return SyncAction.upload;
    if (local == null && server != null) return SyncAction.downloadMerge;
    if (local!.isAfter(server!)) return SyncAction.upload;
    if (server.isAfter(local)) return SyncAction.downloadMerge;
    return SyncAction.none;
  }

  String? _normalizeBaseUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'http://$trimmed';
  }

  DateTime? _parseComparableTimestamp(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final raw = value.trim();
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final hasZone = raw.endsWith('Z') || RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(raw);
    if (hasZone) {
      return parsed.toUtc();
    }
    return DateTime(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).toUtc();
  }

  Future<_LocalSummary> _loadLocalSummary() async {
    final db = await openAppDatabase();
    try {
      final overallLastEdit = await db.rawQuery(
        'SELECT MAX(last_modified) AS maxDate FROM ('
        'SELECT last_modified FROM tierdoku '
        'UNION ALL '
        'SELECT last_modified FROM tierbewegungen'
        ')',
      );
      return _LocalSummary(
        overallLastEditAt: overallLastEdit.first['maxDate'] as String?,
      );
    } finally {
      await db.close();
    }
  }

  Future<_ServerSummary> _loadServerSummary(String normalized, String apiToken) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client.getUrl(Uri.parse('$normalized/sync/summary'));
      if (apiToken.trim().isNotEmpty) {
        request.headers.set('X-API-Token', apiToken.trim());
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw Exception('Server antwortete mit ${response.statusCode}');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      return _ServerSummary(
        overallLastEditAt: data['overall_last_edit_at'] as String?,
      );
    } finally {
      client.close();
    }
  }

  Future<void> _uploadData({
    required String normalized,
    required String apiToken,
    required String deviceName,
  }) async {
    final db = await openAppDatabase();
    final tierdokuRows = await db.query('tierdoku');
    final tierbewegungenRows = await db.query('tierbewegungen');
    await db.close();

    List<Map<String, dynamic>> stripIds(List<Map<String, dynamic>> rows) {
      return rows.map((row) {
        final copy = Map<String, dynamic>.from(row);
        copy.remove('id');
        return copy;
      }).toList();
    }

    final payload = {
      'device_name': deviceName.trim().isEmpty ? null : deviceName.trim(),
      'tierdoku': stripIds(tierdokuRows),
      'tierbewegungen': stripIds(tierbewegungenRows),
    };

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(Uri.parse('$normalized/sync/upload'));
      request.headers.contentType = ContentType.json;
      if (apiToken.trim().isNotEmpty) {
        request.headers.set('X-API-Token', apiToken.trim());
      }
      request.write(jsonEncode(payload));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw Exception('Upload fehlgeschlagen (${response.statusCode})');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      final lastUpload = data['last_upload_at'] as String? ?? nowIso();
      await prefs.setString(lastUploadKey, lastUpload);
    } finally {
      client.close();
    }
  }

  Future<void> _downloadMergeData({
    required String normalized,
    required String apiToken,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    Map<String, dynamic> data;
    try {
      final request = await client.getUrl(Uri.parse('$normalized/sync/download'));
      if (apiToken.trim().isNotEmpty) {
        request.headers.set('X-API-Token', apiToken.trim());
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw Exception('Download fehlgeschlagen (${response.statusCode})');
      }
      data = jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }

    final tierdoku = List<Map<String, dynamic>>.from(
      (data['tierdoku'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e)),
    );
    final tierbewegungen = List<Map<String, dynamic>>.from(
      (data['tierbewegungen'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e)),
    );

    final db = await openAppDatabase();
    await db.transaction((txn) async {
      Future<void> applyRows(String table, List<Map<String, dynamic>> rows) async {
        for (final row in rows) {
          row.remove('id');
          final uuid = row['uuid'] as String?;
          if (uuid == null || uuid.isEmpty) continue;
          final existing = await txn.query(
            table,
            columns: ['uuid', 'last_modified', 'deleted_at'],
            where: 'uuid = ?',
            whereArgs: [uuid],
            limit: 1,
          );
          if (existing.isEmpty) {
            await txn.insert(table, row);
            continue;
          }
          final localModified = existing.first['last_modified'] as String?;
          final localDeleted = existing.first['deleted_at'] as String?;
          final serverModified = row['last_modified'] as String?;
          if (_isServerNewer(serverModified, localModified)) {
            await txn.update(
              table,
              row,
              where: 'uuid = ?',
              whereArgs: [uuid],
            );
          } else if (_isServerNewer(row['deleted_at'] as String?, localDeleted)) {
            await txn.update(
              table,
              {
                'deleted_at': row['deleted_at'],
                'last_modified': row['last_modified'],
              },
              where: 'uuid = ?',
              whereArgs: [uuid],
            );
          }
        }
      }

      await applyRows('tierdoku', tierdoku);
      await applyRows('tierbewegungen', tierbewegungen);
    });
    await _rebuildCounts(db);
    await db.close();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(lastDownloadKey, nowIso());
    await _mergePreferencesFromDb();
  }

  bool _isServerNewer(String? server, String? local) {
    final serverTime = _parseComparableTimestamp(server);
    final localTime = _parseComparableTimestamp(local);
    if (serverTime == null) return false;
    if (localTime == null) return true;
    return serverTime.isAfter(localTime);
  }

  Future<void> _rebuildCounts(Database db) async {
    final rows = await db.rawQuery(
      "SELECT stallname, COALESCE(SUM(CASE "
      "WHEN zugang_abgang = 'Zugang' THEN anzahl "
      "ELSE -anzahl END), 0) AS total "
      "FROM tierbewegungen WHERE deleted_at IS NULL GROUP BY stallname",
    );
    final prefs = await SharedPreferences.getInstance();
    for (final row in rows) {
      final stall = row['stallname'] as String?;
      final total = row['total'] as int?;
      if (stall != null && total != null) {
        await prefs.setInt(stall, total);
      }
    }
  }

  Future<void> _mergePreferencesFromDb() async {
    final prefs = await SharedPreferences.getInstance();
    final mergeSymptoms = prefs.getBool(mergeSymptomsKey) ?? false;
    final mergeMedications = prefs.getBool(mergeMedicationsKey) ?? false;
    final mergeWidgets = prefs.getBool(mergeWidgetsKey) ?? false;
    final mergeBuchten = prefs.getBool(mergeBuchtenKey) ?? false;

    if (!mergeSymptoms && !mergeMedications && !mergeWidgets && !mergeBuchten) {
      return;
    }

    final db = await openAppDatabase();
    try {
      if (mergeSymptoms || mergeMedications || mergeBuchten) {
        final rows = await db.query(
          'tierdoku',
          columns: [
            'symptome',
            'medikament',
            'second_medikament',
            'third_medikament',
            'bucht',
          ],
          where: 'deleted_at IS NULL',
        );

        if (mergeSymptoms) {
          final existing = prefs.getStringList('symptoms') ?? [];
          final merged = existing.toSet();
          for (final row in rows) {
            final values = _extractJsonValues(row['symptome'] as String?);
            merged.addAll(values);
          }
          if (merged.length != existing.length) {
            final list = merged.toList()..sort();
            await prefs.setStringList('symptoms', list);
          }
        }

        if (mergeMedications) {
          final existing = prefs.getStringList('medications') ?? [];
          final merged = existing.toSet();
          for (final row in rows) {
            for (final key in ['medikament', 'second_medikament', 'third_medikament']) {
              final values = _extractJsonValues(row[key] as String?);
              merged.addAll(values);
            }
          }
          if (merged.length != existing.length) {
            final list = merged.toList()..sort();
            await prefs.setStringList('medications', list);
          }
        }

        if (mergeBuchten) {
          final existing = prefs.getStringList('buchten') ?? [];
          final merged = existing.toSet();
          for (final row in rows) {
            merged.addAll(_splitFallback(row['bucht']?.toString() ?? ''));
          }
          if (merged.length != existing.length) {
            final list = merged.toList()..sort();
            await prefs.setStringList('buchten', list);
          }
        }
      }

      if (mergeWidgets) {
        final rows = await db.rawQuery(
          'SELECT stallname FROM tierdoku WHERE deleted_at IS NULL '
          'UNION '
          'SELECT stallname FROM tierbewegungen WHERE deleted_at IS NULL',
        );
        final widgetNames = (prefs.getStringList('widget_names') ?? []).toSet();
        final Map<String, Set<String>> stallMap = {};

        for (final row in rows) {
          final stallname = row['stallname'] as String?;
          if (stallname == null || stallname.isEmpty) continue;
          final parts = stallname.split('#');
          if (parts.length < 2) continue;
          final betrieb = parts[0].trim();
          if (betrieb.isEmpty) continue;
          stallMap.putIfAbsent(betrieb, () => <String>{}).add(stallname);
        }

        for (final entry in stallMap.entries) {
          final betrieb = entry.key;
          widgetNames.add(betrieb);
          final existingStalls = prefs.getStringList(betrieb) ?? [];
          final mergedStalls = existingStalls.toSet()..addAll(entry.value);
          if (mergedStalls.length != existingStalls.length) {
            final list = mergedStalls.toList()..sort();
            await prefs.setStringList(betrieb, list);
          }
        }

        if (widgetNames.length != (prefs.getStringList('widget_names') ?? []).length) {
          final list = widgetNames.toList()..sort();
          await prefs.setStringList('widget_names', list);
        }
      }
    } finally {
      await db.close();
    }
  }

  List<String> _extractJsonValues(String? raw) {
    if (raw == null) return [];
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '[]') return [];
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return decoded
            .map((value) => value?.toString().trim() ?? '')
            .where((value) => value.isNotEmpty)
            .toList();
      }
      if (decoded is String) {
        return _splitFallback(decoded);
      }
    } catch (_) {
      return _splitFallback(trimmed);
    }
    return [];
  }

  List<String> _splitFallback(String value) {
    if (value.contains(',')) {
      return value
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
    }
    return value.trim().isEmpty ? [] : [value.trim()];
  }
}

class _LocalSummary {
  final String? overallLastEditAt;

  const _LocalSummary({
    required this.overallLastEditAt,
  });
}

class _ServerSummary {
  final String? overallLastEditAt;

  const _ServerSummary({
    required this.overallLastEditAt,
  });
}
