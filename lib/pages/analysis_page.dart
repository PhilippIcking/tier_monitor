import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({Key? key}) : super(key: key);

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late Database _db;

  /// Verfügbarer Datumsbereich aus Bewegungen/Dokus
  DateTime? _minDate;
  DateTime? _maxDate;
  DateTimeRange? _selectedRange;

  /// Liste aller Betriebe
  List<String> _allBetriebe = [];
  String _selectedBetrieb = '';

  /// Aus SharedPreferences geladene Symptome/Medikamente
  List<String> _allSymptoms = [];
  List<String> _allMedications = [];
  /// Vom Nutzer aktuell ausgewählte Symptome/Medikamente
  List<String> _selectedSymptoms = [];
  List<String> _selectedMedications = [];

  /// Map: Betrieb -> Liste seiner Ställe
  Map<String, List<String>> _betriebStalls = {};

  bool _loading = false;
  final ScrollController _presetScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initDbAndData();
  }

  @override
  void dispose() {
    _presetScrollController.dispose();
    super.dispose();
  }

  Future<void> _initDbAndData() async {
    setState(() {
      _loading = true;
    });

    // 1) Datenbank öffnen
    var databasesPath = await getDatabasesPath();
    String path = p.join(databasesPath, 'my_database.db');
    _db = await openDatabase(path);

    // 2) Verfügbaren Datumsbereich ermitteln
    await _loadAvailableDateRange();

    // 3) Betriebe und Ställe laden
    await _loadBetriebeUndStalls();

    // 4) Symptome und Medikamente laden
    await _loadSymptomsAndMedications();

    setState(() {
      if (_minDate != null && _maxDate != null) {
        _selectedRange = DateTimeRange(start: _minDate!, end: _maxDate!);
      }
      if (_allBetriebe.isNotEmpty) {
        _selectedBetrieb = _allBetriebe.first;
      }
      _loading = false;
    });
  }

  // Lädt den Datumsbereich, in dem tierbewegungen oder tierdoku Einträge haben.
  Future<void> _loadAvailableDateRange() async {
    final rawMoves = await _db.query('tierbewegungen');
    final rawDoku = await _db.query('tierdoku');

    DateTime? minDate;
    DateTime? maxDate;

    for (var row in rawMoves) {
      String? dateStr = row['date'] as String?;
      final dt = _parseDate(dateStr);
      if (dt == null) continue;
      minDate = (minDate == null || dt.isBefore(minDate)) ? dt : minDate;
      maxDate = (maxDate == null || dt.isAfter(maxDate)) ? dt : maxDate;
    }
    for (var row in rawDoku) {
      String? dateStr = row['date'] as String?;
      final dt = _parseDate(dateStr);
      if (dt == null) continue;
      minDate = (minDate == null || dt.isBefore(minDate)) ? dt : minDate;
      maxDate = (maxDate == null || dt.isAfter(maxDate)) ? dt : maxDate;
    }

    _minDate = minDate;
    _maxDate = maxDate;
  }

  // Lädt alle Betriebe+Ställe aus stallname ("Betrieb#Stall")
  Future<void> _loadBetriebeUndStalls() async {
    final rawMoves = await _db.query('tierbewegungen');
    final rawDoku = await _db.query('tierdoku');

    Set<String> betriebeSet = {};
    Map<String, Set<String>> stallMap = {};

    void handleStallname(String? sn) {
      if (sn == null) return;
      var parts = sn.split('#');
      if (parts.length < 2) return;
      final betrieb = parts[0];
      final stall = parts[1];

      betriebeSet.add(betrieb);
      stallMap.putIfAbsent(betrieb, () => <String>{});
      stallMap[betrieb]?.add(stall);
    }

    for (var row in rawMoves) {
      handleStallname(row['stallname'] as String?);
    }
    for (var row in rawDoku) {
      handleStallname(row['stallname'] as String?);
    }

    _allBetriebe = betriebeSet.toList()..sort();
    _betriebStalls.clear();
    stallMap.forEach((betrieb, stalls) {
      _betriebStalls[betrieb] = stalls.toList()..sort();
    });
  }

  // Lädt Symptoms/Medications aus SharedPreferences
  Future<void> _loadSymptomsAndMedications() async {
    final prefs = await SharedPreferences.getInstance();
    _allSymptoms = prefs.getStringList('symptoms') ?? [];
    _allMedications = prefs.getStringList('medications') ?? [];
  }

  /// Ermittelt den Verlauf der Tierzahlen (tierbestand) aus tierbewegungen
  /// für einen Stall und einen gegebenen Datumsbereich. Das Ergebnis ist eine Liste
  /// (Datum -> Tierbestand).
  Future<List<_TimeSeriesInt>> _fetchTierbestandForStall(
      String betrieb,
      String stall,
      DateTime startDate,
      DateTime endDate,
      ) async {
    String full = '$betrieb#$stall';
    final rows = await _db.query(
      'tierbewegungen',
      where: 'stallname = ?',
      whereArgs: [full],
    );

    List<_TimeSeriesInt> result = [];
    for (var row in rows) {
      String? dateStr = row['date'] as String?;
      final dt = _parseDate(dateStr);
      if (dt == null) continue;
      if (dt.isBefore(startDate) || dt.isAfter(endDate)) continue;

      final tierbestand = row['tierbestand'] as int?;
      if (tierbestand == null) continue;

      result.add(_TimeSeriesInt(dt, tierbestand));
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  Future<List<_TimeSeriesInt>> _fetchTierbestandForStallWithCarryForward(
      String betrieb, String stall, DateTime startDate, DateTime endDate) async {
    List<_TimeSeriesInt> rawData = await _fetchTierbestandForStall(betrieb, stall, startDate, endDate);

    List<_TimeSeriesInt> extendedList = [];
    if (rawData.isEmpty || rawData.first.time.isAfter(startDate)) {
      int prevValue = await _fetchPreviousValueBeforeDate(betrieb, stall, startDate);
      extendedList.add(_TimeSeriesInt(startDate, prevValue));
    }
    extendedList.addAll(rawData);
    if (extendedList.isEmpty || extendedList.last.time.isBefore(endDate)) {
      int lastValue = extendedList.isNotEmpty
          ? extendedList.last.value
          : await _fetchPreviousValueBeforeDate(betrieb, stall, startDate);
      extendedList.add(_TimeSeriesInt(endDate, lastValue));
    }

    List<_TimeSeriesInt> dailySeries = [];
    int currentIndex = 0;
    int currentValue = extendedList.first.value;
    for (DateTime day = startDate; !day.isAfter(endDate); day = day.add(const Duration(days: 1))) {
      while (currentIndex < extendedList.length && !extendedList[currentIndex].time.isAfter(day)) {
        currentValue = extendedList[currentIndex].value;
        currentIndex++;
      }
      dailySeries.add(_TimeSeriesInt(day, currentValue));
    }
    return dailySeries;
  }

  Future<double> _fetchAverageTierbestandForStall(
      String betrieb,
      String stall,
      DateTime startDate,
      DateTime endDate,
      ) async {
    final list = await _fetchTierbestandForStall(betrieb, stall, startDate, endDate);
    final double totalDuration = endDate.difference(startDate).inDays.toDouble();

    double weightedSum = 0.0;

    List<_TimeSeriesInt> extendedList = [];
    if (list.isEmpty || list.first.time.isAfter(startDate)) {
      // Wert vor Startdatum verwenden
      int prevValue = await _fetchPreviousValueBeforeDate(betrieb, stall, startDate);
      extendedList.add(_TimeSeriesInt(startDate, prevValue));
    }
    extendedList.addAll(list);
    if (extendedList.isNotEmpty && extendedList.last.time.isBefore(endDate)) {
      extendedList.add(_TimeSeriesInt(endDate, extendedList.last.value));
    }

    for (int i = 0; i < extendedList.length - 1; i++) {
      final current = extendedList[i];
      final next = extendedList[i + 1];
      final double duration = next.time.difference(current.time).inDays.toDouble();
      weightedSum += current.value * duration;
    }

    if (totalDuration == 0) {
      return extendedList.isNotEmpty ? extendedList.first.value.toDouble() : 0.0;
    }
    return weightedSum / totalDuration;
  }

  Future<int> _fetchPreviousValueBeforeDate(
      String betrieb, String stall, DateTime startDate) async {
    final String fullName = '$betrieb#$stall';
    final String startStr = _dateOnlyString(startDate);
    final prevRows = await _db.query(
      'tierbewegungen',
      where: 'stallname = ? AND date < ?',
      whereArgs: [fullName, startStr],
      orderBy: 'date DESC',
      limit: 1,
    );
    if (prevRows.isNotEmpty) {
      final int? value = prevRows.first['tierbestand'] as int?;
      return value ?? 0;
    } else {
      return 0;
    }
  }

  Future<List<_TimeSeriesInt>> _fetchTierbestandForBetrieb(
      String betrieb,
      DateTime startDate,
      DateTime endDate,
      ) async {
    final stalls = _betriebStalls[betrieb] ?? [];
    List<_TimeSeriesInt> result = [];

    Map<String, List<_TimeSeriesInt>> stallDataMap = {};
    Map<String, int> prevValueMap = {};
    for (var stall in stalls) {
      stallDataMap[stall] = await _fetchTierbestandForStall(betrieb, stall, startDate, endDate);
      prevValueMap[stall] = await _fetchPreviousValueBeforeDate(betrieb, stall, startDate);
    }

    for (DateTime day = startDate; !day.isAfter(endDate); day = day.add(const Duration(days: 1))) {
      int sum = 0;
      for (var stall in stalls) {
        final stallData = stallDataMap[stall] ?? [];
        int stallValue = 0;
        if (stallData.isEmpty || stallData.first.time.isAfter(day)) {
          stallValue = prevValueMap[stall] ?? 0;
        } else {
          for (var point in stallData) {
            if (point.time.isAfter(day)) break;
            stallValue = point.value;
          }
        }
        sum += stallValue;
      }
      result.add(_TimeSeriesInt(day, sum));
    }
    return result;
  }

  Future<double> _fetchAverageTierbestandForBetrieb(
      String betrieb,
      DateTime startDate,
      DateTime endDate,
      ) async {
    final data = await _fetchTierbestandForBetrieb(betrieb, startDate, endDate);
    if (data.isEmpty) return 0.0;

    final double totalDuration = endDate.difference(startDate).inDays.toDouble();

    double weightedSum = 0.0;

    List<_TimeSeriesInt> extendedList = [];
    if (data.first.time.isAfter(startDate)) {
      extendedList.add(_TimeSeriesInt(startDate, data.first.value));
    }
    extendedList.addAll(data);
    if (data.last.time.isBefore(endDate)) {
      extendedList.add(_TimeSeriesInt(endDate, data.last.value));
    }

    for (int i = 0; i < extendedList.length - 1; i++) {
      final current = extendedList[i];
      final next = extendedList[i + 1];
      final double duration = next.time.difference(current.time).inDays.toDouble();
      weightedSum += current.value * duration;
    }

    if (totalDuration == 0) {
      return extendedList.isNotEmpty ? extendedList.first.value.toDouble() : 0.0;
    }
    return weightedSum / totalDuration;
  }

  /// Zählt Doku-Einträge in tierdoku (Symptome oder Medikamente)
  Future<int> _countDokuEntriesForStall(
      String betrieb,
      String stall,
      DateTime startDate,
      DateTime endDate,
      List<String> selectedItems,
      String type,
      ) async {
    if (selectedItems.isEmpty) return 0;
    String full = '$betrieb#$stall';

    final rows = await _db.query(
      'tierdoku',
      where: 'stallname = ?',
      whereArgs: [full],
    );

    int counter = 0;
    for (var row in rows) {
      final dateStr = row['date'] as String?;
      final dt = _parseDate(dateStr);
      if (dt == null) continue;
      if (dt.isBefore(startDate) || dt.isAfter(endDate)) continue;

      if (type == 'symptom') {
        final sympt = row['symptome'] as String? ?? '';
        for (var s in selectedItems) {
          if (sympt.contains(s)) {
            counter++;
            break;
          }
        }
      } else {
        final med1 = row['medikament'] as String? ?? '';
        final med2 = row['second_medikament'] as String? ?? '';
        final med3 = row['third_medikament'] as String? ?? '';
        for (var m in selectedItems) {
          if (med1.contains(m) || med2.contains(m) || med3.contains(m)) {
            counter++;
            break;
          }
        }
      }
    }
    return counter;
  }

  /// Liefert normierte Häufigkeit in Prozent = (count / durchschnittlicher Tierbestand)*100
  Future<double> _fetchNormalizedCount(
      String betrieb,
      String stall,
      DateTime startDate,
      DateTime endDate,
      List<String> items,
      bool isSymptom,
      ) async {
    double avg = await _fetchAverageTierbestandForStall(betrieb, stall, startDate, endDate);
    if (avg == 0) return 0.0;

    int c = await _countDokuEntriesForStall(
      betrieb,
      stall,
      startDate,
      endDate,
      items,
      isSymptom ? 'symptom' : 'medikament',
    );
    return (c / avg) * 100.0;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analyse')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_minDate == null || _maxDate == null || _allBetriebe.isEmpty || _selectedRange == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Analyse')),
        body: const Center(child: Text('Keine Daten oder Tabellen leer.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Analyse')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildFilterSection(),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              child: ExpansionTile(
                initiallyExpanded: true,
                title: Text('1) Tierzahlverlauf', style: Theme.of(context).textTheme.titleMedium),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _buildTierzahlVerlaufSection(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              child: ExpansionTile(
                initiallyExpanded: true,
                title: Text('2) Auswertung Symptome & Medikamente', style: Theme.of(context).textTheme.titleMedium),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: _buildSymMedCharts(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Baut den Filterbereich in einem Card-Widget
  Widget _buildFilterSection() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter'),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _allBetriebe
                    .map((b) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _betriebButton(b),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Zeitraum',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatRangeLabel(_selectedRange!),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zeitraum ändern',
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: _minDate!,
                          lastDate: _maxDate!,
                          initialDateRange: _selectedRange,
                        );
                        if (picked == null) return;
                        setState(() {
                          _selectedRange = picked;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              controller: _presetScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _presetButton('Maximal', _rangeFull()),
                  const SizedBox(width: 8),
                  _presetButton('Dieses Jahr', _rangeForYear(DateTime.now().year)),
                  const SizedBox(width: 8),
                  _presetButton('Letztes Jahr', _rangeForYear(DateTime.now().year - 1)),
                  const SizedBox(width: 8),
                  _presetButton('Letzte 90 Tage', _rangeLastDays(90)),
                  const SizedBox(width: 8),
                  _presetButton('Letzte 30 Tage', _rangeLastDays(30)),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('Symptome'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _allSymptoms.map((sym) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _selectedSymptoms.contains(sym),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedSymptoms.add(sym);
                                } else {
                                  _selectedSymptoms.remove(sym);
                                }
                              });
                            },
                          ),
                          Text(sym),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            ExpansionTile(
              title: const Text('Medikamente'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _allMedications.map((med) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: _selectedMedications.contains(med),
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedMedications.add(med);
                                } else {
                                  _selectedMedications.remove(med);
                                }
                              });
                            },
                          ),
                          Text(med),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 1) Tierzahlverlauf als Liniendiagramme
  Widget _buildTierzahlVerlaufSection() {
    final stalls = _betriebStalls[_selectedBetrieb] ?? [];
    return FutureBuilder(
      future: _buildLineChartsForStallsAndBetrieb(stalls),
      builder: (context, AsyncSnapshot<List<Widget>> snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Text('Keine Tierbewegungs-Daten für diesen Zeitraum.');
        }
        return Column(children: snapshot.data!);
      },
    );
  }

  Future<List<Widget>> _buildLineChartsForStallsAndBetrieb(
      List<String> stalls,
      ) async {
    final range = _selectedRange!;
    List<Widget> result = [];

    // Betrieb gesamt
    final betriebData = await _fetchTierbestandForBetrieb(_selectedBetrieb, range.start, range.end);
    double avgBetrieb = await _fetchAverageTierbestandForBetrieb(_selectedBetrieb, range.start, range.end);

    if (betriebData.isNotEmpty) {
      result.add(
        Card(
          elevation: 2,
          margin: const EdgeInsets.only(top: 16),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Betrieb gesamt: Ø ${avgBetrieb.toStringAsFixed(1)}'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: _buildLineChart(betriebData, range.start, range.end),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Pro Stall
    for (var stall in stalls) {
      final data = await _fetchTierbestandForStallWithCarryForward(_selectedBetrieb, stall, range.start, range.end);
      if (data.isEmpty) continue;
      double avgStall = await _fetchAverageTierbestandForStall(_selectedBetrieb, stall, range.start, range.end);

      result.add(
        Card(
          elevation: 2,
          margin: const EdgeInsets.only(top: 16),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stall "$stall": Ø ${avgStall.toStringAsFixed(1)}'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: _buildLineChart(data, range.start, range.end),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return result;
  }

  /// Baut ein Liniendiagramm für die gegebene Zeitreihe.
  Widget _buildLineChart(List<_TimeSeriesInt> data, DateTime startDate, DateTime endDate) {
    final double maxX = endDate.difference(startDate).inDays.toDouble();

    final List<FlSpot> spots = [];
    final Map<int, DateTime> dateLabels = {};

    for (var point in data) {
      final double x = point.time.difference(startDate).inDays.toDouble();
      spots.add(FlSpot(x, point.value.toDouble()));
      dateLabels[x.toInt()] = point.time;
    }

    final int rangeDays = maxX.toInt();
    final bool includeYear = false;
    int step = 1;
    if (rangeDays > 120) {
      step = 30;
    } else if (rangeDays > 40) {
      step = 14;
    } else if (rangeDays > 14) {
      step = 7;
    }

    final lineBarsData = [
      LineChartBarData(
        spots: spots,
        isCurved: false,
      ),
    ];

    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.black87,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final int dayOffset = spot.x.round();
                final DateTime dt = startDate.add(Duration(days: dayOffset));
                final String dateLabel = _dateOnlyString(dt);
                final String valueLabel = spot.y.toStringAsFixed(0);
                return LineTooltipItem(
                  "$dateLabel\n$valueLabel",
                  const TextStyle(fontSize: 12, color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: lineBarsData,
        minX: 0,
        maxX: maxX,
        minY: 0,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value == 0) {
                  return Text(_formatDateLabel(startDate, includeYear: includeYear, yearOnJanOnly: false),
                      style: const TextStyle(fontSize: 10));
                } else if (value == maxX) {
                  return Text(_formatDateLabel(endDate, includeYear: includeYear, yearOnJanOnly: false),
                      style: const TextStyle(fontSize: 10));
                } else {
                  final dt = startDate.add(Duration(days: value.toInt()));
                  if (value % step == 0) {
                    return Text(
                      _formatDateLabel(dt, includeYear: includeYear, yearOnJanOnly: false),
                      style: const TextStyle(fontSize: 10),
                    );
                  }
                  return Container();
                }
              },
            ),
          ),
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (double value, TitleMeta meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: FlGridData(show: true),
      ),
    );
  }

  // 2) Symptome/Medikamente
  Widget _buildSymMedCharts() {
    if (_selectedSymptoms.isEmpty && _selectedMedications.isEmpty) {
      return const Text('Keine Symptome oder Medikamente ausgewählt.');
    }

    final stalls = _betriebStalls[_selectedBetrieb] ?? [];
    if (stalls.isEmpty) {
      return const Text('Keine Ställe vorhanden.');
    }

    return FutureBuilder(
      future: _buildBarChartsForStalls(stalls),
      builder: (context, AsyncSnapshot<List<Widget>> snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Text('Keine Dokumentations-Daten für diesen Zeitraum.');
        }
        return Column(children: snapshot.data!);
      },
    );
  }

  /// Baut pro Stall ein Balkendiagramm, in dem jedes angewählte Symptom und
  /// jedes angewählte Medikament als eigene Säule dargestellt wird.
  Future<List<Widget>> _buildBarChartsForStalls(List<String> stalls) async {
    final range = _selectedRange!;
    List<Widget> result = [];

    for (var stall in stalls) {
      List<BarChartGroupData> groups = [];
      // Hier speichern wir die Beschriftungen der x-Achse (Itemnamen)
      Map<int, String> itemLabels = {};
      int groupIndex = 0;

      // Für jedes ausgewählte Symptom
      for (var sym in _selectedSymptoms) {
        double normValue = await _fetchNormalizedCount(
          _selectedBetrieb,
          stall,
          range.start,
          range.end,
          [sym],
          true,
        );
        groups.add(
          BarChartGroupData(
            x: groupIndex,
            barRods: [BarChartRodData(toY: normValue)],
          ),
        );
        itemLabels[groupIndex] = sym;
        groupIndex++;
      }
      // Für jedes ausgewählte Medikament
      for (var med in _selectedMedications) {
        double normValue = await _fetchNormalizedCount(
          _selectedBetrieb,
          stall,
          range.start,
          range.end,
          [med],
          false,
        );
        groups.add(
          BarChartGroupData(
            x: groupIndex,
            barRods: [BarChartRodData(toY: normValue)],
          ),
        );
        itemLabels[groupIndex] = med;
        groupIndex++;
      }

      result.add(
        Card(
          elevation: 2,
          margin: const EdgeInsets.only(top: 16),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stall "$stall": Individuelle Auswertung'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: BarChart(
                      BarChartData(
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (group) => Colors.black87,
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final value = rod.toY.toStringAsFixed(2);
                              return BarTooltipItem(
                                "$value%",
                                const TextStyle(fontSize: 12, color: Colors.white),
                              );
                            },
                          ),
                        ),
                        barGroups: groups,
                        gridData: FlGridData(show: true),
                        titlesData: FlTitlesData(
                          // linke Beschriftungen beibehalten
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (v, m) => Text(
                                "${v.toStringAsFixed(1)}%",
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          ),
                          // rechte Beschriftungen ausblenden
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          // obere Beschriftungen ausblenden
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          // untere Beschriftungen mit gedrehten Labels
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 60,
                              getTitlesWidget: (value, meta) {
                                final label = itemLabels[value.toInt()] ?? "";
                                return SideTitleWidget(
                                  meta: meta,
                                  child: RotatedBox(
                                    quarterTurns: 3, // 90° gegen den Uhrzeigersinn
                                    child: Text(
                                      label,
                                      style: const TextStyle(fontSize: 10),
                                      textAlign: TextAlign.left,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      )
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return result;
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.length < 10) return null;
    final y = int.tryParse(dateStr.substring(0, 4));
    final m = int.tryParse(dateStr.substring(5, 7));
    final d = int.tryParse(dateStr.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  String _dateOnlyString(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return "$y-$m-$d";
  }

  String _formatDateLabel(DateTime dt, {bool includeYear = false, bool yearOnJanOnly = false}) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    if (includeYear) {
      if (yearOnJanOnly && !(dt.month == 1 && dt.day == 1)) {
        return "$d.$m";
      }
      final y = dt.year.toString().padLeft(4, '0');
      return "$d.$m.$y";
    }
    return "$d.$m";
  }

  String _formatRangeLabel(DateTimeRange range) {
    final start = _dateOnlyString(range.start);
    final end = _dateOnlyString(range.end);
    return "$start bis $end";
  }


  Widget _presetButton(String label, DateTimeRange? range) {
    final bool disabled = range == null;
    final bool active = !disabled && _isSameRange(_selectedRange, range);
    return OutlinedButton(
      onPressed: disabled
          ? null
          : () {
              setState(() {
                _selectedRange = range;
              });
            },
      style: active
          ? OutlinedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            )
          : null,
      child: Text(label),
    );
  }

  Widget _betriebButton(String name) {
    final bool active = _selectedBetrieb == name;
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _selectedBetrieb = name;
        });
      },
      style: active
          ? OutlinedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            )
          : null,
      child: Text(name),
    );
  }


  DateTimeRange? _rangeLastDays(int days) {
    if (_minDate == null || _maxDate == null) return null;
    final DateTime end = _maxDate!;
    final DateTime start = end.subtract(Duration(days: days - 1));
    final DateTime clampedStart = start.isBefore(_minDate!) ? _minDate! : start;
    return DateTimeRange(start: clampedStart, end: end);
  }

  DateTimeRange? _rangeForYear(int year) {
    if (_minDate == null || _maxDate == null) return null;
    final DateTime start = DateTime(year, 1, 1);
    final DateTime end = DateTime(year, 12, 31);
    if (end.isBefore(_minDate!) || start.isAfter(_maxDate!)) return null;
    final DateTime clampedStart = start.isBefore(_minDate!) ? _minDate! : start;
    final DateTime clampedEnd = end.isAfter(_maxDate!) ? _maxDate! : end;
    return DateTimeRange(start: clampedStart, end: clampedEnd);
  }

  DateTimeRange? _rangeFull() {
    if (_minDate == null || _maxDate == null) return null;
    return DateTimeRange(start: _minDate!, end: _maxDate!);
  }

  bool _isSameRange(DateTimeRange? a, DateTimeRange? b) {
    if (a == null || b == null) return false;
    return a.start.year == b.start.year &&
        a.start.month == b.start.month &&
        a.start.day == b.start.day &&
        a.end.year == b.end.year &&
        a.end.month == b.end.month &&
        a.end.day == b.end.day;
  }
}

// Hilfsklasse für Zeitreihendaten
class _TimeSeriesInt {
  final DateTime time;
  final int value;

  _TimeSeriesInt(this.time, this.value);
}
