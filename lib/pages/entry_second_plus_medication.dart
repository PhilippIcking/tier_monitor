import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; //Android, IOS, MACOS
import 'package:path/path.dart';

class EntryPageSecondMedikation extends StatefulWidget {
  final int entryId;

  const EntryPageSecondMedikation({super.key, required this.entryId});

  @override
  _EntryPageSecondMedikationState createState() =>
      _EntryPageSecondMedikationState();
}

class _EntryPageSecondMedikationState extends State<EntryPageSecondMedikation> {
  // Hinzufügen der benötigten Controller und Variablen für die Medikation
  final TextEditingController _medikationController = TextEditingController();

  String _selectedMedikament = '';
  String _selectedComment = '';
  DateTime selectedDate = DateTime.now();
  List<String> _medikamente = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadMedications();
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
        lastDate: DateTime(2100));
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zweitmedikation eintragen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField(
              value:
              _selectedMedikament.isNotEmpty ? _selectedMedikament : null,
              items: _medikamente.map((medikament) {
                return DropdownMenuItem(
                  value: medikament,
                  child: Text(medikament),
                );
              }).toList(),
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
              onChanged: (newValue) {
                setState(() {
                  _selectedComment = newValue.toString();
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
            ElevatedButton(
              onPressed: () {
                updateEntry(widget.entryId, _selectedMedikament,
                    _selectedComment, selectedDate);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Daten erfolgreich gespeichet')),
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  // Funktion zum Aktualisieren eines Eintrags in der Datenbank
  Future<void> updateEntry(int entryId, String secondMedi, String secondComment,
      DateTime secondDate) async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);

    // Ausführen der Update-Abfrage, um das Kommentarfeld und das Datumsfeld zu aktualisieren
    await database.update(
      'tierdoku', // Tabellenname
      {
        'second_medikament': secondMedi,
        'second_comment': secondComment,
        'second_date': secondDate.toString()
      }, // Aktualisierte Daten
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

  @override
  void dispose() {
    _medikationController.dispose();
    super.dispose();
  }
}

class EntryPageThirdMedikation extends StatefulWidget {
  final int entryId; // Hinzufügen der entryId

  const EntryPageThirdMedikation({super.key, required this.entryId});

  @override
  _EntryPageThirdMedikationState createState() =>
      _EntryPageThirdMedikationState(); // Correcting the generic type here
}

class _EntryPageThirdMedikationState extends State<EntryPageThirdMedikation> {
  final TextEditingController _medikationController = TextEditingController();

  String _selectedMedikament = '';
  String _selectedComment = '';
  DateTime selectedDate = DateTime.now();
  List<String> _medikamente = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadMedications();
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
        lastDate: DateTime(2100));
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drittmedikation Eintragen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField(
              value:
              _selectedMedikament.isNotEmpty ? _selectedMedikament : null,
              items: _medikamente.map((medikament) {
                return DropdownMenuItem(
                  value: medikament,
                  child: Text(medikament),
                );
              }).toList(),
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
              onChanged: (newValue) {
                setState(() {
                  _selectedComment = newValue.toString();
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
            ElevatedButton(
              onPressed: () {
                updateEntry(widget.entryId, _selectedMedikament,
                    _selectedComment, selectedDate);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Daten erfolgreich gespeichet')),
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  // Funktion zum Aktualisieren eines Eintrags in der Datenbank
  Future<void> updateEntry(int entryId, String thirdMedi, String thirdComment,
      DateTime thirdDate) async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);

    // Ausführen der Update-Abfrage, um das Kommentarfeld und das Datumsfeld zu aktualisieren
    await database.update(
      'tierdoku', // Tabellenname
      {
        'third_medikament': thirdMedi,
        'third_comment': thirdComment,
        'third_date': thirdDate.toString()
      }, // Aktualisierte Daten
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

  @override
  void dispose() {
    _medikationController.dispose();
    super.dispose();
  }
}

class EntryPageEnd extends StatefulWidget {
  final int entryId; // Hinzufügen der entryId
  final String stallname;

  const EntryPageEnd(
      {super.key, required this.entryId, required this.stallname});

  @override
  _EntryPageEndState createState() =>
      _EntryPageEndState();
}

class _EntryPageEndState extends State<EntryPageEnd> {

  String _selectedComment = '';
  DateTime selectedDate = DateTime.now();
  bool _isToggleOn = true;

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verendung eintragen'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextFormField(
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
                const Text('Verendung in Tierbewegungen übertragen'),
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
              onPressed: () {
                updateEntry(widget.entryId, _selectedComment, selectedDate,
                    _isToggleOn);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Daten erfolgreich gespeichert')),
                );
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  // Funktion zum Aktualisieren eines Eintrags in der Datenbank
  Future<void> updateEntry(
      int entryId, String endComment, DateTime endDate, bool update) async {
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path);

    // Ausführen der Update-Abfrage, um das Kommentarfeld und das Datumsfeld zu aktualisieren
    await database.update(
      'tierdoku', // Tabellenname
      {'end_comment': endComment, 'end_date': endDate.toString()},
      // Aktualisierte Daten
      where: 'id = ?', // Bedingung: ID
      whereArgs: [entryId], // Wert: ID
    );

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
          'comment': '',
          'date': endDate.toString(),
          'end': 'Verendung',
        });
      }
    }
    await database.close();

    ScaffoldMessenger.of(context as BuildContext).showSnackBar(
      const SnackBar(
        content: Text('Daten erfolgreich gespeichert'),
      ),
    );
  }
}