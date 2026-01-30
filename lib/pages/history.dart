import 'package:flutter/material.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; //Android, IOS, MACOS
import 'package:path/path.dart';
import 'dart:convert';

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
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);

    final stallRows = await database.rawQuery(
      'SELECT stallname FROM $_currentTable GROUP BY stallname ORDER BY stallname ASC',
    );
    final List<String> stalls = [
      'Alle',
      ...stallRows.map((row) => row['stallname'] as String),
    ];

    final dateRow = await database.rawQuery(
      'SELECT MIN(date) as minDate, MAX(date) as maxDate FROM $_currentTable',
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
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);

    final List<String> whereParts = [];
    final List<Object?> args = [];

    if (_selectedStall != 'Alle') {
      whereParts.add('stallname = ?');
      args.add(_selectedStall);
    }

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
          "medikament IS NOT NULL AND TRIM(medikament) NOT IN ('', '[]')"
          ") OR ("
          "second_medikament IS NOT NULL AND TRIM(second_medikament) NOT IN ('', '[]')"
          ") OR ("
          "third_medikament IS NOT NULL AND TRIM(third_medikament) NOT IN ('', '[]')"
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

  Future<void> _deleteEntry(int index) async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);

    // ID des zu löschenden Eintrags abrufen
    int entryId = _entries[index]['id'];

    // Abhängig von der aktuellen Tabelle den Eintrag löschen
    await database.delete(_currentTable, where: 'id = ?', whereArgs: [entryId]);

    // Aktualisierte Einträge aus der aktuellen Tabelle abrufen
    await _fetchEntriesFromDatabase();

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
                return ExpansionTile(
                  title: GestureDetector(
                    onLongPress: () async {
                      if (_currentTable == 'tierdoku') {
                        // Dialog anzeigen und Benutzer nach Bestätigung fragen
                        bool deleteConfirmed = await showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: const Text('Eintrag löschen'),
                              content: const Text(
                                  'Möchten Sie diesen Eintrag wirklich löschen?'),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop(false);
                                  },
                                  child: const Text('Abbrechen'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop(true);
                                  },
                                  child: const Text('Löschen'),
                                ),
                              ],
                            );
                          },
                        );

                        // Wenn der Benutzer die Löschung bestätigt hat, den Eintrag löschen
                        if (deleteConfirmed == true) {
                          await _deleteEntry(index);
                        }
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                              Text('Löschen von Tierbewegungen nicht möglich')),
                        );
                      }
                    },
                    child: Text(
                      "${_entries[index]['stallname']}".split("#")[1] +
                          (_currentTable == 'tierdoku'
                              ? " - Bucht: ${_entries[index]['bucht']} ${_entries[index]['farbe']} ${formatJsonList(_entries[index]['symptome'])}"
                              : " - ${_entries[index]['date'].toString().substring(0, 10)}, ${_entries[index]['zugang_abgang']}: ${_entries[index]['anzahl']}"),
                    ),
                  ),
                  children: [
                    if (_entries[index]['date'] != null)
                      ListTile(
                        title: Text(
                            "Datum: ${_entries[index]['date'].toString().substring(0, 10)}"),
                      ),
                    if (_entries[index]['bucht'] != null)
                      ListTile(
                        title: Text("Bucht: ${_entries[index]['bucht']}"),
                      ),
                    if (_entries[index]['symptome'] != null)
                      ListTile(
                        title: Text("Symptome: ${formatJsonList(_entries[index]['symptome'])}"),
                      ),

                    if (_entries[index]['medikament'] != null)
                      ListTile(
                        title: Text("Erstmedikation: ${formatJsonList(_entries[index]['medikament'])}"),
                      ),
                    if (_entries[index]['farbe'] != null)
                      ListTile(
                        title: Text("Farbe: ${_entries[index]['farbe']}"),
                      ),
                    if (_entries[index]['zugang_abgang'] != null)
                      ListTile(
                        title:
                        Text("Zu-/Abgang: ${_entries[index]['zugang_abgang']}"),
                      ),
                    if (_entries[index]['anzahl'] != null)
                      ListTile(
                        title: Text("Anzahl: ${_entries[index]['anzahl']}"),
                      ),
                    if (_entries[index]['comment'] != null &&
                        _entries[index]['comment'] != "")
                      ListTile(
                        title: Text("Kommentar: ${_entries[index]['comment']}"),
                      ),
                    if (_entries[index]['second_medikament'] != null)
                      ListTile(
                        title: Text("Zweitmedikation: ${formatJsonList(_entries[index]['second_medikament'])}"),
                      ),
                    if (_entries[index]['second_date'] != null)
                      ListTile(
                        title: Text(
                            "Datum Zweitmedikation: ${_entries[index]['second_date'].toString().substring(0, 10)}"),
                      ),
                    if (_entries[index]['second_comment'] != null &&
                        _entries[index]['second_comment'] != "")
                      ListTile(
                        title: Text(
                            "Kommentar Zweitmedikation: ${_entries[index]['second_comment']}"),
                      ),
                    if (_entries[index]['third_medikament'] != null)
                      ListTile(
                        title: Text("Drittmedikation: ${formatJsonList(_entries[index]['third_medikament'])}"),
                      ),
                    if (_entries[index]['third_date'] != null)
                      ListTile(
                        title: Text(
                            "Datum Drittmedikation: ${_entries[index]['third_date'].toString().substring(0, 10)}"),
                      ),
                    if (_entries[index]['third_comment'] != null &&
                        _entries[index]['third_comment'] != "")
                      ListTile(
                        title: Text(
                            "Kommentar Drittmedikation: ${_entries[index]['third_comment']}"),
                      ),
                    if (_entries[index]['end_date'] != null)
                      ListTile(
                        title: Text(
                            "Datum Verendung: ${_entries[index]['end_date'].toString().substring(0, 10)}"),
                      ),
                    if (_entries[index]['end_comment'] != null &&
                        _entries[index]['end_comment'] != "")
                      ListTile(
                        title: Text(
                            "Kommentar Verendung: ${_entries[index]['end_comment']}"),
                      ),
                    if (_entries[index]['end'] != null)
                      ListTile(
                        title: Text("Zusatz: ${_entries[index]['end']}"),
                      ),
                  ],
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
