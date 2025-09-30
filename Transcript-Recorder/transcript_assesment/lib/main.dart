import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transcript Recorder',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const RecorderPage(),
    );
  }
}

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;

  bool _isRecording = false;
  String? _filePath;
  List<FileSystemEntity> _recordings = [];
  Set<String> _playingFiles = {};

  final String backendUrl = "http://192.168.1.15:3000"; // your PC LAN IP

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
    _openRecorder();
    _openPlayer();
    _loadRecordings();
  }

  Future<void> _openRecorder() async {
    await _recorder!.openRecorder();
    await _recorder!.setSubscriptionDuration(const Duration(milliseconds: 500));
    await Permission.microphone.request();
    await Permission.storage.request();
  }

  Future<void> _openPlayer() async {
    await _player!.openPlayer();
  }

  Future<Directory> _getTranscriptDir() async {
    Directory downloads = Directory('/storage/emulated/0/Download');
    Directory transcriptDir = Directory('${downloads.path}/Transcript Recordings');
    if (!(await transcriptDir.exists())) {
      await transcriptDir.create(recursive: true);
    }
    return transcriptDir;
  }

  Future<void> _startRecording() async {
    Directory transcriptDir = await _getTranscriptDir();
    String fileName = 'recording_${DateTime.now().millisecondsSinceEpoch}.aac';
    _filePath = '${transcriptDir.path}/$fileName';

    await _recorder!.startRecorder(
      toFile: _filePath,
      codec: Codec.aacADTS,
      // androidUi: false // optional
    );

    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder!.stopRecorder();
    setState(() {
      _isRecording = false;
    });
    _loadRecordings();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recording saved at $_filePath')),
    );
  }

  Future<void> _loadRecordings() async {
    Directory transcriptDir = await _getTranscriptDir();
    setState(() {
      _recordings = transcriptDir.listSync()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    });
  }

  void _playRecording(String path) async {
    if (_player!.isPlaying) {
      await _player!.stopPlayer();
      setState(() {
        _playingFiles.remove(path);
      });
    } else {
      await _player!.startPlayer(
        fromURI: path,
        whenFinished: () {
          setState(() {
            _playingFiles.remove(path);
          });
        },
      );
      setState(() {
        _playingFiles.add(path);
      });
    }
  }

  Future<void> _deleteRecording(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        _loadRecordings();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $path')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Delete failed: $e')),
      );
    }
  }

  Future<void> _uploadRecording(String path) async {
    final file = File(path);
    final uri = Uri.parse('$backendUrl/upload-audio');
    var request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('audio', file.path));

    try {
      var response = await request.send();
      var resBody = await response.stream.bytesToString();
      var data = jsonDecode(resBody);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(data['message'] ?? 'Upload successful ✅'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed ❌: $e')),
      );
    }
  }

  Future<void> _transcribeRecording(String path) async {
    final file = File(path);
    final uri = Uri.parse('$backendUrl/upload-audio'); // backend endpoint
    var request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('audio', file.path));

    try {
      var response = await request.send();
      var resBody = await response.stream.bytesToString();
      var data = jsonDecode(resBody);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transcript: ${data['transcription'] ?? data['message'] ?? 'Done'}'),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transcription failed ❌: $e')),
      );
    }
  }

  @override
  void dispose() {
    _recorder!.closeRecorder();
    _player!.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcript Recorder'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _isRecording ? _stopRecording : _startRecording,
            icon: Icon(_isRecording ? Icons.stop : Icons.mic),
            label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRecording ? Colors.red : Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.builder(
              itemCount: _recordings.length,
              itemBuilder: (context, index) {
                String path = _recordings[index].path;

                // sanitize filename to remove Chinese/strange characters
                String fileName = path.split('/').last;
                fileName = Uri.decodeComponent(fileName);
                fileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');

                bool isPlaying = _playingFiles.contains(path);

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  elevation: 3,
                  child: ListTile(
                    title: Text(fileName),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                              isPlaying
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                              color: Colors.green),
                          onPressed: () => _playRecording(path),
                          tooltip: '',
                        ),
                        IconButton(
                          icon: const Icon(Icons.cloud_upload, color: Colors.blue),
                          onPressed: () => _uploadRecording(path),
                          tooltip: '',
                        ),
                        IconButton(
                          icon: const Icon(Icons.text_snippet, color: Colors.purple),
                          onPressed: () => _transcribeRecording(path),
                          tooltip: '',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteRecording(path),
                          tooltip: '',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
