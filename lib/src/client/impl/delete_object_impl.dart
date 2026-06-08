import 'package:dart_aliyun_oss/src/client/client.dart';
import 'package:dart_aliyun_oss/src/exceptions/exceptions.dart';
import 'package:dart_aliyun_oss/src/interfaces/service.dart';
import 'package:dart_aliyun_oss/src/models/models.dart';
import 'package:dio/dio.dart';

/// DeleteObjectImpl 是阿里云 OSS 删除对象操作的实现
///
/// 示例:
/// ```dart
/// final response = await client.deleteObject(
///   'example.zip',
/// );
/// ```
mixin DeleteObjectImpl on IOSSService {
  @override
  Future<Response<dynamic>> deleteObject(
    String fileKey, {
    String? versionId,
    OSSRequestParams? params,
  }) {
    // 参数验证
    if (fileKey.isEmpty) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'File key 不能为空',
      );
    }

    if (fileKey.startsWith('/')) {
      throw const OSSException(
        type: OSSErrorType.invalidArgument,
        message: 'File key 不能以 "/" 开头',
      );
    }

    final OSSClient client = this as OSSClient;

    return client.requestHandler.executeRequest(fileKey, params?.cancelToken, (
      CancelToken cancelToken,
    ) async {
      // 更新请求参数。先复制外部 queryParameters，再追加 versionId，
      // 避免修改调用方复用的 OSSRequestParams。
      OSSRequestParams updatedParams = params ?? const OSSRequestParams();
      final Map<String, dynamic> queryParameters = <String, dynamic>{
        ...?updatedParams.queryParameters,
      };
      if (versionId != null) {
        queryParameters['versionId'] = versionId;
      }

      updatedParams = updatedParams.copyWith(queryParameters: queryParameters);

      final Uri uri = client.buildOssUri(
        bucket: updatedParams.bucketName,
        fileKey: fileKey,
        queryParameters: queryParameters,
      );

      final Map<String, dynamic> baseHeaders = <String, dynamic>{
        'Accept': 'text/html',
        ...?updatedParams.options?.headers, // 使用空安全展开运算符
      };

      // Access private method via the casted client instance
      final Map<String, dynamic> headers = client.createSignedHeaders(
        method: 'DELETE',
        fileKey: fileKey,
        baseHeaders: baseHeaders,
        params: updatedParams,
      );

      final Options requestOptions = (params?.options ?? Options()).copyWith(
        headers: headers,
        responseType: ResponseType.bytes,
      );

      final Response<dynamic> response =
          await client.requestHandler.sendRequest(
        uri: uri,
        method: 'DELETE',
        options: requestOptions,
        cancelToken: cancelToken,
        onReceiveProgress: params?.onReceiveProgress,
        onSendProgress: params?.onSendProgress,
      );

      return response;
    });
  }
}
