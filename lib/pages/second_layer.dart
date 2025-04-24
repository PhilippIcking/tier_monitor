import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tier_monitor/pages/change_amount.dart';
import 'package:tier_monitor/pages/documentation.dart';
import 'package:tier_monitor/pages/history_individual.dart';

class WidgetCreator extends StatefulWidget {
  final String name;

  const WidgetCreator({super.key, required this.name});

  @override
  _WidgetCreatorState createState() => _WidgetCreatorState();
}

class _WidgetCreatorState extends State<WidgetCreator> {
  List<String> _subWidgetNames = [];

  @override
  void initState() {
    super.initState();
    _loadSubWidgetNames();
  }

  void _loadSubWidgetNames() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final subWidgetNames = prefs.getStringList(widget.name) ?? [];
    setState(() {
      _subWidgetNames = subWidgetNames;
    });
  }

  void _saveSubWidgetNames() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList(widget.name, _subWidgetNames);
  }

  void _addNewSubWidget(String name) {
    setState(() {
      _subWidgetNames.add(name);
    });
    _saveSubWidgetNames();
  }

  void _showDeleteConfirmationDialogSubWidget(
      BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Löschen bestätigen'),
          content: Text(
              'Bist du dir sicher, dass du ${name.split("#")[1]} löschen möchtest?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _removeSubWidget(name);
              },
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );
  }

  void _removeSubWidget(String name) {
    setState(() {
      _subWidgetNames.remove(name);
    });
    _saveSubWidgetNames();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        elevation: 5.0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(top: 5.0),
        itemCount: _subWidgetNames.length,
        itemBuilder: (BuildContext context, int index) {
          final String stallFullName = _subWidgetNames[index];
          final String stallName = stallFullName.split("#")[1];
          return ExpansionTile(
            title: Center(child: Text(stallName)),
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Lösch-Icon als erstes Element
                    Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: 'Löschen',
                          onPressed: () {
                            _showDeleteConfirmationDialogSubWidget(
                                context, stallFullName);
                          },
                        ),
                        const Text('Löschen',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    // Tierbewegung
                    Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.trending_up),
                          tooltip: 'Tierbewegung',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    Tierbewegung(stallname: stallFullName),
                              ),
                            );
                          },
                        ),
                        const Text('Tierbewegung',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    // Dokumentation
                    Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.assignment),
                          tooltip: 'Dokumentation',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    Tiermassnahme(stallname: stallFullName),
                              ),
                            );
                          },
                        ),
                        const Text('Dokumentation',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    // Verlauf
                    Column(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.history),
                          tooltip: 'Verlauf',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    HistoryPageSecondMedikation(
                                        stallname: stallFullName),
                              ),
                            );
                          },
                        ),
                        const Text('Verlauf',
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final name = await showDialog<String>(
            context: context,
            builder: (BuildContext context) {
              final nameController = TextEditingController();
              return AlertDialog(
                title: const Text('Stall hinzufügen'),
                content: TextField(
                  controller: nameController,
                  decoration: const InputDecoration(hintText: 'Name Stall'),
                  autofocus: true,
                ),
                actions: [
                  TextButton(
                    child: const Text('Abbruch'),
                    onPressed: () {
                      Navigator.pop(context, null);
                    },
                  ),
                  TextButton(
                    child: const Text('Hinzufügen'),
                    onPressed: () {
                      final value = nameController.value.text;
                      Navigator.pop(context, value);
                    },
                  ),
                ],
              );
            },
          );
          if (name != null && name.isNotEmpty) {
            _addNewSubWidget("${widget.name}#$name");
          }
        },
      ),
    );
  }
}
