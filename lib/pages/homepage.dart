import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart'; //Android, IOS, MACOS
import 'package:path/path.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:tier_monitor/pages/medication_settings.dart';
import 'package:tier_monitor/pages/second_layer.dart';
import 'package:tier_monitor/pages/history.dart';





class WidgetList extends StatefulWidget {
  const WidgetList({super.key});

  @override
  _WidgetListState createState() => _WidgetListState();
}

class _WidgetListState extends State<WidgetList> {
  List<String> _widgetNames = [];

  @override
  void initState() {
    super.initState();
    _loadWidgetNames();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    // Pfad zur Datenbankdatei erstellen
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');

    // Datenbank öffnen bzw. erstellen
    Database _ = await openDatabase(
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
  }

  void _loadWidgetNames() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final widgetNames = prefs.getStringList('widget_names') ?? [];
    setState(() {
      _widgetNames = widgetNames;
    });
  }

  void _saveWidgetNames() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('widget_names', _widgetNames);
  }

  void _addNewWidget(String name) {
    setState(() {
      _widgetNames.add(name);
    });
    _saveWidgetNames();
  }

  void _showDeleteConfirmationDialog(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Löschen bestätigen'),
          content: Text('Bist du dir sicher, dass du $name löschen möchtest?'),
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
                _removeWidget(name); // Lösche das Widget
              },
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );
  }

  void _removeWidget(String name) {
    setState(() {
      _widgetNames.remove(name);
    });
    _saveWidgetNames();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Betriebe'),
        leading: IconButton(
          icon: const Icon(Icons.medication_liquid_sharp),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsPage()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HistoryPage()),
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _widgetNames.length,
        itemBuilder: (BuildContext context, int index) {
          final String name = _widgetNames[index];
          return ListTile(
            title: Text(name),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => WidgetCreator(name: name),
                ),
              );
            },
            trailing: IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _showDeleteConfirmationDialog(context, name),
            ),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            child: const Icon(Icons.add),
            onPressed: () async {
              final name = await showDialog<String>(
                context: context,
                builder: (BuildContext context) {
                  final nameController = TextEditingController();
                  return AlertDialog(
                    title: const Text('Betrieb hinzufügen'),
                    content: TextField(
                      controller: nameController,
                      decoration:
                      const InputDecoration(hintText: 'Name Betrieb'),
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
                _addNewWidget(name);
              }
            },
          ),
          const SizedBox(height: 16.0),
          FloatingActionButton(
            child: const Icon(Icons.download),
            onPressed: () async {
              try {
                // Pfad zur Datenbankdatei erstellen
                var databasesPath = await getDatabasesPath();
                String path = join(databasesPath, 'my_database.db');

                Database database = await openDatabase(path, version: 1);

                // Daten aus der Tabelle "tierdoku" abrufen
                List<Map<String, dynamic>> tierdokuRecords =
                await database.query('tierdoku');

                // Daten aus der Tabelle "tierbewegungen" abrufen
                List<Map<String, dynamic>> tierbewegungenRecords =
                await database.query('tierbewegungen');

                // Erstelle neue Excel-Datei
                var excel = Excel.createExcel();

                // Erstelle das erste Arbeitsblatt
                var sheet1 = excel['Tierdoku'];
                // Fügee Spaltenüberschriften hinzu
                sheet1.appendRow([
                  const TextCellValue('Betrieb'),
                  const TextCellValue('Stallname'),
                  const TextCellValue('Bucht'),
                  const TextCellValue('Symptome'),
                  const TextCellValue('Medikament'),
                  const TextCellValue('Farbe'),
                  const TextCellValue('Kommentar'),
                  const TextCellValue('Datum ISO (YYYY-MM-DD)'),
                  const TextCellValue('Datum Excel (DD/MM/YYYY)'),
                  const TextCellValue('Zweitmedikation'),
                  const TextCellValue('Zweitmedikation Kommentar'),
                  const TextCellValue('Zweitmedikation Datum ISO'),
                  const TextCellValue('Drittmedikation'),
                  const TextCellValue('Drittmedikation Kommentar'),
                  const TextCellValue('Drittmedikation Datum ISO'),
                  const TextCellValue('Kommentar Verendung'),
                  const TextCellValue('Datum Verendung ISO')
                ]);

                for (var record in tierdokuRecords) {
                  String betriebName = "${record['stallname']}".split("#")[0];
                  String stallName = "${record['stallname']}".split("#")[1];

                  // Das ursprüngliche Datum im Format "YYYY-MM-DD"
                  String originalDate = record['date'];

                  // Das Datum im Format "DD/MM/YYYY" erstellen
                  String formattedDate =
                      '${originalDate.substring(8, 10)}/${originalDate.substring(5, 7)}/${originalDate.substring(0, 4)}';

                  sheet1.appendRow([
                    TextCellValue(betriebName),
                    TextCellValue(stallName),
                    TextCellValue(record['bucht'] ?? ''),
                    TextCellValue(record['symptome'] ?? ''),
                    TextCellValue(record['medikament'] ?? ''),
                    TextCellValue(record['farbe'] ?? ''),
                    TextCellValue(record['comment'] ?? ''),
                    TextCellValue(originalDate), // Originalformat
                    TextCellValue(formattedDate), // Excel Format
                    TextCellValue(record['second_medikament'] ?? ''),
                    TextCellValue(record['second_comment'] ?? ''),
                    TextCellValue(record['second_date'] ?? ''),
                    TextCellValue(record['third_medikament'] ?? ''),
                    TextCellValue(record['third_comment'] ?? ''),
                    TextCellValue(record['third_date'] ?? ''),
                    TextCellValue(record['end_comment'] ?? ''),
                    TextCellValue(record['end_date'] ?? ''),
                  ]);
                }

                // Erstelle das zweite Arbeitsblatt nur, wenn es Tierbewegungen gibt
                if (tierbewegungenRecords.isNotEmpty) {
                  var sheet2 = excel['Tierbewegungen'];
                  // Füge die Spaltenüberschriften hinzu
                  sheet2.appendRow([
                    const TextCellValue('Betrieb'),
                    const TextCellValue('Stallname'),
                    const TextCellValue('Anzahl'),
                    const TextCellValue('Zugang/Abgang'),
                    const TextCellValue('Tierbestand'),
                    const TextCellValue('Kommentar'),
                    const TextCellValue('Datum ISO (YYYY-MM-DD)'),
                    const TextCellValue('Datum Excel (DD/MM/YYYY)'),
                    const TextCellValue('Zusatz'),
                  ]);
                  // Füge die Datensätze hinzu
                  for (var record in tierbewegungenRecords) {
                    String betriebName = "${record['stallname']}".split("#")[0];
                    String stallName = "${record['stallname']}".split("#")[1];

                    // Das ursprüngliche Datum im Format "YYYY-MM-DD"
                    String originalDate = record['date'];

                    // Das Datum im Format "DD/MM/YYYY" erstellen
                    String formattedDate =
                        '${originalDate.substring(8, 10)}/${originalDate.substring(5, 7)}/${originalDate.substring(0, 4)}';

                    sheet2.appendRow([
                      TextCellValue(betriebName),
                      TextCellValue(stallName),
                      TextCellValue(record['anzahl'].toString()),
                      TextCellValue(record['zugang_abgang'] ?? ''),
                      TextCellValue(record['tierbestand'].toString()),
                      TextCellValue(record['comment'] ?? ''),
                      TextCellValue(originalDate), // Originalformat
                      TextCellValue(formattedDate), // Excel Format
                      TextCellValue(record['end'] ?? ''),
                    ]);
                  }
                }

                // Teilen der Excel-Datei
                final temp = await getTemporaryDirectory();
                String currentDate =
                DateTime.now().toString().split(' ')[0]; // YYYY-MM-DD
                String formattedDate = currentDate.replaceAll('-', '_');
                final pathexcel =
                    '${temp.path}/exported_data_tierdoku_$formattedDate.xlsx';
                File(pathexcel).writeAsBytesSync(excel.save()!);

                await Share.shareXFiles([XFile(pathexcel)],
                    text: 'Export Data');

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Teilen beendet'),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Fehler beim Teilen'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}