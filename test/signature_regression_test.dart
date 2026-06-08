import 'dart:convert';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_aliyun_oss/dart_aliyun_oss.dart';
import 'package:test/test.dart';

void main() {
  const String accessKeyId = 'test-access-key-id';
  const String accessKeySecret = 'test-access-key-secret';
  const String endpoint = 'oss-cn-hangzhou.aliyuncs.com';
  const String region = 'cn-hangzhou';
  const String bucket = 'test-bucket';
  final DateTime fixedTime = DateTime.utc(2026, 6, 5, 12, 30, 40);

  group('签名回归测试', () {
    test('createSignedHeaders 应使用 OSSRequestParams 中声明的签名版本', () {
      final OSSClient client = OSSClient.init(
        OSSConfig.static(
          accessKeyId: accessKeyId,
          accessKeySecret: accessKeySecret,
          bucketName: bucket,
          endpoint: endpoint,
          region: region,
          enableLogInterceptor: false,
        ),
      );

      final Map<String, dynamic> headers = client.createSignedHeaders(
        method: 'GET',
        fileKey: 'example.txt',
        baseHeaders: <String, dynamic>{},
        params: OSSRequestParams(
          dateTime: fixedTime,
          isV1Signature: true,
        ),
      );

      expect(headers['Authorization'], startsWith('OSS $accessKeyId:'));
    });

    test('V1 signedUrl 应将 OSS 子资源 query 纳入签名', () {
      const String key = 'tenant/1/common/example.pdf';
      const int expires = 7200;
      final Map<String, String> queryParameters = <String, String>{
        'x-oss-process': 'image/resize,l_100',
        'response-content-type': 'application/pdf',
      };

      final Uri uri = AliOssV1SignUtils.signatureUri(
        accessKeyId: accessKeyId,
        accessKeySecret: accessKeySecret,
        endpoint: endpoint,
        method: 'GET',
        bucket: bucket,
        key: key,
        expires: expires,
        dateTime: fixedTime,
        queryParameters: queryParameters,
      );

      final int expiresTimestamp =
          fixedTime.millisecondsSinceEpoch ~/ 1000 + expires;
      final String expectedSignature = _v1Signature(
        accessKeySecret: accessKeySecret,
        stringToSign: <String>[
          'GET',
          '',
          '',
          expiresTimestamp.toString(),
          '/$bucket/$key?response-content-type=application/pdf&'
              'x-oss-process=image/resize,l_100',
        ].join('\n'),
      );

      expect(uri.queryParameters['Signature'], expectedSignature);
    });

    test('V1 signedUrl 实际 URL path 应编码加号和括号', () {
      const String key = 'tenant/力特威丝扣球阀---连云港ZL(1) space+plus.txt';
      const int expires = 7200;

      final Uri uri = AliOssV1SignUtils.signatureUri(
        accessKeyId: accessKeyId,
        accessKeySecret: accessKeySecret,
        endpoint: endpoint,
        method: 'GET',
        bucket: bucket,
        key: key,
        expires: expires,
        dateTime: fixedTime,
      );

      final int expiresTimestamp =
          fixedTime.millisecondsSinceEpoch ~/ 1000 + expires;
      final String expectedSignature = _v1Signature(
        accessKeySecret: accessKeySecret,
        stringToSign: <String>[
          'GET',
          '',
          '',
          expiresTimestamp.toString(),
          '/$bucket/$key',
        ].join('\n'),
      );

      expect(uri.toString(), contains('%28'));
      expect(uri.toString(), contains('%29'));
      expect(uri.toString(), contains('%2B'));
      expect(uri.queryParameters['Signature'], expectedSignature);
    });

    test('V4 signedUrl 应使用 UriEncode 后的 Canonical URI 计算签名', () {
      const String key = 'tenant/1/common/力特威丝扣球阀---连云港ZL(1).pdf';
      const int expires = 7200;

      final Uri uri = AliOssV4SignUtils.signatureUri(
        accessKeyId: accessKeyId,
        accessKeySecret: accessKeySecret,
        endpoint: endpoint,
        region: region,
        method: 'GET',
        bucket: bucket,
        key: key,
        expires: expires,
        dateTime: fixedTime,
      );

      final String expectedSignature = _v4PresignedUrlSignature(
        accessKeySecret: accessKeySecret,
        accessKeyId: accessKeyId,
        endpoint: endpoint,
        region: region,
        method: 'GET',
        bucket: bucket,
        key: key,
        expires: expires,
        dateTime: fixedTime,
      );

      expect(uri.queryParameters['x-oss-signature'], expectedSignature);
    });

    test('V4 UriEncode 应编码括号等非官方保留字符', () {
      const String key = 'tenant/1/common/example(1).pdf';
      const int expires = 7200;

      final Uri uri = AliOssV4SignUtils.signatureUri(
        accessKeyId: accessKeyId,
        accessKeySecret: accessKeySecret,
        endpoint: endpoint,
        region: region,
        method: 'GET',
        bucket: bucket,
        key: key,
        expires: expires,
        dateTime: fixedTime,
      );

      final String expectedSignature = _v4PresignedUrlSignature(
        accessKeySecret: accessKeySecret,
        accessKeyId: accessKeyId,
        endpoint: endpoint,
        region: region,
        method: 'GET',
        bucket: bucket,
        key: key,
        expires: expires,
        dateTime: fixedTime,
      );

      expect(uri.toString(), contains('%28'));
      expect(uri.toString(), contains('%29'));
      expect(uri.queryParameters['x-oss-signature'], expectedSignature);
    });

    test('V4 Header 签名应按编码后的 query key/value 排序', () {
      final Uri uri = Uri.https(
        '$bucket.$endpoint',
        'example.txt',
        <String, String>{
          'a': '2',
          '中': '1',
        },
      );

      final String authorization = AliOssV4SignUtils.signature(
        accessKeyId: accessKeyId,
        accessKeySecret: accessKeySecret,
        endpoint: endpoint,
        region: region,
        method: 'GET',
        bucket: bucket,
        key: 'example.txt',
        uri: uri,
        headers: <String, dynamic>{'host': '$bucket.$endpoint'},
        additionalHeaders: <String>{'host'},
        dateTime: fixedTime,
      );

      final String expectedSignature = _v4HeaderSignature(
        accessKeySecret: accessKeySecret,
        region: region,
        method: 'GET',
        canonicalUri: _uriEncodePath('/$bucket/example.txt'),
        queryParameters: <String, String>{
          'a': '2',
          '中': '1',
        },
        canonicalHeaders: 'content-type:\n'
            'host:$bucket.$endpoint\n'
            'x-oss-content-sha256:UNSIGNED-PAYLOAD\n'
            'x-oss-date:20260605T123040Z\n',
        additionalHeaders: 'host',
        dateTime: fixedTime,
      );

      expect(authorization, contains('Signature=$expectedSignature'));
    });

    test('buildOssUri 应按 OSS UriEncode 编码实际请求路径', () {
      final OSSClient client = OSSClient.instance;
      final Uri uri = client.buildOssUri(
        fileKey: 'tenant/力特威丝扣球阀---连云港ZL(1)+space.txt',
      );

      expect(uri.toString(), contains('%28'));
      expect(uri.toString(), contains('%29'));
      expect(uri.toString(), contains('%2B'));
      expect(uri.toString(), contains('%E5%8A%9B'));
      expect(uri.path, contains('tenant/'));
    });

    test('V4 Bucket 根请求应使用 Bucket 资源路径参与 Header 签名', () {
      final Uri uri = Uri.https(
        '$bucket.$endpoint',
        '/',
        <String, String>{
          'list-type': '2',
          'prefix': 'codex-live-test/',
          'fetch-owner': 'false',
        },
      );

      final String authorization = AliOssV4SignUtils.signature(
        accessKeyId: accessKeyId,
        accessKeySecret: accessKeySecret,
        endpoint: endpoint,
        region: region,
        method: 'GET',
        bucket: bucket,
        key: '',
        uri: uri,
        headers: <String, dynamic>{'host': '$bucket.$endpoint'},
        additionalHeaders: <String>{'host'},
        dateTime: fixedTime,
      );

      final String expectedSignature = _v4HeaderSignature(
        accessKeySecret: accessKeySecret,
        region: region,
        method: 'GET',
        canonicalUri: _uriEncodePath('/$bucket/'),
        queryParameters: <String, String>{
          'list-type': '2',
          'prefix': 'codex-live-test/',
          'fetch-owner': 'false',
        },
        canonicalHeaders: 'content-type:\n'
            'host:$bucket.$endpoint\n'
            'x-oss-content-sha256:UNSIGNED-PAYLOAD\n'
            'x-oss-date:20260605T123040Z\n',
        additionalHeaders: 'host',
        dateTime: fixedTime,
      );

      expect(authorization, contains('Signature=$expectedSignature'));
    });

    test('V1 Header 签名应只将 OSS 子资源 query 纳入 CanonicalizedResource', () {
      final Uri uri = Uri.https(
        '$bucket.$endpoint',
        'example.txt',
        <String, String>{
          'uploadId': 'upload-1',
          'normal': 'ignored',
        },
      );

      final String authorization = AliOssV1SignUtils.signature(
        accessKeyId: accessKeyId,
        accessKeySecret: accessKeySecret,
        method: 'GET',
        bucket: bucket,
        uri: uri,
        contentType: 'application/octet-stream',
        dateTime: fixedTime,
      );

      final String expectedSignature = _v1Signature(
        accessKeySecret: accessKeySecret,
        stringToSign: <String>[
          'GET',
          '',
          'application/octet-stream',
          'Fri, 05 Jun 2026 12:30:40 GMT',
          '',
          '/$bucket/example.txt?uploadId=upload-1',
        ].join('\n'),
      );

      expect(authorization, 'OSS $accessKeyId:$expectedSignature');
    });

    test('createSignedHeaders 不应原地修改调用方传入的 queryParameters', () {
      final OSSClient client = OSSClient.instance;
      final Map<String, dynamic> directQueryParameters = <String, dynamic>{
        'direct': '1',
      };
      final Map<String, dynamic> paramsQueryParameters = <String, dynamic>{
        'fromParams': '2',
      };

      client.createSignedHeaders(
        method: 'GET',
        fileKey: 'example.txt',
        queryParameters: directQueryParameters,
        baseHeaders: <String, dynamic>{},
        params: OSSRequestParams(
          dateTime: fixedTime,
          queryParameters: paramsQueryParameters,
        ),
      );

      expect(directQueryParameters, <String, dynamic>{'direct': '1'});
      expect(paramsQueryParameters, <String, dynamic>{'fromParams': '2'});
    });

    test('DateFormatter 应将传入时间统一转换为 UTC 后再格式化', () {
      final DateTime localTime = fixedTime.toLocal();

      expect(
        DateFormatter.formatYYYYMMDDTHHMMSS(localTime),
        DateFormatter.formatYYYYMMDDTHHMMSS(fixedTime),
      );
    });
  });
}

String _v1Signature({
  required String accessKeySecret,
  required String stringToSign,
}) {
  final Hmac hmac = Hmac(sha1, utf8.encode(accessKeySecret));
  final Digest digest = hmac.convert(utf8.encode(stringToSign));
  return base64.encode(digest.bytes);
}

String _v4PresignedUrlSignature({
  required String accessKeySecret,
  required String accessKeyId,
  required String endpoint,
  required String region,
  required String method,
  required String bucket,
  required String key,
  required int expires,
  required DateTime dateTime,
}) {
  final DateTime utcTime = dateTime.toUtc();
  final String signDate = _formatYYYYMMDD(utcTime);
  final String signTime = '${_formatYYYYMMDDTHHMMSS(utcTime)}Z';
  final String host = '$bucket.$endpoint';
  final String scope = '$signDate/$region/oss/aliyun_v4_request';
  final Map<String, String> queryParameters = <String, String>{
    'x-oss-additional-headers': 'host',
    'x-oss-credential': '$accessKeyId/$scope',
    'x-oss-date': signTime,
    'x-oss-expires': expires.toString(),
    'x-oss-signature-version': 'OSS4-HMAC-SHA256',
  };

  final String canonicalRequest = <String>[
    method.toUpperCase(),
    _uriEncodePath('/$bucket/$key'),
    _canonicalQuery(queryParameters),
    'host:$host\n',
    'host',
    'UNSIGNED-PAYLOAD',
  ].join('\n');

  final String stringToSign = <String>[
    'OSS4-HMAC-SHA256',
    signTime,
    scope,
    sha256.convert(utf8.encode(canonicalRequest)).toString(),
  ].join('\n');

  final List<int> dateKey = _hmacSha256(
    utf8.encode('aliyun_v4$accessKeySecret'),
    signDate,
  );
  final List<int> regionKey = _hmacSha256(dateKey, region);
  final List<int> serviceKey = _hmacSha256(regionKey, 'oss');
  final List<int> signingKey = _hmacSha256(serviceKey, 'aliyun_v4_request');
  return hex.encode(_hmacSha256(signingKey, stringToSign));
}

String _v4HeaderSignature({
  required String accessKeySecret,
  required String region,
  required String method,
  required String canonicalUri,
  required Map<String, String> queryParameters,
  required String canonicalHeaders,
  required String additionalHeaders,
  required DateTime dateTime,
}) {
  final DateTime utcTime = dateTime.toUtc();
  final String signDate = _formatYYYYMMDD(utcTime);
  final String signTime = '${_formatYYYYMMDDTHHMMSS(utcTime)}Z';
  final String scope = '$signDate/$region/oss/aliyun_v4_request';
  final String canonicalRequest = <String>[
    method.toUpperCase(),
    canonicalUri,
    _canonicalQuery(queryParameters),
    canonicalHeaders,
    additionalHeaders,
    'UNSIGNED-PAYLOAD',
  ].join('\n');

  final String stringToSign = <String>[
    'OSS4-HMAC-SHA256',
    signTime,
    scope,
    sha256.convert(utf8.encode(canonicalRequest)).toString(),
  ].join('\n');

  final List<int> dateKey = _hmacSha256(
    utf8.encode('aliyun_v4$accessKeySecret'),
    signDate,
  );
  final List<int> regionKey = _hmacSha256(dateKey, region);
  final List<int> serviceKey = _hmacSha256(regionKey, 'oss');
  final List<int> signingKey = _hmacSha256(serviceKey, 'aliyun_v4_request');
  return hex.encode(_hmacSha256(signingKey, stringToSign));
}

List<int> _hmacSha256(List<int> key, String data) {
  final Hmac hmac = Hmac(sha256, key);
  return hmac.convert(utf8.encode(data)).bytes;
}

String _canonicalQuery(Map<String, String> queryParameters) {
  final List<MapEntry<String, String>> entries =
      queryParameters.entries.toList()
        ..sort((MapEntry<String, String> a, MapEntry<String, String> b) {
          final String encodedA = _uriEncode(a.key);
          final String encodedB = _uriEncode(b.key);
          final int keyCompare = encodedA.compareTo(encodedB);
          if (keyCompare != 0) {
            return keyCompare;
          }
          return _uriEncode(a.value).compareTo(_uriEncode(b.value));
        });

  return entries
      .map(
        (MapEntry<String, String> entry) =>
            '${_uriEncode(entry.key)}=${_uriEncode(entry.value)}',
      )
      .join('&');
}

String _uriEncode(String value) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in utf8.encode(value)) {
    if ((byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x30 && byte <= 0x39) ||
        byte == 0x2D ||
        byte == 0x5F ||
        byte == 0x2E ||
        byte == 0x7E) {
      buffer.writeCharCode(byte);
    } else {
      buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}

String _uriEncodePath(String path) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in utf8.encode(path)) {
    if ((byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x30 && byte <= 0x39) ||
        byte == 0x2D ||
        byte == 0x5F ||
        byte == 0x2E ||
        byte == 0x7E ||
        byte == 0x2F) {
      buffer.writeCharCode(byte);
    } else {
      buffer.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return buffer.toString();
}

String _formatYYYYMMDD(DateTime dateTime) =>
    '${dateTime.year.toString().padLeft(4, '0')}'
    '${dateTime.month.toString().padLeft(2, '0')}'
    '${dateTime.day.toString().padLeft(2, '0')}';

String _formatYYYYMMDDTHHMMSS(DateTime dateTime) =>
    '${_formatYYYYMMDD(dateTime)}T'
    '${dateTime.hour.toString().padLeft(2, '0')}'
    '${dateTime.minute.toString().padLeft(2, '0')}'
    '${dateTime.second.toString().padLeft(2, '0')}';
