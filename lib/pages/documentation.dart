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
    _medikamente =
        prefs.getStringList('medications') ?? ['Gehe zu Einstellungen'];
    _farben = prefs.getStringList('farben') ?? ['Gehe zu Einstellungen'];

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

  Future<void> _addNewSymptom(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final prefs = await SharedPreferences.getInstance();

    final String? newSymptom = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Neues Symptom hinzufügen'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Symptom eingeben...',
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
        );
      },
    );

    if (newSymptom != null && newSymptom.isNotEmpty) {
      _symptome.add(newSymptom);
      await prefs.setStringList('symptoms', _symptome);
      setState(() {
        _selectedSymptom = newSymptom;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Symptom "$newSymptom" hinzugefügt')),
      );
    }
  }

  Future<void> _addNewMedikament(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final prefs = await SharedPreferences.getInstance();

    final String? newMedikament = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
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
        );
      },
    );

    if (newMedikament != null && newMedikament.isNotEmpty) {
      _medikamente.add(newMedikament);
      await prefs.setStringList('medications', _medikamente);
      setState(() {
        _selectedMedikament = newMedikament;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Medikament "$newMedikament" hinzugefügt')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canSave = _selectedBucht.isNotEmpty;
    final Color fabColor =
    canSave ? Theme.of(context).colorScheme.primary : Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: Text('Dokumentation: ${widget.stallname.split("#")[1]}'),
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
              padding:
              const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dropdown für Bucht
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
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (newValue) {
                      setState(() {
                        _selectedBucht = newValue.toString();
                      });
                    },
                  ),
                  const Divider(height: 32),

                  DropdownButtonFormField<String>(
                    value: _selectedSymptom.isNotEmpty ? _selectedSymptom : null,
                    items: [
                      ..._symptome.map(
                            (symptom) => DropdownMenuItem(
                          value: symptom,
                          child: Text(symptom),
                        ),
                      ),
                      const DropdownMenuItem<String>(
                        value: '__add_new_symptom__',
                        child: Row(
                          children: [
                            Icon(Icons.add, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Neues Symptom hinzufügen'),
                          ],
                        ),
                      ),
                    ],
                    decoration: const InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: 'Symptom',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (newValue) async {
                      if (newValue == '__add_new_symptom__') {
                        await _addNewSymptom(context);
                      } else {
                        setState(() {
                          _selectedSymptom = newValue ?? '';
                        });
                      }
                    },
                  ),
                  const Divider(height: 32),

                  // Dropdown für Medikament mit Schnell-Hinzufügen
                  DropdownButtonFormField<String>(
                    value: _selectedMedikament.isNotEmpty
                        ? _selectedMedikament
                        : null,
                    items: [
                      ..._medikamente.map(
                            (medikament) => DropdownMenuItem(
                          value: medikament,
                          child: Text(medikament),
                        ),
                      ),
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
                    decoration: const InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: 'Medikament',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (newValue) async {
                      if (newValue == '__add_new_medikament__') {
                        await _addNewMedikament(context);
                      } else {
                        setState(() {
                          _selectedMedikament = newValue ?? '';
                        });
                      }
                    },
                  ),
                  const Divider(height: 32),

                  // Dropdown für Farbe
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
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (newValue) {
                      setState(() {
                        _selectedFarbe = newValue.toString();
                      });
                    },
                  ),
                  const Divider(height: 32),

                  TextFormField(
                    decoration: const InputDecoration(
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: 'Zusatz (optional)',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 18),
                    keyboardType: TextInputType.multiline,
                    minLines: 2,
                    maxLines: 5,
                    onChanged: (newValue) {
                      setState(() {
                        _selectedComment = newValue;
                      });
                    },
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
        onPressed: canSave ? () => _speichern(context) : null,
        backgroundColor: fabColor,
        tooltip: 'Speichern',
        child: const Icon(Icons.save),
      ),
    );
  }
}
