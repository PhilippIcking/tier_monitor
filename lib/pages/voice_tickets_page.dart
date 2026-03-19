import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tier_monitor/pages/change_amount.dart';
import 'package:tier_monitor/pages/documentation.dart';
import 'package:tier_monitor/pages/history_individual.dart';

class VoiceRecordingItem {
  final String path;
  final String fileName;
  final DateTime createdAt;
  final Duration duration;
  final bool isFinished;

  const VoiceRecordingItem({
    required this.path,
    required this.fileName,
    required this.createdAt,
    required this.duration,
    this.isFinished = false,
  });

  VoiceRecordingItem copyWith({
    String? path,
    String? fileName,
    DateTime? createdAt,
    Duration? duration,
    bool? isFinished,
  }) {
    return VoiceRecordingItem(
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      createdAt: createdAt ?? this.createdAt,
      duration: duration ?? this.duration,
      isFinished: isFinished ?? this.isFinished,
    );
  }
}

class VoiceTicketController extends ChangeNotifier with WidgetsBindingObserver {
  VoiceTicketController._() {
    WidgetsBinding.instance.addObserver(this);
    _bindPlayerStreams();
    unawaited(initialize());
  }

  static final VoiceTicketController instance = VoiceTicketController._();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  final List<VoiceRecordingItem> _recordings = [];

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  Timer? _recordTimer;
  DateTime? _recordStartedAt;

  bool _isInitialized = false;
  bool _isLoading = true;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isRecordPressActive = false;
  bool _stopRecordingAfterStart = false;

  String? _recordingPathInProgress;
  String? _activePath;
  String? _errorText;

  Duration _recordDuration = Duration.zero;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  List<VoiceRecordingItem> get recordings => List.unmodifiable(_recordings);
  bool get isLoading => _isLoading;
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  bool get hasOpenTickets => _recordings.any((item) => !item.isFinished);
  int get openTicketCount => _recordings.where((item) => !item.isFinished).length;
  String? get activePath => _activePath;
  String? get errorText => _errorText;
  Duration get recordDuration => _recordDuration;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get recordingPathInProgress => _recordingPathInProgress;

  String? consumeError() {
    final value = _errorText;
    _errorText = null;
    return value;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _loadRecordingsFromDisk();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_handleAppExitOrBackground());
    }
  }

  Future<void> _handleAppExitOrBackground() async {
    _recordTimer?.cancel();
    _recordStartedAt = null;
    _isRecordPressActive = false;
    _stopRecordingAfterStart = false;

    try {
      if (_isRecording) {
        await _recorder.stop();
      }
    } catch (_) {}

    try {
      if (_activePath != null || _isPlaying) {
        await _player.stop();
      }
    } catch (_) {}

    _isRecording = false;
    _isPlaying = false;
    _recordingPathInProgress = null;
    _recordDuration = Duration.zero;
    _position = Duration.zero;
    _duration = Duration.zero;
    _activePath = null;
    notifyListeners();
  }

  void _bindPlayerStreams() {
    _positionSub = _player.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });

    _durationSub = _player.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });

    _playerStateSub = _player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        await _player.pause();
        await _player.seek(Duration.zero);
      }

      _isPlaying =
          state.playing && state.processingState != ProcessingState.completed;
      notifyListeners();
    });
  }

  Future<File> _finishedStateFile() async {
    final tempDir = await getTemporaryDirectory();
    return File(
      p.join(tempDir.path, 'voice_ticket_state.json'),
    );
  }

  Future<Map<String, bool>> _readFinishedStates() async {
    try {
      final file = await _finishedStateFile();
      if (!await file.exists()) return {};

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};

      return decoded.map<String, bool>((key, value) {
        return MapEntry(key.toString(), value == true);
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeFinishedStates(Map<String, bool> states) async {
    final file = await _finishedStateFile();
    await file.writeAsString(jsonEncode(states));
  }

  Future<void> _loadRecordingsFromDisk() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final allEntities = await tempDir.list().toList();
      final finishedStates = await _readFinishedStates();

      final files = allEntities.whereType<File>().where((file) {
        final name = p.basename(file.path).toLowerCase();
        return name.startsWith('voice_') && name.endsWith('.m4a');
      }).toList();

      files.sort((a, b) {
        final aTime = a.statSync().modified;
        final bTime = b.statSync().modified;
        return bTime.compareTo(aTime);
      });

      final loadedItems = <VoiceRecordingItem>[];

      for (final file in files) {
        final stat = await file.stat();
        final duration = await _probeDuration(file.path);
        loadedItems.add(
          VoiceRecordingItem(
            path: file.path,
            fileName: p.basename(file.path),
            createdAt: stat.modified,
            duration: duration,
            isFinished: finishedStates[file.path] ?? false,
          ),
        );
      }

      final cleanedStates = <String, bool>{
        for (final item in loadedItems)
          if (item.isFinished) item.path: true,
      };
      await _writeFinishedStates(cleanedStates);

      _recordings
        ..clear()
        ..addAll(loadedItems);
      _isLoading = false;
      _errorText = null;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorText = 'Aufnahmen konnten nicht geladen werden: $e';
      notifyListeners();
    }
  }

  Future<Duration> _probeDuration(String path) async {
    final probePlayer = AudioPlayer();
    try {
      await probePlayer.setFilePath(path);
      return probePlayer.duration ?? Duration.zero;
    } catch (_) {
      return Duration.zero;
    } finally {
      await probePlayer.dispose();
    }
  }

  Future<void> startRecordingFromPress() async {
    if (_isRecordPressActive || _isRecording) return;

    _isRecordPressActive = true;
    _stopRecordingAfterStart = false;
    notifyListeners();
    await _startRecording();
  }

  Future<void> stopRecordingFromPress() async {
    if (!_isRecordPressActive && !_isRecording) return;

    _isRecordPressActive = false;
    notifyListeners();
    await _stopRecording();
  }

  Future<void> _startRecording() async {
    try {
      _errorText = null;
      notifyListeners();

      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _errorText = 'Mikrofonberechtigung wurde nicht erteilt.';
        notifyListeners();
        return;
      }

      if (_isPlaying) {
        await _player.stop();
      }

      final tempDir = await getTemporaryDirectory();
      final path = p.join(
        tempDir.path,
        'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _recordStartedAt = DateTime.now();
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_recordStartedAt == null) return;
        _recordDuration = DateTime.now().difference(_recordStartedAt!);
        notifyListeners();
      });

      _isRecording = true;
      _recordDuration = Duration.zero;
      _recordingPathInProgress = path;
      notifyListeners();

      if (_stopRecordingAfterStart) {
        await _stopRecording();
      }
    } catch (e) {
      _isRecording = false;
      _recordingPathInProgress = null;
      _errorText = 'Aufnahme konnte nicht gestartet werden: $e';
      notifyListeners();
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) {
      _stopRecordingAfterStart = true;
      return;
    }

    try {
      final path = await _recorder.stop();

      _recordTimer?.cancel();
      _recordStartedAt = null;

      if (path == null) {
        _isRecording = false;
        _recordingPathInProgress = null;
        notifyListeners();
        return;
      }

      final duration = await _probeDuration(path);
      final stat = await File(path).stat();

      final newItem = VoiceRecordingItem(
        path: path,
        fileName: p.basename(path),
        createdAt: stat.modified,
        duration: duration,
      );

      _isRecording = false;
      _recordingPathInProgress = null;
      _recordDuration = Duration.zero;
      _recordings.insert(0, newItem);
      notifyListeners();
    } catch (e) {
      _isRecording = false;
      _recordingPathInProgress = null;
      _errorText = 'Aufnahme konnte nicht gestoppt werden: $e';
      notifyListeners();
    } finally {
      _stopRecordingAfterStart = false;
    }
  }

  Future<void> togglePlayback(VoiceRecordingItem item) async {
    try {
      _errorText = null;
      notifyListeners();

      if (_activePath == item.path) {
        if (_isPlaying) {
          await _player.pause();
        } else {
          await _player.play();
        }
        return;
      }

      await _player.stop();
      await _player.setFilePath(item.path);

      _activePath = item.path;
      _position = Duration.zero;
      _duration = item.duration;
      notifyListeners();

      await _player.play();
    } catch (e) {
      _errorText = 'Wiedergabe fehlgeschlagen: $e';
      notifyListeners();
    }
  }

  Future<void> seekTo(double value) async {
    if (_activePath == null) return;
    await _player.seek(Duration(milliseconds: value.round()));
  }

  Future<void> deleteRecording(VoiceRecordingItem item) async {
    try {
      final isActive = _activePath == item.path;

      if (isActive) {
        await _player.stop();
      }

      final file = File(item.path);
      if (await file.exists()) {
        await file.delete();
      }

      final finishedStates = await _readFinishedStates();
      finishedStates.remove(item.path);

      _recordings.removeWhere((recording) => recording.path == item.path);

      if (isActive) {
        _activePath = null;
        _isPlaying = false;
        _position = Duration.zero;
        _duration = Duration.zero;
      }

      notifyListeners();
      await _writeFinishedStates(finishedStates);
    } catch (e) {
      _errorText = 'Datei konnte nicht gelöscht werden: $e';
      notifyListeners();
    }
  }

  void toggleFinished(VoiceRecordingItem item) {
    final index = _recordings.indexWhere((recording) => recording.path == item.path);
    if (index == -1) return;

    _recordings[index] = _recordings[index].copyWith(
      isFinished: !item.isFinished,
    );
    notifyListeners();
    unawaited(_persistFinishedStates());
  }

  Future<void> _persistFinishedStates() async {
    final states = <String, bool>{};
    for (final item in _recordings) {
      if (item.isFinished) {
        states[item.path] = true;
      }
    }
    await _writeFinishedStates(states);
  }

  Future<void> disposeController() async {
    WidgetsBinding.instance.removeObserver(this);
    _recordTimer?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _playerStateSub?.cancel();
    await _player.dispose();
    await _recorder.dispose();
  }
}

class VoiceTicketsPage extends StatefulWidget {
  const VoiceTicketsPage({super.key});

  @override
  State<VoiceTicketsPage> createState() => _VoiceTicketsPageState();
}

class _VoiceTicketsPageState extends State<VoiceTicketsPage> {
  final VoiceTicketController _controller = VoiceTicketController.instance;
  List<String> _betriebe = [];
  Map<String, List<String>> _betriebStalls = {};
  String _selectedBetrieb = '';
  String _selectedStall = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.initialize());
    unawaited(_loadNavigationOptions());
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    final message = _controller.consumeError();
    if (message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadNavigationOptions() async {
    final prefs = await SharedPreferences.getInstance();
    final betriebe = prefs.getStringList('widget_names') ?? [];
    final Map<String, List<String>> stallMap = {};

    for (final betrieb in betriebe) {
      final stalls = prefs.getStringList(betrieb) ?? [];
      stallMap[betrieb] = List<String>.from(stalls);
    }

    if (!mounted) return;
    setState(() {
      _betriebe = betriebe;
      _betriebStalls = stallMap;

      if (_selectedBetrieb.isNotEmpty && !_betriebe.contains(_selectedBetrieb)) {
        _selectedBetrieb = '';
      }

      final stalls = _selectedStalls;
      final stallLabels = stalls
          .map((fullName) => fullName.split('#').length > 1
              ? fullName.split('#')[1]
              : fullName)
          .toList();
      if (_selectedStall.isNotEmpty && !stallLabels.contains(_selectedStall)) {
        _selectedStall = '';
      }
    });
  }

  List<String> get _selectedStalls =>
      _betriebStalls[_selectedBetrieb] ?? const [];

  bool get _canNavigate =>
      _selectedBetrieb.isNotEmpty && _selectedStall.isNotEmpty;

  String get _selectedFullStallName => '$_selectedBetrieb#$_selectedStall';

  Future<void> _openQuickTarget(String target) async {
    if (!_canNavigate) return;

    Widget page;
    if (target == 'tierbewegung') {
      page = Tierbewegung(stallname: _selectedFullStallName);
    } else if (target == 'ersteintrag') {
      page = Tiermassnahme(stallname: _selectedFullStallName);
    } else {
      page = HistoryPageSecondMedikation(stallname: _selectedFullStallName);
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    await _loadNavigationOptions();
  }

  Widget _buildQuickSelectButton({
    required String label,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OutlinedButton(
        onPressed: onPressed,
        style: active
            ? OutlinedButton.styleFrom(
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              )
            : null,
        child: Text(label),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: FilledButton.tonalIcon(
        onPressed: _canNavigate ? onPressed : null,
        icon: Icon(icon),
        label: Text(label, textAlign: TextAlign.center),
      ),
    );
  }

  Widget _buildBottomQuickNavigation() {
    final stalls = _selectedStalls;
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: Material(
        elevation: 0,
        color: colorScheme.surface,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Schnellnavigation',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _betriebe
                      .map(
                        (betrieb) => _buildQuickSelectButton(
                          label: betrieb,
                          active: _selectedBetrieb == betrieb,
                          onPressed: () {
                            setState(() {
                              _selectedBetrieb = betrieb;
                              _selectedStall = '';
                            });
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: stalls
                      .map(
                        (fullName) {
                          final stallLabel = fullName.split('#').length > 1
                              ? fullName.split('#')[1]
                              : fullName;
                          return _buildQuickSelectButton(
                            label: stallLabel,
                            active: _selectedStall == stallLabel,
                            onPressed: () {
                              setState(() {
                                _selectedStall = stallLabel;
                              });
                            },
                          );
                        },
                      )
                      .toList(),
                ),
              ),
              if (_selectedBetrieb.isNotEmpty && stalls.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Keine Ställe für den gewählten Betrieb vorhanden.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildActionButton(
                    label: 'Tierbewegung',
                    icon: Icons.swap_vert,
                    onPressed: () => _openQuickTarget('tierbewegung'),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    label: 'Ersteintrag',
                    icon: Icons.assignment,
                    onPressed: () => _openQuickTarget('ersteintrag'),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    label: 'Aendern Eintrag',
                    icon: Icons.history,
                    onPressed: () => _openQuickTarget('aendern_eintrag'),
                  ),
                ],
              ),
              if (_betriebe.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Keine Betriebe vorhanden.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dateTime) {
    final y = dateTime.year.toString();
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final h = dateTime.hour.toString().padLeft(2, '0');
    final min = dateTime.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  Widget _buildRecordingTile(VoiceRecordingItem item) {
    final isActive = _controller.activePath == item.path;
    final currentDuration = isActive ? _controller.duration : item.duration;
    final sliderMax = currentDuration.inMilliseconds > 0
        ? currentDuration.inMilliseconds.toDouble()
        : 1.0;
    final sliderValue = isActive
        ? _controller.position.inMilliseconds
            .clamp(0, currentDuration.inMilliseconds)
            .toDouble()
        : 0.0;

    return Dismissible(
      key: ValueKey(item.path),
      direction: _controller.isRecording || !item.isFinished
          ? DismissDirection.none
          : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _controller.deleteRecording(item);
        return true;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _controller.isRecording
                        ? null
                        : () => _controller.togglePlayback(item),
                    icon: Icon(
                      isActive && _controller.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDateTime(item.createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDuration(item.duration),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _controller.isRecording
                        ? null
                        : () => _controller.toggleFinished(item),
                    icon: Icon(
                      item.isFinished
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                    ),
                    color: item.isFinished
                        ? Colors.green.shade700
                        : Colors.grey.shade700,
                  ),
                ],
              ),
              if (isActive) ...[
                const SizedBox(height: 8),
                Slider(
                  value: sliderValue,
                  max: sliderMax,
                  onChanged: _controller.isRecording ? null : _controller.seekTo,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_controller.position)),
                      Text(_formatDuration(currentDuration)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Tickets'),
      ),
      bottomNavigationBar: _buildBottomQuickNavigation(),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: _controller.recordings.isEmpty
                  ? const Center(
                      child: Text(
                        'Noch keine Aufnahmen vorhanden.\nHalte im Tagebuch den Mikrofon-Button gedrückt.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _controller.recordings.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _controller.recordings[index];
                        return _buildRecordingTile(item);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
