import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    unawaited(_controller.initialize());
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

  Widget _buildStatusCard() {
    VoiceRecordingItem? activeRecording;
    for (final item in _controller.recordings) {
      if (item.path == _controller.activePath) {
        activeRecording = item;
        break;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              _controller.isRecording ? Icons.mic : Icons.library_music,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _controller.isRecording
                        ? 'Aufnahme läuft'
                        : '${_controller.recordings.length} Aufnahme(n) gefunden',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _controller.isRecording
                        ? 'Dauer: ${_formatDuration(_controller.recordDuration)}'
                        : activeRecording != null
                            ? 'Aktive Wiedergabe: ${_formatDateTime(activeRecording.createdAt)}'
                            : 'Noch nichts ausgewählt',
                  ),
                  if (_controller.recordingPathInProgress != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      p.basename(_controller.recordingPathInProgress!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            Expanded(
              child: _controller.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _controller.recordings.isEmpty
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
