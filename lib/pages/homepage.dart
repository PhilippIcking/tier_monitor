import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart'; // Android, IOS, MACOS
import 'package:path/path.dart';
import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:tier_monitor/pages/history.dart';
import 'package:tier_monitor/pages/second_layer.dart';

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
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');

    Database _ = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
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
                Navigator.of(context).pop();
              },
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _removeWidget(name);
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

  Future<void> _exportData(BuildContext context) async {
    final currentContext = context; // Speichere den BuildContext
    try {
      var databasesPath = await getDatabasesPath();
      String path = join(databasesPath, 'my_database.db');
      Database database = await openDatabase(path, version: 1);

      List<Map<String, dynamic>> tierdokuRecords =
      await database.query('tierdoku');
      List<Map<String, dynamic>> tierbewegungenRecords =
      await database.query('tierbewegungen');

      var excel = Excel.createExcel();
      var sheet1 = excel['Tierdoku'];
      sheet1.appendRow([
        TextCellValue('Betrieb'),
        TextCellValue('Stallname'),
        TextCellValue('Bucht'),
        TextCellValue('Symptome'),
        TextCellValue('Medikament'),
        TextCellValue('Farbe'),
        TextCellValue('Kommentar'),
        TextCellValue('Datum ISO (YYYY-MM-DD)'),
        TextCellValue('Datum Excel Format'),
        TextCellValue('Zweitmedikation'),
        TextCellValue('Zweitmedikation Kommentar'),
        TextCellValue('Zweitmedikation Datum ISO'),
        TextCellValue('Drittmedikation'),
        TextCellValue('Drittmedikation Kommentar'),
        TextCellValue('Drittmedikation Datum ISO'),
        TextCellValue('Kommentar Verendung'),
        TextCellValue('Datum Verendung ISO')
      ]);

      for (var record in tierdokuRecords) {
        String betriebName = "${record['stallname']}".split("#")[0];
        String stallName = "${record['stallname']}".split("#")[1];
        String originalDate = record['date'];
        int year = int.parse(originalDate.substring(0, 4));
        int month = int.parse(originalDate.substring(5, 7));
        int day = int.parse(originalDate.substring(8, 10));

        sheet1.appendRow([
          TextCellValue(betriebName),
          TextCellValue(stallName),
          TextCellValue(record['bucht'] ?? ''),
          TextCellValue(record['symptome'] ?? ''),
          TextCellValue(record['medikament'] ?? ''),
          TextCellValue(record['farbe'] ?? ''),
          TextCellValue(record['comment'] ?? ''),
          TextCellValue(originalDate),
          TextCellValue('$year-$month-$day'),
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

      if (tierbewegungenRecords.isNotEmpty) {
        var sheet2 = excel['Tierbewegungen'];
        sheet2.appendRow([
          TextCellValue('Betrieb'),
          TextCellValue('Stallname'),
          TextCellValue('Anzahl'),
          TextCellValue('Zugang/Abgang'),
          TextCellValue('Tierbestand'),
          TextCellValue('Kommentar'),
          TextCellValue('Datum ISO (YYYY-MM-DD)'),
          TextCellValue('Datum Excel Format'),
          TextCellValue('Zusatz'),
        ]);

        for (var record in tierbewegungenRecords) {
          String betriebName = "${record['stallname']}".split("#")[0];
          String stallName = "${record['stallname']}".split("#")[1];
          String originalDate = record['date'];
          int year = int.parse(originalDate.substring(0, 4));
          int month = int.parse(originalDate.substring(5, 7));
          int day = int.parse(originalDate.substring(8, 10));

          sheet2.appendRow([
            TextCellValue(betriebName),
            TextCellValue(stallName),
            TextCellValue(record['anzahl'].toString()),
            TextCellValue(record['zugang_abgang'] ?? ''),
            TextCellValue(record['tierbestand'].toString()),
            TextCellValue(record['comment'] ?? ''),
            TextCellValue(originalDate),
            TextCellValue('$year-$month-$day'),
            TextCellValue(record['end'] ?? ''),
          ]);
        }
      }

      final temp = await getTemporaryDirectory();
      String currentDate = DateTime.now().toString().split(' ')[0];
      String formattedDate = currentDate.replaceAll('-', '_');
      final pathexcel =
          '${temp.path}/exported_data_tierdoku_$formattedDate.xlsx';
      File(pathexcel)
        ..createSync(recursive: true)
        ..writeAsBytesSync(excel.encode()!);

      // Verwende shareXFiles statt shareFiles:
      await Share.shareXFiles([XFile(pathexcel)], text: 'Exportierte Daten');
      await database.close();
    } catch (e) {
      ScaffoldMessenger.of(currentContext).showSnackBar(
        SnackBar(content: Text('Export fehlgeschlagen: $e')),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Betriebe'),

        elevation: 5.0, // Erhöhte Elevation für mehr Schatten

        // Entfernt wurde der Button links, der zu den Einstellungen führte.
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
        padding: const EdgeInsets.only(top: 5.0), // Top-Padding hinzugefügt
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
            heroTag: 'addWidget',
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
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 16.0),
          FloatingActionButton(
            heroTag: 'exportData',
            onPressed: () => _exportData(context),
            child: const Icon(Icons.download),
          ),
        ],
      ),
    );
  }
}
