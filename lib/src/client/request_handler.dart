import 'dart:developer';

import 'package:dio/dio.dart';

import 'request_manager.dart';

/// OSS请求处理器
///
/// 用于处理阿里云OSS的HTTP请求,支持各种HTTP方法（GET、PUT、POST、DELETE、HEAD、PATCH）
/// 以及特殊的DOWNLOAD操作。该类是客户端与阿里云OSS服务器交互的核心组件。
///
/// 主要功能：
/// - 封装并统一处理各种HTTP请求
/// - 管理请求的生命周期和取消机制
/// - 提供统一的错误处理和资源清理
/// - 支持进度回调（上传和下载）
///
/// 内部使用 [Dio] 客户端进行实际的网络请求,并与 [OSSRequestManager] 协同工作
/// 管理请求的取消令牌。
class OSSRequestHandler {
  /// 构造函数
  ///
  /// 创建一个新的 OSS 请求处理器实例。
  ///
  /// 参数：
  /// - [_dio] 用于执行 HTTP 请求的 Dio 实例,应已配置好适当的超时和拦截器
  /// - [_requestManager] 请求管理器实例,用于管理请求的取消令牌
  OSSRequestHandler(this._dio, this._requestManager);
  final Dio _dio;
  final OSSRequestManager _requestManager;

  /// 关闭底层 Dio 客户端。
  ///
  /// 参数：
  /// - [force] 是否强制关闭仍在进行的连接
  void close({bool force = false}) {
    _dio.close(force: force);
  }

  /// 封装请求执行逻辑,处理 CancelToken 和资源清理
  ///
  /// 该方法提供了一个统一的框架来执行 OSS 请求,包括：
  /// - 管理取消令牌的生命周期
  /// - 处理请求异常并记录日志
  /// - 确保资源正确清理（即使在出错时）
  ///
  /// 参数：
  /// - [requestKey] 请求的唯一标识符,用于管理取消令牌,通常是文件键或其他唯一标识
  /// - [cancelToken] 可选的外部提供的取消令牌,如果为 null,将创建新的令牌
  /// - [requestExecutor] 实际执行请求的函数,接收一个 CancelToken 并返回 `Future<T>`
  ///
  /// 返回一个 `Future<T>`,其中 T 是请求执行器返回的类型
  ///
  /// 异常处理：
  /// - 所有异常都会被记录并重新抛出,以便调用者可以处理
  /// - 无论请求成功还是失败,都会清理相关的取消令牌
  Future<T> executeRequest<T>(
    String requestKey,
    CancelToken? cancelToken,
    Future<T> Function(CancelToken cancelToken) requestExecutor,
  ) async {
    // 验证请求键
    if (requestKey.isEmpty) {
      throw ArgumentError('请求键不能为空');
    }

    // 获取或创建取消令牌
    final CancelToken effectiveToken =
        cancelToken ?? _requestManager.getToken(requestKey);

    // 记录请求开始
    log('OSS 请求开始: $requestKey');
    final Stopwatch stopwatch = Stopwatch()..start();

    try {
      // 使用 try-catch 块包裹实际的请求执行
      try {
        final T result = await requestExecutor(effectiveToken);
        // 记录成功完成的请求
        log('OSS 请求成功: $requestKey (耗时: ${stopwatch.elapsedMilliseconds}ms)');
        return result;
      } catch (e, s) {
        // 记录详细的错误信息
        log(
          'OSS 请求错误: $requestKey (耗时: ${stopwatch.elapsedMilliseconds}ms)',
          error: e,
          stackTrace: s,
        );

        // 重新抛出异常,让调用者处理具体的错误类型
        rethrow;
      }
    } finally {
      // 无论成功还是失败,都确保移除 CancelToken
      if (cancelToken == null) {
        // 只清理内部创建的令牌
        _requestManager.removeToken(requestKey);
      }
      stopwatch.stop();
    }
  }

  /// 发送OSS请求
  ///
  /// 该方法是所有 OSS 请求的入口点,根据提供的 HTTP 方法选择适当的 Dio 方法来执行请求。
  /// 支持标准的 HTTP 方法（GET、POST、PUT、DELETE、HEAD、PATCH）以及特殊的 DOWNLOAD 操作。
  ///
  /// 参数：
  /// - [uri] 请求的完整 URI,包含协议、主机、路径和查询参数
  /// - [method] HTTP 方法,大小写不敏感（内部会转换为大写）
  /// - [options] Dio 请求配置选项,包含头部、超时等设置
  /// - [data] 请求体数据,用于 POST、PUT 等包含请求体的方法
  /// - [optionalParams] 额外的参数,主要用于 DOWNLOAD 方法,包含保存路径等
  /// - [cancelToken] 用于取消请求的令牌
  /// - [onSendProgress] 发送进度回调函数,用于监控上传进度
  /// - [onReceiveProgress] 接收进度回调函数,用于监控下载进度
  ///
  /// 返回一个 `Future<Response>`,包含请求的响应数据
  ///
  /// 异常：
  /// - 当使用不支持的 HTTP 方法时,抛出 `UnimplementedError`
  /// - 其他网络相关异常将由 Dio 抛出,如 `DioException`
  Future<Response<dynamic>> sendRequest({
    required Uri uri,
    required String method,
    required Options options,
    dynamic data,
    Map<String, dynamic>? optionalParams,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    // 验证必要参数
    if (uri.host.isEmpty) {
      throw ArgumentError('无效的 URI：缺少主机名');
    }

    // 标准化方法名（转换为大写）
    final String normalizedMethod = method.trim().toUpperCase();

    switch (normalizedMethod) {
      case 'GET':
        return _dio.getUri(
          uri,
          options: options,
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
        );
      case 'POST':
        return _dio.postUri(
          uri,
          data: data,
          options: options,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress,
        );
      case 'DELETE':
        return _dio.deleteUri(uri, options: options, cancelToken: cancelToken);
      case 'HEAD':
        return _dio.headUri(uri, options: options, cancelToken: cancelToken);
      case 'PATCH':
        return _dio.patchUri(
          uri,
          data: data,
          options: options,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress,
        );
      case 'DOWNLOAD':
        // 验证下载所需的参数
        final dynamic savePath = optionalParams?['savePath'];
        if (savePath == null) {
          throw ArgumentError('下载请求必须提供 savePath 参数');
        }

        // 获取可选参数并设置默认值
        final bool deleteOnError = optionalParams?['deleteOnError'] ?? true;
        final FileAccessMode fileAccessMode =
            (optionalParams?['fileAccessMode'] as FileAccessMode?) ??
                FileAccessMode.write;

        // 执行下载请求
        return _dio.downloadUri(
          uri,
          savePath,
          deleteOnError: deleteOnError,
          data: data, // 用于 POST 下载
          fileAccessMode: fileAccessMode,
          options: options,
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
        );
      case 'PUT':
        return _dio.putUri(
          uri,
          data: data,
          options: options,
          cancelToken: cancelToken,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress,
        );
      default:
        throw UnimplementedError('Unsupported method: $method');
    }
  }
}
