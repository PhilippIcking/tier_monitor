import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; // Android, iOS, macOS
import 'package:tier_monitor/db/app_database.dart';

class Tierbewegung extends StatefulWidget {
  final String stallname;

  const Tierbewegung({super.key, required this.stallname});

  @override
  _TierbewegungState createState() => _TierbewegungState();
}

class _TierbewegungState extends State<Tierbewegung> {
  int _currentCount = 0;
  int _newCount = 0;
  String _movementType = 'Abgang';
  bool _isToggleOn = false;
  String _selectedComment = '';
  String _selectedNewLocation = '';
  List<String> _locations = [];
  DateTime selectedDate = DateTime.now();

  bool get _isZugang => _movementType == 'Zugang';
  bool get _isAbgang => _movementType == 'Abgang';
  bool get _isUmstallen => _movementType == 'Umstallen';

  @override
  void initState() {
    super.initState();
    _loadCount();
    _loadLocations();
  }

  Future<void> _loadCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentCount = prefs.getInt(widget.stallname) ?? 0;
    });
  }

  Future<void> _loadLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final widgetNames = prefs.getStringList('widget_names') ?? [];
    final locationNames = <String>[];
    for (final w in widgetNames) {
      final locationList = prefs.getStringList(w) ?? [];
      locationNames.addAll(locationList);
    }
    locationNames.remove(widget.stallname);
    setState(() {
      _locations = locationNames;
    });
  }

  Future<void> _saveCount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(widget.stallname, _currentCount);
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

  Future<int> _refreshSharedCountFromDb(Database db, String stallName) async {
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
    return total;
  }

  Future<void> _updateCount(BuildContext context) async {
    if (_newCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte eine positive Anzahl eingeben'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_isUmstallen && _selectedNewLocation.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Zielstall fuer Umstallen auswaehlen'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final database = await openAppDatabase();
    try {
      if (_isAbgang || _isUmstallen) {
        final wouldGoNegative = await _wouldGoNegativeAfterDelta(
          database,
          widget.stallname,
          selectedDate,
          -_newCount,
        );
        if (wouldGoNegative) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Die Änderung würde zu einem negativen Bestand führen'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
      }

      await _speichern(database);
      setState(() {
        _newCount = 0;
        _selectedComment = '';
        if (_isUmstallen) {
          _selectedNewLocation = '';
        }
      });
      _showFeedback(context);
    } finally {
      await database.close();
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    if (selectedDate.isAfter(DateTime.now())) {
      selectedDate = DateTime.now();
    }
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Future<void> _speichern(Database database) async {
    if (_isUmstallen) {
      final target = _selectedNewLocation;
      final commentSuffix =
          _selectedComment.trim().isEmpty ? '' : ': ${_selectedComment.trim()}';
      await database.insert(
        'tierbewegungen',
        withSyncFieldsForInsert({
          'stallname': widget.stallname,
          'anzahl': _newCount,
          'zugang_abgang': 'Abgang',
          'comment':
              'Umgestallt nach ${target.replaceAll("#", "-")}$commentSuffix',
          'date': selectedDate.toString(),
          'end': '',
        }),
      );

      await database.insert(
        'tierbewegungen',
        withSyncFieldsForInsert({
          'stallname': target,
          'anzahl': _newCount,
          'zugang_abgang': 'Zugang',
          'comment':
              'Umgestallt von ${widget.stallname.replaceAll("#", "-")}$commentSuffix',
          'date': selectedDate.toString(),
          'end': '',
        }),
      );

      final currentTotal =
          await _refreshSharedCountFromDb(database, widget.stallname);
      await _refreshSharedCountFromDb(database, target);
      setState(() {
        _currentCount = currentTotal;
      });
      return;
    }

    final newRecord = {
      'stallname': widget.stallname,
      'anzahl': _newCount,
      'zugang_abgang': _isZugang ? 'Zugang' : 'Abgang',
      'comment': _selectedComment,
      'date': selectedDate.toString(),
      'end': _isToggleOn ? 'Verendung' : '',
    };

    await database.insert('tierbewegungen', withSyncFieldsForInsert(newRecord));
    final currentTotal = await _refreshSharedCountFromDb(database, widget.stallname);

    setState(() {
      _currentCount = currentTotal;
    });
    await _saveCount();
  }

  void _showFeedback(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Die Daten wurden erfolgreich gespeichert')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        _newCount > 0 && (!_isUmstallen || _selectedNewLocation.isNotEmpty);
    final colorScheme = Theme.of(context).colorScheme;
    final Color fabColor = canSave
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return Scaffold(
      appBar: AppBar(
        title: Text('Tierbewegung: ${widget.stallname.split("#")[1]}'),
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
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: 12),
                      Text(
                        'Aktuelle Tierzahl: $_currentCount',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  ToggleButtons(
                    isSelected: [
                      _movementType == 'Zugang',
                      _movementType == 'Abgang',
                      _movementType == 'Umstallen',
                    ],
                    onPressed: (index) {
                      setState(() {
                        if (index == 0) {
                          _movementType = 'Zugang';
                        } else if (index == 1) {
                          _movementType = 'Abgang';
                        } else {
                          _movementType = 'Umstallen';
                        }

                        if (!_isAbgang) {
                          _isToggleOn = false;
                        }
                        if (!_isUmstallen) {
                          _selectedNewLocation = '';
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    constraints: const BoxConstraints(minHeight: 64, minWidth: 74),
                    selectedColor: Theme.of(context).colorScheme.onPrimary,
                    color: Theme.of(context).colorScheme.onSurface,
                    fillColor: Theme.of(context).colorScheme.primaryContainer,
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add_circle_outline, size: 18),
                            SizedBox(height: 4),
                            Text('Zugang', style: TextStyle(fontSize: 15)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.remove_circle_outline, size: 18),
                            SizedBox(height: 4),
                            Text('Abgang', style: TextStyle(fontSize: 15)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swap_horiz, size: 18),
                            SizedBox(height: 4),
                            Text('Umstallen', style: TextStyle(fontSize: 15)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),

                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Anzahl',
                      hintText: 'Anzahl eingeben',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 18),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _newCount = int.tryParse(value) ?? 0;
                      });
                    },
                  ),
                  const Divider(height: 32),

                  if (_isUmstallen) ...[
                    InputDecorator(
                      isEmpty: _selectedNewLocation.isEmpty,
                      decoration: const InputDecoration(
                        labelText: 'Umstallen nach',
                        hintText: 'Stall auswählen',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedNewLocation.isNotEmpty
                            ? _selectedNewLocation
                            : null,
                        isExpanded: true,
                        underline: Container(),
                        items: _locations
                            .map(
                              (loc) => DropdownMenuItem(
                                value: loc,
                                child: Text(loc.replaceAll('#', '-')),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedNewLocation = val ?? ''),
                      ),
                    ),
                    const Divider(height: 32),
                  ],

                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Kommentar',
                      hintText: 'Optional',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 18),
                    keyboardType: TextInputType.multiline,
                    minLines: 2,
                    maxLines: 5,
                    onChanged: (newValue) {
                      setState(() {
                        _selectedComment = newValue.toString();
                      });
                    },
                  ),
                  const Divider(height: 32),

                  if (_isAbgang) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 12),
                        const Text('Verendung', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 12),
                        Switch(
                          value: _isToggleOn,
                          onChanged: (value) {
                            setState(() {
                              _isToggleOn = value;
                            });
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                  ],

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
        onPressed: canSave ? () => _updateCount(context) : null,
        backgroundColor: fabColor,
        tooltip: 'Speichern',
        child: const Icon(Icons.save),
      ),
    );
  }
}
