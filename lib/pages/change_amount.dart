import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; // Android, iOS, macOS
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

  Future<void> _updateCount(BuildContext context) async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path, version: 1);

    final baselineResult = await database.rawQuery(
      "SELECT tierbestand FROM tierbewegungen "
          "WHERE stallname = ? AND date < ? "
          "ORDER BY date DESC LIMIT 1",
      [widget.stallname, selectedDate.toString()],
    );
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
    if (selectedDate.isAfter(DateTime.now())) {
      selectedDate = DateTime.now();
    }
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

  Future<void> _speichern(BuildContext context) async {
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

    await database.insert('tierbewegungen', newRecord);

    final baselineResult = await database.rawQuery(
      "SELECT tierbestand FROM tierbewegungen "
          "WHERE stallname = ? AND date < ? "
          "ORDER BY date DESC LIMIT 1",
      [widget.stallname, selectedDate.toString()],
    );
    int baseline = 0;
    if (baselineResult.isNotEmpty) {
      baseline = baselineResult.first['tierbestand'] as int;
    }

    final subsequentRecords = await database.rawQuery(
      "SELECT * FROM tierbewegungen "
          "WHERE stallname = ? AND date >= ? "
          "ORDER BY date ASC, id ASC",
      [widget.stallname, selectedDate.toString()],
    );

    int cumulative = baseline;
    for (var record in subsequentRecords) {
      int recordAnzahl = record['anzahl'] as int;
      String zugangAbgang = record['zugang_abgang'] as String;
      int recordMovement = (zugangAbgang == 'Zugang') ? recordAnzahl : -recordAnzahl;
      cumulative += recordMovement;

      int recordId = record['id'] as int;
      await database.update(
        'tierbewegungen',
        {'tierbestand': cumulative},
        where: 'id = ?',
        whereArgs: [recordId],
      );
    }

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
    final Color fabColor = (_newCount > 0)
        ? Theme.of(context).colorScheme.primary
        : Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: Text('Tierbewegung: ${widget.stallname.split("#")[1]}'),
        elevation: 5.0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
              child: Column(
                children: [
                  // Aktuelle Tierzahl
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 12),
                      Text(
                        'Aktuelle Tierzahl: $_currentCount',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  // Toggle Buttons für Zugang/Abgang
                  ToggleButtons(
                    isSelected: [_isZugang, !_isZugang],
                    onPressed: (index) {
                      setState(() {
                        _isZugang = index == 0;
                        if (_isZugang) _isToggleOn = false;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    selectedColor: Theme.of(context).colorScheme.onPrimary,
                    color: Theme.of(context).colorScheme.onSurface,
                    fillColor: Theme.of(context).colorScheme.primaryContainer,
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text('Zugang', style: TextStyle(fontSize: 16)),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text('Abgang', style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  // Eingabefeld für Tierbewegung
                  TextFormField(
                    decoration: const InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: 'Tierbewegung',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 18),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _newCount = int.tryParse(value) ?? 0;
                      });
                    },
                  ),
                  const Divider(height: 32),

                  // Kommentar-Eingabe (multiline, min 3 Zeilen, max 5 Zeilen)
                  TextFormField(
                    decoration: const InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: 'Zusatzkommentar (optional)',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 18),
                    keyboardType: TextInputType.multiline,
                    minLines: 2,
                    maxLines: 5,
                    onChanged: (newValue) {
                      setState(() {
                        _selectedComment = newValue.toString();
                      });
                    },
                  ),
                  const Divider(height: 32),

                  // Switch für Verendung
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 12),
                      const Text('Verendung', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
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
                  const Divider(height: 32),

                  // Datumsauswahl
                  ListTile(
                    leading: const Icon(Icons.calendar_today, size: 28),
                    title: Text(
                      "${selectedDate.toLocal()}".split(' ')[0],
                      style: const TextStyle(fontSize: 18),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, size: 28),
                      onPressed: () => _selectDate(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: (_newCount > 0) ? () => _updateCount(context) : null,
        backgroundColor: fabColor,
        tooltip: 'Speichern',
        child: const Icon(Icons.save),
      ),
    );
  }
}
