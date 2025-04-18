import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Subtitle Burner',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SubtitleBurnerScreen(),
    );
  }
}

class SubtitleEntrys {
  final int number;
  final String startTime;
  final String endTime;
  final String text;

  SubtitleEntrys({
    required this.number,
    required this.startTime,
    required this.endTime,
    required this.text,
  });

  // Convert time format from "00:00:01,000" to milliseconds
  int get startTimeInMilliseconds {
    final parts = startTime.split(':');
    final secondsParts = parts[2].split(',');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final seconds = int.parse(secondsParts[0]);
    final milliseconds = int.parse(secondsParts[1]);

    return (hours * 3600 + minutes * 60 + seconds) * 1000 + milliseconds;
  }

  int get endTimeInMilliseconds {
    final parts = endTime.split(':');
    final secondsParts = parts[2].split(',');
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final seconds = int.parse(secondsParts[0]);
    final milliseconds = int.parse(secondsParts[1]);

    return (hours * 3600 + minutes * 60 + seconds) * 1000 + milliseconds;
  }
}

class SubtitleBurnerScreen extends StatefulWidget {
  const SubtitleBurnerScreen({Key? key}) : super(key: key);

  @override
  State<SubtitleBurnerScreen> createState() => _SubtitleBurnerScreenState();
}

class _SubtitleBurnerScreenState extends State<SubtitleBurnerScreen> {
  File? _selectedVideo;
  File? _processedVideo;
  bool _isProcessing = false;
  String _processingStatus = '';
  VideoPlayerController? _controller;
  String? _currentSubtitle;
  bool _showSubtitlesOnPreview = true;
  Directory? _appVideosDirectory;

  // Subtitle list
  final List<SubtitleEntrys> subtitleList = [
    SubtitleEntrys(
      number: 1,
      startTime: '00:00:01,000',
      endTime: '00:00:04,000',
      text: 'Welcome to the video!',
    ),
    SubtitleEntrys(
      number: 2,
      startTime: '00:00:05,000',
      endTime: '00:00:07,000',
      text: 'Let\'s learn something new.',
    ),
    SubtitleEntrys(
      number: 3,
      startTime: '00:00:08,000',
      endTime: '00:00:10,000',
      text: 'Flutter is awesome!',
    ),
    SubtitleEntrys(
      number: 4,
      startTime: '00:00:11,000',
      endTime: '00:00:13,000',
      text: 'You can build apps fast.',
    ),
    SubtitleEntrys(
      number: 5,
      startTime: '00:00:14,000',
      endTime: '00:00:16,000',
      text: 'Let\'s get started.',
    ),
    SubtitleEntrys(
      number: 6,
      startTime: '00:00:17,000',
      endTime: '00:00:20,000',
      text: 'Thanks for watching!',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _setupAppDirectory();
  }

  Future<void> _setupAppDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    _appVideosDirectory = Directory('${appDir.path}/processed_videos');

    // Create the directory if it doesn't exist
    if (!await _appVideosDirectory!.exists()) {
      await _appVideosDirectory!.create(recursive: true);
    }
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    await Permission.videos.request();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoPositionChanged);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.gallery);

    if (video != null) {
      setState(() {
        _selectedVideo = File(video.path);
        _processedVideo = null;
        _initializeVideoPlayer(_selectedVideo!);
      });
    }
  }

  void _initializeVideoPlayer(File videoFile) {
    _controller?.dispose();
    _controller = VideoPlayerController.file(videoFile)
      ..initialize().then((_) {
        setState(() {});
        _controller!.addListener(_onVideoPositionChanged);
      });
  }

  void _onVideoPositionChanged() {
    if (_controller == null || !_controller!.value.isPlaying) return;

    final int currentPositionMs = _controller!.value.position.inMilliseconds;
    String? subtitleText;

    for (var subtitle in subtitleList) {
      if (currentPositionMs >= subtitle.startTimeInMilliseconds &&
          currentPositionMs <= subtitle.endTimeInMilliseconds) {
        subtitleText = subtitle.text;
        break;
      }
    }

    if (_currentSubtitle != subtitleText) {
      setState(() {
        _currentSubtitle = subtitleText;
      });
    }
  }

  Future<String> _createSubtitleFile() async {
    final Directory? appDocDir = await getExternalStorageDirectory();
    final String subtitlePath = '${appDocDir?.path}/subtitles.srt';
    final File subtitleFile = File(subtitlePath);

    String srtContent = '';
    for (var entry in subtitleList) {
      srtContent += '${entry.number}\n';
      srtContent += '${entry.startTime} --> ${entry.endTime}\n';
      srtContent += '${entry.text}\n\n';
    }

    await subtitleFile.writeAsString(srtContent);
    return subtitlePath;
  }

  Future<void> _burnSubtitles() async {
    if (_selectedVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a video first')),
      );
      return;
    }

    if (_appVideosDirectory == null) {
      await _setupAppDirectory();
    }

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Creating subtitle file...';
    });

    try {
      final String subtitlePath = await _createSubtitleFile();
      final String fileName = 'video_with_subtitles_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final String outputPath = '${_appVideosDirectory!.path}/$fileName';

      setState(() {
        _processingStatus = 'Processing video with FFmpeg...';
      });

      // FFmpeg command to burn subtitles
      final String command = '-y -i "${_selectedVideo!.path}" '
          '-vf "subtitles=\'$subtitlePath\':force_style=\'Fontsize=24,PrimaryColour=&HFFFFFF&\'" '
          '-c:v libx264 -preset fast -crf 23 '
          '-c:a aac -b:a 128k '
          '-movflags +faststart '
          '"$outputPath"';

      await FFmpegKit.execute(command).then((session) async {
        final returnCode = await session.getReturnCode();

        if (ReturnCode.isSuccess(returnCode)) {
          // Verify the file exists before proceeding
          final File processedFile = File(outputPath);
          if (await processedFile.exists()) {
            setState(() {
              _processedVideo = processedFile;
              _processingStatus = 'Video processing completed';
              _initializeVideoPlayer(_processedVideo!);
            });
          } else {
            setState(() {
              _processingStatus = 'Error: Output file was not created';
            });
          }
        } else {
          final logs = await session.getLogs();
          String errorMessage = 'Error processing video';
          for (var log in logs) {
            print(log.getMessage());
          }
          setState(() {
            _processingStatus = errorMessage;
          });
        }
      });
    } catch (e) {
      setState(() {
        _processingStatus = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _showProcessedVideos() async {
    if (_appVideosDirectory == null) {
      await _setupAppDirectory();
    }

    final List<FileSystemEntity> files = _appVideosDirectory!.listSync();
    final List<File> videoFiles = files
        .whereType<File>()
        .where((file) => file.path.endsWith('.mp4'))
        .toList();

    if (videoFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No processed videos found')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Processed Videos'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: videoFiles.length,
            itemBuilder: (context, index) {
              final file = videoFiles[index];
              final fileName = path.basename(file.path);
              return ListTile(
                title: Text(fileName),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _processedVideo = file;
                    _initializeVideoPlayer(file);
                  });
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    await file.delete();
                    Navigator.pop(context);
                    _showProcessedVideos();
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subtitle Burner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder),
            tooltip: 'Processed Videos',
            onPressed: _showProcessedVideos,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton(
                onPressed: _pickVideo,
                child: const Text('Pick Video'),
              ),
              const SizedBox(height: 16),
              if (_selectedVideo != null) ...[
                Text('Selected video: ${path.basename(_selectedVideo!.path)}'),
                const SizedBox(height: 16),
                if (_controller != null && _controller!.value.isInitialized)
                  Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            VideoPlayer(_controller!),
                            IconButton(
                              icon: Icon(
                                _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                size: 50,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_controller!.value.isPlaying) {
                                    _controller!.pause();
                                  } else {
                                    _controller!.play();
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      if (_showSubtitlesOnPreview && _currentSubtitle != null)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          margin: const EdgeInsets.only(bottom: 40),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _currentSubtitle!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: _showSubtitlesOnPreview,
                      onChanged: (value) {
                        setState(() {
                          _showSubtitlesOnPreview = value ?? true;
                        });
                      },
                    ),
                    const Text('Show subtitles on preview'),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isProcessing ? null : _burnSubtitles,
                  child: const Text('Burn Subtitles & Save to App Directory'),
                ),
              ],
              if (_isProcessing) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 8),
                Center(child: Text(_processingStatus)),
              ],
              if (_processedVideo != null && !_isProcessing) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text('Processed video saved to app directory:\n${_processedVideo!.path}',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        if (_processedVideo != null) {
                          _controller?.dispose();
                          _initializeVideoPlayer(_processedVideo!);
                        }
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                    ),
                    // ElevatedButton.icon(
                    //   onPressed: _shareVideo,
                    //   icon: const Icon(Icons.share),
                    //   label: const Text('Share'),
                    // ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              const Text('Subtitles to burn:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (var subtitle in subtitleList)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${subtitle.number}. ${subtitle.text}'),
                        Text('${subtitle.startTime} → ${subtitle.endTime}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}