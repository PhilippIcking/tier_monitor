import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tier_monitor/db/app_database.dart';

class SelfHostedSyncPage extends StatefulWidget {
  const SelfHostedSyncPage({super.key});

  @override
  State<SelfHostedSyncPage> createState() => _SelfHostedSyncPageState();
}

class _SelfHostedSyncPageState extends State<SelfHostedSyncPage> {
  static const String _enabledKey = 'selfhosted_enabled';
  static const String _baseUrlKey = 'selfhosted_base_url';
  static const String _apiTokenKey = 'selfhosted_api_token';
  static const String _deviceNameKey = 'selfhosted_device_name';
  static const String _lastUploadKey = 'selfhosted_last_upload_at';
  static const String _lastDownloadKey = 'selfhosted_last_download_at';
  static const String _mergeSymptomsKey = 'selfhosted_merge_symptoms';
  static const String _mergeMedicationsKey = 'selfhosted_merge_medications';
  static const String _mergeWidgetsKey = 'selfhosted_merge_widgets';
  static const String _mergeBuchtenKey = 'selfhosted_merge_buchten';

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiTokenController = TextEditingController();
  final TextEditingController _deviceNameController = TextEditingController();

  bool _enabled = false;
  bool _testing = false;
  bool _syncBusy = false;
  bool _summaryLoading = false;
  bool _mergeSymptoms = false;
  bool _mergeMedications = false;
  bool _mergeWidgets = false;
  bool _mergeBuchten = false;
  String? _lastTestResult;
  String? _localMaxDokuDate;
  String? _localMaxMoveDate;
  String? _serverMaxDokuDate;
  String? _serverMaxMoveDate;
  String? _serverOverallLastEditAt;
  String? _serverLastUploadAt;
  String? _localLastUploadAt;
  String? _localLastDownloadAt;
  String? _localOverallLastEditAt;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiTokenController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _baseUrlController.text = prefs.getString(_baseUrlKey) ?? '';
    _apiTokenController.text = prefs.getString(_apiTokenKey) ?? '';
    _deviceNameController.text = prefs.getString(_deviceNameKey) ?? '';
    _localLastUploadAt = prefs.getString(_lastUploadKey);
    _localLastDownloadAt = prefs.getString(_lastDownloadKey);
    _mergeSymptoms = prefs.getBool(_mergeSymptomsKey) ?? false;
    _mergeMedications = prefs.getBool(_mergeMedicationsKey) ?? false;
    _mergeWidgets = prefs.getBool(_mergeWidgetsKey) ?? false;
    _mergeBuchten = prefs.getBool(_mergeBuchtenKey) ?? false;
    setState(() {});
    await _refreshStatus();
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _saveString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
  }

  Future<void> _refreshStatus() async {
    await _loadLocalSummary();
    if (_enabled) {
      await _loadServerSummary();
    }
  }

  Future<void> _loadLocalSummary() async {
    final db = await openAppDatabase();
    final maxDoku = await db.rawQuery(
      'SELECT MAX(date) AS maxDate FROM tierdoku WHERE deleted_at IS NULL',
    );
    final maxMove = await db.rawQuery(
      'SELECT MAX(date) AS maxDate FROM tierbewegungen WHERE deleted_at IS NULL',
    );
    final overallLastEdit = await db.rawQuery(
      'SELECT MAX(last_modified) AS maxDate FROM ('
      'SELECT last_modified FROM tierdoku '
      'UNION ALL '
      'SELECT last_modified FROM tierbewegungen'
      ')',
    );
    await db.close();
    setState(() {
      _localMaxDokuDate = maxDoku.first['maxDate'] as String?;
      _localMaxMoveDate = maxMove.first['maxDate'] as String?;
      _localOverallLastEditAt = overallLastEdit.first['maxDate'] as String?;
    });
  }

  Future<void> _loadServerSummary() async {
    final normalized = _normalizeBaseUrl(_baseUrlController.text);
    if (normalized == null) return;
    setState(() => _summaryLoading = true);
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(Uri.parse('$normalized/sync/summary'));
      final token = _apiTokenController.text.trim();
      if (token.isNotEmpty) {
        request.headers.set('X-API-Token', token);
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      if (response.statusCode != 200) return;
      final data = jsonDecode(body) as Map<String, dynamic>;
      setState(() {
        _serverLastUploadAt = data['last_upload_at'] as String?;
        _serverMaxDokuDate = data['max_date_tierdoku'] as String?;
        _serverMaxMoveDate = data['max_date_tierbewegungen'] as String?;
        _serverOverallLastEditAt = data['overall_last_edit_at'] as String?;
      });
    } catch (_) {
      // Ignore summary errors.
    } finally {
      if (mounted) {
        setState(() => _summaryLoading = false);
      }
    }
  }

  String? _normalizeBaseUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'http://$trimmed';
  }

  Future<void> _testConnection() async {
    final normalized = _normalizeBaseUrl(_baseUrlController.text);
    if (normalized == null) {
      setState(() {
        _lastTestResult = 'Bitte eine Server-Adresse eingeben.';
      });
      return;
    }

    setState(() {
      _testing = true;
      _lastTestResult = null;
    });

    try {
      final uri = Uri.parse('$normalized/health');
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(uri);
      final token = _apiTokenController.text.trim();
      if (token.isNotEmpty) {
        request.headers.set('X-API-Token', token);
      }
      final response = await request.close();
      final statusCode = response.statusCode;
      await response.drain();
      client.close();

      if (statusCode == 200) {
        _lastTestResult = 'Verbindung erfolgreich.';
      } else if (statusCode == 401 || statusCode == 403) {
        _lastTestResult = 'Authentifizierung fehlgeschlagen.';
      } else {
        _lastTestResult = 'Server antwortete mit Status $statusCode.';
      }
    } catch (error) {
      _lastTestResult = 'Verbindung fehlgeschlagen: $error';
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
        });
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_lastTestResult ?? 'Test abgeschlossen.')),
    );
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '—';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final local = parsed.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  Future<void> _uploadData() async {
    final normalized = _normalizeBaseUrl(_baseUrlController.text);
    if (!_enabled || normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Sync aktivieren und Server angeben.')),
      );
      return;
    }

    setState(() => _syncBusy = true);
    try {
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
        'device_name': _deviceNameController.text.trim().isEmpty
            ? null
            : _deviceNameController.text.trim(),
        'tierdoku': stripIds(tierdokuRows),
        'tierbewegungen': stripIds(tierbewegungenRows),
      };

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request =
          await client.postUrl(Uri.parse('$normalized/sync/upload'));
      request.headers.contentType = ContentType.json;
      final token = _apiTokenController.text.trim();
      if (token.isNotEmpty) {
        request.headers.set('X-API-Token', token);
      }
      request.write(jsonEncode(payload));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final prefs = await SharedPreferences.getInstance();
        final lastUpload = data['last_upload_at'] as String? ?? nowIso();
        await prefs.setString(_lastUploadKey, lastUpload);
        setState(() {
          _localLastUploadAt = lastUpload;
          _serverLastUploadAt = data['last_upload_at'] as String?;
          _serverMaxDokuDate = data['max_date_tierdoku'] as String?;
          _serverMaxMoveDate = data['max_date_tierbewegungen'] as String?;
          _serverOverallLastEditAt = data['overall_last_edit_at'] as String?;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload abgeschlossen.')),
        );
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentifizierung fehlgeschlagen.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload fehlgeschlagen: ${response.statusCode}')),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _syncBusy = false);
      }
    }
  }

  Future<void> _downloadData() async {
    final normalized = _normalizeBaseUrl(_baseUrlController.text);
    if (!_enabled || normalized == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Sync aktivieren und Server angeben.')),
      );
      return;
    }

    final mode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download-Modus'),
        content: const Text(
          'Möchtest du die lokalen Daten ersetzen oder mit dem Server zusammenführen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'merge'),
            child: const Text('Zusammenführen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'replace'),
            child: const Text('Ersetzen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
    if (mode == null) return;

    setState(() => _syncBusy = true);
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request =
          await client.getUrl(Uri.parse('$normalized/sync/download'));
      final token = _apiTokenController.text.trim();
      if (token.isNotEmpty) {
        request.headers.set('X-API-Token', token);
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download fehlgeschlagen: ${response.statusCode}')),
        );
        return;
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      final tierdoku = List<Map<String, dynamic>>.from(
        (data['tierdoku'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e)),
      );
      final tierbewegungen = List<Map<String, dynamic>>.from(
        (data['tierbewegungen'] as List<dynamic>).map((e) => Map<String, dynamic>.from(e)),
      );

      final db = await openAppDatabase();
      await db.transaction((txn) async {
        Future<void> applyRows(String table, List<Map<String, dynamic>> rows) async {
          if (mode == 'replace') {
            await txn.delete(table);
          }
          for (final row in rows) {
            row.remove('id');
            final uuid = row['uuid'] as String?;
            if (uuid == null || uuid.isEmpty) continue;
            if (mode == 'replace') {
              await txn.insert(table, row);
              continue;
            }
            final existing = await txn.query(
              table,
              columns: ['uuid', 'last_modified', 'deleted_at'],
              where: 'uuid = ?',
              whereArgs: [uuid],
              limit: 1,
            );
            if (existing.isEmpty) {
              await txn.insert(table, row);
            } else {
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
        }

        await applyRows('tierdoku', tierdoku);
        await applyRows('tierbewegungen', tierbewegungen);
      });
      await _rebuildCounts(db);
      await db.close();

      final prefs = await SharedPreferences.getInstance();
      final lastDownload = nowIso();
      await prefs.setString(_lastDownloadKey, lastDownload);
      setState(() {
        _localLastDownloadAt = lastDownload;
        _serverLastUploadAt = data['last_upload_at'] as String?;
        _serverMaxDokuDate = data['max_date_tierdoku'] as String?;
        _serverMaxMoveDate = data['max_date_tierbewegungen'] as String?;
        _serverOverallLastEditAt = data['overall_last_edit_at'] as String?;
      });
      await _loadLocalSummary();
      final mergeResult = await _mergePreferencesFromDb(showSnack: false);
      if (mounted && mergeResult.totalAdded > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'UI aktualisiert: '
              '+${mergeResult.symptomsAdded} Symptome, '
              '+${mergeResult.medicationsAdded} Medikamente, '
              '+${mergeResult.buchtenAdded} Buchten, '
              '+${mergeResult.widgetsAdded} Betriebe, '
              '+${mergeResult.stallsAdded} Ställe.',
            ),
          ),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download abgeschlossen.')),
      );
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download fehlgeschlagen: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _syncBusy = false);
      }
    }
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

  Future<_MergeResult> _mergePreferencesFromDb({bool showSnack = true}) async {
    if (!_mergeSymptoms && !_mergeMedications && !_mergeWidgets && !_mergeBuchten) {
      return const _MergeResult();
    }

    final db = await openAppDatabase();
    final prefs = await SharedPreferences.getInstance();
    var result = const _MergeResult();

    try {
      if (_mergeSymptoms || _mergeMedications || _mergeBuchten) {
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

        if (_mergeSymptoms) {
          final existing = prefs.getStringList('symptoms') ?? [];
          final merged = existing.toSet();
          for (final row in rows) {
            final values = _extractJsonValues(row['symptome'] as String?);
            for (final value in values) {
              if (merged.add(value)) {
                result = result.copyWith(symptomsAdded: result.symptomsAdded + 1);
              }
            }
          }
          if (merged.length != existing.length) {
            final list = merged.toList()..sort();
            await prefs.setStringList('symptoms', list);
          }
        }

        if (_mergeMedications) {
          final existing = prefs.getStringList('medications') ?? [];
          final merged = existing.toSet();
          for (final row in rows) {
            for (final key in [
              'medikament',
              'second_medikament',
              'third_medikament',
            ]) {
              final values = _extractJsonValues(row[key] as String?);
              for (final value in values) {
                if (merged.add(value)) {
                  result = result.copyWith(
                    medicationsAdded: result.medicationsAdded + 1,
                  );
                }
              }
            }
          }
          if (merged.length != existing.length) {
            final list = merged.toList()..sort();
            await prefs.setStringList('medications', list);
          }
        }

        if (_mergeBuchten) {
          final existing = prefs.getStringList('buchten') ?? [];
          final merged = existing.toSet();
          for (final row in rows) {
            final values = _splitFallback(row['bucht']?.toString() ?? '');
            for (final value in values) {
              if (merged.add(value)) {
                result = result.copyWith(buchtenAdded: result.buchtenAdded + 1);
              }
            }
          }
          if (merged.length != existing.length) {
            final list = merged.toList()..sort();
            await prefs.setStringList('buchten', list);
          }
        }
      }

      if (_mergeWidgets) {
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
          if (widgetNames.add(betrieb)) {
            result = result.copyWith(widgetsAdded: result.widgetsAdded + 1);
          }
          final existingStalls = prefs.getStringList(betrieb) ?? [];
          final mergedStalls = existingStalls.toSet();
          for (final stall in entry.value) {
            if (mergedStalls.add(stall)) {
              result = result.copyWith(stallsAdded: result.stallsAdded + 1);
            }
          }
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

    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'UI aktualisiert: '
            '+${result.symptomsAdded} Symptome, '
            '+${result.medicationsAdded} Medikamente, '
            '+${result.buchtenAdded} Buchten, '
            '+${result.widgetsAdded} Betriebe, '
            '+${result.stallsAdded} Ställe.',
          ),
        ),
      );
    }

    return result;
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

  bool _isServerNewer(String? server, String? local) {
    if (server == null || server.isEmpty) return false;
    if (local == null || local.isEmpty) return true;
    final serverTime = DateTime.tryParse(server);
    final localTime = DateTime.tryParse(local);
    if (serverTime == null || localTime == null) {
      return server.compareTo(local) > 0;
    }
    return serverTime.isAfter(localTime);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseUrlEmpty = _baseUrlController.text.trim().isEmpty;
    final syncDisabled = !_enabled || baseUrlEmpty || _syncBusy;
    final mergeDisabled = _syncBusy ||
        (!_mergeSymptoms &&
            !_mergeMedications &&
            !_mergeWidgets &&
            !_mergeBuchten);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Self-Hosted Sync'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            child: SwitchListTile(
              value: _enabled,
              title: const Text('Self-Hosted Sync aktivieren'),
              subtitle: const Text(
                'Nur mit Self-Hosted-Server möglich.',
              ),
              onChanged: (value) {
                setState(() {
                  _enabled = value;
                });
                _saveBool(_enabledKey, value);
                if (value) {
                  _refreshStatus();
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    controller: _baseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Server-Adresse',
                      hintText: 'z.B. 192.168.1.50:8000',
                    ),
                    keyboardType: TextInputType.url,
                    onChanged: (value) => _saveString(_baseUrlKey, value.trim()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiTokenController,
                    decoration: const InputDecoration(
                      labelText: 'API Token (optional)',
                    ),
                    obscureText: true,
                    onChanged: (value) => _saveString(_apiTokenKey, value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _deviceNameController,
                    decoration: const InputDecoration(
                      labelText: 'Gerätename (optional)',
                    ),
                    onChanged: (value) =>
                        _saveString(_deviceNameKey, value.trim()),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          (_testing || baseUrlEmpty) ? null : _testConnection,
                      icon: _testing
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.network_check),
                      label: Text(_testing
                          ? 'Teste Verbindung...'
                          : 'Verbindung testen'),
                    ),
                  ),
                  if (_lastTestResult != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _lastTestResult!,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Status',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Status aktualisieren',
                        onPressed: _summaryLoading ? null : _refreshStatus,
                        icon: _summaryLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Lokal: Tierdoku bis ${_formatDate(_localMaxDokuDate)}'),
                  Text(
                    'Lokal: Tierbewegungen bis ${_formatDate(_localMaxMoveDate)}',
                  ),
                  Text(
                    'Lokal: Letzte Änderung ${_formatDate(_localOverallLastEditAt)}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Server: Tierdoku bis ${_formatDate(_serverMaxDokuDate)}',
                  ),
                  Text(
                    'Server: Tierbewegungen bis ${_formatDate(_serverMaxMoveDate)}',
                  ),
                  Text(
                    'Server: Letzte Änderung ${_formatDate(_serverOverallLastEditAt)}',
                  ),
                  Text(
                    'Server-Upload: ${_formatDate(_serverLastUploadAt)}',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Letzter Upload lokal: ${_formatDate(_localLastUploadAt)}',
                  ),
                  Text(
                    'Letzter Download lokal: ${_formatDate(_localLastDownloadAt)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: syncDisabled ? null : _uploadData,
                      icon: const Icon(Icons.cloud_upload),
                      label: Text(_syncBusy ? 'Bitte warten...' : 'Upload'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: syncDisabled ? null : _downloadData,
                      icon: const Icon(Icons.cloud_download),
                      label: Text(_syncBusy ? 'Bitte warten...' : 'Download'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'UI aus Datenbank zusammenführen',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _mergeSymptoms,
                    title: const Text('Symptome'),
                    onChanged: (value) {
                      final enabled = value ?? false;
                      setState(() => _mergeSymptoms = enabled);
                      _saveBool(_mergeSymptomsKey, enabled);
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _mergeMedications,
                    title: const Text('Medikamente'),
                    onChanged: (value) {
                      final enabled = value ?? false;
                      setState(() => _mergeMedications = enabled);
                      _saveBool(_mergeMedicationsKey, enabled);
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _mergeWidgets,
                    title: const Text('Homepage-Widgets'),
                    subtitle: const Text(
                      'Betriebe und Ställe aus vorhandenen Einträgen.',
                    ),
                    onChanged: (value) {
                      final enabled = value ?? false;
                      setState(() => _mergeWidgets = enabled);
                      _saveBool(_mergeWidgetsKey, enabled);
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _mergeBuchten,
                    title: const Text('Buchten'),
                    onChanged: (value) {
                      final enabled = value ?? false;
                      setState(() => _mergeBuchten = enabled);
                      _saveBool(_mergeBuchtenKey, enabled);
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: mergeDisabled ? null : _mergePreferencesFromDb,
                      icon: const Icon(Icons.merge),
                      label: const Text('Aus Datenbank übernehmen'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Hinweis'),
              subtitle: const Text(
                'Auf GitHub befindet sich ein vorbereiteter Docker-Container '
                'für das Self-Hosting. '
                'Zur Synchronisierung sollte sich das Gerät im gleichen '
                'Netzwerk befinden.',

              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MergeResult {
  final int symptomsAdded;
  final int medicationsAdded;
  final int buchtenAdded;
  final int widgetsAdded;
  final int stallsAdded;

  const _MergeResult({
    this.symptomsAdded = 0,
    this.medicationsAdded = 0,
    this.buchtenAdded = 0,
    this.widgetsAdded = 0,
    this.stallsAdded = 0,
  });

  int get totalAdded =>
      symptomsAdded + medicationsAdded + buchtenAdded + widgetsAdded + stallsAdded;

  _MergeResult copyWith({
    int? symptomsAdded,
    int? medicationsAdded,
    int? buchtenAdded,
    int? widgetsAdded,
    int? stallsAdded,
  }) {
    return _MergeResult(
      symptomsAdded: symptomsAdded ?? this.symptomsAdded,
      medicationsAdded: medicationsAdded ?? this.medicationsAdded,
      buchtenAdded: buchtenAdded ?? this.buchtenAdded,
      widgetsAdded: widgetsAdded ?? this.widgetsAdded,
      stallsAdded: stallsAdded ?? this.stallsAdded,
    );
  }
}

