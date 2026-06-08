import 'package:dart_aliyun_oss/src/client/client.dart';
import 'package:dart_aliyun_oss/src/exceptions/exceptions.dart';
import 'package:dart_aliyun_oss/src/interfaces/service.dart';
import 'package:dart_aliyun_oss/src/models/models.dart';
import 'package:dio/dio.dart';

/// 分片上传实现类
///
/// 提供分片上传的核心功能,支持两种上传方式：
/// 1. 内存数据上传：适用于小文件或已加载到内存的数据
/// 2. 流式上传：适用于大文件,避免内存占用过高
///
/// 主要特性：
/// - 支持分片上传进度回调
/// - 自动处理签名和请求头生成
/// - 支持请求取消
/// - 兼容V1和V4签名算法
///
/// 使用注意事项：
/// 1. 分片编号(partNumber)必须从1开始且连续
/// 2. 每个分片大小(除最后一个)必须≥100KB
/// 3. 上传前必须已调用initiateMultipartUpload获取uploadId
/// 4. 成功上传后需记录返回的ETag用于完成分片上传
///
/// 参考文档：
/// [阿里云OSS分片上传文档](https://help.aliyun.com/document_detail/31996.html)
mixin UploadPartImpl on IOSSService {
  /// 上传分片
  ///
  /// 上传文件的一个分片。
  ///
  /// [fileKey] OSS 对象键
  /// [partData] 分片数据 ([List<int>])
  /// [partNumber] 分片编号 (从 1 开始)
  /// [uploadId] [initiateMultipartUpload] 返回的 Upload ID
  /// [params] 可选的请求参数 ([OSSRequestParams])
  ///   - 可以通过 params.onSendProgress 设置上传进度回调
  /// 返回一个 [Response]。成功时响应体为空,但 Headers 包含 ETag。
  @override
  Future<Response<dynamic>> uploadPart(
    String fileKey,
    List<int> partData,
    int partNumber,
    String uploadId, {
    OSSRequestParams? params,
  }) async {
    // 添加参数验证
    if (fileKey.isEmpty) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'fileKey不能为空',
      );
    }
    if (partNumber < 1 || partNumber > 10000) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'partNumber必须在1-10000之间',
      );
    }
    if (uploadId.isEmpty) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'uploadId不能为空',
      );
    }
    if (partData.isEmpty) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'partData不能为空',
      );
    }
    final OSSClient client = this as OSSClient;
    final String requestKey = '$fileKey-$uploadId-$partNumber';
    return client.requestHandler.executeRequest(
      requestKey,
      params?.cancelToken,
      (CancelToken cancelToken) async {
        // 准备查询参数
        final Map<String, dynamic> queryParams = <String, dynamic>{
          'partNumber': partNumber,
          'uploadId': uploadId,
        };

        // 更新请求参数
        final OSSRequestParams updatedParams =
            params ?? const OSSRequestParams();
        final OSSRequestParams paramsWithQuery = updatedParams.copyWith(
          queryParameters: queryParams,
        );

        final Uri uri = client.buildOssUri(
          bucket: paramsWithQuery.bucketName,
          fileKey: fileKey,
          queryParameters: paramsWithQuery.queryParameters,
        );

        final Map<String, dynamic> baseHeaders = <String, dynamic>{
          ...(paramsWithQuery.options?.headers ?? <String, dynamic>{}),
        };

        final Map<String, dynamic> headers = client.createSignedHeaders(
          method: 'PUT',
          fileKey: fileKey,
          contentLength: partData.length,
          baseHeaders: baseHeaders,
          params: paramsWithQuery,
        );

        final Options requestOptions = (params?.options ?? Options()).copyWith(
          headers: headers,
        );

        final Response<dynamic> response =
            await client.requestHandler.sendRequest(
          uri: uri,
          method: 'PUT',
          options: requestOptions,
          data: Stream<List<int>>.fromIterable(<List<int>>[partData]),
          cancelToken: cancelToken,
          onReceiveProgress: params?.onReceiveProgress,
          onSendProgress: params?.onSendProgress,
        );

        return response;
      },
    );
  }

  /// 使用流式数据上传分片
  ///
  /// 上传文件的一个分片，使用流式数据避免一次性加载整个分片到内存。
  ///
  /// [fileKey] OSS 对象键
  /// [dataStream] 分片数据流
  /// [contentLength] 分片数据长度
  /// [partNumber] 分片编号 (从 1 开始)
  /// [uploadId] [initiateMultipartUpload] 返回的 Upload ID
  /// [params] 可选的请求参数 ([OSSRequestParams])
  ///   - 可以通过 params.onSendProgress 设置上传进度回调
  Future<Response<dynamic>> uploadPartStream(
    String fileKey,
    Stream<List<int>> dataStream,
    int contentLength,
    int partNumber,
    String uploadId, {
    OSSRequestParams? params,
  }) async {
    // 添加参数验证
    if (contentLength <= 0) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'contentLength必须大于0',
      );
    }

    final OSSClient client = this as OSSClient;
    // 优化requestKey生成方式,避免时间戳冲突
    final String requestKey =
        'uploadPartStream_${fileKey}_${uploadId}_$partNumber';

    return client.requestHandler.executeRequest(
      requestKey,
      params?.cancelToken,
      (CancelToken effectiveToken) async {
        // 准备查询参数
        final Map<String, dynamic> queryParams = <String, dynamic>{
          'partNumber': partNumber,
          'uploadId': uploadId,
        };

        // 更新请求参数
        final OSSRequestParams updatedParams =
            params ?? const OSSRequestParams();
        final OSSRequestParams paramsWithQuery = updatedParams.copyWith(
          queryParameters: queryParams,
        );

        final Uri uri = client.buildOssUri(
          bucket: paramsWithQuery.bucketName,
          fileKey: fileKey,
          queryParameters: paramsWithQuery.queryParameters,
        );

        final Map<String, dynamic> baseHeaders = <String, dynamic>{
          ...(paramsWithQuery.options?.headers ?? <String, dynamic>{}),
        };

        final Map<String, dynamic> headers = client.createSignedHeaders(
          method: 'PUT',
          fileKey: fileKey,
          contentLength: contentLength,
          baseHeaders: baseHeaders,
          params: paramsWithQuery,
        );

        final Options requestOptions = (params?.options ?? Options()).copyWith(
          headers: headers,
        );

        final Response<dynamic> response =
            await client.requestHandler.sendRequest(
          uri: uri,
          method: 'PUT',
          data: dataStream,
          options: requestOptions,
          cancelToken: effectiveToken,
          onReceiveProgress: params?.onReceiveProgress,
          onSendProgress: params?.onSendProgress,
        );

        return response;
      },
    );
  }
}
