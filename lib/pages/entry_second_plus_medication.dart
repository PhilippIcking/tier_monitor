import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Seite für Zweitmedikation
class EntryPageSecondMedikation extends StatefulWidget {
  final int entryId;
  const EntryPageSecondMedikation({super.key, required this.entryId});

  @override
  _EntryPageSecondMedikationState createState() =>
      _EntryPageSecondMedikationState();
}

class _EntryPageSecondMedikationState extends State<EntryPageSecondMedikation> {
  List<String> _medikamente = [];
  List<String> _selectedMedikamente = [];
  String _selectedComment = '';
  DateTime selectedDate = DateTime.now();
  String? _dropdownMedikamentValue;

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

  Future<void> _loadMedications() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _medikamente = prefs.getStringList('medications') ?? [];
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Future<void> _addNewMedication(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final prefs = await SharedPreferences.getInstance();

    final String? newMedikament = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Neues Medikament hinzufügen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Medikament eingeben...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, text);
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );

    if (newMedikament != null && newMedikament.isNotEmpty) {
      _medikamente.add(newMedikament);
      await prefs.setStringList('medications', _medikamente);
      setState(() {
        _selectedMedikamente.add(newMedikament);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Medikament "$newMedikament" hinzugefügt')),
      );
    }
  }

  Future<void> updateEntry(
      int entryId, String field, List<String> values, DateTime date) async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);

    await database.update(
      'tierdoku',
      {
        field: values.join(', '),
        '${field.split("_")[0]}_date': date.toString(),
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
    await database.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zweitmedikation eintragen'),
        elevation: 5.0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Behandlung',
                border: OutlineInputBorder(),
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedMedikamente.isNotEmpty)
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: _selectedMedikamente.map((medikament) {
                        return Chip(
                          label: Text(medikament),
                          deleteIcon: const Icon(Icons.close),
                          onDeleted: () {
                            setState(() {
                              _selectedMedikamente.remove(medikament);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  DropdownButton<String>(
                    value: _dropdownMedikamentValue,
                    isExpanded: true,
                    underline: Container(),
                    items: [
                      ..._medikamente.map((medikament) => DropdownMenuItem(
                        value: medikament,
                        child: Text(medikament),
                      )),
                      const DropdownMenuItem<String>(
                        value: '__add_new_medikament__',
                        child: Row(
                          children: [
                            Icon(Icons.add, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Neues Medikament hinzufügen'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      if (value == '__add_new_medikament__') {
                        await _addNewMedication(context);
                      } else if (!_selectedMedikamente.contains(value)) {
                        setState(() {
                          _selectedMedikamente.add(value);
                        });
                      }
                      setState(() {
                        _dropdownMedikamentValue = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Kommentar',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 5,
              onChanged: (val) {
                setState(() {
                  _selectedComment = val;
                });
              },
            ),
            const SizedBox(height: 16.0),
            Text("${selectedDate.toLocal()}".split(' ')[0]),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              child: const Text('Datum ändern'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          updateEntry(widget.entryId, 'second_medikament', _selectedMedikamente, selectedDate);
          updateEntry(widget.entryId, 'second_comment', [_selectedComment], selectedDate);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Zweitmedikation gespeichert')),
          );
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        tooltip: 'Speichern',
        child: const Icon(Icons.save),
      ),
    );
  }
}

/// Seite für Drittmedikation
class EntryPageThirdMedikation extends StatefulWidget {
  final int entryId;
  const EntryPageThirdMedikation({super.key, required this.entryId});

  @override
  _EntryPageThirdMedikationState createState() =>
      _EntryPageThirdMedikationState();
}

class _EntryPageThirdMedikationState extends State<EntryPageThirdMedikation> {
  List<String> _medikamente = [];
  List<String> _selectedMedikamente = [];
  String _selectedComment = '';
  DateTime selectedDate = DateTime.now();
  String? _dropdownMedikamentValue;

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

  Future<void> _loadMedications() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _medikamente = prefs.getStringList('medications') ?? [];
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Future<void> _addNewMedication(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final prefs = await SharedPreferences.getInstance();

    final String? newMedikament = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Neues Medikament hinzufügen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Medikament eingeben...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(context, text);
            },
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );

    if (newMedikament != null && newMedikament.isNotEmpty) {
      _medikamente.add(newMedikament);
      await prefs.setStringList('medications', _medikamente);
      setState(() {
        _selectedMedikamente.add(newMedikament);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Medikament "$newMedikament" hinzugefügt')),
      );
    }
  }

  Future<void> updateEntry(
      int entryId, String field, List<String> values, DateTime date) async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);

    await database.update(
      'tierdoku',
      {
        field: values.join(', '),
        '${field.split("_")[0]}_date': date.toString(),
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
    await database.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drittmedikation eintragen'),
        elevation: 5.0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Behandlung',
                border: OutlineInputBorder(),
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectedMedikamente.isNotEmpty)
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: _selectedMedikamente.map((medikament) {
                        return Chip(
                          label: Text(medikament),
                          deleteIcon: const Icon(Icons.close),
                          onDeleted: () {
                            setState(() {
                              _selectedMedikamente.remove(medikament);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  DropdownButton<String>(
                    value: _dropdownMedikamentValue,
                    isExpanded: true,
                    underline: Container(),
                    items: [
                      ..._medikamente.map((medikament) => DropdownMenuItem(
                        value: medikament,
                        child: Text(medikament),
                      )),
                      const DropdownMenuItem<String>(
                        value: '__add_new_medikament__',
                        child: Row(
                          children: [
                            Icon(Icons.add, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Neues Medikament hinzufügen'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value == null) return;
                      if (value == '__add_new_medikament__') {
                        await _addNewMedication(context);
                      } else if (!_selectedMedikamente.contains(value)) {
                        setState(() {
                          _selectedMedikamente.add(value);
                        });
                      }
                      setState(() {
                        _dropdownMedikamentValue = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Kommentar',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 5,
              onChanged: (val) {
                setState(() {
                  _selectedComment = val;
                });
              },
            ),
            const SizedBox(height: 16.0),
            Text("${selectedDate.toLocal()}".split(' ')[0]),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              child: const Text('Datum ändern'),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          updateEntry(widget.entryId, 'third_medikament', _selectedMedikamente, selectedDate);
          updateEntry(widget.entryId, 'third_comment', [_selectedComment], selectedDate);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Drittmedikation gespeichert')),
          );
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        tooltip: 'Speichern',
        child: const Icon(Icons.save),
      ),
    );
  }
}

/// Seite für Verendung (Ende)
class EntryPageEnd extends StatefulWidget {
  final int entryId;
  final String stallname;
  const EntryPageEnd({super.key, required this.entryId, required this.stallname});

  @override
  _EntryPageEndState createState() => _EntryPageEndState();
}

class _EntryPageEndState extends State<EntryPageEnd> {
  String _selectedComment = '';
  DateTime selectedDate = DateTime.now();
  bool _isToggleOn = true;

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() => selectedDate = picked);
    }
  }

  Future<Database> _openDb() async {
    final path = join(await getDatabasesPath(), 'my_database.db');
    return openDatabase(path, version: 1);
  }

  Future<int> _getBaselineBeforeDate(
      Database db, String stallName, DateTime date) async {
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(CASE "
          "WHEN zugang_abgang = 'Zugang' THEN anzahl "
          "ELSE -anzahl END), 0) AS total "
          "FROM tierbewegungen WHERE stallname = ? AND date < ?",
      [stallName, date.toString()],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  int _movementDelta(Map<String, dynamic> row) {
    final qty = row['anzahl'] as int? ?? 0;
    return row['zugang_abgang'] == 'Zugang' ? qty : -qty;
  }

  Future<bool> _wouldGoNegativeAfterDelta(
      Database db, String stallName, DateTime date, int delta) async {
    int baseline = await _getBaselineBeforeDate(db, stallName, date);
    int cumulative = baseline + delta;
    if (cumulative < 0) return true;

    final subsequentRecords = await db.rawQuery(
      "SELECT * FROM tierbewegungen "
          "WHERE stallname = ? AND date >= ? "
          "ORDER BY date ASC, id ASC",
      [stallName, date.toString()],
    );
    for (var record in subsequentRecords) {
      cumulative += _movementDelta(record);
      if (cumulative < 0) return true;
    }
    return false;
  }

  Future<void> _refreshSharedCountFromDb(Database db, String stallName) async {
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(CASE "
          "WHEN zugang_abgang = 'Zugang' THEN anzahl "
          "ELSE -anzahl END), 0) AS total "
          "FROM tierbewegungen WHERE stallname = ?",
      [stallName],
    );
    final total = (result.first['total'] as int?) ?? 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(stallName, total);
  }

  Future<void> _updateEndEntry(
      int entryId, String comment, DateTime date) async {
    final db = await _openDb();
    await db.update(
      'tierdoku',
      {
        'end_comment': comment,
        'end_date': date.toString(),
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );
    await db.close();
  }

  Future<void> _insertVerendungMovement(BuildContext context) async {
    final db = await _openDb();
    final wouldGoNegative = await _wouldGoNegativeAfterDelta(
      db,
      widget.stallname,
      selectedDate,
      -1,
    );
    if (wouldGoNegative) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Fehler: Abgang würde negativen Bestand erzeugen'),
        ),
      );
      await db.close();
      return;
    }

    await db.insert('tierbewegungen', {
      'stallname': widget.stallname,
      'anzahl': 1,
      'zugang_abgang': 'Abgang',
      'comment': 'Verendung'
          '${_selectedComment.isNotEmpty ? ': $_selectedComment' : ''}',
      'date': selectedDate.toString(),
      'end': 'Verendung',
    });

    await _refreshSharedCountFromDb(db, widget.stallname);
    await db.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verendung eintragen')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Kommentar (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) =>
                  setState(() => _selectedComment = val),
            ),
            const SizedBox(height: 16.0),
            Text("${selectedDate.toLocal()}".split(' ')[0]),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              child: const Text('Datum ändern'),
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                const Text('Verendung in Tierbewegungen übertragen'),
                Switch(
                  value: _isToggleOn,
                  onChanged: (v) => setState(() => _isToggleOn = v),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton:
      FloatingActionButton(
        onPressed: () async {
          // 1) tierdoku‑Eintrag speichern
          await _updateEndEntry(
              widget.entryId, _selectedComment, selectedDate);
          // 2) optional Abgang eintragen
          if (_isToggleOn) {
            await _insertVerendungMovement(context);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Verendung gespeichert')),
          );
          Navigator.pop(context);
        },
        child: const Icon(Icons.save),
      ),
    );
  }
}
