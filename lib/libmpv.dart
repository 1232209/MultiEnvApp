import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// MPV 事件类型常量
///
/// 定义了 MPV 播放器可能触发的事件类型，用于事件处理和状态管理。
class MpvEventType {
  /// 无事件，表示当前没有事件发生
  static const int none = 0;

  /// 关闭事件，表示播放器正在关闭
  static const int shutdown = 1;

  /// 日志消息事件，表示有新的日志消息
  static const int logMessage = 2;

  /// 文件结束事件，表示当前视频播放结束
  static const int endFile = 3;
}

/// MPV 日志消息结构
///
/// 用于接收和处理 MPV 播放器的日志消息，包含日志级别、前缀和具体内容。
@Native<MpvLogMessage>()
final class MpvLogMessage extends Struct {
  /// 日志级别，表示日志的严重程度
  @Int32()
  external int level;

  /// 日志前缀，通常包含模块名称
  external Pointer<Utf8> prefix;

  /// 日志内容，具体的日志信息
  external Pointer<Utf8> text;
}

/// MPV 播放器类
///
/// 用于播放网络视频的播放器类，支持多种视频格式和流媒体协议。
/// 通过 FFI 调用 libmpv 动态库实现视频播放功能。
class MPVPlayer {
  /// MPV 动态库实例
  ///
  /// 用于加载和访问 libmpv 动态库中的函数
  late final DynamicLibrary _lib;

  /// MPV 上下文指针
  ///
  /// 存储 MPV 播放器的上下文信息，用于所有 MPV 相关操作
  late final Pointer<Void> _ctx;

  /// 播放器是否已销毁
  ///
  /// 用于防止在播放器销毁后继续调用其方法
  bool _isDisposed = false;

  /// 是否正在播放视频
  ///
  /// 用于跟踪播放器的播放状态
  bool _isPlaying = false;

  /// MPV 函数指针
  ///
  /// 存储从动态库中加载的 MPV 函数，用于后续调用
  /// 创建 MPV 实例
  late final Pointer<Void> Function() mpvCreate;

  /// 初始化 MPV 实例
  late final int Function(Pointer<Void>) mpvInitialize;

  /// 执行 MPV 命令
  late final int Function(Pointer<Void>, Pointer<Pointer<Utf8>>) mpvCommand;

  /// 设置 MPV 选项
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) mpvSetOptionString;

  /// 等待 MPV 事件
  late final Pointer<Void> Function(Pointer<Void>, double) mpvWaitEvent;

  /// 销毁 MPV 实例
  late final int Function(Pointer<Void>) mpvTerminateDestroy;

  /// 请求 MPV 日志消息
  late final int Function(Pointer<Void>, Pointer<Utf8>, int) mpvRequestLogMessages;

  /// 设置 MPV 属性
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) mpvSetPropertyString;

  /// 播放器状态回调
  final void Function(String message)? onStateChanged;

  /// 播放器错误回调
  final void Function(String error)? onError;

  /// 构造函数
  ///
  /// [onStateChanged] 状态变化回调
  /// [onError] 错误回调
  MPVPlayer({this.onStateChanged, this.onError}) {
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
  ///
  /// 从动态库中加载并绑定所有需要的 MPV 函数。
  /// 这些函数将用于后续的播放器操作。
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
  ///
  /// 创建 MPV 播放器的上下文，这是所有 MPV 操作的基础。
  /// 如果创建失败，将抛出异常。
  void _createContext() {
    _ctx = mpvCreate();
    if (_ctx.address == 0) {
      throw Exception('Failed to create mpv context.');
    }
  }

  /// 设置 MPV 选项
  ///
  /// 配置 MPV 播放器的各种选项，包括：
  /// - 视频输出设置
  /// - 窗口控制
  /// - 网络相关选项
  /// - 缓存设置
  /// - HTTP 请求头
  void _setOptions() {
    final options = {
      // 视频输出设置
      'vo': 'libmpv', // 使用 libmpv 视频输出
      'gpu-context': 'cocoa', // 使用 Cocoa 图形上下文
      'terminal': 'yes', // 启用终端输出
      'msg-level': 'all=v', // 设置日志级别

      // 界面控制
      'no-terminal': 'yes', // 禁用终端
      'no-config': 'yes', // 不使用配置文件
      'no-input-default-bindings': 'yes', // 禁用默认按键绑定
      'no-input-terminal': 'yes', // 禁用终端输入
      'no-osc': 'yes', // 禁用屏幕控制
      'no-osd-bar': 'yes', // 禁用屏幕显示条
      'no-border': 'no', // 显示窗口边框
      'window-controls': 'yes', // 启用窗口控制
      'force-window': 'yes', // 强制创建窗口
      'window-scale': '1.0', // 窗口缩放比例

      // 网络相关选项
      'network-timeout': '30', // 网络超时时间（秒）
      'cache': 'yes', // 启用缓存
      'cache-secs': '30', // 缓存秒数
      'demuxer-max-bytes': '500M', // 最大缓冲大小
      'demuxer-readahead-secs': '30', // 预读秒数
      'stream-buffer-size': '50M', // 流缓冲区大小

      // YouTube 下载支持
      'ytdl': 'yes', // 启用 youtube-dl 支持
      'ytdl-format': 'best', // 选择最佳质量

      // HTTP 请求头
      'user-agent':
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'http-header-fields':
          'Accept: video/webm,video/mp4,video/*;q=0.9,application/ogg;q=0.7,audio/*;q=0.6,*/*;q=0.5\r\nAccept-Language: en-US,en;q=0.9\r\nAccept-Encoding: gzip, deflate, br\r\nConnection: keep-alive\r\nRange: bytes=0-\r\nSec-Fetch-Dest: video\r\nSec-Fetch-Mode: cors\r\nSec-Fetch-Site: cross-site\r\nOrigin: https://vjs.zencdn.net\r\nReferer: https://vjs.zencdn.net/',

      // TLS 设置
      'tls-verify': 'no', // 禁用 TLS 验证
      'tls-ca-file': '', // 不使用 CA 证书
      'tls-client-cert': '', // 不使用客户端证书
      'tls-client-key': '', // 不使用客户端密钥

      // HTTP 设置
      'http-proxy': '', // 不使用代理
      'http-keep-alive': 'yes', // 保持连接
      'http-max-requests': '100', // 最大请求数
      'http-max-redirects': '10', // 最大重定向次数
      'http-connect-timeout': '30', // 连接超时时间
      'http-referrer': 'https://vjs.zencdn.net/', // 引用页
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
  ///
  /// 完成 MPV 播放器的初始化，包括：
  /// 1. 初始化 MPV 上下文
  /// 2. 设置日志级别
  /// 3. 设置窗口标题
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
  /// 播放指定 URL 的网络视频，支持多种视频格式和流媒体协议。
  /// 播放过程包括：
  /// 1. 状态检查
  /// 2. 发送播放命令
  /// 3. 处理播放事件
  /// 4. 错误处理
  ///
  /// [url] 视频的 URL 地址，支持 HTTP/HTTPS 协议
  Future<void> playNetworkVideo(String url) async {
    if (_isDisposed) {
      onError?.call('播放器已被销毁');
      return;
    }

    if (_isPlaying) {
      onError?.call('已经在播放中，请先停止当前播放');
      return;
    }

    _isPlaying = true;

    try {
      // 在后台线程中执行播放操作
      await compute(_playVideoInBackground, {
        'url': url,
        'ctx': _ctx.address,
        'mpvCommand': mpvCommand,
        'mpvWaitEvent': mpvWaitEvent,
      });
    } catch (e) {
      onError?.call(e.toString());
    } finally {
      _isPlaying = false;
    }
  }

  /// 在后台线程中播放视频
  static Future<void> _playVideoInBackground(Map<String, dynamic> params) async {
    final url = params['url'] as String;
    final ctx = Pointer<Void>.fromAddress(params['ctx'] as int);
    final mpvCommand = params['mpvCommand'] as Function;
    final mpvWaitEvent = params['mpvWaitEvent'] as Function;

    try {
      // 准备播放命令
      final command = ['loadfile', url];
      final Pointer<Pointer<Utf8>> cmdPtr = calloc<Pointer<Utf8>>(command.length + 1);
      try {
        // 转换命令参数为 UTF8 字符串
        for (var i = 0; i < command.length; i++) {
          cmdPtr[i] = command[i].toNativeUtf8();
        }
        cmdPtr[command.length] = nullptr;

        // 执行播放命令
        final ret = mpvCommand(ctx, cmdPtr);
        if (ret < 0) {
          throw Exception('播放失败，错误码: $ret');
        }

        // 事件处理循环
        while (true) {
          final eventPtr = mpvWaitEvent(ctx, 0.1);
          if (eventPtr.address == 0) {
            await Future.delayed(const Duration(milliseconds: 10));
            continue;
          }

          final eventId = eventPtr.cast<Int32>().value;
          if (eventId == MpvEventType.endFile) {
            break;
          }
        }
      } finally {
        // 释放内存
        for (var i = 0; i < command.length; i++) {
          calloc.free(cmdPtr[i]);
        }
        calloc.free(cmdPtr);
      }
    } catch (e) {
      throw Exception('播放过程中出错: $e');
    }
  }

  /// 停止播放
  ///
  /// 停止当前正在播放的视频。
  /// 会检查播放器状态，确保安全停止。
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
    _isPlaying = false;
  }

  /// 销毁播放器
  ///
  /// 清理播放器资源，包括：
  /// 1. 停止播放
  /// 2. 销毁 MPV 上下文
  /// 3. 标记播放器为已销毁状态
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

/// MPV 日志消息结构体大小
///
/// 用于内存分配和结构体操作
// ignore: constant_identifier_names
const int MPV_LOG_MESSAGE_SIZE = 24; // 根据实际结构体大小调整
