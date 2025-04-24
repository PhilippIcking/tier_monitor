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
  String _selectedMedikament = '';
  String _selectedComment = '';
  DateTime selectedDate = DateTime.now();
  List<String> _medikamente = [];

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
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  /// Update-Funktion: Es werden das jeweilige Feld (z. B. "second_medikament")
  /// und das zugehörige Datum (z. B. "second_date") aktualisiert.
  Future<void> updateEntry(
      int entryId, String field, String value, DateTime date) async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);
    await database.update(
      'tierdoku',
      {
        field: value,
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
            DropdownButtonFormField(
              value: _selectedMedikament.isNotEmpty ? _selectedMedikament : null,
              items: _medikamente
                  .map((med) => DropdownMenuItem(
                value: med,
                child: Text(med),
              ))
                  .toList(),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Medikament',
                hintText: 'keine',
                border: OutlineInputBorder(),
              ),
              onChanged: (newValue) {
                setState(() {
                  _selectedMedikament = newValue.toString();
                });
              },
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Zusatz',
                hintText: 'Kommentar (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                setState(() {
                  _selectedComment = val.toString();
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
          // Speichern der Zweitmedikation: Es werden beide Felder (Medikament und Kommentar)
          // sowie das Datum in der Datenbank aktualisiert.
          updateEntry(widget.entryId, 'second_medikament', _selectedMedikament, selectedDate);
          updateEntry(widget.entryId, 'second_comment', _selectedComment, selectedDate);
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
  String _selectedMedikament = '';
  String _selectedComment = '';
  DateTime selectedDate = DateTime.now();
  List<String> _medikamente = [];

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
      lastDate: DateTime(2100),
    );
    if(picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Future<void> updateEntry(
      int entryId, String field, String value, DateTime date) async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);
    await database.update(
      'tierdoku',
      {
        field: value,
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
            DropdownButtonFormField(
              value: _selectedMedikament.isNotEmpty ? _selectedMedikament : null,
              items: _medikamente
                  .map((med) => DropdownMenuItem(
                value: med,
                child: Text(med),
              ))
                  .toList(),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Medikament',
                hintText: 'keine',
                border: OutlineInputBorder(),
              ),
              onChanged: (newValue) {
                setState(() {
                  _selectedMedikament = newValue.toString();
                });
              },
            ),
            const SizedBox(height: 16.0),
            TextFormField(
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Zusatz',
                hintText: 'Kommentar (optional)',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) {
                setState(() {
                  _selectedComment = val.toString();
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
          updateEntry(widget.entryId, 'third_medikament', _selectedMedikament, selectedDate);
          updateEntry(widget.entryId, 'third_comment', _selectedComment, selectedDate);
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
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != selectedDate) {
      setState(() => selectedDate = picked);
    }
  }

  Future<Database> _openDb() async {
    final path = join(await getDatabasesPath(), 'my_database.db');
    return openDatabase(path, version: 1);
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

  /// Neu: context wird übergeben, um SnackBar anzuzeigen
  Future<void> _insertVerendungMovement(BuildContext context) async {
    final db = await _openDb();

    // 1) aktuellen Bestand ermitteln
    final prev = await db.rawQuery(
      "SELECT tierbestand FROM tierbewegungen "
          "WHERE stallname = ? AND date <= ? "
          "ORDER BY date DESC LIMIT 1",
      [widget.stallname, selectedDate.toString()],
    );
    final prefs = await SharedPreferences.getInstance();
    final current = prev.isNotEmpty
        ? prev.first['tierbestand'] as int
        : prefs.getInt(widget.stallname) ?? 0;

    // 2) Negativ-Check
    if (current - 1 < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Fehler: Abgang würde negativen Bestand erzeugen'),
        ),
      );
      await db.close();
      return;
    }

    // 3) Abgang eintragen
    await db.insert('tierbewegungen', {
      'stallname': widget.stallname,
      'anzahl': 1,
      'zugang_abgang': 'Abgang',
      'tierbestand': 0, // wird gleich neu berechnet
      'comment': 'Verendung'
          '${_selectedComment.isNotEmpty ? ': $_selectedComment' : ''}',
      'date': selectedDate.toString(),
      'end': 'Verendung',
    });

    // 4) kumulative Neuberechnung
    int cumulative = current;
    final rows = await db.rawQuery(
      "SELECT * FROM tierbewegungen "
          "WHERE stallname = ? AND date >= ? "
          "ORDER BY date ASC, id ASC",
      [widget.stallname, selectedDate.toString()],
    );
    for (var row in rows) {
      final qty = row['anzahl'] as int;
      final isZugang = row['zugang_abgang'] == 'Zugang';
      cumulative += isZugang ? qty : -qty;
      await db.update(
        'tierbewegungen',
        {'tierbestand': cumulative},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    // 5) SharedPreferences aktualisieren
    await prefs.setInt(widget.stallname, cumulative);
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
