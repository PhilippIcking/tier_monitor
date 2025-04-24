import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  // Controllers
  final TextEditingController _symptomController = TextEditingController();
  final TextEditingController _medicationController = TextEditingController();
  final TextEditingController _buchtController = TextEditingController();
  final TextEditingController _farbeController = TextEditingController();

  // Data lists
  List<String> _symptoms = [];
  List<String> _medications = [];
  List<String> _buchten = [];
  List<String> _farben = [];

  // Flags for add‑feedback
  bool _symptomAdded = false;
  bool _medicationAdded = false;
  bool _buchtAdded = false;
  bool _farbeAdded = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();

    // Symptome: default ["Husten"]
    _symptoms = prefs.getStringList('symptoms') ?? [];
    if (_symptoms.isEmpty) {
      _symptoms = ['Husten'];
      await prefs.setStringList('symptoms', _symptoms);
    }

    // Medikamente: default ["Hustensaft"]
    _medications = prefs.getStringList('medications') ?? [];
    if (_medications.isEmpty) {
      _medications = ['Hustensaft'];
      await prefs.setStringList('medications', _medications);
    }

    // Buchten: default ["1"... "16"]
    _buchten = prefs.getStringList('buchten') ?? [];
    if (_buchten.isEmpty) {
      _buchten = List.generate(16, (i) => (i + 1).toString());
      await prefs.setStringList('buchten', _buchten);
    }

    // Farben: default ["Rot","Grün","Blau"]
    _farben = prefs.getStringList('farben') ?? [];
    if (_farben.isEmpty) {
      _farben = ['Rot', 'Grün', 'Blau'];
      await prefs.setStringList('farben', _farben);
    }

    setState(() {});
  }

  Future<void> _saveList(String key, List<String> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, list);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
        elevation: 5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Symptome
            _buildPanel(
              title: 'Symptome',
              items: _symptoms,
              controller: _symptomController,
              addedFlag: _symptomAdded,
              chipColor: Colors.blue.shade100,
              saveKey: 'symptoms',
            ),

            // Medikamente
            _buildPanel(
              title: 'Medikamente',
              items: _medications,
              controller: _medicationController,
              addedFlag: _medicationAdded,
              chipColor: Colors.green.shade100,
              saveKey: 'medications',
            ),

            // Buchten
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ExpansionTile(
                title: const Text('Buchten'),
                childrenPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                children: [
                  TextField(
                    controller: _buchtController,
                    decoration: InputDecoration(
                      hintText: 'Bucht hinzufügen',
                      suffixIcon: IconButton(
                        icon: _buchtAdded
                            ? const Icon(Icons.check, color: Colors.grey)
                            : const Icon(Icons.add),
                        onPressed: () {
                          final text = _buchtController.text.trim();
                          if (text.isEmpty) return;
                          setState(() {
                            _buchten.add(text);
                            _buchtAdded = true;
                          });
                          _buchtController.clear();
                          _saveList('buchten', _buchten);
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Bucht hinzugefügt')));
                          Future.delayed(const Duration(milliseconds: 500), () {
                            setState(() => _buchtAdded = false);
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ReorderableListView(
                    key: const PageStorageKey('buchten'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _buchten.removeAt(oldIndex);
                        _buchten.insert(newIndex, item);
                      });
                      _saveList('buchten', _buchten);
                    },
                    children: [
                      for (int i = 0; i < _buchten.length; i++)
                        Chip(
                          key: ValueKey('bucht_$i'),
                          label: Text(_buchten[i]),
                          backgroundColor: Colors.grey.shade300,
                          onDeleted: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Löschen bestätigen'),
                                content: Text(
                                  'Bist du dir sicher, dass du Bucht "${_buchten[i]}" entfernen möchtest?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Abbrechen'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Löschen'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              setState(() => _buchten.removeAt(i));
                              _saveList('buchten', _buchten);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Bucht entfernt')));
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Farben
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ExpansionTile(
                title: const Text('Farben'),
                childrenPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                children: [
                  TextField(
                    controller: _farbeController,
                    decoration: InputDecoration(
                      hintText: 'Farbe hinzufügen',
                      suffixIcon: IconButton(
                        icon: _farbeAdded
                            ? const Icon(Icons.check, color: Colors.grey)
                            : const Icon(Icons.add),
                        onPressed: () {
                          final text = _farbeController.text.trim();
                          if (text.isEmpty) return;
                          setState(() {
                            _farben.add(text);
                            _farbeAdded = true;
                          });
                          _farbeController.clear();
                          _saveList('farben', _farben);
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Farbe hinzugefügt')));
                          Future.delayed(const Duration(milliseconds: 500), () {
                            setState(() => _farbeAdded = false);
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ReorderableListView(
                    key: const PageStorageKey('farben'),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _farben.removeAt(oldIndex);
                        _farben.insert(newIndex, item);
                      });
                      _saveList('farben', _farben);
                    },
                    children: [
                      for (int i = 0; i < _farben.length; i++)
                        Chip(
                          key: ValueKey('farbe_$i'),
                          label: Text(_farben[i]),
                          backgroundColor: Colors.grey.shade300,
                          onDeleted: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Löschen bestätigen'),
                                content: Text(
                                  'Bist du dir sicher, dass du Farbe "${_farben[i]}" entfernen möchtest?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Abbrechen'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Löschen'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              setState(() => _farben.removeAt(i));
                              _saveList('farben', _farben);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('Farbe entfernt')));
                            }
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Helper for Symptom & Medication panels
  Widget _buildPanel({
    required String title,
    required List<String> items,
    required TextEditingController controller,
    required bool addedFlag,
    required Color chipColor,
    required String saveKey,
  }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ExpansionTile(
        title: Text(title),
        childrenPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: '$title hinzufügen',
              suffixIcon: IconButton(
                icon: addedFlag
                    ? Icon(Icons.check, color: chipColor)
                    : const Icon(Icons.add),
                onPressed: () {
                  final text = controller.text.trim();
                  if (text.isEmpty) return;
                  setState(() {
                    items.add(text);
                    if (saveKey == 'symptoms') _symptomAdded = true;
                    if (saveKey == 'medications') _medicationAdded = true;
                  });
                  controller.clear();
                  _saveList(saveKey, items);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$title hinzugefügt')));
                  Future.delayed(const Duration(milliseconds: 500), () {
                    setState(() {
                      if (saveKey == 'symptoms') _symptomAdded = false;
                      if (saveKey == 'medications') _medicationAdded = false;
                    });
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          ReorderableListView(
            key: PageStorageKey(saveKey),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = items.removeAt(oldIndex);
                items.insert(newIndex, item);
              });
              _saveList(saveKey, items);
            },
            children: [
              for (int i = 0; i < items.length; i++)
                Chip(
                  key: ValueKey('$saveKey\_$i'),
                  label: Text(items[i]),
                  backgroundColor: chipColor,
                  onDeleted: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Löschen bestätigen'),
                        content: Text(
                          'Bist du dir sicher, dass du "${items[i]}" löschen möchtest?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Abbrechen'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Löschen'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      setState(() => items.removeAt(i));
                      _saveList(saveKey, items);
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$title entfernt')));
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
