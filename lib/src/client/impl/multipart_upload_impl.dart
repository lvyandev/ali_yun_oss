import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dart_aliyun_oss/src/client/client.dart';
import 'package:dart_aliyun_oss/src/exceptions/exceptions.dart';
import 'package:dart_aliyun_oss/src/interfaces/service.dart';
import 'package:dart_aliyun_oss/src/models/models.dart';
import 'package:dart_aliyun_oss/src/utils/utils.dart';
import 'package:dio/dio.dart';

mixin MultipartUploadImpl on IOSSService {
  /// 阿里云 OSS 分片上传实现
  ///
  /// 提供高效、可靠的大文件上传能力,自动处理分片逻辑,支持并发上传。
  /// 针对移动设备进行了特别优化,采用流式处理和内存管理策略,确保在资源受限环境下的稳定性。
  ///
  /// 主要特性：
  /// - 自动分片：根据文件大小智能计算最优分片大小和数量
  /// - 并发控制：支持自定义并发度,默认为 5
  /// - 断点续传：支持从断点处恢复上传（需要外部保存上传状态）
  /// - 进度回调：支持整体上传进度和单片上传进度的监控
  /// - 错误处理：完善的错误检测和恢复机制
  /// - 资源管理：优化的内存使用,采用流式处理避免大文件加载
  ///
  /// 工作流程：
  /// 1. 文件检查：验证文件存在性和大小
  /// 2. 分片计算：根据文件大小确定分片策略
  /// 3. 初始化上传：获取 uploadId
  /// 4. 并发上传：多线程上传各个分片
  /// 5. 完成上传：合并所有分片
  ///
  /// 性能优化：
  /// - 使用 StreamController 实现流式读取,避免一次性加载大文件
  /// - 采用信号量控制并发数,避免资源耗尽
  /// - 优化的缓冲区大小（64KB）,平衡内存使用和传输效率
  ///
  /// 错误处理：
  /// - 完整的异常捕获和转换机制
  /// - 分片上传失败自动中止
  /// - 支持请求取消
  /// - 资源自动清理
  ///
  /// 使用示例：
  /// ```dart
  /// final response = await client.multipartUpload(
  ///   File('large_file.zip'),
  ///   'example/large_file.zip',
  ///   maxConcurrency: 3,
  ///   onProgress: (count, total) {
  ///     print('总进度：${count / total * 100}%');
  ///   },
  ///   onPartProgress: (partNumber, count, total) {
  ///     print('分片 $partNumber 进度：${count / total * 100}%');
  ///   },
  /// );
  /// ```
  ///
  /// 注意事项：
  /// - 建议对大文件（如>100MB）使用分片上传
  /// - 单个分片大小范围：100KB~5GB
  /// - 分片数量限制：1~10000
  /// - 确保网络环境稳定,避免中断导致上传失败
  /// - 建议实现断点续传机制,保存上传状态
  ///
  /// 相关接口：
  /// - [initiateMultipartUpload]: 初始化分片上传
  /// - [uploadPart]: 上传单个分片
  /// - [completeMultipartUpload]: 完成分片上传
  /// - [abortMultipartUpload]: 取消分片上传
  ///
  /// 参考：
  /// - [阿里云 OSS 分片上传文档](https://help.aliyun.com/document_detail/31850.html)
  ///
  /// [file] 要上传的文件
  /// [ossObjectKey] OSS 对象键
  /// [maxConcurrency] 最大并发上传分片数,默认为 5
  /// [numberOfParts] 可选的期望分片数量
  /// [onPartProgress] 单个分片上传进度回调
  /// [cancelToken] 可选的取消令牌
  /// [params] 可选的请求参数
  /// 返回完成分片上传的响应
  @override
  Future<Response<CompleteMultipartUploadResult>> multipartUpload(
    File file,
    String ossObjectKey, {
    int? maxConcurrency,
    int? numberOfParts,
    PartProgressCallback? onPartProgress,
    CancelToken? cancelToken,
    OSSRequestParams? params,
  }) async {
    final OSSClient client = this as OSSClient;
    final String requestKey =
        'multipartUpload_${ossObjectKey}_${DateTime.now().millisecondsSinceEpoch}';
    final Lock progressLock = Lock();

    return client.requestHandler.executeRequest(requestKey, cancelToken, (
      CancelToken effectiveToken,
    ) async {
      params = params?.copyWith(cancelToken: effectiveToken);

      String? uploadId;
      List<PartInfo?> uploadedPartsInfo = <PartInfo?>[];
      int totalUploadedSize = 0;
      bool hasErrorOccurred = false;

      try {
        // 1. 检查文件是否存在
        if (!file.existsSync()) {
          throw OSSException(
            type: OSSErrorType.fileSystem,
            message: '文件未找到: ${file.path}',
          );
        }

        final int totalFileSize = file.lengthSync();
        if (totalFileSize == 0) {
          throw const OSSException(
            type: OSSErrorType.invalidArgument,
            message: '文件大小为0,不能进行分片上传',
          );
        }

        // 2. 计算分片配置
        final ({int numberOfParts, int partSize}) partConfig =
            OSSUtils.calculatePartConfig(
          totalFileSize,
          numberOfParts,
        );
        final int numParts = partConfig.numberOfParts;
        final int partSize = partConfig.partSize;

        // 验证分片大小是否在允许范围内
        if (partSize < 100 * 1024 || partSize > 5 * 1024 * 1024 * 1024) {
          throw const OSSException(
            type: OSSErrorType.invalidArgument,
            message: '分片大小必须在 100KB 到 5GB 之间',
          );
        }

        // 验证分片数量是否在允许范围内
        if (numParts < 1 || numParts > 10000) {
          throw const OSSException(
            type: OSSErrorType.invalidArgument,
            message: '分片数量必须在 1 到 10000 之间',
          );
        }

        log('分片上传配置: 文件大小=$totalFileSize字节, 分片数=$numParts, 分片大小=$partSize字节');

        uploadedPartsInfo = List<PartInfo?>.filled(numParts, null);
        params?.onSendProgress?.call(0, totalFileSize);

        // 3. 初始化分片上传
        final Response<InitiateMultipartUploadResult> initResponse =
            await client.initiateMultipartUpload(ossObjectKey, params: params);
        uploadId = initResponse.data?.uploadId;
        if (uploadId == null || uploadId.isEmpty) {
          throw OSSException(
            type: OSSErrorType.initiateMultipartFailed,
            message: '初始化分片上传失败, uploadId 为 null 或为空。',
            response: initResponse,
            requestOptions: initResponse.requestOptions,
          );
        }

        if (effectiveToken.isCancelled) {
          throw OSSException(
            type: OSSErrorType.requestCancelled,
            message: '分片上传在初始化后被取消。',
            requestOptions: initResponse.requestOptions,
            originalError: DioException.requestCancelled(
              requestOptions: initResponse.requestOptions,
              reason: '分片上传在初始化后被取消。',
            ),
          );
        }

        // 4. 并发上传分片 - 使用信号量控制并发
        final Semaphore semaphore = Semaphore(
          maxConcurrency ?? client.config.maxConcurrency,
        );
        final List<Future<void>> partTasks = <Future<void>>[];

        for (int i = 0; i < numParts; i++) {
          final int partNumber = i + 1;
          final int offset = i * partSize;
          final int readLength = math.min(partSize, totalFileSize - offset);

          if (readLength <= 0) {
            break;
          }

          // 为每个分片创建一个独立的上传任务,使用信号量控制并发
          final Future<void> partTask = semaphore.acquire().then((_) async {
            if (hasErrorOccurred || effectiveToken.isCancelled) {
              semaphore.release();
              return;
            }

            try {
              // 使用流式上传替代一次性读取整个分片
              await _uploadPartStreaming(
                client: client,
                file: file,
                offset: offset,
                length: readLength,
                ossObjectKey: ossObjectKey,
                partNumber: partNumber,
                uploadId: uploadId!,
                params: params,
                effectiveToken: effectiveToken,
                onPartProgress: onPartProgress,
                isErrorGlobally: hasErrorOccurred,
                onSuccess: (PartInfo partInfo) {
                  uploadedPartsInfo[i] = partInfo;
                  progressLock.synchronized(() {
                    if (!hasErrorOccurred) {
                      totalUploadedSize += readLength;
                      params?.onSendProgress
                          ?.call(totalUploadedSize, totalFileSize);
                    }
                  });
                },
                onError: (dynamic e, StackTrace s) {
                  log(
                    '上传分片 $partNumber 时出错',
                    error: e,
                    stackTrace: s,
                    level: 1000,
                  );
                  progressLock.synchronized(() {
                    if (!hasErrorOccurred) {
                      hasErrorOccurred = true;
                    }
                  });
                },
              );
            } catch (e, s) {
              log('处理分片 $partNumber 时出错', error: e, stackTrace: s, level: 1000);
              await progressLock.synchronized(() {
                if (!hasErrorOccurred) {
                  hasErrorOccurred = true;
                }
              });
              rethrow;
            } finally {
              semaphore.release();
            }
          });

          partTasks.add(partTask);
        }

        // 等待所有任务完成
        await Future.wait(partTasks);

        // 检查是否有错误发生或请求被取消
        if (hasErrorOccurred) {
          throw const OSSException(
            type: OSSErrorType.uploadPartFailed,
            message: '分片上传过程中发生错误,上传已中止。',
          );
        }

        if (effectiveToken.isCancelled) {
          throw const OSSException(
            type: OSSErrorType.requestCancelled,
            message: '分片上传在上传分片过程中被取消。',
          );
        }

        // 检查是否所有分片都上传成功
        final List<PartInfo> validParts =
            uploadedPartsInfo.whereType<PartInfo>().toList();
        if (validParts.length != numParts) {
          throw OSSException(
            type: OSSErrorType.uploadPartFailed,
            message: '部分分片上传失败,预期 $numParts 个分片,实际成功 ${validParts.length} 个。',
          );
        }

        // 5. 完成分片上传
        final Response<CompleteMultipartUploadResult> completeResponse =
            await client.completeMultipartUpload(
          ossObjectKey,
          uploadId,
          validParts,
          params: params,
        );

        return completeResponse;
      } catch (e) {
        // 如果上传过程中出错,尝试中止分片上传
        if (uploadId != null && uploadId.isNotEmpty) {
          try {
            log('上传过程中出错,尝试中止分片上传: $uploadId');
            await client.abortMultipartUpload(
              ossObjectKey,
              uploadId,
              params: params?.copyWith(),
            );
            log('成功中止分片上传: $uploadId');
          } catch (abortError) {
            log('中止分片上传失败: $abortError');
          }
        }

        // 重新抛出原始异常
        if (e is OSSException) {
          rethrow;
        } else if (e is DioException && e.type == DioExceptionType.cancel) {
          throw OSSException(
            type: OSSErrorType.requestCancelled,
            message: '分片上传被取消。',
            originalError: e,
          );
        } else {
          throw OSSException(
            type: OSSErrorType.unknown,
            message: '分片上传失败: $e',
            originalError: e,
          );
        }
      }
    });
  }

  /// 使用断点续传方式上传文件。
  @override
  Future<Response<CompleteMultipartUploadResult>> resumableUpload(
    File file,
    String ossObjectKey, {
    OSSMultipartUploadCheckpoint? checkpoint,
    int? partSize,
    int maxConcurrency = 5,
    PartProgressCallback? onPartProgress,
    MultipartUploadCheckpointCallback? onCheckpoint,
    bool abortOnError = false,
    CancelToken? cancelToken,
    OSSRequestParams? params,
  }) async {
    final OSSClient client = this as OSSClient;
    final String requestKey =
        'resumableUpload_${ossObjectKey}_${DateTime.now().millisecondsSinceEpoch}';

    return client.requestHandler.executeRequest(requestKey, cancelToken, (
      CancelToken effectiveToken,
    ) async {
      final OSSRequestParams effectiveParams =
          (params ?? const OSSRequestParams()).copyWith(
        cancelToken: effectiveToken,
      );
      String? uploadId = checkpoint?.uploadId;
      OSSMultipartUploadCheckpoint? currentCheckpoint = checkpoint;

      try {
        _validateResumableUploadInput(
          file: file,
          ossObjectKey: ossObjectKey,
          maxConcurrency: maxConcurrency,
        );

        final int totalFileSize = file.lengthSync();
        final int effectivePartSize = _resolveResumablePartSize(
          totalFileSize: totalFileSize,
          checkpoint: currentCheckpoint,
          partSize: partSize,
        );
        final int numberOfParts = (totalFileSize / effectivePartSize).ceil();

        _validateResumablePartConfig(
          partSize: effectivePartSize,
          numberOfParts: numberOfParts,
        );

        if (currentCheckpoint != null &&
            !currentCheckpoint.matchesFile(file, ossObjectKey)) {
          throw const OSSException(
            type: OSSErrorType.invalidArgument,
            message: '断点续传检查点与当前文件不匹配，请重新初始化上传。',
          );
        }

        if (uploadId == null || uploadId.isEmpty) {
          final Response<InitiateMultipartUploadResult> initResponse =
              await client.initiateMultipartUpload(
            ossObjectKey,
            params: effectiveParams,
          );
          uploadId = initResponse.data?.uploadId;
          if (uploadId == null || uploadId.isEmpty) {
            throw OSSException(
              type: OSSErrorType.initiateMultipartFailed,
              message: '初始化断点续传失败, uploadId 为 null 或为空。',
              response: initResponse,
              requestOptions: initResponse.requestOptions,
            );
          }
          currentCheckpoint = OSSMultipartUploadCheckpoint.fromFile(
            file: file,
            objectKey: ossObjectKey,
            uploadId: uploadId,
            partSize: effectivePartSize,
          );
          await _notifyCheckpoint(onCheckpoint, currentCheckpoint);
        }

        final Map<int, PartInfo> uploadedPartsByNumber = <int, PartInfo>{};
        for (final PartInfo part in currentCheckpoint!.uploadedParts) {
          if (part.partNumber >= 1 && part.partNumber <= numberOfParts) {
            uploadedPartsByNumber[part.partNumber] = part;
          }
        }

        final List<PartInfo> remoteParts = await _listAllUploadedParts(
          client: client,
          ossObjectKey: ossObjectKey,
          uploadId: uploadId,
          params: effectiveParams,
        );
        for (final PartInfo part in remoteParts) {
          if (part.partNumber >= 1 && part.partNumber <= numberOfParts) {
            uploadedPartsByNumber[part.partNumber] = part;
          }
        }

        currentCheckpoint = currentCheckpoint.copyWith(
          uploadedParts: _sortParts(uploadedPartsByNumber.values),
        );
        await _notifyCheckpoint(onCheckpoint, currentCheckpoint);

        int uploadedSize = _calculateUploadedBytes(
          uploadedPartsByNumber.keys,
          totalFileSize,
          effectivePartSize,
        );
        effectiveParams.onSendProgress?.call(uploadedSize, totalFileSize);

        bool hasErrorOccurred = false;
        Object? firstError;
        StackTrace? firstStackTrace;
        final Semaphore semaphore = Semaphore(maxConcurrency);
        final List<Future<void>> partTasks = <Future<void>>[];

        for (int partIndex = 0; partIndex < numberOfParts; partIndex++) {
          final int partNumber = partIndex + 1;
          if (uploadedPartsByNumber.containsKey(partNumber)) {
            continue;
          }

          final int offset = partIndex * effectivePartSize;
          final int readLength = math.min(
            effectivePartSize,
            totalFileSize - offset,
          );

          final Future<void> partTask = semaphore.acquire().then((_) async {
            if (hasErrorOccurred || effectiveToken.isCancelled) {
              semaphore.release();
              return;
            }

            try {
              await _uploadPartStreaming(
                client: client,
                file: file,
                offset: offset,
                length: readLength,
                ossObjectKey: ossObjectKey,
                partNumber: partNumber,
                uploadId: uploadId!,
                params: effectiveParams,
                effectiveToken: effectiveToken,
                onPartProgress: onPartProgress,
                isErrorGlobally: hasErrorOccurred,
                onSuccess: (PartInfo partInfo) async {
                  uploadedPartsByNumber[partNumber] = partInfo;
                  uploadedSize += readLength;
                  effectiveParams.onSendProgress?.call(
                    uploadedSize,
                    totalFileSize,
                  );
                  currentCheckpoint = currentCheckpoint!.copyWith(
                    uploadedParts: _sortParts(uploadedPartsByNumber.values),
                  );
                  await _notifyCheckpoint(onCheckpoint, currentCheckpoint!);
                },
                onError: (dynamic error, StackTrace stackTrace) {
                  hasErrorOccurred = true;
                  firstError ??= error;
                  firstStackTrace ??= stackTrace;
                },
              );
            } catch (error, stackTrace) {
              hasErrorOccurred = true;
              firstError ??= error;
              firstStackTrace ??= stackTrace;
              rethrow;
            } finally {
              semaphore.release();
            }
          });

          partTasks.add(partTask);
        }

        await Future.wait(partTasks);

        if (effectiveToken.isCancelled) {
          throw const OSSException(
            type: OSSErrorType.requestCancelled,
            message: '断点续传上传被取消。',
          );
        }

        if (hasErrorOccurred) {
          if (firstError is OSSException) {
            Error.throwWithStackTrace(firstError!, firstStackTrace!);
          }
          throw OSSException(
            type: OSSErrorType.uploadPartFailed,
            message: '断点续传上传分片失败: $firstError',
            originalError: firstError,
          );
        }

        final List<PartInfo> completedParts = _sortParts(
          uploadedPartsByNumber.values,
        );
        if (completedParts.length != numberOfParts) {
          throw OSSException(
            type: OSSErrorType.uploadPartFailed,
            message:
                '断点续传分片不完整,预期 $numberOfParts 个分片,实际 ${completedParts.length} 个。',
          );
        }

        final Response<CompleteMultipartUploadResult> completeResponse =
            await client.completeMultipartUpload(
          ossObjectKey,
          uploadId,
          completedParts,
          params: effectiveParams,
        );

        return completeResponse;
      } catch (error) {
        if (abortOnError && uploadId != null && uploadId.isNotEmpty) {
          try {
            await client.abortMultipartUpload(
              ossObjectKey,
              uploadId,
              params: effectiveParams,
            );
          } catch (abortError) {
            log('断点续传失败后清理 uploadId 失败: $abortError');
          }
        }

        if (error is OSSException) {
          rethrow;
        }
        if (error is DioException && error.type == DioExceptionType.cancel) {
          throw OSSException(
            type: OSSErrorType.requestCancelled,
            message: '断点续传上传被取消。',
            originalError: error,
          );
        }
        throw OSSException(
          type: OSSErrorType.unknown,
          message: '断点续传上传失败: $error',
          originalError: error,
        );
      }
    });
  }

  void _validateResumableUploadInput({
    required File file,
    required String ossObjectKey,
    required int maxConcurrency,
  }) {
    if (ossObjectKey.isEmpty) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'OSS 对象键不能为空',
      );
    }
    if (!file.existsSync()) {
      throw OSSException(
        type: OSSErrorType.fileSystem,
        message: '文件未找到: ${file.path}',
      );
    }
    if (file.lengthSync() == 0) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: '文件大小为0,不能进行断点续传上传',
      );
    }
    if (maxConcurrency < 1) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'maxConcurrency 必须大于 0',
      );
    }
  }

  int _resolveResumablePartSize({
    required int totalFileSize,
    required OSSMultipartUploadCheckpoint? checkpoint,
    required int? partSize,
  }) {
    if (checkpoint != null) {
      if (partSize != null && checkpoint.partSize != partSize) {
        throw const OSSException(
          type: OSSErrorType.invalidArgument,
          message: '指定的 partSize 与断点续传检查点不一致',
        );
      }
      return checkpoint.partSize;
    }
    if (partSize != null) {
      return partSize;
    }
    return OSSUtils.calculatePartConfig(totalFileSize, null).partSize;
  }

  void _validateResumablePartConfig({
    required int partSize,
    required int numberOfParts,
  }) {
    if (numberOfParts < 1 || numberOfParts > 10000) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: '分片数量必须在 1 到 10000 之间',
      );
    }
    if (partSize > 5 * 1024 * 1024 * 1024) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: '分片大小不能超过 5GB',
      );
    }
    if (numberOfParts > 1 && partSize < 100 * 1024) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: '除最后一个分片外,分片大小必须大于等于 100KB',
      );
    }
  }

  Future<List<PartInfo>> _listAllUploadedParts({
    required OSSClient client,
    required String ossObjectKey,
    required String uploadId,
    required OSSRequestParams params,
  }) async {
    final List<PartInfo> parts = <PartInfo>[];
    int? partNumberMarker;
    do {
      final Response<ListPartsResult> response = await client.listParts(
        ossObjectKey,
        uploadId,
        maxParts: 1000,
        partNumberMarker: partNumberMarker,
        params: params,
      );
      final ListPartsResult? result = response.data;
      if (result == null) {
        break;
      }
      parts.addAll(result.parts);
      partNumberMarker =
          result.isTruncated ? result.nextPartNumberMarker : null;
    } while (partNumberMarker != null);
    return parts;
  }

  int _calculateUploadedBytes(
    Iterable<int> uploadedPartNumbers,
    int totalFileSize,
    int partSize,
  ) {
    int uploadedBytes = 0;
    for (final int partNumber in uploadedPartNumbers) {
      final int offset = (partNumber - 1) * partSize;
      if (offset >= totalFileSize) {
        continue;
      }
      uploadedBytes += math.min(partSize, totalFileSize - offset);
    }
    return uploadedBytes;
  }

  List<PartInfo> _sortParts(Iterable<PartInfo> parts) {
    final List<PartInfo> sortedParts = parts.toList();
    sortedParts.sort((PartInfo left, PartInfo right) {
      return left.partNumber.compareTo(right.partNumber);
    });
    return sortedParts;
  }

  Future<void> _notifyCheckpoint(
    MultipartUploadCheckpointCallback? onCheckpoint,
    OSSMultipartUploadCheckpoint checkpoint,
  ) async {
    if (onCheckpoint == null) {
      return;
    }
    await onCheckpoint(checkpoint);
  }

  /// 流式上传单个分片,避免一次性加载整个分片到内存
  Future<void> _uploadPartStreaming({
    required OSSClient client,
    required File file,
    required int offset,
    required int length,
    required String ossObjectKey,
    required int partNumber,
    required String uploadId,
    required OSSRequestParams? params,
    required CancelToken effectiveToken,
    required PartProgressCallback? onPartProgress,
    required bool isErrorGlobally,
    required FutureOr<void> Function(PartInfo partInfo) onSuccess,
    required void Function(dynamic error, StackTrace stackTrace) onError,
  }) async {
    try {
      if (effectiveToken.isCancelled || isErrorGlobally) {
        return;
      }

      final RandomAccessFile raf = await file.open();
      StreamController<List<int>>? controller;

      try {
        await raf.setPosition(offset);
        final int bufferSize = math.min(length, 64 * 1024); // 64KB 缓冲区
        final Uint8List buffer = Uint8List(bufferSize);

        controller = StreamController<List<int>>(
          onListen: () async {
            int totalBytesRead = 0;
            try {
              while (totalBytesRead < length && !controller!.isClosed) {
                final int remainingBytes = length - totalBytesRead;
                final int bytesToRead = math.min(bufferSize, remainingBytes);
                final int bytesRead =
                    await raf.readInto(buffer, 0, bytesToRead);

                if (bytesRead <= 0) {
                  break;
                }

                final Uint8List chunk =
                    Uint8List.fromList(buffer.sublist(0, bytesRead));
                controller.add(chunk);
                totalBytesRead += bytesRead;
              }

              // 验证是否读取了足够的数据
              if (totalBytesRead != length) {
                controller?.addError(
                  OSSException(
                    type: OSSErrorType.fileSystem,
                    message: '无法读取足够的数据：预期 $length 字节,实际读取 $totalBytesRead 字节',
                  ),
                );
              }
            } catch (e, s) {
              controller?.addError(e, s);
            } finally {
              await controller?.close();
            }
          },
          onCancel: () {
            controller?.close();
          },
        );

        // 上传分片
        // 创建一个新的 params，包含 cancelToken 和 onSendProgress
        final OSSRequestParams? uploadParams = params?.copyWith(
          cancelToken: effectiveToken,
          onSendProgress: (int count, int total) {
            onPartProgress?.call(partNumber, count, length);
          },
        );

        final Response<dynamic> uploadResponse = await client.uploadPartStream(
          ossObjectKey,
          controller.stream,
          length,
          partNumber,
          uploadId,
          params: uploadParams,
        );

        // 处理响应
        final String? eTag = uploadResponse.headers.value('ETag');
        if (eTag == null || eTag.isEmpty) {
          throw OSSException(
            type: OSSErrorType.uploadPartFailed,
            message: '分片 $partNumber 上传响应中缺少或 ETag 为空。',
            response: uploadResponse,
            requestOptions: uploadResponse.requestOptions,
          );
        }

        // 创建 PartInfo
        final PartInfo partInfo = PartInfo(
          partNumber: partNumber,
          eTag: eTag.replaceAll('"', ''),
          size: length,
          lastModified: DateTime.now().toUtc().toIso8601String(),
        );

        // 报告成功
        await onSuccess(partInfo);
      } finally {
        await controller?.close();
        await raf.close();
      }
    } catch (e, s) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        log('分片 $partNumber 上传被取消。', level: 800);
      }
      onError(e, s);
      rethrow;
    }
  }
}
