import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _symptomController = TextEditingController();
  final TextEditingController _medicationController = TextEditingController();
  List<String> _symptoms = [];
  List<String> _medications = [];

  @override
  void initState() {
    super.initState();
    _loadSymptoms();
    _loadMedications();
  }

  Future<void> _loadSymptoms() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _symptoms = prefs.getStringList('symptoms') ?? [];
    });
  }

  Future<void> _loadMedications() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _medications = prefs.getStringList('medications') ?? [];
    });
  }

  Future<void> _saveSymptoms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('symptoms', _symptoms);
  }

  Future<void> _saveMedications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('medications', _medications);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _symptomController,
              decoration: InputDecoration(
                hintText: 'Symptom hinzufügen',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    setState(() {
                      _symptoms.add(_symptomController.text);
                      _symptomController.clear();
                      _saveSymptoms();
                    });
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _symptoms.length,
              itemBuilder: (BuildContext context, int index) {
                final symptom = _symptoms[index];
                return ListTile(
                  title: Text(symptom),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text("Löschen bestätigen"),
                            content: Text(
                                "Bist du dir sicher, dass du \"$symptom\" wirklich löschen möchtest?"),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context)
                                      .pop(); // Schließen Sie den Dialog
                                },
                                child: const Text("Abbrechen"),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _symptoms.removeAt(index);
                                    _saveSymptoms();
                                  });
                                  Navigator.of(context)
                                      .pop(); // Schließen Sie den Dialog
                                },
                                child: const Text("Löschen"),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _medicationController,
              decoration: InputDecoration(
                hintText: 'Medikament hinzufügen',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    setState(() {
                      _medications.add(_medicationController.text);
                      _medicationController.clear();
                      _saveMedications();
                    });
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _medications.length,
              itemBuilder: (BuildContext context, int index) {
                final medication = _medications[index];
                return ListTile(
                  title: Text(medication),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text("Löschen bestätigen"),
                            content: Text(
                                "Bist du dir sicher, dass du \"$medication\" löschen möchtest?"),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context)
                                      .pop(); // Schließen Sie den Dialog
                                },
                                child: const Text("Abbrechen"),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _medications.removeAt(index);
                                    _saveMedications();
                                  });
                                  Navigator.of(context)
                                      .pop(); // Schließen Sie den Dialog
                                },
                                child: const Text("Löschen"),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
