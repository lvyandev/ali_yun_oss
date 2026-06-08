library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dart_aliyun_oss/src/exceptions/exceptions.dart';
import 'package:dio/dio.dart';

export 'date_formatter.dart';
export 'lock.dart';
export 'oss_log_interceptor.dart';
export 'semaphore.dart';

/// 阿里云OSS工具类
///
/// 提供了一组实用工具方法,用于处理OSS操作中的常见任务,如：
/// - 计算分片上传的分片大小和数量
/// - 将错误映射到特定的错误类型
/// - 将文件分块读取为流
///
/// 该类提供的是静态工具方法,不应该被实例化。
class OSSUtils {
  /// 私有构造函数,防止实例化
  OSSUtils._();

  /// 阿里云 OSS 官方 UriEncode。
  ///
  /// OSS V4 签名要求比 Dart [Uri] 默认编码更严格：只有 `A-Z`、`a-z`、
  /// `0-9`、`-`、`_`、`.`、`~` 保持原样，括号、加号、空格和中文等都必须
  /// 按 UTF-8 字节转成大写十六进制 `%XX`。构造路径时可通过 [encodeSlash]
  /// 控制是否保留 `/` 分隔符。
  static String ossUriEncode(String value, {bool encodeSlash = true}) {
    final StringBuffer buffer = StringBuffer();
    for (final int byte in utf8.encode(value)) {
      final bool isUnreserved = (byte >= 0x41 && byte <= 0x5A) ||
          (byte >= 0x61 && byte <= 0x7A) ||
          (byte >= 0x30 && byte <= 0x39) ||
          byte == 0x2D ||
          byte == 0x5F ||
          byte == 0x2E ||
          byte == 0x7E;
      if (isUnreserved || (!encodeSlash && byte == 0x2F)) {
        buffer.writeCharCode(byte);
      } else {
        buffer
            .write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      }
    }
    return buffer.toString();
  }

  /// 计算分片上传的最佳分片配置
  ///
  /// 根据文件大小和用户指定的分片数量（如果有）,计算最佳的分片数量和分片大小。
  /// 该方法实现了自适应的分片策略,优化了不同大小文件的上传效率。
  ///
  /// 分片策略的主要特点：
  /// - 小文件使用较小的分片大小,减少内存占用
  /// - 大文件使用较大的分片大小,提高传输效率
  /// - 分片大小始终保持在阿里云OSS的允许范围内（100KB - 5GB）
  /// - 分片数量始终不超过阿里云OSS的限制（10000个分片）
  ///
  /// 参数：
  /// - [totalFileSize] 文件总大小（字节）
  /// - [userNumberOfParts] 用户指定的分片数量（可选）,如果不提供则自动计算
  ///
  /// 返回一个记录,包含计算出的分片数量（numberOfParts）和分片大小（partSize）
  ///
  /// 示例：
  /// ```dart
  /// // 自动计算分片配置
  /// final config = OSSUtils.calculatePartConfig(100 * 1024 * 1024, null);
  /// print('分片数量: ${config.numberOfParts}, 分片大小: ${config.partSize} 字节');
  ///
  /// // 指定分片数量
  /// final customConfig = OSSUtils.calculatePartConfig(100 * 1024 * 1024, 10);
  /// print('分片数量: ${customConfig.numberOfParts}, 分片大小: ${customConfig.partSize} 字节');
  /// ```
  static ({int numberOfParts, int partSize}) calculatePartConfig(
    int totalFileSize,
    int? userNumberOfParts,
  ) {
    // 调整分片大小参数,更适合移动设备
    const int minPartSize = 100 * 1024; // 100 KB
    const int maxPartSize = 5 * 1024 * 1024 * 1024; // 5 GB
    const int maxParts = 10000;

    // 大文件使用自适应分片大小策略
    int adaptivePartSize(int fileSize) {
      if (fileSize < 10 * 1024 * 1024) {
        // 10MB以下
        return 512 * 1024; // 512KB
      } else if (fileSize < 100 * 1024 * 1024) {
        // 10MB-100MB
        return 1 * 1024 * 1024; // 1MB
      } else if (fileSize < 500 * 1024 * 1024) {
        // 100MB-500MB
        return 2 * 1024 * 1024; // 2MB
      } else {
        // 500MB以上
        return 5 * 1024 * 1024; // 5MB
      }
    }

    if (totalFileSize == 0) {
      return (numberOfParts: 1, partSize: 0);
    }

    int numParts;
    int partSize;

    if (userNumberOfParts != null) {
      // 用户指定了分片数
      numParts = userNumberOfParts.clamp(1, maxParts);
      partSize = (totalFileSize / numParts).ceil();

      if (partSize > maxPartSize) {
        numParts = (totalFileSize / maxPartSize).ceil();
      } else if (partSize < minPartSize && numParts > 1) {
        numParts = (totalFileSize / minPartSize).ceil();
      }

      // 重新限制 part 数量
      numParts = numParts.clamp(1, maxParts);
      partSize = (totalFileSize / numParts).ceil();
    } else {
      // 未指定分片数,使用自适应分片大小
      final int adaptedPartSize = adaptivePartSize(totalFileSize);
      numParts = (totalFileSize / adaptedPartSize).ceil();
      numParts = numParts.clamp(1, maxParts); // 限制最大数量
      partSize = (totalFileSize / numParts).ceil();

      // 检查最小分片大小 (仅当分片数大于1时)
      if (partSize < minPartSize && numParts > 1) {
        partSize = minPartSize;
        numParts = (totalFileSize / partSize).ceil();
        numParts = numParts.clamp(1, maxParts); // 重新限制
        partSize = (totalFileSize / numParts).ceil(); // 重新计算最终 partSize
      }
    }

    // 最终确保 partSize 不小于 minPartSize (除非只有一个分片)
    if (numParts > 1) {
      partSize = math.max(partSize, minPartSize);
    }

    return (numberOfParts: numParts, partSize: partSize);
  }

  /// 将错误映射到特定的OSS错误类型
  ///
  /// 根据错误对象和可选的OSS错误码,将错误映射到适当的 [OSSErrorType] 枚举值。
  /// 这有助于客户端代码根据错误类型执行不同的错误处理逻辑。
  ///
  /// 映射策略：
  /// 1. 首先检查是否提供了OSS错误码,如果有则根据错误码映射
  /// 2. 如果没有错误码或无法根据错误码映射,则根据异常类型映射
  /// 3. 对于 DioException,还会根据 HTTP 状态码进行进一步判断
  ///
  /// 参数：
  /// - [error] 原始错误对象,可以是任何类型的异常
  /// - [ossErrorCode] 可选的OSS错误码,如 'AccessDenied'、'NoSuchKey' 等
  ///
  /// 返回映射后的 [OSSErrorType] 枚举值,如果无法映射则返回 [OSSErrorType.unknown]
  ///
  /// 示例：
  /// ```dart
  /// try {
  ///   // 执行 OSS 操作
  /// } catch (e) {
  ///   // 从响应中提取 OSS 错误码（如果有）
  ///   String? ossErrorCode;
  ///   if (e is DioException && e.response?.data is String) {
  ///     final match = RegExp(r'<Code>(.*?)</Code>').firstMatch(e.response!.data);
  ///     ossErrorCode = match?.group(1);
  ///   }
  ///
  ///   // 映射错误类型
  ///   final errorType = OSSUtils.mapErrorToType(e, ossErrorCode);
  ///
  ///   // 根据错误类型处理
  ///   switch (errorType) {
  ///     case OSSErrorType.accessDenied:
  ///       print('访问被拒绝,请检查权限');
  ///       break;
  ///     case OSSErrorType.notFound:
  ///       print('资源不存在');
  ///       break;
  ///     // 处理其他错误类型...
  ///   }
  /// }
  /// ```
  static OSSErrorType mapErrorToType(Object error, [String? ossErrorCode]) {
    // 优先根据 OSS 错误码判断
    if (ossErrorCode != null) {
      switch (ossErrorCode) {
        case 'AccessDenied':
          return OSSErrorType.accessDenied;
        case 'NoSuchKey':
        case 'NoSuchBucket':
        case 'NoSuchUpload':
          return OSSErrorType.notFound;
        case 'InvalidAccessKeyId':
        case 'SignatureDoesNotMatch':
          return OSSErrorType.signatureMismatch; // 或者 accessDenied
        case 'InvalidArgument':
        case 'InvalidPart':
        case 'InvalidPartOrder':
          return OSSErrorType.invalidArgument;
        case 'RequestTimeout':
          return OSSErrorType.network;
        case 'InternalError':
          return OSSErrorType.serverError;
        // 添加更多 OSS 特定错误码映射...
        // 可以在这里根据需要添加更多常见的OSS错误码及其映射
        // 例如: 'BucketAlreadyExists', 'EntityTooLarge', 'EntityTooSmall', 'InvalidBucketName', etc.
      }
    }

    // 如果没有特定 OSS 错误码或无法映射,则根据异常类型判断
    if (error is DioException) {
      if (error.type == DioExceptionType.cancel) {
        return OSSErrorType.requestCancelled;
      }
      // 可以根据 status code 补充判断
      if (error.response?.statusCode == 403) {
        return OSSErrorType.accessDenied;
      }
      if (error.response?.statusCode == 404) {
        return OSSErrorType.notFound;
      }
      if (error.response?.statusCode != null &&
          error.response!.statusCode! >= 500) {
        return OSSErrorType.serverError;
      }
      // 其他 Dio 错误视为网络问题
      return OSSErrorType.network;
    } else if (error is FileSystemException) {
      return OSSErrorType.fileSystem;
    }
    // ... 其他错误类型映射 ...

    // 默认返回未知错误
    return OSSErrorType.unknown;
  }
}
