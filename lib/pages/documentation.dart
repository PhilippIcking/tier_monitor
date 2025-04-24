import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class Tiermassnahme extends StatefulWidget {
  final String stallname;

  const Tiermassnahme({super.key, required this.stallname});

  @override
  _TiermassnahmeState createState() => _TiermassnahmeState();
}

class _TiermassnahmeState extends State<Tiermassnahme> {
    List<String> _buchten = [];
  List<String> _symptome = [];
  List<String> _medikamente = [];
  List<String> _farben = [];
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
      final prefs = await SharedPreferences.getInstance();
      _buchten = prefs.getStringList('buchten') ?? ['Gehe zu Einstellungen'];
      _symptome = prefs.getStringList('symptoms') ?? ['Gehe zu Einstellungen'];
      _medikamente = prefs.getStringList('medications') ?? ['Gehe zu Einstellungen'];
      _farben      = prefs.getStringList('farben')    ?? ['Gehe zu Einstellungen'];

      setState(() {});
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
    final bucht = _selectedBucht;
    final symptome = _selectedSymptom;
    final medikament = _selectedMedikament;
    final farbe = _selectedFarbe;
    final comment = _selectedComment;
    final date = selectedDate.toString();

    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    Database database = await openDatabase(path, version: 1);
    await database.insert('tierdoku', {
      'stallname': widget.stallname,
      'bucht': bucht,
      'symptome': symptome,
      'medikament': medikament,
      'farbe': farbe,
      'comment': comment,
      'date': date,
    });
    await database.close();
    _showFeedback(context);
  }

  void _showFeedback(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Die Daten wurden erfolgreich gespeichert')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canSave = _selectedBucht.isNotEmpty;
    final Color fabColor = canSave
        ? Theme.of(context).colorScheme.primary
        : Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: Text('Dokumentation: ${widget.stallname.split("#")[1]}'),
        elevation: 5.0,
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              DropdownButtonFormField(
                value: _selectedBucht.isNotEmpty ? _selectedBucht : null,
                items: _buchten
                    .map((bucht) => DropdownMenuItem(
                  value: bucht,
                  child: Text(bucht),
                ))
                    .toList(),
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
                items: _symptome
                    .map((symptom) => DropdownMenuItem(
                  value: symptom,
                  child: Text(symptom),
                ))
                    .toList(),
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
                value: _selectedMedikament.isNotEmpty ? _selectedMedikament : null,
                items: _medikamente
                    .map((medikament) => DropdownMenuItem(
                  value: medikament,
                  child: Text(medikament),
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
              DropdownButtonFormField(
                value: _selectedFarbe.isNotEmpty ? _selectedFarbe : null,
                items: _farben
                    .map((farbe) => DropdownMenuItem(
                  value: farbe,
                  child: Text(farbe),
                ))
                    .toList(),
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
              const SizedBox(height: 16.0),
              ElevatedButton(
                onPressed: () => _selectDate(context),
                child: const Text('Datum ändern'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: canSave
            ? () {
          _speichern(context);
        }
            : null,
        backgroundColor: fabColor,
        tooltip: 'Speichern',
        child: const Icon(Icons.save),
      ),
    );
  }
}
