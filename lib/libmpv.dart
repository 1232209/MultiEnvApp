import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

/// MPV 事件类型
class MpvEventType {
  static const int MPV_EVENT_NONE = 0;
  static const int MPV_EVENT_SHUTDOWN = 1;
  static const int MPV_EVENT_LOG_MESSAGE = 2;
  static const int MPV_EVENT_END_FILE = 3;
}

/// MPV 日志消息结构
@Native<MpvLogMessage>()
final class MpvLogMessage extends Struct {
  @Int32()
  external int level;

  external Pointer<Utf8> prefix;

  external Pointer<Utf8> text;
}

/// MPV 播放器类
class MPVPlayer {
  late final DynamicLibrary _lib;
  late final Pointer<Void> _ctx;
  bool _isDisposed = false;
  bool _isPlaying = false;
  bool _shouldStop = false;

  // MPV 函数指针
  late final Pointer<Void> Function() _mpv_create;
  late final int Function(Pointer<Void>) _mpv_initialize;
  late final int Function(Pointer<Void>, Pointer<Pointer<Utf8>>) _mpv_command;
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) _mpv_set_option_string;
  late final Pointer<Void> Function(Pointer<Void>, double) _mpv_wait_event;
  late final int Function(Pointer<Void>) _mpv_terminate_destroy;
  late final int Function(Pointer<Void>, Pointer<Utf8>, int) _mpv_request_log_messages;
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) _mpv_set_property_string;

  /// 构造函数
  MPVPlayer() {
    if (Platform.isMacOS) {
      _lib = DynamicLibrary.open('libmpv.dylib');
    } else {
      throw UnsupportedError('Only macOS is supported for now.');
    }

    // 绑定函数
    _mpv_create = _lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('mpv_create');
    _mpv_initialize = _lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('mpv_initialize');
    _mpv_command = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>),
        int Function(Pointer<Void>, Pointer<Pointer<Utf8>>)>("mpv_command");
    _mpv_set_option_string = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('mpv_set_option_string');
    _mpv_wait_event = _lib.lookupFunction<Pointer<Void> Function(Pointer<Void>, Double),
        Pointer<Void> Function(Pointer<Void>, double)>('mpv_wait_event');
    _mpv_terminate_destroy =
        _lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('mpv_terminate_destroy');
    _mpv_request_log_messages = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32),
        int Function(Pointer<Void>, Pointer<Utf8>, int)>('mpv_request_log_messages');
    _mpv_set_property_string = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('mpv_set_property_string');

    // 创建mpv上下文
    _ctx = _mpv_create();
    if (_ctx.address == 0) {
      throw Exception('Failed to create mpv context.');
    }

    // 设置基本选项
    final options = {
      'vo': 'gpu',
      'gpu-context': 'cocoa',
      'terminal': 'yes',
      'msg-level': 'all=v',
      'no-terminal': 'yes',
      'no-config': 'yes',
      'no-input-default-bindings': 'yes',
      'no-input-terminal': 'yes',
      'no-osc': 'yes',
      'no-osd-bar': 'yes',
      'no-border': 'no',
      'window-controls': 'yes',
      // 网络相关选项
      'network-timeout': '30',
      'cache': 'yes',
      'cache-secs': '30',
      'demuxer-max-bytes': '500M',
      'demuxer-readahead-secs': '30',
      'stream-buffer-size': '50M',
      'ytdl': 'yes',
      'ytdl-format': 'best',
      'user-agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'http-header-fields':
          'Accept: video/webm,video/mp4,video/*;q=0.9,application/ogg;q=0.7,audio/*;q=0.6,*/*;q=0.5\r\nAccept-Language: en-US,en;q=0.9\r\nAccept-Encoding: gzip, deflate, br\r\nConnection: keep-alive\r\nRange: bytes=0-\r\nSec-Fetch-Dest: video\r\nSec-Fetch-Mode: cors\r\nSec-Fetch-Site: cross-site\r\nOrigin: https://vjs.zencdn.net\r\nReferer: https://vjs.zencdn.net/',
      'tls-verify': 'no',
      'tls-ca-file': '',
      'tls-client-cert': '',
      'tls-client-key': '',
      'http-proxy': '',
      'http-keep-alive': 'yes',
      'http-max-requests': '100',
      'http-max-redirects': '10',
      'http-connect-timeout': '30',
      'http-referrer': 'https://vjs.zencdn.net/',
      'http-user-agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };

    for (final entry in options.entries) {
      final name = entry.key.toNativeUtf8();
      final value = entry.value.toNativeUtf8();
      try {
        final res = _mpv_set_option_string(_ctx, name, value);
        if (res < 0) {
          print('设置选项 ${entry.key}=${entry.value} 失败，错误码: $res');
        }
      } finally {
        calloc.free(name);
        calloc.free(value);
      }
    }

    if (_mpv_initialize(_ctx) < 0) {
      throw Exception('Failed to initialize mpv context.');
    }

    // 设置日志级别
    final logLevel = 'v'.toNativeUtf8();
    _mpv_request_log_messages(_ctx, logLevel, 0);
    calloc.free(logLevel);

    // 设置窗口标题
    final title = 'MPV Player'.toNativeUtf8();
    final titleProp = 'title'.toNativeUtf8();
    _mpv_set_property_string(_ctx, titleProp, title);
    calloc.free(title);
    calloc.free(titleProp);
  }

  /// 播放网络视频
  Future<void> playNetworkVideo(String url) async {
    if (_isDisposed) {
      print('播放器已被销毁');
      return;
    }

    if (_isPlaying) {
      print('已经在播放中，请先停止当前播放');
      return;
    }

    try {
      print('开始播放网络视频: $url');
      _isPlaying = true;
      _shouldStop = false;

      final command = ['loadfile', url];
      final Pointer<Pointer<Utf8>> cmdPtr = calloc<Pointer<Utf8>>(command.length + 1);
      try {
        for (var i = 0; i < command.length; i++) {
          cmdPtr[i] = command[i].toNativeUtf8();
        }
        cmdPtr[command.length] = nullptr;

        final ret = _mpv_command(_ctx, cmdPtr);
        if (ret < 0) {
          print('播放失败，错误码: $ret');
          print('可能的原因：');
          print('1. URL格式不正确');
          print('2. 网络连接失败');
          print('3. 视频格式不支持');
          print('4. 服务器响应超时');
          _isPlaying = false;
          return;
        }

        print('正在播放网络视频: $url');

        while (_isPlaying && !_shouldStop && !_isDisposed) {
          try {
            final eventPtr = _mpv_wait_event(_ctx, 0.1);
            if (eventPtr.address == 0) {
              await Future.delayed(Duration(milliseconds: 10));
              continue;
            }

            final eventId = eventPtr.cast<Int32>().value;
            if (eventId == MpvEventType.MPV_EVENT_END_FILE) {
              print('播放结束');
              _isPlaying = false;
              break;
            } else if (eventId == MpvEventType.MPV_EVENT_LOG_MESSAGE) {
              try {
                final logMsg = eventPtr.cast<MpvLogMessage>();
                if (logMsg.address == 0) {
                  print('日志消息指针为空');
                  continue;
                }

                final prefixPtr = logMsg.ref.prefix;
                final textPtr = logMsg.ref.text;

                if (prefixPtr.address == 0 || textPtr.address == 0) {
                  print('日志消息内容为空');
                  continue;
                }

                final prefix = prefixPtr.cast<Utf8>().toDartString();
                final text = textPtr.cast<Utf8>().toDartString();
                print('MPV日志 [$prefix]: $text');
              } catch (e, stackTrace) {
                print('处理日志消息时出错: $e');
                print('错误堆栈: $stackTrace');
              }
            }
          } catch (e) {
            print('处理事件时出错: $e');
            await Future.delayed(Duration(milliseconds: 100));
          }
        }
      } finally {
        for (var i = 0; i < command.length; i++) {
          calloc.free(cmdPtr[i]);
        }
        calloc.free(cmdPtr);
      }
    } catch (e) {
      print('播放过程中出错: $e');
      _isPlaying = false;
    }
  }

  /// 停止播放
  void stop() {
    if (_isDisposed) {
      print('播放器已被销毁');
      return;
    }

    if (!_isPlaying) {
      print('当前没有在播放');
      return;
    }

    print('正在停止播放...');
    _shouldStop = true;
    _isPlaying = false;
  }

  /// 销毁播放器
  void dispose() {
    if (_isDisposed) {
      print('播放器已被销毁');
      return;
    }

    print('正在销毁播放器...');
    stop();
    _mpv_terminate_destroy(_ctx);
    _isDisposed = true;
  }
}

// 定义结构体大小
const int MPV_LOG_MESSAGE_SIZE = 24; // 根据实际结构体大小调整
