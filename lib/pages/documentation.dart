import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

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
  String _selectedFarbe = '';
  String _selectedComment = '';

  List<String> _selectedSymptome = [];
  List<String> _selectedMedikamente = [];
  String? _dropdownSymptomValue;
  String? _dropdownMedikamentValue;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _buchten = prefs.getStringList('buchten') ?? List.generate(16, (i) => (i + 1).toString());
    _symptome = prefs.getStringList('symptoms') ?? [];
    _medikamente =
        prefs.getStringList('medications') ?? [];
    _farben = prefs.getStringList('farben') ?? ['Rot', 'Grün', 'Blau'];

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
    final symptome = jsonEncode(_selectedSymptome);
    final medikamente = jsonEncode(_selectedMedikamente);
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
      'medikament': medikamente,
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
        _selectedSymptome.add(newSymptom);
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
        _selectedMedikamente.add(newMedikament);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Medikament "$newMedikament" hinzugefügt')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canSave = _selectedBucht.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;
    final Color fabColor = canSave
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.38);

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

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Symptome',
                          border: OutlineInputBorder(),
                          floatingLabelBehavior:
                          FloatingLabelBehavior.always,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_selectedSymptome.isNotEmpty)
                              Wrap(
                                spacing: 8.0,
                                runSpacing: 4.0,
                                children: _selectedSymptome.map((symptom) {
                                  return Chip(
                                    label: Text(symptom),
                                    deleteIcon: const Icon(Icons.close),
                                    onDeleted: () {
                                      setState(() {
                                        _selectedSymptome.remove(symptom);
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            DropdownButton<String>(
                              value: _dropdownSymptomValue,
                              isExpanded: true,
                              underline: Container(),
                              items: [
                                ..._symptome.map(
                                      (symptom) => DropdownMenuItem(
                                    value: symptom,
                                    child: Text(symptom),
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: '__add_new_symptom__',
                                  child: Row(
                                    children: [
                                      Icon(Icons.add, color: colorScheme.primary),
                                      SizedBox(width: 8),
                                      Text('Neues Symptom hinzufügen'),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;

                                if (value == '__add_new_symptom__') {
                                  await _addNewSymptom(context);
                                } else if (!_selectedSymptome.contains(value)) {
                                  setState(() {
                                    _selectedSymptome.add(value);
                                  });
                                }

                                setState(() {
                                  _dropdownSymptomValue = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Behandlung',
                          border: OutlineInputBorder(),
                          floatingLabelBehavior:
                          FloatingLabelBehavior.always,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_selectedMedikamente.isNotEmpty)
                              Wrap(
                                spacing: 8.0,
                                runSpacing: 4.0,
                                children:
                                _selectedMedikamente.map((medikament) {
                                  return Chip(
                                    label: Text(medikament),
                                    deleteIcon: const Icon(Icons.close),
                                    onDeleted: () {
                                      setState(() {
                                        _selectedMedikamente.remove(medikament);
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            DropdownButton<String>(
                              value: _dropdownMedikamentValue,
                              isExpanded: true,
                              underline: Container(),
                              items: [
                                ..._medikamente.map(
                                      (medikament) => DropdownMenuItem(
                                    value: medikament,
                                    child: Text(medikament),
                                  ),
                                ),
                                DropdownMenuItem<String>(
                                  value: '__add_new_medikament__',
                                  child: Row(
                                    children: [
                                      Icon(Icons.add, color: colorScheme.secondary),
                                      SizedBox(width: 8),
                                      Text('Neues Medikament hinzufügen'),
                                    ],
                                  ),
                                ),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;

                                if (value == '__add_new_medikament__') {
                                  await _addNewMedikament(context);
                                } else if (!_selectedMedikamente
                                    .contains(value)) {
                                  setState(() {
                                    _selectedMedikamente.add(value);
                                  });
                                }

                                setState(() {
                                  _dropdownMedikamentValue = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),

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
                      labelText: 'Makierung',
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
                      labelText: 'Kommentar',
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
