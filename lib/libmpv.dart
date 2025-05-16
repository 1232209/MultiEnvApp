import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

/// MPV 事件类型常量
class MpvEventType {
  /// 无事件
  static const int none = 0;

  /// 关闭事件
  static const int shutdown = 1;

  /// 日志消息事件
  static const int logMessage = 2;

  /// 文件结束事件
  static const int endFile = 3;
}

/// MPV 日志消息结构
@Native<MpvLogMessage>()
final class MpvLogMessage extends Struct {
  /// 日志级别
  @Int32()
  external int level;

  /// 日志前缀
  external Pointer<Utf8> prefix;

  /// 日志内容
  external Pointer<Utf8> text;
}

/// MPV 播放器类
///
/// 用于播放网络视频的播放器类，支持多种视频格式和流媒体协议。
class MPVPlayer {
  /// MPV 动态库
  late final DynamicLibrary _lib;

  /// MPV 上下文
  late final Pointer<Void> _ctx;

  /// 是否已销毁
  bool _isDisposed = false;

  /// 是否正在播放
  bool _isPlaying = false;

  /// 是否应该停止
  bool _shouldStop = false;

  /// MPV 函数指针
  late final Pointer<Void> Function() mpvCreate;
  late final int Function(Pointer<Void>) mpvInitialize;
  late final int Function(Pointer<Void>, Pointer<Pointer<Utf8>>) mpvCommand;
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) mpvSetOptionString;
  late final Pointer<Void> Function(Pointer<Void>, double) mpvWaitEvent;
  late final int Function(Pointer<Void>) mpvTerminateDestroy;
  late final int Function(Pointer<Void>, Pointer<Utf8>, int) mpvRequestLogMessages;
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) mpvSetPropertyString;

  /// 构造函数
  ///
  /// 初始化 MPV 播放器，加载动态库并设置基本选项。
  ///
  /// 目前仅支持 macOS 平台。
  MPVPlayer() {
    if (Platform.isMacOS) {
      _lib = DynamicLibrary.open('libmpv.dylib');
    } else {
      throw UnsupportedError('Only macOS is supported for now.');
    }

    _bindFunctions();
    _createContext();
    _setOptions();
    _initializeContext();
  }

  /// 绑定 MPV 函数
  void _bindFunctions() {
    mpvCreate = _lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('mpv_create');
    mpvInitialize = _lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('mpv_initialize');
    mpvCommand = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Pointer<Utf8>>),
        int Function(Pointer<Void>, Pointer<Pointer<Utf8>>)>("mpv_command");
    mpvSetOptionString = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('mpv_set_option_string');
    mpvWaitEvent = _lib.lookupFunction<Pointer<Void> Function(Pointer<Void>, Double),
        Pointer<Void> Function(Pointer<Void>, double)>('mpv_wait_event');
    mpvTerminateDestroy =
        _lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('mpv_terminate_destroy');
    mpvRequestLogMessages = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32),
        int Function(Pointer<Void>, Pointer<Utf8>, int)>('mpv_request_log_messages');
    mpvSetPropertyString = _lib.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('mpv_set_property_string');
  }

  /// 创建 MPV 上下文
  void _createContext() {
    _ctx = mpvCreate();
    if (_ctx.address == 0) {
      throw Exception('Failed to create mpv context.');
    }
  }

  /// 设置 MPV 选项
  void _setOptions() {
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
        final res = mpvSetOptionString(_ctx, name, value);
        if (res < 0) {
          debugPrint('设置选项 ${entry.key}=${entry.value} 失败，错误码: $res');
        }
      } finally {
        calloc.free(name);
        calloc.free(value);
      }
    }
  }

  /// 初始化 MPV 上下文
  void _initializeContext() {
    if (mpvInitialize(_ctx) < 0) {
      throw Exception('Failed to initialize mpv context.');
    }

    // 设置日志级别
    final logLevel = 'v'.toNativeUtf8();
    mpvRequestLogMessages(_ctx, logLevel, 0);
    calloc.free(logLevel);

    // 设置窗口标题
    final title = 'MPV Player'.toNativeUtf8();
    final titleProp = 'title'.toNativeUtf8();
    mpvSetPropertyString(_ctx, titleProp, title);
    calloc.free(title);
    calloc.free(titleProp);
  }

  /// 播放网络视频
  ///
  /// [url] 视频的 URL 地址
  Future<void> playNetworkVideo(String url) async {
    if (_isDisposed) {
      debugPrint('播放器已被销毁');
      return;
    }

    if (_isPlaying) {
      debugPrint('已经在播放中，请先停止当前播放');
      return;
    }

    try {
      debugPrint('开始播放网络视频: $url');
      _isPlaying = true;
      _shouldStop = false;

      final command = ['loadfile', url];
      final Pointer<Pointer<Utf8>> cmdPtr = calloc<Pointer<Utf8>>(command.length + 1);
      try {
        for (var i = 0; i < command.length; i++) {
          cmdPtr[i] = command[i].toNativeUtf8();
        }
        cmdPtr[command.length] = nullptr;

        final ret = mpvCommand(_ctx, cmdPtr);
        if (ret < 0) {
          debugPrint('播放失败，错误码: $ret');
          debugPrint('可能的原因：');
          debugPrint('1. URL格式不正确');
          debugPrint('2. 网络连接失败');
          debugPrint('3. 视频格式不支持');
          debugPrint('4. 服务器响应超时');
          _isPlaying = false;
          return;
        }

        debugPrint('正在播放网络视频: $url');

        while (_isPlaying && !_shouldStop && !_isDisposed) {
          try {
            final eventPtr = mpvWaitEvent(_ctx, 0.1);
            if (eventPtr.address == 0) {
              await Future.delayed(const Duration(milliseconds: 10));
              continue;
            }

            final eventId = eventPtr.cast<Int32>().value;
            if (eventId == MpvEventType.endFile) {
              debugPrint('播放结束');
              _isPlaying = false;
              break;
            } else if (eventId == MpvEventType.logMessage) {
              try {
                final logMsg = eventPtr.cast<MpvLogMessage>();
                if (logMsg.address == 0) {
                  debugPrint('日志消息指针为空');
                  continue;
                }

                final prefixPtr = logMsg.ref.prefix;
                final textPtr = logMsg.ref.text;

                if (prefixPtr.address == 0 || textPtr.address == 0) {
                  debugPrint('日志消息内容为空');
                  continue;
                }

                final prefix = prefixPtr.cast<Utf8>().toDartString();
                final text = textPtr.cast<Utf8>().toDartString();
                debugPrint('MPV日志 [$prefix]: $text');
              } catch (e, stackTrace) {
                debugPrint('处理日志消息时出错: $e');
                debugPrint('错误堆栈: $stackTrace');
              }
            }
          } catch (e) {
            debugPrint('处理事件时出错: $e');
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      } finally {
        for (var i = 0; i < command.length; i++) {
          calloc.free(cmdPtr[i]);
        }
        calloc.free(cmdPtr);
      }
    } catch (e) {
      debugPrint('播放过程中出错: $e');
      _isPlaying = false;
    }
  }

  /// 停止播放
  void stop() {
    if (_isDisposed) {
      debugPrint('播放器已被销毁');
      return;
    }

    if (!_isPlaying) {
      debugPrint('当前没有在播放');
      return;
    }

    debugPrint('正在停止播放...');
    _shouldStop = true;
    _isPlaying = false;
  }

  /// 销毁播放器
  void dispose() {
    if (_isDisposed) {
      debugPrint('播放器已被销毁');
      return;
    }

    debugPrint('正在销毁播放器...');
    stop();
    mpvTerminateDestroy(_ctx);
    _isDisposed = true;
  }
}

// 定义结构体大小
// ignore: constant_identifier_names
const int MPV_LOG_MESSAGE_SIZE = 24; // 根据实际结构体大小调整
