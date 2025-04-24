import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; // Android, IOS, MACOS
import 'package:path/path.dart';

class Tierbewegung extends StatefulWidget {
  final String stallname;

  const Tierbewegung({super.key, required this.stallname});

  @override
  _TierbewegungState createState() => _TierbewegungState();
}

class _TierbewegungState extends State<Tierbewegung> {
  late int _currentCount;
  int _newCount = 0;
  bool _isZugang = false;
  bool _isToggleOn = false;
  String _selectedComment = '';
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentCount = prefs.getInt(widget.stallname) ?? 0;
    });
  }

  Future<void> _saveCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(widget.stallname, _currentCount);
  }

  // Aktualisierte Funktion zur Überprüfung und Verarbeitung der neuen Bewegung
  Future<void> _updateCount(BuildContext context) async {
    // Ermittele den Baseline-Wert: Letzter tierbestand vor dem neuen Datum
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path, version: 1);

    final baselineResult = await database.rawQuery(
        "SELECT tierbestand FROM tierbewegungen WHERE stallname = ? AND date < ? ORDER BY date DESC LIMIT 1",
        [widget.stallname, selectedDate.toString()]);
    int baseline = 0;
    if (baselineResult.isNotEmpty) {
      baseline = baselineResult.first['tierbestand'] as int;
    }
    int movementValue = _isZugang ? _newCount : -_newCount;
    int newTierbestand = baseline + movementValue;
    await database.close();

    if (newTierbestand < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Die Anzahl darf nicht negativ sein'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      await _speichern(context);
      setState(() {
        _newCount = 0;
      });
      _showFeedback(context);
    }
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

  Future<void> _speichern(BuildContext context) async {
    // final int movementValue = _isZugang ? _newCount : -_newCount;

    // Neuen Eintrag vorbereiten (temporärer tierbestand 0, wird später aktualisiert)
    final newRecord = {
      'stallname': widget.stallname,
      'anzahl': _newCount,
      'zugang_abgang': _isZugang ? 'Zugang' : 'Abgang',
      'tierbestand': 0,
      'comment': _selectedComment,
      'date': selectedDate.toString(),
      'end': _isToggleOn ? 'Verendung' : '',
    };

    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path, version: 1);

    // Neuen Eintrag in die Datenbank einfügen
    await database.insert('tierbewegungen', newRecord);

    // Baseline ermitteln: Letzter tierbestand vor dem neuen Datum
    final baselineResult = await database.rawQuery(
        "SELECT tierbestand FROM tierbewegungen WHERE stallname = ? AND date < ? ORDER BY date DESC LIMIT 1",
        [widget.stallname, selectedDate.toString()]);
    int baseline = 0;
    if (baselineResult.isNotEmpty) {
      baseline = baselineResult.first['tierbestand'] as int;
    }

    // Alle Einträge ab dem neuen Datum (inklusive) abfragen – sortiert nach Datum und id
    final List<Map<String, dynamic>> subsequentRecords = await database.rawQuery(
        "SELECT * FROM tierbewegungen WHERE stallname = ? AND date >= ? ORDER BY date ASC, id ASC",
        [widget.stallname, selectedDate.toString()]);

    int cumulative = baseline;
    // Alle betroffenen Einträge neu kalkulieren
    for (var record in subsequentRecords) {
      int recordAnzahl = record['anzahl'] as int;
      String zugangAbgang = record['zugang_abgang'] as String;
      int recordMovement = (zugangAbgang == 'Zugang') ? recordAnzahl : -recordAnzahl;
      cumulative += recordMovement;

      // Den tierbestand für den aktuellen Datensatz updaten (vorausgesetzt, es gibt eine 'id'-Spalte)
      int recordId = record['id'] as int;
      await database.update(
        'tierbewegungen',
        {'tierbestand': cumulative},
        where: 'id = ?',
        whereArgs: [recordId],
      );
    }

    // _currentCount aktualisieren
    setState(() {
      _currentCount = cumulative;
    });
    await _saveCount();
    await database.close();
  }

  void _showFeedback(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Die Daten wurden erfolgreich gespeichert')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hintergrundfarbe des FAB: Aktiv nur, wenn _newCount > 0
    final Color fabColor = (_newCount > 0)
        ? Theme.of(context).colorScheme.primary
        : Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: Text('Tierbewegung: ${widget.stallname.split("#")[1]}'),
        elevation: 5.0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Anzeige der aktuellen Tierzahl
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Aktuelle Tierzahl: $_currentCount',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          // Eingabefelder und weitere Optionen
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Toggle Buttons für Zugang/Abgang
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ToggleButtons(
                      isSelected: [_isZugang, !_isZugang],
                      onPressed: (index) {
                        setState(() {
                          _isZugang = index == 0;
                          if (_isZugang) _isToggleOn = false;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      selectedColor: Theme.of(context).colorScheme.onPrimary,
                      color: Theme.of(context).colorScheme.onSurface,
                      fillColor: Theme.of(context).colorScheme.primaryContainer,
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text('Zugang'),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text('Abgang'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  // Eingabefeld für Tierbewegung
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: TextFormField(
                      decoration: const InputDecoration(
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        hintText: 'Anzahl',
                        labelText: 'Tierbewegung',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setState(() {
                          _newCount = int.tryParse(value) ?? 0;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  // Eingabefeld für Zusatzkommentar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: TextFormField(
                      decoration: const InputDecoration(
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        labelText: 'Zusatz',
                        hintText: 'Kommentar (optional)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (newValue) {
                        setState(() {
                          _selectedComment = newValue.toString();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  // Switch für Verendung
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Verendung'),
                        Switch(
                          value: _isToggleOn,
                          onChanged: !_isZugang
                              ? (value) {
                            setState(() {
                              _isToggleOn = value;
                            });
                          }
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16.0),
                  // Datumsauswahl
                  Text("${selectedDate.toLocal()}".split(' ')[0]),
                  const SizedBox(height: 16.0),
                  ElevatedButton(
                    onPressed: () => _selectDate(context),
                    child: const Text('Datum ändern'),
                  ),
                  const SizedBox(height: 16.0),
                ],
              ),
            ),
          ),
        ],
      ),
      // Floating Action Button: Aktiv nur, wenn _newCount > 0
      floatingActionButton: FloatingActionButton(
        onPressed: (_newCount > 0) ? () => _updateCount(context) : null,
        backgroundColor: fabColor,
        tooltip: 'Speichern',
        child: const Icon(Icons.save),
      ),
    );
  }
}
