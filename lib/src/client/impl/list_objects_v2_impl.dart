import 'package:dart_aliyun_oss/src/client/client.dart';
import 'package:dart_aliyun_oss/src/exceptions/exceptions.dart';
import 'package:dart_aliyun_oss/src/interfaces/service.dart';
import 'package:dart_aliyun_oss/src/models/models.dart';
import 'package:dio/dio.dart';

/// ListBucketResultImpl 是阿里云 OSS 获取bucket文件列表操作的实现
///
/// 示例:
/// ```dart
/// final response = await client.listBucketResultV2();
/// ```
mixin ListBucketResultImpl on IOSSService {
  @override
  Future<Response<ListBucketResultV2>> listBucketResultV2({
    String? delimiter = '/',
    String? startAfter,
    String? continuationToken,
    int? maxKeys,
    String? prefix,
    bool fetchOwner = false,
    OSSRequestParams? params,
  }) async {
    // 参数验证
    if (prefix != null && prefix.startsWith('/')) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'Prefix 不能以 "/" 开头',
      );
    }

    if (prefix != null && prefix.length >= 1024) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'Prefix 长度必须小于1024字节',
      );
    }

    if (startAfter != null && startAfter.length >= 1024) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'StartAfter 长度必须小于1024字节',
      );
    }

    if (maxKeys != null && (maxKeys <= 0 || maxKeys > 1000)) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'MaxKeys 必须在1到1000之间',
      );
    }

    final OSSClient client = this as OSSClient;

    // 使用更简洁的 requestKey
    final String requestKey =
        'listBucketResultV2_${DateTime.now().millisecondsSinceEpoch}';

    return client.requestHandler.executeRequest(requestKey, params?.cancelToken,
        (
      CancelToken cancelToken,
    ) async {
      // 更新请求参数
      final Map<String, dynamic> queryParameters = <String, dynamic>{
        'list-type': '2', // 必须为2表示V2版本
        if (delimiter != null) 'delimiter': delimiter,
        if (startAfter != null) 'start-after': startAfter,
        if (continuationToken != null) 'continuation-token': continuationToken,
        if (maxKeys != null) 'max-keys': maxKeys.toString(),
        if (prefix != null) 'prefix': prefix,
        'fetch-owner': fetchOwner.toString(),
      };
      OSSRequestParams updatedParams = params ??
          const OSSRequestParams(queryParameters: <String, dynamic>{});
      queryParameters
          .addAll(updatedParams.queryParameters ?? <String, dynamic>{});
      updatedParams = updatedParams.copyWith(queryParameters: queryParameters);

      final Uri uri = client.buildOssUri(
        bucket: updatedParams.bucketName,
        fileKey: '', // Bucket 根路径请求不需要 Object key
        queryParameters: updatedParams.queryParameters,
      );

      final Map<String, dynamic> baseHeaders = <String, dynamic>{
        'Accept': 'application/xml',
        ...?updatedParams.options?.headers,
      };

      // 创建签名头
      final Map<String, dynamic> headers = client.createSignedHeaders(
        method: 'GET',
        fileKey: '',
        baseHeaders: baseHeaders,
        params: updatedParams,
      );
      final Options requestOptions = (params?.options ?? Options()).copyWith(
        headers: headers,
        responseType: ResponseType.plain,
      );

      final Response<dynamic> response =
          await client.requestHandler.sendRequest(
        uri: uri,
        method: 'GET',
        options: requestOptions,
        cancelToken: cancelToken,
        onReceiveProgress: params?.onReceiveProgress,
        onSendProgress: params?.onSendProgress,
      );

      // 解析XML响应
      if (response.data == null) {
        throw const OSSException(
          type: OSSErrorType.invalidResponse,
          message: '响应数据为空',
        );
      }

      try {
        final ListBucketResultV2 result =
            ListBucketResultV2.parse(response.data!);
        return Response<ListBucketResultV2>(
          data: result,
          headers: response.headers,
          requestOptions: response.requestOptions,
          statusCode: response.statusCode,
          statusMessage: response.statusMessage,
          isRedirect: response.isRedirect,
          redirects: response.redirects,
          extra: response.extra,
        );
      } catch (e) {
        throw OSSException(
          type: OSSErrorType.parseError,
          message: '解析响应数据失败: $e',
        );
      }
    });
  }
}
