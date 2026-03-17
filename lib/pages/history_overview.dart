import 'package:flutter/material.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; //Android, IOS, MACOS
import 'dart:convert';
import 'package:tier_monitor/db/app_database.dart';
import 'package:tier_monitor/pages/history_individual.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _entries = [];
  String _currentTable = 'tierdoku'; // Initial ist die Tabelle "tierdoku"
  List<String> _stallOptions = ['Alle'];
  String _selectedStall = 'Alle';
  DateTimeRange? _selectedRange;
  String _selectedType = 'Alle';
  DateTime? _minDate;
  DateTime? _maxDate;

  @override
  void initState() {
    super.initState();
    _loadFiltersAndEntries();
  }

  Future<void> _loadFiltersAndEntries() async {
    await _loadFilterOptions();
    await _fetchEntriesFromDatabase();
  }

  Future<void> _loadFilterOptions() async {
    Database database = await openAppDatabase();

    final stallRows = await database.rawQuery(
      'SELECT stallname FROM $_currentTable '
          'WHERE deleted_at IS NULL '
          'GROUP BY stallname ORDER BY stallname ASC',
    );
    final List<String> stalls = [
      'Alle',
      ...stallRows.map((row) => row['stallname'] as String),
    ];

    final dateRow = await database.rawQuery(
      'SELECT MIN(date) as minDate, MAX(date) as maxDate FROM $_currentTable '
          'WHERE deleted_at IS NULL',
    );
    DateTime? minDate;
    DateTime? maxDate;
    if (dateRow.isNotEmpty) {
      final minStr = dateRow.first['minDate'] as String?;
      final maxStr = dateRow.first['maxDate'] as String?;
      minDate = minStr != null ? DateTime.tryParse(minStr) : null;
      maxDate = maxStr != null ? DateTime.tryParse(maxStr) : null;
    }

    setState(() {
      _stallOptions = stalls;
      if (!_stallOptions.contains(_selectedStall)) {
        _selectedStall = 'Alle';
      }
      _selectedType = 'Alle';
      _minDate = minDate;
      _maxDate = maxDate;
      _selectedRange = null;
    });

    await database.close();
  }

  Future<void> _fetchEntriesFromDatabase() async {
    Database database = await openAppDatabase();

    final List<String> whereParts = [];
    final List<Object?> args = [];

    if (_selectedStall != 'Alle') {
      whereParts.add('stallname = ?');
      args.add(_selectedStall);
    }

    whereParts.add('deleted_at IS NULL');

    if (_selectedRange != null) {
      final start = DateTime(
        _selectedRange!.start.year,
        _selectedRange!.start.month,
        _selectedRange!.start.day,
      );
      final end = DateTime(
        _selectedRange!.end.year,
        _selectedRange!.end.month,
        _selectedRange!.end.day,
        23,
        59,
        59,
      );
      whereParts.add('date >= ? AND date <= ?');
      args.add(start.toString());
      args.add(end.toString());
    }

    if (_selectedType != 'Alle') {
      if (_currentTable == 'tierbewegungen') {
        if (_selectedType == 'Verendung') {
          whereParts.add("end = 'Verendung'");
        } else {
          whereParts.add('zugang_abgang = ?');
          args.add(_selectedType);
        }
      } else if (_selectedType == 'Behandelt mit Medikament') {
        whereParts.add(
          "("
          "("
          "medikament IS NOT NULL AND TRIM(medikament) NOT IN ('', '[]')"
          ") OR ("
          "second_medikament IS NOT NULL AND TRIM(second_medikament) NOT IN ('', '[]')"
          ") OR ("
          "third_medikament IS NOT NULL AND TRIM(third_medikament) NOT IN ('', '[]')"
          ")"
          ")",
        );
      }
    }

    final whereClause =
        whereParts.isEmpty ? '' : 'WHERE ${whereParts.join(' AND ')}';

    // Abhängig von der aktuellen Tabelle die entsprechenden Einträge abrufen
    List<Map<String, dynamic>> entries = await database.rawQuery(
      'SELECT * FROM $_currentTable $whereClause ORDER BY id DESC LIMIT 50',
      args,
    );

    setState(() {
      _entries = entries;
    });

    await database.close();
  }

  String formatJsonList(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return "";
    try {
      final List<dynamic> list = jsonDecode(jsonString);
      return list.join(", ");
    } catch (e) {
      return jsonString; // fallback falls kein JSON
    }
  }

  int _medikationCount(Map<String, dynamic> entry) {
    int count = 0;
    bool hasValue(String? v) {
      if (v == null) return false;
      final trimmed = v.trim();
      return trimmed.isNotEmpty && trimmed != '[]';
    }

    if (hasValue(entry['medikament']?.toString())) count++;
    if (hasValue(entry['second_medikament']?.toString())) count++;
    if (hasValue(entry['third_medikament']?.toString())) count++;
    return count;
  }

  bool _hasVerendung(Map<String, dynamic> entry) {
    final endDate = entry['end_date']?.toString().trim() ?? '';
    final endComment = entry['end_comment']?.toString().trim() ?? '';
    final endFlag = entry['end']?.toString().trim() ?? '';
    return endDate.isNotEmpty || endComment.isNotEmpty || endFlag.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Letzte Einträge'),
        elevation: 5.0, // Erhöhte Elevation für mehr Schatten
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: () {
              // Beim Drücken des Buttons die Tabelle wechseln
              setState(() {
                _currentTable = (_currentTable == 'tierdoku')
                    ? 'tierbewegungen'
                    : 'tierdoku';
              });
              // Einträge aus der aktualisierten Tabelle abrufen
              _loadFiltersAndEntries();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(context),
          Expanded(
            child: ListView.builder(
              itemCount: _entries.length,
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final medCount =
                    _currentTable == 'tierdoku' ? _medikationCount(entry) : 0;
                return Dismissible(
                  key: ValueKey('history_${entry['id']}'),
                  direction: DismissDirection.startToEnd,
                  confirmDismiss: (_) async {
                    final stallname = entry['stallname']?.toString();
                    if (stallname == null || stallname.isEmpty) {
                      return false;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HistoryPageSecondMedikation(
                          stallname: stallname,
                          initialTable: _currentTable,
                          highlightEntryId: entry['id'] as int?,
                        ),
                      ),
                    );
                    return false;
                  },
                  background: Container(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20.0),
                    child: Icon(
                      Icons.arrow_forward,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      size: 30.0,
                    ),
                  ),
                  child: ExpansionTile(
                    collapsedBackgroundColor: _hasVerendung(entry)
                        ? Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                        : null,
                    backgroundColor: _hasVerendung(entry)
                        ? Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                        : null,
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            "${entry['stallname']}".split("#")[1] +
                                (_currentTable == 'tierdoku'
                                    ? " - Bucht: ${entry['bucht']} ${entry['farbe']} ${formatJsonList(entry['symptome'])}"
                                    : " - ${entry['date'].toString().substring(0, 10)}, ${entry['zugang_abgang']}: ${entry['anzahl']}"),
                          ),
                        ),
                        if (_currentTable == 'tierdoku' && medCount > 0) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.medication_outlined, size: 16),
                          if (medCount > 1) ...[
                            const SizedBox(width: 4),
                            Text(
                              medCount.toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ],
                      ],
                    ),
                    children: [
                      if (entry['date'] != null)
                        ListTile(
                          title: Text(
                              "Datum: ${entry['date'].toString().substring(0, 10)}"),
                        ),
                      if (entry['bucht'] != null)
                        ListTile(
                          title: Text("Bucht: ${entry['bucht']}"),
                        ),
                      if (entry['symptome'] != null)
                        ListTile(
                          title: Text(
                              "Symptome: ${formatJsonList(entry['symptome'])}"),
                        ),
                      if (entry['medikament'] != null)
                        ListTile(
                          title: Text(
                              "Erstmedikation: ${formatJsonList(entry['medikament'])}"),
                        ),
                      if (entry['farbe'] != null)
                        ListTile(
                          title: Text("Farbe: ${entry['farbe']}"),
                        ),
                      if (entry['zugang_abgang'] != null)
                        ListTile(
                          title:
                              Text("Zu-/Abgang: ${entry['zugang_abgang']}"),
                        ),
                      if (entry['anzahl'] != null)
                        ListTile(
                          title: Text("Anzahl: ${entry['anzahl']}"),
                        ),
                      if (entry['comment'] != null && entry['comment'] != "")
                        ListTile(
                          title: Text("Kommentar: ${entry['comment']}"),
                        ),
                      if (entry['second_medikament'] != null)
                        ListTile(
                          title: Text(
                              "Zweitmedikation: ${formatJsonList(entry['second_medikament'])}"),
                        ),
                      if (entry['second_date'] != null)
                        ListTile(
                          title: Text(
                              "Datum Zweitmedikation: ${entry['second_date'].toString().substring(0, 10)}"),
                        ),
                      if (entry['second_comment'] != null &&
                          entry['second_comment'] != "")
                        ListTile(
                          title: Text(
                              "Kommentar Zweitmedikation: ${entry['second_comment']}"),
                        ),
                      if (entry['third_medikament'] != null)
                        ListTile(
                          title: Text(
                              "Drittmedikation: ${formatJsonList(entry['third_medikament'])}"),
                        ),
                      if (entry['third_date'] != null)
                        ListTile(
                          title: Text(
                              "Datum Drittmedikation: ${entry['third_date'].toString().substring(0, 10)}"),
                        ),
                      if (entry['third_comment'] != null &&
                          entry['third_comment'] != "")
                        ListTile(
                          title: Text(
                              "Kommentar Drittmedikation: ${entry['third_comment']}"),
                        ),
                      if (entry['end_date'] != null)
                        ListTile(
                          title: Text(
                              "Datum Verendung: ${entry['end_date'].toString().substring(0, 10)}"),
                        ),
                      if (entry['end_comment'] != null &&
                          entry['end_comment'] != "")
                        ListTile(
                          title: Text(
                              "Kommentar Verendung: ${entry['end_comment']}"),
                        ),
                      if (entry['end'] != null)
                        ListTile(
                          title: Text("Zusatz: ${entry['end']}"),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<String> _typeOptions() {
    if (_currentTable == 'tierbewegungen') {
      return ['Alle', 'Zugang', 'Abgang', 'Verendung'];
    }
    return ['Alle', 'Behandelt mit Medikament'];
  }

  String _formatRangeLabel(DateTimeRange range) {
    final start = range.start.toString().substring(0, 10);
    final end = range.end.toString().substring(0, 10);
    return "$start bis $end";
  }

  Widget _buildFilters(BuildContext context) {
    final typeOptions = _typeOptions();
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(12.0),
      child: ExpansionTile(
        title: Text('Filter', style: Theme.of(context).textTheme.titleMedium),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.all(12.0),
        children: [
          DropdownButtonFormField<String>(
            value: _selectedStall,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Stall',
              border: OutlineInputBorder(),
            ),
            items: _stallOptions
                .map((stall) => DropdownMenuItem(
                      value: stall,
                      child: Text(stall.replaceAll('#', '-')),
                    ))
                .toList(),
            onChanged: (val) {
              setState(() {
                _selectedStall = val ?? 'Alle';
              });
              _fetchEntriesFromDatabase();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: typeOptions.contains(_selectedType) ? _selectedType : 'Alle',
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Typ',
              border: OutlineInputBorder(),
            ),
            items: typeOptions
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (val) {
              setState(() {
                _selectedType = val ?? 'Alle';
              });
              _fetchEntriesFromDatabase();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedRange == null
                      ? 'Zeitraum: Alle'
                      : 'Zeitraum: ${_formatRangeLabel(_selectedRange!)}',
                ),
              ),
              TextButton(
                onPressed: (_minDate == null || _maxDate == null)
                    ? null
                    : () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: _minDate!,
                          lastDate: _maxDate!,
                          initialDateRange: _selectedRange,
                        );
                        if (picked == null) return;
                        setState(() {
                          _selectedRange = picked;
                        });
                        _fetchEntriesFromDatabase();
                      },
                child: const Text('Zeitraum ändern'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedRange = null;
                    _selectedStall = 'Alle';
                    _selectedType = 'Alle';
                  });
                  _fetchEntriesFromDatabase();
                },
                child: const Text('Zurücksetzen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}






