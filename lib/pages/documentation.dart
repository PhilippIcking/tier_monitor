import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; //Android, IOS, MACOS
import 'package:path/path.dart';

class Tiermassnahme extends StatefulWidget {
  final String stallname;

  const Tiermassnahme({super.key, required this.stallname});

  @override
  _TiermassnahmeState createState() => _TiermassnahmeState();
}

class _TiermassnahmeState extends State<Tiermassnahme> {
  final List<String> _buchten = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15',
    '16'
  ];

  List<String> _symptome = [];
  List<String> _medikamente = [];
  final List<String> _farben = ['blau', 'rot', 'grün'];
  DateTime selectedDate = DateTime.now();

  String _selectedBucht = '';
  String _selectedSymptom = '';
  String _selectedMedikament = '';
  String _selectedFarbe = '';
  String _selectedComment = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _loadSymptoms();
    await _loadMedications();
  }

  Future<void> _loadSymptoms() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _symptome = prefs.getStringList('symptoms') ?? [];
    });
  }

  Future<void> _loadMedications() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _medikamente = prefs.getStringList('medications') ?? [];
    });
  }

  Future<void> _speichern(BuildContext context) async {
    final bucht = _selectedBucht;
    final symptome = _selectedSymptom;
    final medikament = _selectedMedikament;
    final farbe = _selectedFarbe;
    final comment = _selectedComment;
    final date = selectedDate.toString();

    // Pfad zur Datenbankdatei erstellen
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');

    // Datenbank öffnen bzw. erstellen
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
    await database.insert('tierdoku', {
      'stallname': widget.stallname,
      'bucht': bucht,
      'symptome': symptome,
      'medikament': medikament,
      'farbe': farbe,
      'comment': comment,
      'date': date,
    });

    // Datenbankverbindung schließen
    await database.close();
    _showFeedback(context);
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

  void _showFeedback(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Die Daten wurden erfolgreich gespeichert')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Dokumentation: ${widget.stallname.split("#")[1]}'),
      ),
      body: Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            DropdownButtonFormField(
              value: _selectedBucht.isNotEmpty ? _selectedBucht : null,
              items: _buchten.map((bucht) {
                return DropdownMenuItem(
                  value: bucht,
                  child: Text(bucht),
                );
              }).toList(),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Bucht',
                hintText: 'keine',
                border: OutlineInputBorder(),
              ),
              onChanged: (newValue) {
                setState(() {
                  _selectedBucht = newValue.toString();
                });
              },
            ),
            const SizedBox(height: 16.0),
            DropdownButtonFormField(
              value: _selectedSymptom.isNotEmpty ? _selectedSymptom : null,
              items: _symptome.map((symptom) {
                return DropdownMenuItem(
                  value: symptom,
                  child: Text(symptom),
                );
              }).toList(),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Symptom',
                hintText: 'keine',
                border: OutlineInputBorder(),
              ),
              onChanged: (newValue) {
                setState(() {
                  _selectedSymptom = newValue.toString();
                });
              },
            ),
            const SizedBox(height: 16.0),
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
            DropdownButtonFormField(
              value: _selectedFarbe.isNotEmpty ? _selectedFarbe : null,
              items: _farben.map((farbe) {
                return DropdownMenuItem(
                  value: farbe,
                  child: Text(farbe),
                );
              }).toList(),
              decoration: const InputDecoration(
                floatingLabelBehavior: FloatingLabelBehavior.always,
                labelText: 'Farbe',
                hintText: 'keine',
                border: OutlineInputBorder(),
              ),
              onChanged: (newValue) {
                setState(() {
                  _selectedFarbe = newValue.toString();
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
              onPressed: () => _speichern(context),
              child: const Text('Eintrag speichern'),
            ),
          ],
        ),
      ),
    );
  }
}