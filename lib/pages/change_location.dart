import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:tier_monitor/db/app_database.dart';

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
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() => selectedDate = picked);
    }
  }

  Future<int> _getBaselineBeforeDate(
      Database db, String stallName, DateTime date) async {
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(CASE "
          "WHEN zugang_abgang = 'Zugang' THEN anzahl "
          "ELSE -anzahl END), 0) AS total "
          "FROM tierbewegungen WHERE deleted_at IS NULL AND stallname = ? AND date < ?",
      [stallName, date.toString()],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  int _movementDelta(Map<String, dynamic> row) {
    final qty = row['anzahl'] as int? ?? 0;
    return row['zugang_abgang'] == 'Zugang' ? qty : -qty;
  }

  Future<bool> _wouldGoNegativeAfterDelta(
      Database db, String stallName, DateTime date, int delta) async {
    int baseline = await _getBaselineBeforeDate(db, stallName, date);
    int cumulative = baseline + delta;
    if (cumulative < 0) return true;

    final subsequentRecords = await db.rawQuery(
      "SELECT * FROM tierbewegungen "
          "WHERE deleted_at IS NULL AND stallname = ? AND date >= ? "
          "ORDER BY date ASC, id ASC",
      [stallName, date.toString()],
    );
    for (var record in subsequentRecords) {
      cumulative += _movementDelta(record);
      if (cumulative < 0) return true;
    }
    return false;
  }

  Future<void> _refreshSharedCountFromDb(Database db, String stallName) async {
    final result = await db.rawQuery(
      "SELECT COALESCE(SUM(CASE "
          "WHEN zugang_abgang = 'Zugang' THEN anzahl "
          "ELSE -anzahl END), 0) AS total "
          "FROM tierbewegungen WHERE deleted_at IS NULL AND stallname = ?",
      [stallName],
    );
    final total = (result.first['total'] as int?) ?? 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(stallName, total);
  }

  Future<void> updateEntry(
      BuildContext context,
      int entryId,
      String newLocation,
      DateTime date,
      bool update,
      ) async {
    final db = await openAppDatabase();

    if (update) {
      final wouldGoNegative = await _wouldGoNegativeAfterDelta(
        db,
        widget.stallname,
        date,
        -1,
      );
      if (wouldGoNegative) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler: Abgang würde negativen Bestand erzeugen'),
          ),
        );
        await db.close();
        return;
      }
      await db.insert(
        'tierbewegungen',
        withSyncFieldsForInsert({
          'stallname': widget.stallname,
          'anzahl': 1,
          'zugang_abgang': 'Abgang',
          'comment': 'Umgestallt nach ${newLocation.replaceAll("#", "-")}',
          'date': date.toString(),
          'end': '',
        }),
      );
      await _refreshSharedCountFromDb(db, widget.stallname);

      await db.insert(
        'tierbewegungen',
        withSyncFieldsForInsert({
          'stallname': newLocation,
          'anzahl': 1,
          'zugang_abgang': 'Zugang',
          'comment': 'Umgestallt von ${widget.stallname.replaceAll("#", "-")}',
          'date': date.toString(),
          'end': '',
        }),
      );
      await _refreshSharedCountFromDb(db, newLocation);
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
      withSyncFieldsForUpdate({
        'stallname': newLocation,
        'comment': newComment,
      }),
      where: 'id = ?',
      whereArgs: [entryId],
    );

    await db.close();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _selectedNewLocation.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;
    final fabColor = canSave
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Umstallen'),
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
                  InputDecorator(
                    isEmpty: _selectedNewLocation.isEmpty,
                    decoration: const InputDecoration(
                      labelText: 'Umstallen nach',
                      hintText: 'Stall auswählen',
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButton<String>(
                      value:
                          _selectedNewLocation.isNotEmpty ? _selectedNewLocation : null,
                      isExpanded: true,
                      underline: Container(),
                      items: _locations
                          .map((loc) => DropdownMenuItem(
                                value: loc,
                                child: Text(loc.replaceAll('#', '-')),
                              ))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedNewLocation = val ?? ''),
                    ),
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
                  const Divider(height: 32),
                  Row(
                    children: [
                      const Spacer(),
                      const Text('In Tierbewegungen übertragen'),
                      Switch(
                        value: _isToggleOn,
                        onChanged: (v) => setState(() => _isToggleOn = v),
                      ),
                      const Spacer(),
                    ],
                  ),
                ],
              ),
            ),
          ),
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





