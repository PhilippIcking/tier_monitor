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

  void _removeSubWidget(String fullName) {
    setState(() {
      _subWidgetNames.remove(fullName);
    });
    _saveSubWidgetNames();
  }

  Future<bool?> _confirmDelete(BuildContext context, String fullName) {
    final stallLabel = fullName.split("#")[1];
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Löschen bestätigen'),
          content:
          Text('Bist du dir sicher, dass du "$stallLabel" löschen möchtest?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeleteConfirmationDialogSubWidget(
      BuildContext context, String fullName) async {
    final stallLabel = fullName.split("#")[1];
    // Bei Bedarf manuelle Löschung über Dialog (optional, da Swipe-Dismiss vorhanden)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Löschen bestätigen'),
          content:
          Text('Bist du dir sicher, dass du "$stallLabel" löschen möchtest?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      _removeSubWidget(fullName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        elevation: 5.0,
      ),
      body: Center(
        child: ListView.builder(
          shrinkWrap: true,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          itemCount: _subWidgetNames.length,
          itemBuilder: (BuildContext context, int index) {
            final String fullName = _subWidgetNames[index];
            final String stallLabel = fullName.split("#")[1];

            return Padding(
              padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Dismissible(
                key: Key(fullName),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) async {
                  final bool? confirmed =
                  await _confirmDelete(context, fullName);
                  return confirmed ?? false;
                },
                onDismissed: (_) {
                  _removeSubWidget(fullName);
                },
                background: Container(),
                secondaryBackground: Container(
                  color: Colors.red,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20.0),
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                    size: 30.0,
                  ),
                ),
                child: Card(
                  elevation: 3.0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: ExpansionTile(
                    title: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.house_siding, size: 28.0),
                          const SizedBox(width: 10.0),
                          Text(
                            stallLabel,
                            style: const TextStyle(fontSize: 20.0),
                          ),
                        ],
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Tierbewegung
                            Column(
                              children: [
                                IconButton(
                                  icon:
                                  const Icon(Icons.trending_up, size: 28.0),
                                  tooltip: 'Tierbewegung',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            Tierbewegung(stallname: fullName),
                                      ),
                                    );
                                  },
                                ),
                                const Text('Tierbewegung',
                                    style: TextStyle(fontSize: 14)),
                              ],
                            ),
                            // Dokumentation
                            Column(
                              children: [
                                IconButton(
                                  icon:
                                  const Icon(Icons.assignment, size: 28.0),
                                  tooltip: 'Dokumentation',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            Tiermassnahme(stallname: fullName),
                                      ),
                                    );
                                  },
                                ),
                                const Text('Dokumentation',
                                    style: TextStyle(fontSize: 14)),
                              ],
                            ),
                            // Verlauf
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.history, size: 28.0),
                                  tooltip: 'Verlauf',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            HistoryPageSecondMedikation(
                                                stallname: fullName),
                                      ),
                                    );
                                  },
                                ),
                                const Text('Verlauf',
                                    style: TextStyle(fontSize: 14)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          final name = await showDialog<String>(
            context: context,
            builder: (BuildContext dialogContext) {
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
                      Navigator.pop(dialogContext, null);
                    },
                  ),
                  TextButton(
                    child: const Text('Hinzufügen'),
                    onPressed: () {
                      final value = nameController.value.text;
                      Navigator.pop(dialogContext, value);
                    },
                  ),
                ],
              );
            },
          );
          if (name != null && name.trim().isNotEmpty) {
            _addNewSubWidget("${widget.name}#$name");
          }
        },
      ),
    );
  }
}
