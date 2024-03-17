import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; //Android, IOS, MACOS
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

  void _updateCount(BuildContext context) {
    setState(() {
      int updatedCount;

      if (_isZugang) {
        updatedCount = _currentCount + _newCount;
      } else {
        updatedCount = _currentCount - _newCount;
      }

      if (updatedCount < 0) {
        // Fehlermeldung negative Tierzahl
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Die Anzahl darf nicht negativ sein'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        _speichern(context);
        _currentCount = updatedCount;
        _newCount = 0;
        _saveCount();
        _showFeedback(context);
      }
    });
  }

  DateTime selectedDate = DateTime.now();

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
    final anzahl = _newCount;
    final zugangAbgang = _isZugang ? 'Zugang' : 'Abgang';
    final tierbestand =
    _isZugang ? _currentCount + _newCount : _currentCount - _newCount;
    final comment = _selectedComment;
    final date = selectedDate.toString();
    final end = _isToggleOn ? 'Verendung' : '';

    // Pfad zur Datenbankdatei erstellen
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');

    Database database = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        // Tabelle "tierdoku" erstellen
        await db.execute('CREATE TABLE tierdoku ('
            'id INTEGER PRIMARY KEY,'
            'stallname TEXT,'
            'bucht TEXT,'
            'symptome TEXT,'
            'medikament TEXT,'
            'farbe TEXT,'
            'comment TEXT,'
            'date TEXT,'
            'second_medikament TEXT,'
            'second_comment TEXT,'
            'second_date TEXT,'
            'third_medikament TEXT,'
            'third_comment TEXT,'
            'third_date TEXT,'
            'end_comment TEXT,'
            'end_date TEXT'
            ')');

        // Tabelle "tierbewegungen" erstellen
        await db.execute('CREATE TABLE tierbewegungen ('
            'id INTEGER PRIMARY KEY,'
            'stallname TEXT,'
            'anzahl INTEGER,'
            'zugang_abgang TEXT,'
            'tierbestand INTEGER,'
            'comment TEXT,'
            'date TEXT,'
            'end TEXT'
            ')');
      },
    );

    // Daten in die Tabelle einfügen
    await database.insert('tierbewegungen', {
      'stallname': widget.stallname,
      'anzahl': anzahl,
      'zugang_abgang': zugangAbgang,
      'tierbestand': tierbestand,
      'comment': comment,
      'date': date,
      'end': end,
    });
    await database.close();
  }

  void _showFeedback(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Die Daten wurden erfolgreich gespeichert')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tierbewegung: ${widget.stallname.split("#")[1]}'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Aktuelle Anzahl: $_currentCount',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ToggleButtons(
                  isSelected: [_isZugang, !_isZugang],
                  onPressed: (index) {
                    setState(() {
                      _isZugang = index == 0;
                      if (_isZugang) {
                        _isToggleOn =
                        false;
                      }
                    });
                  },
                  children: const [
                    Text('Zugang'),
                    Text('Abgang'),
                  ],
                ),
                const SizedBox(height: 16.0),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
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
                const SizedBox(
                  height: 16.0,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 8.0),
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
                const SizedBox(
                  height: 16.0,
                ),
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
          ElevatedButton(
            onPressed: _newCount > 0 ? () => _updateCount(context) : null,
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}