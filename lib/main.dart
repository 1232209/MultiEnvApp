import 'package:flutter/material.dart';
import 'libmpv.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // 替换成你本地的视频绝对路径
  final String videoPath = '/assets/video.mp4';
  final player = MPVPlayer();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter MPV Demo',
      home: Scaffold(
        appBar: AppBar(title: const Text('MPV 视频播放器')),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              player.playNetworkVideo(
                  'https://sf1-cdn-tos.huoshanstatic.com/obj/media-fe/xgplayer_doc_video/mp4/xgplayer-demo-360p.mp4');
            },
            child: const Text('播放视频'),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    player.dispose();
  }
}
