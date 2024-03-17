import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tier_monitor/pages/third_layer.dart';

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
                Navigator.of(context).pop(); // Schließe das Dialogfenster
              },
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Schließe das Dialogfenster
                _removeSubWidget(name); // Lösche das Sub-Widget
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
      ),
      body: ListView.builder(
        itemCount: _subWidgetNames.length,
        itemBuilder: (BuildContext context, int index) {
          final String name = _subWidgetNames[index];
          return ListTile(
            title: Text(name.split("#")[1]),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SelectionPage(
                    stallName: name.toString(),
                  ),
                ),
              );
            },
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () =>
                  _showDeleteConfirmationDialogSubWidget(context, name),
            ),
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
          if (name != null) {
            _addNewSubWidget("${widget.name}#$name");
          }
        },
      ),
    );
  }
}