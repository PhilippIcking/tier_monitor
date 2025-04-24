import 'package:flutter/material.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; //Android, IOS, MACOS
import 'package:path/path.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  _HistoryPageState createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _entries = [];
  String _currentTable = 'tierdoku'; // Initial ist die Tabelle "tierdoku"

  @override
  void initState() {
    super.initState();
    _fetchEntriesFromDatabase();
  }

  Future<void> _fetchEntriesFromDatabase() async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);

    // Abhängig von der aktuellen Tabelle die entsprechenden Einträge abrufen
    List<Map<String, dynamic>> entries = await database.rawQuery(
      'SELECT * FROM $_currentTable ORDER BY id DESC LIMIT 50',
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
              _fetchEntriesFromDatabase();
            },
          ),
        ],
      ),
      body: ListView.builder(
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
                        ? " - Bucht: ${_entries[index]['bucht']} ${_entries[index]['farbe']} ${_entries[index]['symptome']}"
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
                  title: Text("Symptom: ${_entries[index]['symptome']}"),
                ),
              if (_entries[index]['medikament'] != null)
                ListTile(
                  title:
                  Text("Erstmedikation: ${_entries[index]['medikament']}"),
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
              if (_entries[index]['tierbestand'] != null)
                ListTile(
                  title:
                  Text("Gesamtbestand: ${_entries[index]['tierbestand']}"),
                ),
              if (_entries[index]['comment'] != null &&
                  _entries[index]['comment'] != "")
                ListTile(
                  title: Text("Kommentar: ${_entries[index]['comment']}"),
                ),
              if (_entries[index]['second_medikament'] != null)
                ListTile(
                  title: Text(
                      "Zweitmedikation: ${_entries[index]['second_medikament']}"),
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
                  title: Text(
                      "Drittmedikation: ${_entries[index]['third_medikament']}"),
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
    );
  }
}