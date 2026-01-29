import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class ChangeLocation extends StatefulWidget {
  final int entryId;
  final String stallname;
  const ChangeLocation({
    super.key,
    required this.entryId,
    required this.stallname,
  });

  @override
  _ChangeLocationState createState() => _ChangeLocationState();
}

class _ChangeLocationState extends State<ChangeLocation> {
  String _selectedNewLocation = '';
  DateTime selectedDate = DateTime.now();
  bool _isToggleOn = true;
  List<String> _locations = [];

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final widgetNames = prefs.getStringList('widget_names') ?? [];
    List<String> locationNames = [];
    for (String w in widgetNames) {
      final locationList = prefs.getStringList(w) ?? [];
      locationNames.addAll(locationList);
    }
    locationNames.remove(widget.stallname);
    setState(() => _locations = locationNames);
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && picked != selectedDate) {
      setState(() => selectedDate = picked);
    }
  }

  Future<void> _updateSharedCount(String stallName, int delta) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(stallName) ?? 0;
    await prefs.setInt(stallName, current + delta);
  }

  Future<void> updateEntry(
      BuildContext context,
      int entryId,
      String newLocation,
      DateTime date,
      bool update,
      ) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'my_database.db');
    final db = await openDatabase(path, version: 1);

    if (update) {
      final prefs = await SharedPreferences.getInstance();
      final baselineOld = prefs.getInt(widget.stallname) ?? 0;

      if (baselineOld - 1 < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler: Abgang würde negativen Bestand erzeugen'),
          ),
        );
        await db.close();
        return;
      }

      await db.insert('tierbewegungen', {
        'stallname': widget.stallname,
        'anzahl': 1,
        'zugang_abgang': 'Abgang',
        'comment': 'Umgestallt nach ${newLocation.replaceAll("#", "-")}',
        'date': date.toString(),
        'end': '',
      });
      await _updateSharedCount(widget.stallname, -1);

      await db.insert('tierbewegungen', {
        'stallname': newLocation,
        'anzahl': 1,
        'zugang_abgang': 'Zugang',
        'comment': 'Umgestallt von ${widget.stallname.replaceAll("#", "-")}',
        'date': date.toString(),
        'end': '',
      });
      await _updateSharedCount(newLocation, 1);
    }

    final current = await db.query(
      'tierdoku',
      columns: ['comment'],
      where: 'id = ?',
      whereArgs: [entryId],
    );
    final oldComment = current.isNotEmpty
        ? current.first['comment'] as String
        : '';
    final newComment =
        '$oldComment\nUmgestallt am ${date.toString().split(" ")[0]} '
        'von ${widget.stallname.replaceAll("#", "-")} '
        'nach ${newLocation.replaceAll("#", "-")}';
    await db.update(
      'tierdoku',
      {
        'stallname': newLocation,
        'comment': newComment,
      },
      where: 'id = ?',
      whereArgs: [entryId],
    );

    await db.close();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _selectedNewLocation.isNotEmpty;
    final fabColor = canSave
        ? Theme.of(context).colorScheme.primary
        : Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Umstallen'),
        elevation: 5.0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: canSave ? _selectedNewLocation : null,
              items: _locations
                  .map((loc) => DropdownMenuItem(
                value: loc,
                child: Text(loc.replaceAll('#', '-')),
              ))
                  .toList(),
              decoration: const InputDecoration(
                labelText: 'Umstallen nach',
                border: OutlineInputBorder(),
              ),
              onChanged: (val) =>
                  setState(() => _selectedNewLocation = val ?? ''),
            ),
            const SizedBox(height: 16.0),
            Text("${selectedDate.toLocal()}".split(' ')[0]),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              child: const Text('Datum ändern'),
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                const Text('Umstallen in Tierbewegungen übertragen'),
                Switch(
                  value: _isToggleOn,
                  onChanged: (v) => setState(() => _isToggleOn = v),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: fabColor,
        tooltip: 'Speichern',
        onPressed: canSave
            ? () async {
          await updateEntry(
            context,
            widget.entryId,
            _selectedNewLocation,
            selectedDate,
            _isToggleOn,
          );
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Umstallen erfolgreich dokumentiert'),
            ),
          );
          Navigator.pop(context);
        }
            : null,
        child: const Icon(Icons.save),
      ),
    );
  }
}
