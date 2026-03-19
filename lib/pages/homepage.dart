import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart'; // Android, iOS, macOS
import 'package:excel/excel.dart' hide Border;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'dart:io';
import 'package:tier_monitor/pages/second_layer.dart';
import 'package:tier_monitor/pages/voice_tickets_page.dart';
import 'package:tier_monitor/db/app_database.dart';
import 'package:tier_monitor/sync/self_hosted_sync_models.dart';
import 'package:tier_monitor/sync/self_hosted_sync_service.dart';

class WidgetList extends StatefulWidget {
  const WidgetList({super.key});

  @override
  _WidgetListState createState() => _WidgetListState();
}

class _WidgetListState extends State<WidgetList>
    with SingleTickerProviderStateMixin {
  List<String> _widgetNames = [];
  final SelfHostedSyncService _syncService = SelfHostedSyncService.instance;
  final VoiceTicketController _voiceTicketController =
      VoiceTicketController.instance;
  SyncStatus _syncStatus = const SyncStatus.initial();
  late final AnimationController _syncIconController;

  @override
  void initState() {
    super.initState();
    _syncIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadWidgetNames();
    _syncService.status.addListener(_onSyncStatusChanged);
    _voiceTicketController.addListener(_onVoiceTicketChanged);
    _syncStatus = _syncService.status.value;
    _updateSyncAnimation();
    Future.microtask(() async {
      await _syncService.initialize();
      await _syncService.refreshConfig();
      await _voiceTicketController.initialize();
    });
  }

  @override
  void dispose() {
    _syncService.status.removeListener(_onSyncStatusChanged);
    _voiceTicketController.removeListener(_onVoiceTicketChanged);
    _syncIconController.dispose();
    super.dispose();
  }

  void _onSyncStatusChanged() {
    if (!mounted) return;
    setState(() {
      _syncStatus = _syncService.status.value;
    });
    _updateSyncAnimation();
  }

  void _onVoiceTicketChanged() {
    if (!mounted) return;
    final message = _voiceTicketController.consumeError();
    setState(() {});
    if (message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _updateSyncAnimation() {
    if (_syncStatus.state == SyncStateType.syncing) {
      if (!_syncIconController.isAnimating) {
        _syncIconController.repeat();
      }
    } else {
      _syncIconController.stop();
      _syncIconController.reset();
    }
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

  void _removeWidget(String name) {
    setState(() {
      _widgetNames.remove(name);
    });
    _saveWidgetNames();
  }

  Future<void> _runManualSync() async {
    final result = await _syncService.syncNow(trigger: SyncTrigger.manual);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    await _syncService.refreshConfig();
  }

  Future<void> _openVoiceTickets() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const VoiceTicketsPage(),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildVoiceRecordDialChild() {
    return AnimatedBuilder(
      animation: _voiceTicketController,
      builder: (context, _) {
        return Listener(
          onPointerDown: (_) => _voiceTicketController.startRecordingFromPress(),
          onPointerUp: (_) => _voiceTicketController.stopRecordingFromPress(),
          onPointerCancel: (_) =>
              _voiceTicketController.stopRecordingFromPress(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 68,
            height: 52,
            decoration: BoxDecoration(
              color: _voiceTicketController.isRecording
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).secondaryHeaderColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  _voiceTicketController.isRecording
                      ? Icons.radio_button_on
                      : Icons.mic,
                  color: _voiceTicketController.isRecording
                      ? Theme.of(context).colorScheme.onError
                      : Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildVoiceTicketListFab() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FloatingActionButton.small(
          heroTag: 'voice_ticket_list_fab',
          tooltip: 'Voice Tickets',
          onPressed: _openVoiceTickets,
          child: const Icon(Icons.list_alt),
        ),
        if (_voiceTicketController.hasOpenTickets)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_voiceTicketController.openTicketCount}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onError,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _exportData(BuildContext context) async {
    final currentContext = context;
    try {
      Database database = await openAppDatabase();

      List<Map<String, dynamic>> tierdokuRecords =
      await database.query('tierdoku', where: 'deleted_at IS NULL');
      List<Map<String, dynamic>> tierbewegungenRecords =
      await database.query('tierbewegungen', where: 'deleted_at IS NULL');

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
        TextCellValue('Datum Verendung ISO'),
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

      await Share.shareXFiles([XFile(pathexcel)], text: 'Exportierte Daten');
      await database.close();
    } catch (e) {
      ScaffoldMessenger.of(currentContext).showSnackBar(
        SnackBar(content: Text('Export fehlgeschlagen: $e')),
      );
    }
  }

  Future<void> _showAddBetriebDialog(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) {
        final nameController = TextEditingController();
        return AlertDialog(
          title: const Text('Betrieb hinzufügen'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(hintText: 'Name Betrieb'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              child: const Text('Abbruch'),
              onPressed: () {
                Navigator.pop(dialogContext, null);
              },
            ),
            TextButton(
              child: const Text('Hinzufügen'),
              onPressed: () {
                final value = nameController.value.text;
                Navigator.pop(dialogContext, value);
              },
            ),
          ],
        );
      },
    );

    if (name != null && name.trim().isNotEmpty) {
      _addNewWidget(name.trim());
    }
  }

  Future<bool?> _confirmDelete(BuildContext context, String name) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Löschen bestätigen'),
          content: Text('Bist du dir sicher, dass du "$name" löschen möchtest?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Löschen'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Betriebe'),
        elevation: 5.0,
        actions: [
          if (_syncStatus.showButton)
            IconButton(
              tooltip: 'Synchronisieren',
              onPressed: _syncStatus.state == SyncStateType.syncing ? null : _runManualSync,
              icon: RotationTransition(
                turns: _syncIconController,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.sync),
                    if (_syncStatus.state == SyncStateType.error)
                      Positioned(
                        top: -1,
                        right: -1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: ListView.builder(
          shrinkWrap: true,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          itemCount: _widgetNames.length,
          itemBuilder: (BuildContext context, int index) {
            final String name = _widgetNames[index];
            return Dismissible(
              key: Key(name),
              direction: DismissDirection.endToStart,
              confirmDismiss: (DismissDirection direction) async {
                final bool? confirmed = await _confirmDelete(context, name);
                return confirmed ?? false;
              },
              onDismissed: (direction) {
                _removeWidget(name);
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
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                elevation: 3.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8.0),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => WidgetCreator(name: name),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.store, size: 30.0),
                        const SizedBox(width: 12.0),
                        Text(
                          name,
                          style: const TextStyle(fontSize: 20.0),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_voiceTicketController.hasOpenTickets) ...[
            _buildVoiceTicketListFab(),
            const SizedBox(width: 12),
          ],
          SpeedDial(
            icon: Icons.add,
            activeIcon: Icons.close,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            overlayOpacity: 0.0,
            spacing: 8,
            spaceBetweenChildren: 8,
            children: [
              SpeedDialChild(
                child: _buildVoiceRecordDialChild(),
                label: _voiceTicketController.isRecording
                    ? 'Aufnahme läuft'
                    : 'Für Voice Ticket halten',
                labelBackgroundColor: Theme.of(context).cardColor,
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.transparent,
                onTap: () {},
              ),
              SpeedDialChild(
                child: const Icon(Icons.add),
                label: 'Betrieb hinzufügen',
                labelBackgroundColor: Theme.of(context).cardColor,
                onTap: () => _showAddBetriebDialog(context),
              ),
              SpeedDialChild(
                child: const Icon(Icons.download),
                label: 'Als Tabelle exportieren',
                labelBackgroundColor: Theme.of(context).cardColor,
                onTap: () => _exportData(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


