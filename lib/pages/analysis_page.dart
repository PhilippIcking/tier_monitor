import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart';
import 'dart:async';
import 'dart:collection';

// fl_chart
import 'package:fl_chart/fl_chart.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({Key? key}) : super(key: key);

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  late Database _db;

  /// Liste möglicher Jahre, in denen Bewegungen/Dokus existieren
  List<String> _availableYears = [];
  String _selectedYear = '';

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

  @override
  void initState() {
    super.initState();
    _initDbAndData();
  }

  Future<void> _initDbAndData() async {
    setState(() {
      _loading = true;
    });

    // 1) Datenbank öffnen
    var databasesPath = await getDatabasesPath();
    String path = join(databasesPath, 'my_database.db');
    _db = await openDatabase(path);

    // 2) Mögliche Jahre ermitteln
    await _loadAvailableYears();

    // 3) Betriebe und Ställe laden
    await _loadBetriebeUndStalls();

    // 4) Symptome und Medikamente laden
    await _loadSymptomsAndMedications();

    setState(() {
      if (_availableYears.isNotEmpty) {
        _selectedYear = _availableYears.first;
      }
      if (_allBetriebe.isNotEmpty) {
        _selectedBetrieb = _allBetriebe.first;
      }
      _loading = false;
    });
  }

  // Lädt alle Jahre, in denen tierbewegungen oder tierdoku einen Eintrag haben.
  Future<void> _loadAvailableYears() async {
    final rawMoves = await _db.query('tierbewegungen');
    final rawDoku = await _db.query('tierdoku');

    Set<String> years = {};

    for (var row in rawMoves) {
      String? dateStr = row['date'] as String?;
      if (dateStr != null && dateStr.length >= 4) {
        years.add(dateStr.substring(0, 4));
      }
    }
    for (var row in rawDoku) {
      String? dateStr = row['date'] as String?;
      if (dateStr != null && dateStr.length >= 4) {
        years.add(dateStr.substring(0, 4));
      }
    }

    final sorted = years.toList()..sort();
    _availableYears = sorted;
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
  /// für einen Stall und ein gegebenes Jahr. Das Ergebnis ist eine Liste
  /// (Datum -> Tierbestand).
  Future<List<_TimeSeriesInt>> _fetchTierbestandForStall(
      String betrieb,
      String stall,
      String year,
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
      if (dateStr == null || dateStr.length < 10) continue;
      if (dateStr.substring(0, 4) != year) continue;

      final tierbestand = row['tierbestand'] as int?;
      if (tierbestand == null) continue;

      final y = int.parse(dateStr.substring(0, 4));
      final m = int.parse(dateStr.substring(5, 7));
      final d = int.parse(dateStr.substring(8, 10));

      result.add(_TimeSeriesInt(DateTime(y, m, d), tierbestand));
    }
    result.sort((a, b) => a.time.compareTo(b.time));
    return result;
  }

  Future<List<_TimeSeriesInt>> _fetchTierbestandForStallWithCarryForward(
      String betrieb, String stall, String year) async {
    List<_TimeSeriesInt> rawData = await _fetchTierbestandForStall(betrieb, stall, year);
    final int yearInt = int.parse(year);
    final DateTime startOfYear = DateTime(yearInt, 1, 1);
    final DateTime endOfYear = DateTime(yearInt, 12, 31);

    List<_TimeSeriesInt> extendedList = [];
    if (rawData.isEmpty || rawData.first.time.isAfter(startOfYear)) {
      int prevValue = await _fetchPreviousYearValue(betrieb, stall, year);
      extendedList.add(_TimeSeriesInt(startOfYear, prevValue));
    }
    extendedList.addAll(rawData);
    if (extendedList.isEmpty || extendedList.last.time.isBefore(endOfYear)) {
      int lastValue = extendedList.isNotEmpty
          ? extendedList.last.value
          : await _fetchPreviousYearValue(betrieb, stall, year);
      extendedList.add(_TimeSeriesInt(endOfYear, lastValue));
    }

    List<_TimeSeriesInt> dailySeries = [];
    int currentIndex = 0;
    int currentValue = extendedList.first.value;
    for (DateTime day = startOfYear; !day.isAfter(endOfYear); day = day.add(const Duration(days: 1))) {
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
      String year,
      ) async {
    final list = await _fetchTierbestandForStall(betrieb, stall, year);
    if (list.isEmpty) return 0.0;

    final int yearInt = int.parse(year);
    final DateTime startOfYear = DateTime(yearInt, 1, 1);
    final DateTime endOfYear = DateTime(yearInt, 12, 31);
    final double totalDuration = endOfYear.difference(startOfYear).inDays.toDouble();

    double weightedSum = 0.0;

    List<_TimeSeriesInt> extendedList = [];
    if (list.first.time.isAfter(startOfYear)) {
      // Hier holen wir den Wert aus dem Vorjahr anstelle des ersten Eintrags
      int prevValue = await _fetchPreviousYearValue(betrieb, stall, year);
      extendedList.add(_TimeSeriesInt(startOfYear, prevValue));
    }
    extendedList.addAll(list);
    if (list.last.time.isBefore(endOfYear)) {
      extendedList.add(_TimeSeriesInt(endOfYear, list.last.value));
    }

    for (int i = 0; i < extendedList.length - 1; i++) {
      final current = extendedList[i];
      final next = extendedList[i + 1];
      final double duration = next.time.difference(current.time).inDays.toDouble();
      weightedSum += current.value * duration;
    }

    return weightedSum / totalDuration;
  }

  Future<int> _fetchPreviousYearValue(String betrieb, String stall, String year) async {
    final int yearInt = int.parse(year);
    final DateTime startOfYear = DateTime(yearInt, 1, 1);
    final String fullName = '$betrieb#$stall';
    final prevRows = await _db.query(
      'tierbewegungen',
      where: 'stallname = ? AND date < ?',
      whereArgs: [fullName, startOfYear.toIso8601String()],
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
      String year,
      ) async {
    final stalls = _betriebStalls[betrieb] ?? [];
    final int yearInt = int.parse(year);
    final DateTime startOfYear = DateTime(yearInt, 1, 1);
    final DateTime endOfYear = DateTime(yearInt, 12, 31);
    List<_TimeSeriesInt> result = [];

    Map<String, List<_TimeSeriesInt>> stallDataMap = {};
    for (var stall in stalls) {
      stallDataMap[stall] = await _fetchTierbestandForStall(betrieb, stall, year);
    }

    for (DateTime day = startOfYear; !day.isAfter(endOfYear); day = day.add(const Duration(days: 1))) {
      int sum = 0;
      for (var stall in stalls) {
        final stallData = stallDataMap[stall] ?? [];
        int stallValue = 0;
        if (stallData.isEmpty || stallData.first.time.isAfter(day)) {
          stallValue = await _fetchPreviousYearValue(betrieb, stall, year);
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
      String year,
      ) async {
    final data = await _fetchTierbestandForBetrieb(betrieb, year);
    if (data.isEmpty) return 0.0;

    final int yearInt = int.parse(year);
    final DateTime startOfYear = DateTime(yearInt, 1, 1);
    final DateTime endOfYear = DateTime(yearInt, 12, 31);
    final double totalDuration = endOfYear.difference(startOfYear).inDays.toDouble();

    double weightedSum = 0.0;

    List<_TimeSeriesInt> extendedList = [];
    if (data.first.time.isAfter(startOfYear)) {
      extendedList.add(_TimeSeriesInt(startOfYear, data.first.value));
    }
    extendedList.addAll(data);
    if (data.last.time.isBefore(endOfYear)) {
      extendedList.add(_TimeSeriesInt(endOfYear, data.last.value));
    }

    for (int i = 0; i < extendedList.length - 1; i++) {
      final current = extendedList[i];
      final next = extendedList[i + 1];
      final double duration = next.time.difference(current.time).inDays.toDouble();
      weightedSum += current.value * duration;
    }

    return weightedSum / totalDuration;
  }

  /// Zählt Doku-Einträge in tierdoku (Symptome oder Medikamente)
  Future<int> _countDokuEntriesForStall(
      String betrieb,
      String stall,
      String year,
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
      if (dateStr == null || dateStr.length < 10) continue;
      if (dateStr.substring(0, 4) != year) continue;

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
      String year,
      List<String> items,
      bool isSymptom,
      ) async {
    double avg = await _fetchAverageTierbestandForStall(betrieb, stall, year);
    if (avg == 0) return 0.0;

    int c = await _countDokuEntriesForStall(
      betrieb,
      stall,
      year,
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

    if (_availableYears.isEmpty || _allBetriebe.isEmpty) {
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
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('1) Tierzahlverlauf', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _buildTierzahlVerlaufSection(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('2) Auswertung Symptome & Medikamente', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    _buildSymMedCharts(),
                  ],
                ),
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
            Row(
              children: [
                const Text('Jahr: '),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedYear,
                  items: _availableYears
                      .map((y) => DropdownMenuItem<String>(
                    value: y,
                    child: Text(y),
                  ))
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _selectedYear = val;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Betrieb: '),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _selectedBetrieb,
                  items: _allBetriebe
                      .map((b) => DropdownMenuItem<String>(
                    value: b,
                    child: Text(b),
                  ))
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _selectedBetrieb = val;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Symptome:'),
            Wrap(
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
            const SizedBox(height: 12),
            Text('Medikamente:'),
            Wrap(
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
          return const Text('Keine Tierbewegungs-Daten für dieses Jahr.');
        }
        return Column(children: snapshot.data!);
      },
    );
  }

  Future<List<Widget>> _buildLineChartsForStallsAndBetrieb(
      List<String> stalls,
      ) async {
    List<Widget> result = [];

    // Betrieb gesamt
    final betriebData = await _fetchTierbestandForBetrieb(_selectedBetrieb, _selectedYear);
    double avgBetrieb = await _fetchAverageTierbestandForBetrieb(_selectedBetrieb, _selectedYear);

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
                  child: _buildLineChart(betriebData),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Pro Stall
    for (var stall in stalls) {
      final data = await _fetchTierbestandForStallWithCarryForward(_selectedBetrieb, stall, _selectedYear);
      if (data.isEmpty) continue;
      double avgStall = await _fetchAverageTierbestandForStall(_selectedBetrieb, stall, _selectedYear);

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
                  child: _buildLineChart(data),
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
  Widget _buildLineChart(List<_TimeSeriesInt> data) {
    final int yearInt = int.parse(_selectedYear);
    final DateTime startOfYear = DateTime(yearInt, 1, 1);
    final DateTime endOfYear = DateTime(yearInt, 12, 31);
    final double maxX = endOfYear.difference(startOfYear).inDays.toDouble();

    final List<FlSpot> spots = [];
    final Map<int, DateTime> dateLabels = {};

    for (var point in data) {
      final double x = point.time.difference(startOfYear).inDays.toDouble();
      spots.add(FlSpot(x, point.value.toDouble()));
      dateLabels[x.toInt()] = point.time;
    }

    final lineBarsData = [
      LineChartBarData(
        spots: spots,
        isCurved: false,
      ),
    ];

    return LineChart(
      LineChartData(
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
                  return const Text("01.01", style: TextStyle(fontSize: 10));
                } else if (value == maxX) {
                  return const Text("31.12", style: TextStyle(fontSize: 10));
                } else {
                  final dt = startOfYear.add(Duration(days: value.toInt()));
                  if (value % 30 == 0) {
                    return Text(
                      "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}",
                      style: const TextStyle(fontSize: 10),
                    );
                  }
                  return Container();
                }
              },
            ),
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
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
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
          return const Text('Keine Dokumentations-Daten für dieses Jahr.');
        }
        return Column(children: snapshot.data!);
      },
    );
  }

  /// Baut pro Stall ein Balkendiagramm, in dem jedes angewählte Symptom und
  /// jedes angewählte Medikament als eigene Säule dargestellt wird.
  Future<List<Widget>> _buildBarChartsForStalls(List<String> stalls) async {
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
          _selectedYear,
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
          _selectedYear,
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
}

// Hilfsklasse für Zeitreihendaten
class _TimeSeriesInt {
  final DateTime time;
  final int value;

  _TimeSeriesInt(this.time, this.value);
}
