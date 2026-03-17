import 'package:flutter/material.dart';
import 'dart:async';
import 'package:sqflite/sqflite.dart'; //Android, IOS, MACOS
import 'package:tier_monitor/pages/entry_second_plus_medication.dart';
import 'package:tier_monitor/pages/change_location.dart';
import 'package:tier_monitor/pages/documentation.dart';
import 'dart:convert';
import 'package:tier_monitor/db/app_database.dart';


class HistoryPageSecondMedikation extends StatefulWidget {
  final String stallname;
  final String initialTable;
  final int? highlightEntryId;

  const HistoryPageSecondMedikation({
    super.key,
    required this.stallname,
    this.initialTable = 'tierdoku',
    this.highlightEntryId,
  });

  @override
  _HistoryPageSecondMedikationState createState() =>
      _HistoryPageSecondMedikationState();
}

class _HistoryPageSecondMedikationState
    extends State<HistoryPageSecondMedikation> {
  List<Map<String, dynamic>> _entries = [];
  String _currentTable = 'tierdoku'; // Initial ist die Tabelle "tierdoku"
  bool _highlightBlinkOn = false;
  bool _highlightShouldAnimate = false;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _currentTable = widget.initialTable;
    _fetchEntriesFromDatabase();
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchEntriesFromDatabase() async {
    Database database = await openAppDatabase();

    // Abhängig von der aktuellen Tabelle die entsprechenden Einträge abrufen
    List<Map<String, dynamic>> entries = await database.rawQuery(
      'SELECT * FROM $_currentTable '
          'WHERE deleted_at IS NULL AND stallname = ? '
          'ORDER BY id DESC LIMIT 100',
      [widget.stallname],
    );

    final shouldHighlight = widget.highlightEntryId != null &&
        _currentTable == widget.initialTable &&
        entries.any((entry) => entry['id'] == widget.highlightEntryId);

    setState(() {
      _entries = entries;
      _highlightShouldAnimate = shouldHighlight;
      _highlightBlinkOn = shouldHighlight;
    });

    if (shouldHighlight) {
      _startHighlightBlink();
    } else {
      _highlightTimer?.cancel();
    }

    await database.close();
  }

  void _startHighlightBlink() {
    _highlightTimer?.cancel();
    int ticks = 0;
    _highlightTimer = Timer.periodic(const Duration(milliseconds: 650), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      ticks++;
      if (ticks >= 6) {
        timer.cancel();
        setState(() {
          _highlightBlinkOn = false;
          _highlightShouldAnimate = false;
        });
        return;
      }

      setState(() {
        _highlightBlinkOn = !_highlightBlinkOn;
      });
    });
  }

  Future<void> _deleteEntry(int index) async {
    Database database = await openAppDatabase();

    // ID des zu löschenden Eintrags abrufen
    int entryId = _entries[index]['id'];

    // Abhängig von der aktuellen Tabelle den Eintrag löschen
    await database.update(
      _currentTable,
      withTombstone(),
      where: 'id = ?',
      whereArgs: [entryId],
    );

    // Aktualisierte Einträge aus der aktuellen Tabelle abrufen
    await _fetchEntriesFromDatabase();

    await database.close();
  }

  String formatJsonList(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return "";
    try {
      final List<dynamic> list = jsonDecode(jsonString);
      return list.join(", ");
    } catch (e) {
      return jsonString; // fallback falls kein JSON
    }
  }

  int _medikationCount(Map<String, dynamic> entry) {
    int count = 0;
    bool hasValue(String? v) {
      if (v == null) return false;
      final trimmed = v.trim();
      return trimmed.isNotEmpty && trimmed != '[]';
    }

    if (hasValue(entry['medikament']?.toString())) count++;
    if (hasValue(entry['second_medikament']?.toString())) count++;
    if (hasValue(entry['third_medikament']?.toString())) count++;
    return count;
  }

  bool _hasVerendung(Map<String, dynamic> entry) {
    final endDate = entry['end_date']?.toString().trim() ?? '';
    final endComment = entry['end_comment']?.toString().trim() ?? '';
    final endFlag = entry['end']?.toString().trim() ?? '';
    return endDate.isNotEmpty || endComment.isNotEmpty || endFlag.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Letzte Einträge: ${widget.stallname.split("#")[1]}'),
        elevation: 5.0, // Erhöhte Elevation für mehr Schatten
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: () {
              // Beim Drücken des Buttons die Tabelle wechseln
              setState(() {
                _currentTable = (_currentTable == 'tierdoku')
                    ? 'tierbewegungen'
                    : 'tierdoku';
              });
              // Einträge aus der aktualisierten Tabelle abrufen
              _fetchEntriesFromDatabase();
            },
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final medCount = _currentTable == 'tierdoku'
              ? _medikationCount(entry)
              : 0;
          final isHighlighted = _highlightShouldAnimate &&
              _currentTable == widget.initialTable &&
              entry['id'] == widget.highlightEntryId;
          final baseColor =
              _hasVerendung(entry) ? colorScheme.surfaceContainerHighest : null;
          return Dismissible(
            key: ValueKey('entry_${entry['id']}'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (direction) async {
              if (_currentTable != 'tierdoku') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Löschen von Tierbewegungen nicht möglich'),
                  ),
                );
                return false;
              }

              final bool? deleteConfirmed = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Eintrag löschen'),
                    content:
                        const Text('Möchten Sie diesen Eintrag wirklich löschen?'),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(false);
                        },
                        child: const Text('Abbrechen'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop(true);
                        },
                        child: const Text('Löschen'),
                      ),
                    ],
                  );
                },
              );
              return deleteConfirmed ?? false;
            },
            onDismissed: (_) async {
              if (_currentTable == 'tierdoku') {
                await _deleteEntry(index);
              }
            },
            background: Container(),
            secondaryBackground: Container(
              color: colorScheme.error,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20.0),
              child: Icon(
                Icons.delete,
                color: colorScheme.onError,
                size: 30.0,
              ),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(8),
                border: isHighlighted
                    ? Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: 1.0,
                      )
                    : null,
              ),
              child: Stack(
                children: [
                  if (isHighlighted)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeInOut,
                        opacity: _highlightBlinkOn ? 1.0 : 0.18,
                        child: IgnorePointer(
                          child: Container(
                            width: 42,
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(8),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  colorScheme.primary.withValues(alpha: 0.22),
                                  colorScheme.primary.withValues(alpha: 0.08),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ExpansionTile(
            initiallyExpanded: isHighlighted,
            collapsedBackgroundColor: Colors.transparent,
            backgroundColor: Colors.transparent,
            title: Row(
                children: [
                  Expanded(
                    child: Text(
                      "${entry['stallname']}".split("#")[1] +
                          (_currentTable == 'tierdoku'
                              ? " - Bucht: ${entry['bucht']} ${formatJsonList(entry['symptome'])}"
                              : " - ${entry['date'].toString().substring(0, 10)}, ${entry['zugang_abgang']}: ${entry['anzahl']}"),
                    ),
                  ),
                  if (_currentTable == 'tierdoku' && medCount > 0) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.medication_outlined, size: 16),
                    if (medCount > 1) ...[
                      const SizedBox(width: 4),
                      Text(
                        medCount.toString(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ],
              ),
            trailing: _currentTable == 'tierdoku'
                ? PopupMenuButton<String>(
                    onSelected: (String value) async {
                      if (value == 'ersteintrag') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => Tiermassnahme(
                              stallname: widget.stallname,
                              entryId: _entries[index]['id'] as int,
                            ),
                          ),
                        ).then((_) {
                          _fetchEntriesFromDatabase();
                        });
                      } else if (value == 'zweit_medikation') {
                        // Navigation zur Seite für die Zweitmedikation
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EntryPageSecondMedikation(
                                entryId: _entries[index]['id']),
                          ),
                        ).then((_) {
                          // This code executes when the SecondMedikation page is popped
                          _fetchEntriesFromDatabase();
                        });
                      } else if (value == 'dritt_medikation') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EntryPageThirdMedikation(
                                entryId: _entries[index]['id']),
                          ),
                        ).then((_) {
                          // This code executes when the SecondMedikation page is popped
                          _fetchEntriesFromDatabase();
                        });
                      } else if (value == 'verendung_dokumentieren') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EntryPageEnd(
                                entryId: _entries[index]['id'],
                                stallname: widget.stallname),
                          ),
                        ).then((_) {
                          // This code executes when the SecondMedikation page is popped
                          _fetchEntriesFromDatabase();
                        });
                      } else if (value == 'umstallen') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChangeLocation(
                                entryId: _entries[index]['id'],
                                stallname: widget.stallname),
                          ),
                        ).then((_) {
                          // This code executes when the SecondMedikation page is popped
                          _fetchEntriesFromDatabase();
                        });
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      const PopupMenuItem<String>(
                        value: 'ersteintrag',
                        child: Text('Ersteintrag ändern'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'zweit_medikation',
                        child: Text('Zweitmedikation eintragen'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'dritt_medikation',
                        child: Text('Drittmedikation eintragen'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'verendung_dokumentieren',
                        child: Text('Verendung dokumentieren'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'umstallen',
                        child: Text('Umstallen'),
                      ),
                    ],
                  )
                : null,
            children: [
              if (_entries[index]['date'] != null)
                ListTile(
                  title: Text(
                      "Datum: ${_entries[index]['date'].toString().substring(0, 10)}"),
                ),
              if (_entries[index]['bucht'] != null)
                ListTile(
                  title: Text("Bucht: ${_entries[index]['bucht']}"),
                ),
              if (_entries[index]['symptome'] != null)
                ListTile(
                  title: Text("Symptome: ${formatJsonList(_entries[index]['symptome'])}"),
                ),

              if (_entries[index]['medikament'] != null)
                ListTile(
                  title: Text("Erstmedikation: ${formatJsonList(_entries[index]['medikament'])}"),
                ),
              if (_entries[index]['farbe'] != null)
                ListTile(
                  title: Text("Farbe: ${_entries[index]['farbe']}"),
                ),
              if (_entries[index]['zugang_abgang'] != null)
                ListTile(
                  title:
                  Text("Zu-/Abgang: ${_entries[index]['zugang_abgang']}"),
                ),
              if (_entries[index]['anzahl'] != null)
                ListTile(
                  title: Text("Anzahl: ${_entries[index]['anzahl']}"),
                ),
              if (_entries[index]['comment'] != null &&
                  _entries[index]['comment'] != "")
                ListTile(
                  title: Text("Kommentar: ${_entries[index]['comment']}"),
                ),
              if (_entries[index]['second_medikament'] != null)
                ListTile(
                  title: Text("Zweitmedikation: ${formatJsonList(_entries[index]['second_medikament'])}"),
                ),
              if (_entries[index]['second_date'] != null)
                ListTile(
                  title: Text(
                      "Datum Zweitmedikation: ${_entries[index]['second_date'].toString().substring(0, 10)}"),
                ),
              if (_entries[index]['second_comment'] != null &&
                  _entries[index]['second_comment'] != "")
                ListTile(
                  title: Text(
                      "Kommentar Zweitmedikation: ${_entries[index]['second_comment']}"),
                ),
              if (_entries[index]['third_medikament'] != null)
                ListTile(
                  title: Text("Drittmedikation: ${formatJsonList(_entries[index]['third_medikament'])}"),
                ),
              if (_entries[index]['third_date'] != null)
                ListTile(
                  title: Text(
                      "Datum Drittmedikation: ${_entries[index]['third_date'].toString().substring(0, 10)}"),
                ),
              if (_entries[index]['third_comment'] != null &&
                  _entries[index]['third_comment'] != "")
                ListTile(
                  title: Text(
                      "Kommentar Drittmedikation: ${_entries[index]['third_comment']}"),
                ),
              if (_entries[index]['end_date'] != null)
                ListTile(
                  title: Text(
                      "Datum Verendung: ${_entries[index]['end_date'].toString().substring(0, 10)}"),
                ),
              if (_entries[index]['end_comment'] != null &&
                  _entries[index]['end_comment'] != "")
                ListTile(
                  title: Text(
                      "Kommentar Verendung: ${_entries[index]['end_comment']}"),
                ),
              if (_entries[index]['end'] != null)
                ListTile(
                  title: Text("Zusatz: ${_entries[index]['end']}"),
                ),
            ],
            ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
