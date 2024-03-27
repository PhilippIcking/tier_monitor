import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; //Android, IOS, MACOS
import 'package:path/path.dart';

class ChangeLocation extends StatefulWidget {
  final int entryId; // Hinzufügen der entryId
  final String stallname;

  const ChangeLocation(
      {super.key, required this.entryId, required this.stallname});

  @override
  _ChangeLocationState createState() => _ChangeLocationState();
}

class _ChangeLocationState extends State<ChangeLocation> {
  String _selectedNewLocation = '';
  bool _buttonPressed = false;
  DateTime selectedDate = DateTime.now();
  bool _isToggleOn = true;
  List<String> _locations = [];

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: selectedDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final widgetNames = prefs.getStringList('widget_names') ?? [];
    List<String> locationNames = [];

    for (String w in widgetNames) {
      // Specify the type of 'w' as String
      final locationList = prefs.getStringList(w) ??
          []; // Retrieve location list for the current widget
      locationNames
          .addAll(locationList); // Add all locations to locationNames list
      locationNames.remove(widget.stallname);
    }

    setState(() {
      _locations = locationNames;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Umstallen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField(
              value:
                  _selectedNewLocation.isNotEmpty ? _selectedNewLocation : null,
              items: _locations.map((newlocation) {
                return DropdownMenuItem(
                  value: newlocation,
                  child: Text(newlocation.replaceAll('#', '-')),
                );
              }).toList(),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Umstallen nach',
                hintText: 'Stall auswählen',
                border: OutlineInputBorder(),
              ),
              onChanged: (newValue) {
                setState(() {
                  _selectedNewLocation = newValue.toString();
                });
              },
            ),
            const SizedBox(height: 16.0),
            Text("${selectedDate.toLocal()}".split(' ')[0]),
            const SizedBox(
              height: 16.0,
            ),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              child: const Text('Datum ändern'),
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                const Text('Umstallen in Tierbewegungen übertragen'),
                Switch(
                  value: _isToggleOn,
                  onChanged: (value) {
                    setState(() {
                      _isToggleOn = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: _selectedNewLocation != '' && !_buttonPressed
                  ? () {
                      setState(() {
                        _buttonPressed = true;
                      });
                      updateEntry(widget.entryId, _selectedNewLocation,
                          selectedDate, _isToggleOn);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Daten erfolgreich gespeichert'),
                        ),
                      );
                    }
                  : null,
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  // Funktion zum Aktualisieren eines Eintrags in der Datenbank
  Future<void> updateEntry(
      int entryId, String newLocation, DateTime endDate, bool update) async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);

    // SQL-Abfrage, um den letzten Eintrag für den gegebenen Stallnamen zu erhalten
    List<Map<String, dynamic>> lastEntry = await database.rawQuery(
      'SELECT * FROM tierbewegungen WHERE stallname = ? ORDER BY id DESC LIMIT 1',
      [widget.stallname],
    );

    // Überprüfen, ob ein Eintrag gefunden wurde

    if (lastEntry.isNotEmpty) {
      // Den Tierbestand aus dem letzten Eintrag extrahieren
      int lastTierbestand = lastEntry[0]['tierbestand'];

      if (update) {
        final prefs = await SharedPreferences.getInstance();
        var currentCount = prefs.getInt(widget.stallname) ?? 0;
        await prefs.setInt(widget.stallname, currentCount - 1);

        await database.insert('tierbewegungen', {
          'stallname': widget.stallname,
          'anzahl': 1,
          'zugang_abgang': 'Abgang',
          'tierbestand': lastTierbestand - 1,
          'comment': 'Umgestallt nach ${newLocation.replaceAll('#', '-')}',
          'date': endDate.toString(),
          'end': '',
        });
      }
    }

    // SQL-Abfrage, um den letzten Eintrag für den gegebenen Stallnamen zu erhalten
    List<Map<String, dynamic>> lastEntryNewLocation = await database.rawQuery(
      'SELECT * FROM tierbewegungen WHERE stallname = ? ORDER BY id DESC LIMIT 1',
      [newLocation],
    );

    // Überprüfen, ob ein Eintrag gefunden wurde

    if (lastEntryNewLocation.isNotEmpty) {
      // Den Tierbestand aus dem letzten Eintrag extrahieren
      int lastTierbestand = lastEntryNewLocation[0]['tierbestand'];

      if (update) {
        final prefs = await SharedPreferences.getInstance();
        var currentCount = prefs.getInt(newLocation) ?? 0;
        await prefs.setInt(newLocation, currentCount + 1);

        await database.insert('tierbewegungen', {
          'stallname': newLocation,
          'anzahl': 1,
          'zugang_abgang': 'Zugang',
          'tierbestand': lastTierbestand + 1,
          'comment': 'Umgestallt von ${widget.stallname.replaceAll('#', '-')}',
          'date': endDate.toString(),
          'end': '',
        });
      }
    }

    final List<Map<String, dynamic>> currentData = await database.query(
      'tierdoku',
      columns: ['comment'],
      where: 'id = ?', // Bedingung: ID
      whereArgs: [entryId], // Wert: ID
    );

    // Den alten Kommentarwert aus dem aktuellen Daten-Map extrahieren
    final String oldComment =
        currentData.isNotEmpty ? currentData.first['comment'] : '';

    // Den neuen Kommentarwert zusammensetzen, indem der alte Wert beibehalten und der neue Wert angefügt wird
    final String newComment =
        '$oldComment\nUmgestallt am ${endDate.toString().substring(0, 10)} von ${widget.stallname.toString().replaceAll('#', '-')} nach ${newLocation.replaceAll('#', '-')}';

    await database.update(
      'tierdoku', // Tabellenname
      {
        'stallname': newLocation, // Neue Stallname-Wert
        'comment': newComment
      },
      where: 'id = ?', // Bedingung: ID
      whereArgs: [entryId], // Wert: ID
    );

    await database.close();

    ScaffoldMessenger.of(context as BuildContext).showSnackBar(
      const SnackBar(
        content: Text('Daten erfolgreich gespeichert'),
      ),
    );
  }
}
