import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_aliyun_oss/src/utils/utils.dart';

/// 阿里云OSS V1版本签名工具类
///
/// 用于生成阿里云OSS V1版本的签名和授权头信息。
/// 该类实现了基于 HMAC-SHA1 算法的签名生成过程，符合阿里云OSS API规范。
///
/// V1签名算法的主要步骤：
/// 1. 构建规范化的OSS头部（CanonicalizedOSSHeaders）
/// 2. 构建规范化的资源路径（CanonicalizedResource）
/// 3. 组合各元素构建待签名字符串
/// 4. 使用 HMAC-SHA1 算法计算签名并进行 Base64 编码
/// 5. 生成最终的授权头格式：`OSS {AccessKeyId}:{Signature}`
///
/// 注意：该类提供的是静态工具方法，不应该被实例化。
/// 对于新应用，建议使用更安全的 V4 签名算法。
class AliOssV1SignUtils {
  // 私有构造函数，防止实例化
  AliOssV1SignUtils._();

  /// OSS头部前缀常量
  static const String _ossHeaderPrefix = 'x-oss-';

  /// V1 签名需要纳入 CanonicalizedResource 的 OSS 子资源。
  ///
  /// OSS V1 规范并不是把所有 query 都放进待签名资源路径；只有这里列出的
  /// OSS 子资源和响应头覆盖参数需要参与签名。普通业务 query 如果误签，
  /// 服务端会按不同的 CanonicalizedResource 计算签名并返回 403。
  static const Set<String> _signedSubresources = <String>{
    'acl',
    'append',
    'bucketInfo',
    'callback',
    'callback-var',
    'cname',
    'comp',
    'cors',
    'delete',
    'lifecycle',
    'location',
    'logging',
    'objectMeta',
    'partNumber',
    'policy',
    'position',
    'referer',
    'replication',
    'response-cache-control',
    'response-content-disposition',
    'response-content-encoding',
    'response-content-language',
    'response-content-type',
    'response-expires',
    'security-token',
    'uploadId',
    'uploads',
    'x-oss-process',
  };

  /// 生成阿里云OSS V1签名所需的Authorization头
  ///
  /// 根据提供的参数生成符合阿里云OSS V1版本规范的授权头字符串。
  /// 该方法实现了完整的V1签名过程,包括构建规范化头部、资源路径和计算签名。
  ///
  /// 签名过程：
  /// 1. 处理时间参数并格式化为 HTTP 日期格式
  /// 2. 处理安全令牌（如果提供）
  /// 3. 构建规范化的OSS头部
  /// 4. 构建规范化的资源路径
  /// 5. 组合各元素构建待签名字符串
  /// 6. 计算HMAC-SHA1签名并进行 Base64 编码
  /// 7. 生成最终的授权头格式：`OSS {AccessKeyId}:{Signature}`
  ///
  /// 参数：
  /// - [accessKeyId] 阿里云访问密钥ID
  /// - [accessKeySecret] 阿里云访问密钥
  /// - [method] HTTP方法（大写,如：PUT/GET）
  /// - [bucket] OSS存储空间名称
  /// - [uri] 完整的请求URI（用于解析查询参数）
  /// - [ossHeaders] 参与签名计算的自定义OSS头（可选）
  /// - [contentMd5] 请求体的MD5值（可选）
  /// - [contentType] 请求体的Content-Type（可选）
  /// - [securityToken] 安全令牌（STS临时凭证需要）
  /// - [dateTime] 指定请求时间（可选,默认为当前时间）
  ///
  /// 返回完整的授权头字符串,格式为 `OSS {AccessKeyId}:{Signature}`
  ///
  /// 示例：
  /// ```dart
  /// final authHeader = AliOssV1SignUtils.signature(
  ///   accessKeyId: 'your-access-key-id',
  ///   accessKeySecret: 'your-access-key-secret',
  ///   method: 'GET',
  ///   bucket: 'example-bucket',
  ///   uri: Uri.parse('https://example-bucket.oss-cn-hangzhou.aliyuncs.com/example.txt'),
  /// );
  /// // 结果如：'OSS your-access-key-id:Base64EncodedSignature'
  /// ```
  static String signature({
    required String accessKeyId,
    required String accessKeySecret,
    required String method,
    required String bucket,
    required Uri uri,
    Map<String, dynamic>? ossHeaders,
    String? contentMd5,
    String? contentType,
    String? securityToken,
    DateTime? dateTime,
    int? expires,
  }) {
    // 1. 处理时间参数
    final DateTime now = dateTime ?? DateTime.now().toUtc();
    final String date = HttpDate.format(now);

    // 处理安全令牌
    final Map<String, dynamic> headers = <String, dynamic>{
      ...ossHeaders ?? <String, dynamic>{},
    };
    if (securityToken != null) {
      headers['${_ossHeaderPrefix}security-token'] = securityToken;
    }

    // 2. 构建规范OSS头
    final String canonicalizedHeaders = _buildCanonicalizedHeaders(headers);

    // 3. 构建规范资源
    final String canonicalizedResource =
        _buildCanonicalizedResource(uri, bucket);

    // 4. 构建待签名字符串
    String dateOrExpires;
    if (expires != null) {
      // 如果提供了过期时间，使用过期时间戳
      final int expiresTimestamp =
          (now.millisecondsSinceEpoch ~/ 1000) + expires;
      dateOrExpires = expiresTimestamp.toString();
    } else {
      // 否则使用日期
      dateOrExpires = date;
    }

    final String stringToSign = <String>[
      method.toUpperCase(),
      contentMd5 ?? '',
      contentType ?? '',
      dateOrExpires,
      canonicalizedHeaders,
      canonicalizedResource,
    ].join('\n');

    // 5. 计算签名
    final String signature = _calculateSignature(accessKeySecret, stringToSign);

    // 6. 构建Authorization头
    return 'OSS $accessKeyId:$signature';
  }

  /// 生成包含签名的完整HTTP请求头
  ///
  /// 根据提供的参数生成包含阿里云OSS V1签名的完整HTTP请求头。
  /// 该方法不仅生成授权头,还会处理其他必要的头部,如内容类型、内容长度和日期等。
  ///
  /// 处理流程：
  /// 1. 从原始头部中提取并分离所有 x-oss-* 头部
  /// 2. 处理时间参数并格式化为 HTTP 日期格式
  /// 3. 调用 [signature] 方法生成授权头
  /// 4. 组装最终的请求头,包含所有原始头部、OSS头部、内容类型、内容长度、日期和授权头
  ///
  /// 参数：
  /// - [accessKeyId] 阿里云访问密钥ID
  /// - [accessKeySecret] 阿里云访问密钥
  /// - [method] HTTP方法（大写,如：PUT/GET）
  /// - [bucket] OSS存储空间名称
  /// - [uri] 完整的请求URI
  /// - [headers] 原始HTTP请求头（可选）
  /// - [contentMd5] 请求体的MD5值（可选）
  /// - [contentType] 请求体的Content-Type（可选）
  /// - [contentLength] 请求体的长度（可选）
  /// - [securityToken] 安全令牌（STS临时凭证需要）
  /// - [dateTime] 指定请求时间（可选,默认为当前时间）
  ///
  /// 返回包含完整签名头部的Map,可直接用于 HTTP 请求
  ///
  /// 示例：
  /// ```dart
  /// final headers = AliOssV1SignUtils.signedHeaders(
  ///   accessKeyId: 'your-access-key-id',
  ///   accessKeySecret: 'your-access-key-secret',
  ///   method: 'PUT',
  ///   bucket: 'example-bucket',
  ///   uri: Uri.parse('https://example-bucket.oss-cn-hangzhou.aliyuncs.com/example.txt'),
  ///   contentType: 'text/plain',
  ///   contentLength: 1024,
  ///   headers: {'x-oss-meta-author': 'example'},
  /// );
  /// // 结果包含如下头部：
  /// // {
  /// //   'x-oss-meta-author': 'example',
  /// //   'content-type': 'text/plain',
  /// //   'content-length': 1024,
  /// //   'Date': 'Wed, 15 Jun 2023 12:30:45 GMT',
  /// //   'Authorization': 'OSS your-access-key-id:Base64EncodedSignature'
  /// // }
  /// ```
  static Map<String, dynamic> signedHeaders({
    required String accessKeyId,
    required String accessKeySecret,
    required String method,
    required String bucket,
    required Uri uri,
    Map<String, dynamic>? headers,
    String? contentMd5,
    String? contentType,
    int? contentLength,
    String? securityToken,
    DateTime? dateTime,
  }) {
    // 若有 header,从 header 中提取 x-oss-* 头并移除
    final Map<String, dynamic> ossHeaders = <String, dynamic>{};
    final Map<String, dynamic> resultHeaders = <String, dynamic>{
      ...headers ?? <String, dynamic>{},
    };

    if (resultHeaders.isNotEmpty) {
      final List<String> keysToRemove = <String>[];
      resultHeaders.forEach((String key, dynamic value) {
        final String lowerKey = key.toLowerCase();
        if (lowerKey.startsWith(_ossHeaderPrefix)) {
          ossHeaders[lowerKey] = value;
          keysToRemove.add(key);
        }
      });

      for (final String key in keysToRemove) {
        resultHeaders.remove(key);
      }
    }

    // 处理时间参数
    final DateTime now = dateTime ?? DateTime.now().toUtc();
    final String date = HttpDate.format(now);

    // 添加安全令牌到OSS头部（如果有）
    if (securityToken != null) {
      ossHeaders['${_ossHeaderPrefix}security-token'] = securityToken;
    }

    // 构建OSS签名
    final String sign = signature(
      accessKeyId: accessKeyId,
      accessKeySecret: accessKeySecret,
      method: method,
      uri: uri,
      bucket: bucket,
      ossHeaders: ossHeaders,
      contentType: contentType,
      contentMd5: contentMd5,
      securityToken: securityToken,
      dateTime: now,
    );

    // 组装最终请求头
    final Map<String, dynamic> finalHeaders = <String, dynamic>{
      ...ossHeaders,
      if (contentType != null) 'content-type': contentType,
      if (contentLength != null) 'content-length': contentLength,
      'Date': date,
      'Authorization': sign,
      ...resultHeaders,
    };

    return finalHeaders;
  }

  /// 构建规范化的OSS头部字符串
  ///
  /// 将所有以 x-oss- 开头的头部按照字典序排序,并以 `key:value` 格式拼接成字符串。
  /// 多个头部之间使用换行符分隔。
  ///
  /// 处理流程：
  /// 1. 过滤出所有以 x-oss- 开头的头部
  /// 2. 将头部名转换为小写,并对值进行去除首尾空格处理
  /// 3. 按照头部名的字典序排序
  /// 4. 将排序后的头部以 `key:value` 格式拼接,并用换行符分隔
  ///
  /// 参数：
  /// - [headers] 要处理的头部映射
  ///
  /// 返回规范化的OSS头部字符串,如果没有相关头部则返回空字符串
  static String _buildCanonicalizedHeaders(Map<String, dynamic> headers) {
    if (headers.isEmpty) {
      return '';
    }

    final List<MapEntry<String, String>> entries = headers.entries
        .where(
          (MapEntry<String, dynamic> entry) =>
              entry.key.toLowerCase().startsWith(_ossHeaderPrefix),
        )
        .map(
          (MapEntry<String, dynamic> entry) => MapEntry<String, String>(
            entry.key.toLowerCase(),
            (entry.value?.toString() ?? '').trim(),
          ),
        )
        .toList()
      ..sort(
        (MapEntry<String, String> a, MapEntry<String, String> b) =>
            a.key.compareTo(b.key),
      );

    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < entries.length; i++) {
      if (i > 0) {
        buffer.write('\n');
      }
      buffer.write('${entries[i].key}:${entries[i].value}');
    }

    return buffer.toString();
  }

  /// 构建规范化的资源路径字符串
  ///
  /// 生成符合阿里云OSS V1签名规范的规范化资源字符串。
  /// 格式为: `/bucket/object?param1=value1&param2=value2`
  ///
  /// 处理流程：
  /// 1. 组合存储空间名称和对象路径
  /// 2. 仅保留 OSS V1 规范要求签名的子资源查询参数
  /// 3. 对生成的路径进行 URL 解码,确保特殊字符正确处理
  ///
  /// 参数：
  /// - [uri] 请求的完整URI,包含路径和查询参数
  /// - [bucket] OSS存储空间名称
  ///
  /// 返回规范化的资源路径字符串
  static String _buildCanonicalizedResource(Uri uri, String bucket) {
    // 检查 uri.path 是否已经包含 bucket 名称
    final String path = uri.path;
    final String resource =
        path.startsWith('/$bucket/') ? path : '/$bucket$path';
    final String decodedResource = Uri.decodeFull(resource);

    // Header 签名同样需要过滤 query；普通业务 query 会出现在实际 URL，
    // 但不属于 V1 CanonicalizedResource 的签名子资源。
    final Map<String, String> signedQueryParameters = <String, String>{};
    uri.queryParametersAll.forEach((String key, List<String> values) {
      if (!_signedSubresources.contains(key)) {
        return;
      }
      signedQueryParameters[key] = values.isEmpty ? '' : values.first;
    });

    if (signedQueryParameters.isEmpty) {
      return decodedResource;
    }

    return _appendCanonicalizedQuery(
      decodedResource,
      signedQueryParameters,
    );
  }

  /// 计算HMAC-SHA1签名并进行Base64编码
  ///
  /// 使用HMAC-SHA1算法对待签名字符串进行签名,并将结果进行 Base64 编码。
  /// 这是阿里云OSS V1签名算法的核心步骤。
  ///
  /// 处理流程：
  /// 1. 使用访问密钥作为 HMAC-SHA1 算法的密钥
  /// 2. 对待签名字符串进行 HMAC-SHA1 计算,生成摘要
  /// 3. 将摘要进行 Base64 编码,生成最终的签名字符串
  ///
  /// 参数：
  /// - [secret] 阿里云访问密钥,用作 HMAC 算法的密钥
  /// - [stringToSign] 待签名的字符串,包含方法、内容类型、日期等信息
  ///
  /// 返回 Base64 编码后的签名字符串
  static String _calculateSignature(String secret, String stringToSign) {
    // 使用 HMAC-SHA1 算法计算签名
    final Hmac hmac = Hmac(sha1, utf8.encode(secret));
    final Digest digest = hmac.convert(utf8.encode(stringToSign));

    // 对签名进行 Base64 编码
    return base64.encode(digest.bytes);
  }

  /// 生成包含签名的URL
  ///
  /// 根据提供的参数生成包含阿里云OSS V1签名的URL。
  /// 该方法将签名信息作为URL的查询参数，可以直接用于访问OSS资源。
  /// 生成的URL格式为：`https://{bucket}.{endpoint}/{key}?OSSAccessKeyId={accessKeyId}&Expires={expires}&Signature={signature}`
  /// 或自定义域名格式：`https://{endpoint}/{key}?OSSAccessKeyId={accessKeyId}&Expires={expires}&Signature={signature}`
  ///
  /// 签名过程：
  /// 1. 处理时间参数并计算过期时间戳
  /// 2. 构建规范资源路径 `/{bucket}/{key}`
  /// 3. 构建待签名字符串，格式为：
  ///    `{METHOD}\n{CONTENT-MD5}\n{CONTENT-TYPE}\n{EXPIRES}\n{RESOURCE}`
  /// 4. 使用HMAC-SHA1算法计算签名并进行Base64编码
  /// 5. 构建最终URL，包含必要的查询参数（OSSAccessKeyId、Expires、Signature）
  /// 6. 添加安全令牌和其他自定义参数（如果有）
  ///
  /// 参数：
  /// - [accessKeyId] 阿里云访问密钥ID
  /// - [accessKeySecret] 阿里云访问密钥
  /// - [endpoint] 阿里云OSS端点（如：oss-cn-hangzhou.aliyuncs.com）或自定义域名
  /// - [method] HTTP方法（大写，如：GET/PUT/POST/DELETE）
  /// - [bucket] OSS存储空间名称
  /// - [key] 对象键（文件路径）
  /// - [expires] 签名过期时间（秒），默认3600秒（1小时）
  /// - [cname] 是否使用自定义域名，默认为false
  /// - [ossHeaders] 参与签名计算的自定义OSS头（可选）
  /// - [contentMd5] 请求体的MD5值（可选）
  /// - [contentType] 请求体的Content-Type（可选）
  /// - [securityToken] 安全令牌（STS临时凭证需要）
  /// - [dateTime] 指定请求时间（可选，默认为当前时间）
  /// - [queryParameters] 自定义查询参数, 如图片处理参数等, 将参与签名计算
  ///
  /// 返回包含签名的完整URL（Uri对象）
  ///
  /// 示例：
  /// ```dart
  /// // 基础用法
  /// final uri = AliOssV1SignUtils.signatureUri(
  ///   accessKeyId: 'your-access-key-id',
  ///   accessKeySecret: 'your-access-key-secret',
  ///   endpoint: 'oss-cn-hangzhou.aliyuncs.com',
  ///   method: 'GET',
  ///   bucket: 'example-bucket',
  ///   key: 'example.txt',
  ///   expires: 3600, // 1小时后过期
  /// );
  ///
  /// // 自定义域名用法
  /// final customUri = AliOssV1SignUtils.signatureUri(
  ///   accessKeyId: 'your-access-key-id',
  ///   accessKeySecret: 'your-access-key-secret',
  ///   endpoint: 'img.example.com',
  ///   method: 'GET',
  ///   bucket: 'example-bucket',
  ///   key: 'example.txt',
  ///   cname: true, // 启用自定义域名
  /// );
  ///
  /// // 带图片处理参数的用法
  /// final imageUri = AliOssV1SignUtils.signatureUri(
  ///   accessKeyId: 'your-access-key-id',
  ///   accessKeySecret: 'your-access-key-secret',
  ///   endpoint: 'oss-cn-hangzhou.aliyuncs.com',
  ///   method: 'GET',
  ///   bucket: 'example-bucket',
  ///   key: 'image.jpg',
  ///   queryParameters: {
  ///     'x-oss-process': 'image/resize,l_100',
  ///   },
  /// );
  ///
  /// // 使用生成的URL访问OSS资源
  /// final response = await http.get(uri);
  /// ```
  static Uri signatureUri({
    required String accessKeyId,
    required String accessKeySecret,
    required String endpoint,
    required String method,
    required String bucket,
    required String key,
    int expires = 3600,
    bool cname = false,
    Map<String, dynamic>? ossHeaders,
    String? contentMd5,
    String? contentType,
    String? securityToken,
    DateTime? dateTime,
    Map<String, String>? queryParameters,
  }) {
    // 1. 处理时间参数
    final DateTime now = dateTime ?? DateTime.now().toUtc();
    final int expiresTimestamp = (now.millisecondsSinceEpoch ~/ 1000) + expires;

    // 2. 构建基础URL
    // 根据是否启用CNAME选择不同的域名构造方式
    final String host = cname ? endpoint : '$bucket.$endpoint';
    final String encodedPath = OSSUtils.ossUriEncode(
      '/$key',
      encodeSlash: false,
    );

    // URL 签名的 query 同时用于最终 URL 和 CanonicalizedResource。
    // 先收集可参与签名的用户参数、STS token 和 x-oss-* 参数，再计算签名。
    final Map<String, String> queryParams = <String, String>{};
    if (queryParameters != null && queryParameters.isNotEmpty) {
      _validateCustomQueryParameters(queryParameters);
      queryParams.addAll(queryParameters);
    }
    if (securityToken != null) {
      queryParams['security-token'] = securityToken;
    }
    if (ossHeaders != null && ossHeaders.isNotEmpty) {
      ossHeaders.forEach((String key, dynamic value) {
        final String lowerKey = key.toLowerCase();
        if (lowerKey.startsWith(_ossHeaderPrefix)) {
          queryParams[lowerKey] = value.toString();
        }
      });
    }

    // 3. 构建规范资源路径。部分 OSS 子资源 query 必须参与 V1 URL 签名。
    final String canonicalizedResource = _buildCanonicalizedResourceForUrl(
      bucket: bucket,
      key: key,
      queryParameters: queryParams,
    );

    // 4. 构建待签名字符串
    final String stringToSign = <String>[
      method.toUpperCase(),
      contentMd5 ?? '',
      contentType ?? '',
      expiresTimestamp.toString(),
      canonicalizedResource,
    ].join('\n');

    // 5. 计算签名
    final String signature = _calculateSignature(accessKeySecret, stringToSign);

    queryParams.addAll(<String, String>{
      'OSSAccessKeyId': accessKeyId,
      'Expires': expiresTimestamp.toString(),
      'Signature': signature,
    });

    // 9. 构建最终 URL。V1 签名的 CanonicalizedResource 使用原始 key，
    // 但实际 URL path 仍必须按 OSS UriEncode 编码，避免 `+` 被服务端当成空格。
    final String encodedQuery = _buildQueryString(queryParams);
    return Uri.parse('https://$host$encodedPath?$encodedQuery');
  }

  static String _buildCanonicalizedResourceForUrl({
    required String bucket,
    required String key,
    required Map<String, String> queryParameters,
  }) {
    final String resource = '/$bucket/$key';
    return _appendCanonicalizedQuery(resource, queryParameters);
  }

  static String _appendCanonicalizedQuery(
    String resource,
    Map<String, String> queryParameters,
  ) {
    // OSS V1 子资源按参数名排序，格式为 key 或 key=value。
    // 这里再次过滤，保证 Header 签名和 URL 签名复用同一套规则。
    final List<MapEntry<String, String>> signedEntries = queryParameters.entries
        .where(
          (MapEntry<String, String> entry) =>
              _signedSubresources.contains(entry.key),
        )
        .toList()
      ..sort(
        (MapEntry<String, String> a, MapEntry<String, String> b) =>
            a.key.compareTo(b.key),
      );

    if (signedEntries.isEmpty) {
      return resource;
    }

    final String canonicalizedQuery = signedEntries
        .map(
          (MapEntry<String, String> entry) =>
              entry.value.isEmpty ? entry.key : '${entry.key}=${entry.value}',
        )
        .join('&');
    return '$resource?$canonicalizedQuery';
  }

  static String _buildQueryString(Map<String, String> queryParameters) {
    return queryParameters.entries.map((MapEntry<String, String> entry) {
      final String encodedKey = OSSUtils.ossUriEncode(entry.key);
      if (entry.value.isEmpty) {
        return encodedKey;
      }
      return '$encodedKey=${OSSUtils.ossUriEncode(entry.value)}';
    }).join('&');
  }

  /// 验证自定义查询参数
  ///
  /// 检查自定义查询参数是否与OSS保留参数冲突
  ///
  /// 参数：
  /// - [queryParameters] 自定义查询参数映射
  ///
  /// 如果发现冲突参数，将抛出 [ArgumentError]
  static void _validateCustomQueryParameters(
    Map<String, String> queryParameters,
  ) {
    // OSS V1签名保留的查询参数
    const Set<String> reservedParams = <String>{
      'ossaccesskeyid',
      'expires',
      'signature',
      'security-token',
    };

    // 检查是否有冲突的参数
    for (final String key in queryParameters.keys) {
      if (reservedParams.contains(key.toLowerCase())) {
        throw ArgumentError(
          '自定义查询参数 "$key" 与OSS保留参数冲突，请使用其他参数名',
        );
      }
    }
  }
}
