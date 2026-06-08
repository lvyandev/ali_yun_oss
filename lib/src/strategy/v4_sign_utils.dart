import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_aliyun_oss/src/utils/utils.dart';

/// 阿里云OSS V4版本签名工具类
///
/// 用于生成阿里云OSS V4版本的签名和授权头信息, 符合阿里云OSS API规范。
/// 该类实现了基于 HMAC-SHA256 算法的签名生成过程, 提供比 V1 签名更安全的认证机制。
///
/// V4签名算法的主要步骤：
/// 1. 构建规范化的URI、查询参数和头部
/// 2. 组合各元素构建规范化请求
/// 3. 构建签名范围和待签名字符串
/// 4. 生成派生密钥并计算 HMAC-SHA256 签名
/// 5. 生成最终的授权头格式：`OSS4-HMAC-SHA256 Credential={AccessKeyId}/{Date}/{Region}/oss/aliyun_v4_request, Signature={Signature}`
///
/// 与 V1 签名相比, V4 签名的主要优势：
/// - 使用更安全的 HMAC-SHA256 算法
/// - 包含区域信息, 增强了安全性
/// - 支持更多的头部参与签名
/// - 签名过程更复杂, 更难被破解
///
/// 注意：该类提供的是静态工具方法, 不应该被实例化。
/// 对于新应用, 建议优先使用 V4 签名算法。
class AliOssV4SignUtils {
  // 私有构造函数, 防止实例化
  AliOssV4SignUtils._();

  /// OSS头部前缀常量
  static const String _ossHeaderPrefix = 'x-oss-';

  /// 默认需要签名的头部
  static const Set<String> _defaultSignHeaders = <String>{
    'x-oss-date',
    'x-oss-content-sha256',
    'content-type',
  };

  /// 生成阿里云OSS V4签名所需的Authorization头
  ///
  /// 根据提供的参数生成符合阿里云OSS V4版本规范的授权头字符串。
  /// 该方法实现了完整的V4签名过程, 包括构建规范化请求、签名范围和计算签名。
  ///
  /// 签名过程：
  /// 1. 处理时间参数并格式化为 ISO8601 格式
  /// 2. 设置必要的请求头, 如 x-oss-content-sha256 和 x-oss-date
  /// 3. 处理安全令牌（如果提供）
  /// 4. 构建规范化的URI、查询参数和头部
  /// 5. 处理额外需要签名的头部
  /// 6. 构建规范化请求字符串
  /// 7. 构建签名范围和待签名字符串
  /// 8. 计算HMAC-SHA256签名
  /// 9. 生成最终的授权头格式
  ///
  /// 参数：
  /// - [accessKeyId] 阿里云访问密钥ID
  /// - [accessKeySecret] 阿里云访问密钥
  /// - [endpoint] 阿里云OSS端点（如：oss-cn-hangzhou.aliyuncs.com）
  /// - [region] 区域代码（如：cn-hangzhou）
  /// - [method] HTTP方法（大写, 如：PUT/GET）
  /// - [bucket] OSS存储空间名称
  /// - [key] 对象键（文件路径）
  /// - [uri] 完整的请求URI（用于解析查询参数）
  /// - [headers] 请求头集合, 将被用于签名计算
  /// - [additionalHeaders] 需要参与签名的额外头名称集合, 默认为空集合
  /// - [securityToken] 安全令牌（STS临时凭证需要）
  /// - [dateTime] 指定请求时间（可选, 默认为当前时间）
  ///
  /// 返回完整的授权头字符串, 格式为 `OSS4-HMAC-SHA256 Credential={AccessKeyId}/{Date}/{Region}/oss/aliyun_v4_request, Signature={Signature}`
  ///
  /// 示例：
  /// ```dart
  /// final authHeader = AliOssV4SignUtils.signature(
  ///   accessKeyId: 'your-access-key-id',
  ///   accessKeySecret: 'your-access-key-secret',
  ///   endpoint: 'oss-cn-hangzhou.aliyuncs.com',
  ///   region: 'cn-hangzhou',
  ///   method: 'GET',
  ///   bucket: 'example-bucket',
  ///   key: 'example.txt',
  ///   uri: Uri.parse('https://example-bucket.oss-cn-hangzhou.aliyuncs.com/example.txt'),
  ///   headers: {'content-type': 'application/octet-stream'},
  /// );
  /// ```
  static String signature({
    required String accessKeyId,
    required String accessKeySecret,
    required String endpoint,
    required String region,
    required String method,
    required String bucket,
    required String key,
    required Uri uri,
    required Map<String, dynamic> headers,
    bool cname = false,
    Set<String> additionalHeaders = const <String>{},
    String? securityToken,
    DateTime? dateTime,
  }) {
    // 创建headers的副本, 避免修改原始map
    final Map<String, dynamic> headersToSign = <String, dynamic>{...headers};
    // 把_defaultSignHeaders添加到headersToSign中
    for (final String key in _defaultSignHeaders) {
      headersToSign[key] = headers[key];
    }

    // 1. 处理时间相关参数
    final DateTime now = (dateTime ?? DateTime.now()).toUtc();
    final String signDate = DateFormatter.formatYYYYMMDD(now);
    final String signTime = '${DateFormatter.formatYYYYMMDDTHHMMSS(now)}Z';

    // 2. 设置必要的请求头
    headersToSign['x-oss-content-sha256'] = 'UNSIGNED-PAYLOAD';
    headersToSign['x-oss-date'] = signTime;

    // 3. 添加安全令牌头（如果有）
    if (securityToken != null) {
      headersToSign['x-oss-security-token'] = securityToken;
    }

    // 4. 构建规范请求组件
    final String canonicalUri = _buildCanonicalUri(
      bucket,
      key,
    );
    final String canonicalQuery = _buildCanonicalQuery(uri);
    final String canonicalHeaders = _buildCanonicalHeaders(
      headersToSign,
      additionalHeaders,
    );

    // 5. 处理额外头部
    final List<String> addHeaders = additionalHeaders
        .where((String e) => !_isDefaultSignHeader(e))
        .toList()
      ..sort();
    final String additionalHeadersString = addHeaders.join(';');

    // 6. 构建规范请求
    final String canonicalRequestString = <String>[
      method.toUpperCase(),
      canonicalUri,
      canonicalQuery,
      canonicalHeaders,
      additionalHeadersString,
      headersToSign['x-oss-content-sha256'] ?? 'UNSIGNED-PAYLOAD',
    ].join('\n');

    // 7. 构建签名范围和待签名字符串
    final String scope = '$signDate/$region/oss/aliyun_v4_request';
    final String stringToSign = _buildStringToSign(
      iso8601Time: signTime,
      scope: scope,
      canonicalRequest: canonicalRequestString.trim(),
    );

    // 8. 计算签名
    final String signature = _calculateV4Signature(
      accessKeySecret: accessKeySecret,
      date: signDate,
      region: region,
      stringToSign: stringToSign,
    );

    // 9. 构建并返回Authorization头
    return _buildAuthorizationHeader(
      accessKeyId: accessKeyId,
      scope: scope,
      additionalHeaders: additionalHeadersString,
      signature: signature,
    );
  }

  /// 生成包含签名的完整HTTP请求头
  ///
  /// 根据提供的参数生成包含阿里云OSS V4签名的完整HTTP请求头。
  /// 该方法不仅生成授权头, 还会处理其他必要的头部, 如日期、主机和内容哈希等。
  ///
  /// 处理流程：
  /// 1. 创建原始头部的副本, 避免修改原始数据
  /// 2. 处理时间参数并格式化为 ISO8601 格式
  /// 3. 更新标准请求头, 如 x-oss-date、Host、x-oss-content-sha256 和 Date
  /// 4. 处理安全令牌（如果提供）
  /// 5. 调用 [signature] 方法生成授权头
  /// 6. 将授权头添加到结果头部中并返回
  ///
  /// 参数：
  /// - [accessKeyId] 阿里云访问密钥ID
  /// - [accessKeySecret] 阿里云访问密钥
  /// - [endpoint] 阿里云OSS端点（如：oss-cn-hangzhou.aliyuncs.com）或自定义域名
  /// - [region] 区域代码（如：cn-hangzhou）
  /// - [method] HTTP方法（大写, 如：PUT/GET）
  /// - [bucket] OSS存储空间名称
  /// - [key] 对象键（文件路径）
  /// - [uri] 完整的请求URI
  /// - [headers] 原始请求头集合, 将被扩展并签名
  /// - [cname] 是否使用自定义域名，默认为false
  /// - [additionalHeaders] 需要参与签名的额外头名称集合, 默认为空集合
  /// - [securityToken] 安全令牌（STS临时凭证需要）
  /// - [dateTime] 指定请求时间（可选, 默认为当前时间）
  ///
  /// 返回包含完整签名头部的Map, 可直接用于 HTTP 请求
  ///
  /// 示例：
  /// ```dart
  /// final headers = AliOssV4SignUtils.signedHeaders(
  ///   accessKeyId: 'your-access-key-id',
  ///   accessKeySecret: 'your-access-key-secret',
  ///   endpoint: 'oss-cn-hangzhou.aliyuncs.com',
  ///   region: 'cn-hangzhou',
  ///   method: 'PUT',
  ///   bucket: 'example-bucket',
  ///   key: 'example.txt',
  ///   uri: Uri.parse('https://example-bucket.oss-cn-hangzhou.aliyuncs.com/example.txt'),
  ///   headers: {'content-type': 'text/plain'},
  /// );
  /// // 结果包含如下头部：
  /// // {
  /// //   'content-type': 'text/plain',
  /// //   'x-oss-date': '20230615T123045Z',
  /// //   'Host': 'example-bucket.oss-cn-hangzhou.aliyuncs.com',
  /// //   'x-oss-content-sha256': 'UNSIGNED-PAYLOAD',
  /// //   'Date': 'Wed, 15 Jun 2023 12:30:45 GMT',
  /// //   'Authorization': 'OSS4-HMAC-SHA256 Credential=...,Signature=...'
  /// // }
  /// ```
  static Map<String, dynamic> signedHeaders({
    required String accessKeyId,
    required String accessKeySecret,
    required String endpoint,
    required String region,
    required String method,
    required String bucket,
    required String key,
    required Uri uri,
    required Map<String, dynamic> headers,
    bool cname = false,
    Set<String> additionalHeaders = const <String>{},
    String? securityToken,
    DateTime? dateTime,
  }) {
    // 创建headers的副本, 避免修改原始map
    final Map<String, dynamic> result = <String, dynamic>{...headers};

    // 1. 处理时间相关参数
    final DateTime now = (dateTime ?? DateTime.now()).toUtc();
    final String signTime = '${DateFormatter.formatYYYYMMDDTHHMMSS(now)}Z';

    // 2. 更新标准请求头
    result['x-oss-date'] = signTime;
    // 根据是否启用CNAME选择不同的Host头构造方式
    result['Host'] = cname ? endpoint : '$bucket.$endpoint';
    result['x-oss-content-sha256'] = 'UNSIGNED-PAYLOAD';
    result['Date'] = HttpDate.format(now);

    // 3. 添加安全令牌头（如果有）
    if (securityToken != null) {
      result['x-oss-security-token'] = securityToken;
    }

    // 4. 构建签名
    final String auth = signature(
      accessKeyId: accessKeyId,
      accessKeySecret: accessKeySecret,
      endpoint: endpoint,
      region: region,
      method: method,
      bucket: bucket,
      key: key,
      uri: uri,
      headers: result,
      cname: cname,
      additionalHeaders: additionalHeaders,
      securityToken: securityToken,
      dateTime: now,
    );

    // 5. 设置Authorization头并返回完整头部
    result['Authorization'] = auth;
    return result;
  }

  /// 构建Authorization头
  static String _buildAuthorizationHeader({
    required String accessKeyId,
    required String scope,
    required String additionalHeaders,
    required String signature,
  }) {
    final List<String> components = <String>[
      'OSS4-HMAC-SHA256 Credential=$accessKeyId/$scope',
    ];

    if (additionalHeaders.isNotEmpty) {
      components.add('AdditionalHeaders=$additionalHeaders');
    }

    components.add('Signature=$signature');
    return components.join(',');
  }

  /// 判断是否默认签名头
  static bool _isDefaultSignHeader(String header) {
    return header.startsWith(_ossHeaderPrefix) ||
        header == 'content-type' ||
        header == 'content-md5';
  }

  /// 构建规范URI
  ///
  /// 根据使用场景构建不同格式的规范URI：
  /// - 对于签名URL：格式为 /object, 不包含 bucket 名称
  /// - 对于请求头签名：格式为 /bucket/object, 包含 bucket 名称
  ///
  /// 参数：
  /// - [bucket] 存储空间名称
  /// - [key] 对象键（文件路径）
  /// - [isForSignedUrl] 是否用于生成签名URL, 默认为false
  ///
  /// 返回编码后的规范URI字符串
  static String _buildCanonicalUri(
    String bucket,
    String key, {
    bool isForSignedUrl = false,
  }) {
    // 验证参数
    if (bucket.isEmpty) {
      throw ArgumentError('bucket 不能为空');
    }

    final String resourcePath = isForSignedUrl ? '/$key' : '/$bucket/$key';
    return _ossUriEncode(resourcePath, encodeSlash: false);
  }

  /// 构建规范查询字符串
  ///
  /// 构建 V4 规范查询字符串。
  ///
  /// 阿里云 OSS V4 要求先按官方 UriEncode 规则编码 key/value，再按编码后的
  /// `key=value` 片段字典序排序。不能先按原始中文或特殊字符排序，否则在
  /// query 含中文、空格、括号等字符时会和服务端计算结果不一致。
  ///
  /// 参数：
  /// - [uri] 包含查询参数的 URI 对象
  ///
  /// 返回格式化后的规范查询字符串, 格式为 key1=value1&key2=value2
  static String _buildCanonicalQuery(Uri uri) {
    // 如果没有查询参数, 直接返回空字符串
    final Map<String, List<String>> queryParams = uri.queryParametersAll;
    if (queryParams.isEmpty) {
      return '';
    }

    final List<String> params = <String>[];

    for (final String key in queryParams.keys) {
      final String encodedKey = _ossUriEncode(key);

      // 处理每个值
      for (final String value in queryParams[key] ?? <String>[]) {
        final String encodedValue = value.isEmpty ? '' : _ossUriEncode(value);

        // 构建参数字符串
        if (encodedValue.isEmpty) {
          params.add(encodedKey);
        } else {
          params.add('$encodedKey=$encodedValue');
        }
      }
    }

    // 对已经编码完成的片段排序，保持和 OSS 服务端 CanonicalQueryString 一致。
    params.sort();
    return params.join('&');
  }

  /// 构建规范头列表
  ///
  /// 按照字典序排序头部, 并格式化为key:value形式
  ///
  /// 参数：
  /// - [headers] 请求头集合
  /// - [additionalHeaders] 需要参与签名的额外头名称集合
  ///
  /// 返回格式化后的规范头列表字符串, 每行一个头部, 格式为 key:value, 末尾有换行符
  ///
  /// 兼容性说明（依据阿里云文档）：
  /// - x-oss-*、content-type、content-md5 若存在则应参与签名（不需要出现在 AdditionalHeaders 中）。
  /// - AdditionalHeaders 仅用于声明除上述“默认/条件性头”之外、必须参与签名的头（例如 host）。
  static String _buildCanonicalHeaders(
    Map<String, dynamic> headers,
    Set<String> additionalHeaders,
  ) {
    // 转换所有键为小写, 以符合规范
    final Map<String, String> lowerHeaders = <String, String>{};
    headers.forEach((String key, dynamic value) {
      lowerHeaders[key.toLowerCase()] = (value?.toString() ?? '').trim();
    });

    // 自动收集“若存在则参与签名”的头部：x-oss-* / content-type / content-md5
    final Set<String> autoSignHeaders =
        lowerHeaders.keys.where((String k) => _isDefaultSignHeader(k)).toSet();

    // 合并：额外声明的头 ∪ 默认固定头 ∪ 自动收集头
    final Set<String> allSignHeaders = <String>{
      ...additionalHeaders.map((String header) => header.toLowerCase()),
      ..._defaultSignHeaders,
      ...autoSignHeaders,
    };

    // 仅添加存在于 lowerHeaders 且属于签名集合的头部
    final List<String> headerList = <String>[];
    lowerHeaders.forEach((String key, String value) {
      if (allSignHeaders.contains(key)) {
        headerList.add('$key:$value');
      }
    });

    headerList.sort();
    return '${headerList.join('\n')}\n';
  }

  /// 构建待签名字符串
  ///
  /// 包含算法标识、时间戳、作用域和请求哈希
  ///
  /// 参数：
  /// - [iso8601Time] ISO8601 格式的时间戳
  /// - [scope] 签名范围, 格式为 {date}/{region}/oss/aliyun_v4_request
  /// - [canonicalRequest] 规范请求字符串
  ///
  /// 返回格式化后的待签名字符串, 格式为：
  /// OSS4-HMAC-SHA256\n
  /// {iso8601Time}\n
  /// {scope}\n
  /// {hashedRequest}
  static String _buildStringToSign({
    required String iso8601Time,
    required String scope,
    required String canonicalRequest,
  }) {
    // 计算规范请求的SHA256哈希
    final List<int> requestBytes = utf8.encode(canonicalRequest);
    final Digest digest = sha256.convert(requestBytes);
    final String hashedRequest = hex.encode(digest.bytes);

    // 构建待签名字符串的组成部分
    final List<String> components = <String>[
      'OSS4-HMAC-SHA256', // 算法标识
      iso8601Time, // 时间戳
      scope, // 签名范围
      hashedRequest, // 请求哈希
    ];

    // 连接各部分, 使用换行符分隔
    return components.join('\n');
  }

  /// 计算V4签名
  ///
  /// 使用派生密钥进行HMAC-SHA256签名
  /// 根据阿里云文档, V4 签名的密钥派生过程为：
  /// 1. 生成初始密钥：aliyun_v4$accessKeySecret
  /// 2. 派生日期密钥：HMAC-SHA256(初始密钥, date)
  /// 3. 派生区域密钥：HMAC-SHA256(日期密钥, region)
  /// 4. 派生服务密钥：HMAC-SHA256(区域密钥, "oss")
  /// 5. 派生签名密钥：HMAC-SHA256(服务密钥, "aliyun_v4_request")
  ///
  /// 参数：
  /// - [accessKeySecret] 阿里云访问密钥
  /// - [date] 签名日期, 格式为 YYYYMMDD
  /// - [region] 区域代码（如：cn-hangzhou）
  /// - [stringToSign] 待签名字符串
  ///
  /// 返回十六进制编码的签名字符串
  static String _calculateV4Signature({
    required String accessKeySecret,
    required String date,
    required String region,
    required String stringToSign,
  }) {
    // 1. 生成初始密钥
    final List<int> v4Key = utf8.encode('aliyun_v4$accessKeySecret');

    // 2. 派生日期密钥
    final List<int> signingDate = _hmacSha256(v4Key, date);

    // 3. 派生区域密钥
    final List<int> signingRegion = _hmacSha256(signingDate, region);

    // 4. 派生服务密钥
    final List<int> signingOss = _hmacSha256(signingRegion, 'oss');

    // 5. 派生签名密钥
    final List<int> signingKey = _hmacSha256(signingOss, 'aliyun_v4_request');

    // 6. 计算最终签名
    final List<int> signatureBytes = _hmacSha256(signingKey, stringToSign);

    // 7. 返回十六进制编码的签名
    return hex.encode(signatureBytes);
  }

  /// 辅助方法：计算 HMAC-SHA256
  ///
  /// 使用给定的密钥对消息进行 HMAC-SHA256 计算
  ///
  /// 参数：
  /// - [key] 密钥字节数组
  /// - [message] 待计算的消息字符串
  ///
  /// 返回计算结果的字节数组
  static List<int> _hmacSha256(List<int> key, String message) {
    return Hmac(sha256, key).convert(utf8.encode(message)).bytes;
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
    // OSS V4签名保留的查询参数
    const Set<String> reservedParams = <String>{
      'x-oss-credential',
      'x-oss-date',
      'x-oss-expires',
      'x-oss-signature-version',
      'x-oss-additional-headers',
      'x-oss-security-token',
      'x-oss-signature',
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

  /// 生成包含签名的URL
  ///
  /// 根据提供的参数生成包含阿里云OSS V4签名的URL。
  /// 该方法将签名信息作为URL的查询参数,可以直接用于访问OSS资源。
  ///
  /// 参数：
  /// - [accessKeyId] 阿里云访问密钥ID
  /// - [accessKeySecret] 阿里云访问密钥
  /// - [endpoint] 阿里云OSS端点（如：oss-cn-hangzhou.aliyuncs.com）或自定义域名
  /// - [region] 区域代码（如：cn-hangzhou）
  /// - [method] HTTP方法（大写, 如：PUT/GET）
  /// - [bucket] OSS存储空间名称
  /// - [key] 对象键（文件路径）
  /// - [expires] 签名过期时间（秒）, 默认3600秒
  /// - [cname] 是否使用自定义域名，默认为false
  /// - [headers] 请求头集合, 将被用于签名计算
  /// - [additionalHeaders] 需要参与签名的额外头名称集合, 默认为空集合
  /// - [securityToken] 安全令牌（STS临时凭证需要）
  /// - [dateTime] 指定请求时间（可选, 默认为当前时间）
  /// - [queryParameters] 自定义查询参数, 如图片处理参数等, 将参与签名计算
  ///
  /// 返回包含签名的完整URL
  ///
  /// 示例：
  /// ```dart
  /// // 基础用法
  /// final url = AliOssV4SignUtils.signatureUri(
  ///   accessKeyId: 'your-access-key-id',
  ///   accessKeySecret: 'your-access-key-secret',
  ///   endpoint: 'oss-cn-hangzhou.aliyuncs.com',
  ///   region: 'cn-hangzhou',
  ///   method: 'GET',
  ///   bucket: 'example-bucket',
  ///   key: 'example.txt',
  /// );
  ///
  /// // 自定义域名用法
  /// final customUrl = AliOssV4SignUtils.signatureUri(
  ///   accessKeyId: 'your-access-key-id',
  ///   accessKeySecret: 'your-access-key-secret',
  ///   endpoint: 'img.example.com',
  ///   region: 'cn-hangzhou',
  ///   method: 'GET',
  ///   bucket: 'example-bucket',
  ///   key: 'example.txt',
  ///   cname: true, // 启用自定义域名
  /// );
  ///
  /// // 带图片处理参数的用法
  /// final imageUrl = AliOssV4SignUtils.signatureUri(
  ///   accessKeyId: 'your-access-key-id',
  ///   accessKeySecret: 'your-access-key-secret',
  ///   endpoint: 'oss-cn-hangzhou.aliyuncs.com',
  ///   region: 'cn-hangzhou',
  ///   method: 'GET',
  ///   bucket: 'example-bucket',
  ///   key: 'image.jpg',
  ///   queryParameters: {
  ///     'x-oss-process': 'image/resize,l_100',
  ///   },
  /// );
  /// ```
  static Uri signatureUri({
    required String accessKeyId,
    required String accessKeySecret,
    required String endpoint,
    required String region,
    required String method,
    required String bucket,
    required String key,
    int expires = 3600,
    bool cname = false,
    Map<String, dynamic>? headers,
    Set<String>? additionalHeaders,
    String? securityToken,
    DateTime? dateTime,
    Map<String, String>? queryParameters,
  }) {
    // 1. 验证参数
    if (bucket.isEmpty) {
      throw ArgumentError('bucket 不能为空');
    }
    if (key.isEmpty) {
      throw ArgumentError('key 不能为空');
    }
    if (method.isEmpty) {
      throw ArgumentError('method 不能为空');
    }
    if (region.isEmpty) {
      throw ArgumentError('region 不能为空, V4 签名必须指定区域');
    }
    if (expires < 1) {
      throw ArgumentError('expires 必须大于 0');
    }

    // 2. 处理时间相关参数
    final DateTime now = (dateTime ?? DateTime.now()).toUtc();
    final String signDate = DateFormatter.formatYYYYMMDD(now);
    final String signTime = '${DateFormatter.formatYYYYMMDDTHHMMSS(now)}Z';

    // 3. 构建基础URL
    // 根据是否启用CNAME选择不同的域名构造方式
    final String host = cname ? endpoint : '$bucket.$endpoint';
    final String encodedObjectPath = _ossUriEncode('/$key', encodeSlash: false);

    final String canonicalUri = _buildCanonicalUri(bucket, key);

    final Map<String, dynamic> headersToSign = <String, dynamic>{...?headers};
    headersToSign['host'] = host;

    // 6. 构建查询参数
    final Map<String, String> queryParams = <String, String>{};

    // 6.1 首先添加自定义查询参数（如果有）
    if (queryParameters != null && queryParameters.isNotEmpty) {
      // 验证自定义参数不与OSS保留参数冲突
      _validateCustomQueryParameters(queryParameters);
      queryParams.addAll(queryParameters);
    }

    // 6.2 添加OSS签名相关的查询参数
    queryParams.addAll(<String, String>{
      'x-oss-credential':
          '$accessKeyId/$signDate/$region/oss/aliyun_v4_request',
      'x-oss-date': signTime,
      'x-oss-expires': expires.toString(),
      'x-oss-signature-version': 'OSS4-HMAC-SHA256',
    });

    final Set<String> normalizedAdditionalHeaders =
        (additionalHeaders ?? <String>{'host'})
            .map((String header) => header.toLowerCase())
            .toSet();
    final List<String> addHeaders = normalizedAdditionalHeaders
        .where((String e) => !_isDefaultSignHeader(e))
        .toList()
      ..sort();
    final String additionalHeadersString = addHeaders.join(';');

    // 添加额外头部参数（如果有）
    if (additionalHeadersString.isNotEmpty) {
      queryParams['x-oss-additional-headers'] = additionalHeadersString;
    }

    // 添加安全令牌（如果有）
    if (securityToken != null && securityToken.isNotEmpty) {
      queryParams['x-oss-security-token'] = securityToken;
    }

    // 5. 构建规范请求
    // 根据阿里云文档和错误信息, 规范请求的格式应该是：
    // <HTTPMethod>\n<CanonicalURI>\n<CanonicalQueryString>\n<CanonicalHeaders>\n<SignedHeaders>\n<HashedPayload>

    // 5.1 构建规范查询字符串
    final String canonicalQueryString = _buildCanonicalQuery(
      Uri(queryParameters: queryParams),
    );

    // 5.2 构建规范头部
    final String canonicalHeaders = _buildCanonicalHeaders(
      headersToSign,
      normalizedAdditionalHeaders,
    );

    // 5.4 获取负载哈希值
    final String hashedPayload =
        headersToSign['x-oss-content-sha256'] ?? 'UNSIGNED-PAYLOAD';

    // 5.5 组合构建规范请求
    final String canonicalRequest = <String>[
      method.toUpperCase(), // HTTP方法
      canonicalUri, // 规范URI
      canonicalQueryString, // 规范查询字符串
      canonicalHeaders, // 规范头部
      additionalHeadersString, // 签名头部列表
      hashedPayload, // 负载哈希值
    ].join('\n');

    // 6. 构建待签名字符串
    final String scope = '$signDate/$region/oss/aliyun_v4_request';
    final String stringToSign = _buildStringToSign(
      iso8601Time: signTime,
      scope: scope,
      canonicalRequest: canonicalRequest,
    );

    // 7. 计算签名
    final String signature = _calculateV4Signature(
      accessKeySecret: accessKeySecret,
      date: signDate,
      region: region,
      stringToSign: stringToSign,
    );

    // 8. 添加签名到查询参数
    queryParams['x-oss-signature'] = signature;

    // 9. 构建并返回最终URL。这里不能依赖 Dart Uri 的默认编码，
    // OSS V4 要求使用官方 UriEncode 规则（例如括号必须编码）。
    final String encodedQuery = _buildQueryString(queryParams);
    return Uri.parse('https://$host$encodedObjectPath?$encodedQuery');
  }

  /// 构建最终 URL 的 query 字符串。
  ///
  /// 预签名 URL 的实际 query 必须和参与签名的 CanonicalQueryString 使用同一套
  /// OSS UriEncode 和排序规则，否则 URL 看起来合法但服务端验签会失败。
  static String _buildQueryString(Map<String, String> queryParameters) {
    final List<MapEntry<String, String>> entries =
        queryParameters.entries.toList()
          ..sort((MapEntry<String, String> a, MapEntry<String, String> b) {
            final String encodedA = _ossUriEncode(a.key);
            final String encodedB = _ossUriEncode(b.key);
            final int keyCompare = encodedA.compareTo(encodedB);
            if (keyCompare != 0) {
              return keyCompare;
            }
            return _ossUriEncode(a.value).compareTo(_ossUriEncode(b.value));
          });

    return entries.map((MapEntry<String, String> entry) {
      final String encodedKey = _ossUriEncode(entry.key);
      if (entry.value.isEmpty) {
        return encodedKey;
      }
      return '$encodedKey=${_ossUriEncode(entry.value)}';
    }).join('&');
  }

  /// 阿里云 OSS V4 官方 UriEncode。
  ///
  /// 仅 `A-Z`、`a-z`、`0-9`、`-`、`_`、`.`、`~` 保持原样；其他 UTF-8 字节
  /// 都用大写十六进制 `%XX` 编码。构建 CanonicalURI 时路径分隔符 `/` 不编码，
  /// 构建 query key/value 时 `/` 也要按普通字符编码。
  static String _ossUriEncode(String value, {bool encodeSlash = true}) {
    return OSSUtils.ossUriEncode(value, encodeSlash: encodeSlash);
  }
}
