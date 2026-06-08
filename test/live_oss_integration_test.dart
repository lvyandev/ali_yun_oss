import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_aliyun_oss/dart_aliyun_oss.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 真实 OSS 集成测试开关。
///
/// 默认跳过，避免普通 `dart test` 或 CI 意外访问真实 Bucket。
/// 运行真实测试前设置：
/// - `ALIYUN_OSS_LIVE_TEST=1`
/// - `ALIYUN_OSS_ACCESS_KEY_ID`
/// - `ALIYUN_OSS_ACCESS_KEY_SECRET`
/// - `ALIYUN_OSS_BUCKET`
/// - `ALIYUN_OSS_ENDPOINT`
/// - `ALIYUN_OSS_REGION`
/// - 可选 `ALIYUN_OSS_SECURITY_TOKEN`
const String _liveTestSwitch = 'ALIYUN_OSS_LIVE_TEST';

void main() {
  if (Platform.environment[_liveTestSwitch] != '1') {
    test('真实 OSS 集成测试默认关闭', () {
      markTestSkipped('设置 $_liveTestSwitch=1 后才会访问真实 OSS。');
    });
    return;
  }

  final _LiveOssConfig liveConfig = _LiveOssConfig.load();
  final String prefix =
      'codex-live-test/${DateTime.now().toUtc().millisecondsSinceEpoch}/';
  final List<String> objectKeys = <String>[];
  final List<_PendingMultipartUpload> pendingMultipartUploads =
      <_PendingMultipartUpload>[];
  late final OSSClient client;
  late final Dio signedUrlDio;
  late final Directory tempDirectory;

  setUpAll(() async {
    client = OSSClient.init(
      liveConfig.toOssConfig(),
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 3),
      sendTimeout: const Duration(minutes: 3),
    );
    signedUrlDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 3),
      ),
    );
    tempDirectory = await Directory.systemTemp.createTemp(
      'dart-aliyun-oss-live-',
    );
  });

  tearDownAll(() async {
    for (final _PendingMultipartUpload upload
        in pendingMultipartUploads.reversed) {
      try {
        await client.abortMultipartUpload(upload.key, upload.uploadId);
      } catch (_) {
        // 清理失败不应掩盖主测试结果；未完成分片后续可按 prefix 定位清理。
      }
    }

    for (final String key in objectKeys.reversed) {
      try {
        await client.deleteObject(key);
      } catch (_) {
        // 对象可能已在测试中删除，或因前置步骤失败未创建。
      }
    }

    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  group('真实 OSS 集成测试', () {
    test('初始化真实 OSS 配置', () {
      expect(liveConfig.accessKeyId, isNotEmpty);
      expect(liveConfig.accessKeySecret, isNotEmpty);
      expect(liveConfig.bucketName, isNotEmpty);
      expect(liveConfig.endpoint, isNotEmpty);
      expect(liveConfig.region, isNotEmpty);
    });

    test('putObjectFromString、getObject、getObjectMeta、getObjectStream',
        () async {
      final String key = '${prefix}string-中文-(1)+space.txt';
      const String content = 'live oss string content: 中文、括号(1)、空格 和 plus+';
      objectKeys.add(key);

      final Response<dynamic> putResponse =
          await client.putObjectFromString(content, key);
      expect(putResponse.statusCode, inInclusiveRange(200, 299));

      final Response<dynamic> getResponse = await client.getObject(key);
      expect(_bytesFromResponse(getResponse), utf8.encode(content));

      final ObjectMeta? meta = await client.getObjectMeta(key);
      expect(meta, isNotNull);
      expect(meta!.contentLength, utf8.encode(content).length);
      expect(meta.eTag, isNotEmpty);

      final Response<Stream<List<int>>> streamResponse =
          await client.getObjectStream(key);
      final List<int> streamedBytes = await _collectStream(
        streamResponse.data!,
      );
      expect(streamedBytes, utf8.encode(content));
    });

    test('putObjectFromBytes 和 getObject', () async {
      final String key = '${prefix}bytes-(2).bin';
      final Uint8List bytes = Uint8List.fromList(
        List<int>.generate(4096, (int index) => index % 251),
      );
      objectKeys.add(key);

      final Response<dynamic> putResponse =
          await client.putObjectFromBytes(bytes, key);
      expect(putResponse.statusCode, inInclusiveRange(200, 299));

      final Response<dynamic> getResponse = await client.getObject(key);
      expect(_bytesFromResponse(getResponse), bytes);
    });

    test('putObject(File) 和 getObject', () async {
      final String key = '${prefix}file-upload-(3).txt';
      final File file = File('${tempDirectory.path}/file-upload.txt');
      const String content = 'file upload content with () and 中文';
      await file.writeAsString(content);
      objectKeys.add(key);

      final Response<dynamic> putResponse = await client.putObject(file, key);
      expect(putResponse.statusCode, inInclusiveRange(200, 299));

      final Response<dynamic> getResponse = await client.getObject(key);
      expect(_bytesFromResponse(getResponse), utf8.encode(content));
    });

    test('V1/V4 signedUrl 可读取包含括号、空格和加号的文件名', () async {
      final String key = '$prefix力特威丝扣球阀---连云港ZL(1) space+plus.txt';
      const String content = 'signed url special object content';
      objectKeys.add(key);

      await client.putObjectFromString(content, key);

      final String v1Url = client.signedUrl(
        key,
        expires: 600,
      );
      final Response<List<int>> v1Response = await signedUrlDio.get<List<int>>(
        v1Url,
        options: Options(responseType: ResponseType.bytes),
      );
      expect(v1Response.statusCode, inInclusiveRange(200, 299));
      expect(v1Response.data, utf8.encode(content));

      final String v4Url = client.signedUrl(
        key,
        expires: 600,
        isV1Signature: false,
      );
      final Response<List<int>> v4Response = await signedUrlDio.get<List<int>>(
        v4Url,
        options: Options(responseType: ResponseType.bytes),
      );
      expect(v4Response.statusCode, inInclusiveRange(200, 299));
      expect(v4Response.data, utf8.encode(content));
    });

    test('V4 与 V1 请求 query 签名边界可读取对象', () async {
      final String key = '${prefix}query-boundary-(4).txt';
      const String content = 'query boundary content';
      objectKeys.add(key);

      await client.putObjectFromString(content, key);

      final Response<dynamic> v4Response = await client.getObject(
        key,
        params: const OSSRequestParams(
          queryParameters: <String, dynamic>{
            'a': '2',
            '中': '1',
          },
        ),
      );
      expect(_bytesFromResponse(v4Response), utf8.encode(content));

      final Response<dynamic> v1Response = await client.getObject(
        key,
        params: const OSSRequestParams(
          isV1Signature: true,
          queryParameters: <String, dynamic>{
            'normal': 'ignored-by-v1-canonical-resource',
            'response-cache-control': 'no-cache',
          },
        ),
      );
      expect(_bytesFromResponse(v1Response), utf8.encode(content));
    });

    test('listBucketResultV2 可列出当前测试前缀对象', () async {
      final String keyA = '${prefix}list-a.txt';
      final String keyB = '${prefix}list-b(1).txt';
      objectKeys.addAll(<String>[keyA, keyB]);
      await client.putObjectFromString('list-a', keyA);
      await client.putObjectFromString('list-b', keyB);

      final Response<ListBucketResultV2> response =
          await client.listBucketResultV2(
        prefix: prefix,
        delimiter: null,
        maxKeys: 100,
      );

      expect(response.statusCode, inInclusiveRange(200, 299));
      final Set<String?> listedKeys = response.data!.contents
          .map((Contents content) => content.key)
          .toSet();
      expect(listedKeys, containsAll(<String>[keyA, keyB]));
    });

    test('手动分片上传、listParts、completeMultipartUpload', () async {
      final String key = '${prefix}manual-multipart-(5).txt';
      objectKeys.add(key);
      final List<int> partOne = _patternBytes(128 * 1024, seed: 11);
      final List<int> partTwo = _patternBytes(16 * 1024, seed: 29);
      final List<int> expectedContent = <int>[...partOne, ...partTwo];

      final Response<InitiateMultipartUploadResult> initResponse =
          await client.initiateMultipartUpload(key);
      final String uploadId = initResponse.data!.uploadId;
      final _PendingMultipartUpload pending = _PendingMultipartUpload(
        key,
        uploadId,
      );
      pendingMultipartUploads.add(pending);

      final Response<dynamic> partOneResponse =
          await client.uploadPart(key, partOne, 1, uploadId);
      final String? partOneETag = partOneResponse.headers.value('ETag');
      expect(partOneETag, isNotNull);

      final Response<dynamic> partTwoResponse = await client.uploadPartStream(
        key,
        Stream<List<int>>.fromIterable(<List<int>>[partTwo]),
        partTwo.length,
        2,
        uploadId,
      );
      final String? partTwoETag = partTwoResponse.headers.value('ETag');
      expect(partTwoETag, isNotNull);

      final Response<ListPartsResult> listPartsResponse =
          await client.listParts(key, uploadId, maxParts: 10);
      expect(listPartsResponse.data!.parts, hasLength(2));
      expect(
        listPartsResponse.data!.parts.map((PartInfo part) => part.partNumber),
        containsAllInOrder(<int>[1, 2]),
      );

      final Response<CompleteMultipartUploadResult> completeResponse =
          await client.completeMultipartUpload(
        key,
        uploadId,
        <PartInfo>[
          PartInfo.forComplete(1, partOneETag!),
          PartInfo.forComplete(2, partTwoETag!),
        ],
      );
      expect(completeResponse.data!.key, key);
      pendingMultipartUploads.remove(pending);

      final Response<dynamic> getResponse = await client.getObject(key);
      expect(_bytesFromResponse(getResponse), expectedContent);
    });

    test('listMultipartUploads 和 abortMultipartUpload', () async {
      final String key = '${prefix}abort-multipart-(6).txt';
      final Response<InitiateMultipartUploadResult> initResponse =
          await client.initiateMultipartUpload(key);
      final String uploadId = initResponse.data!.uploadId;
      final _PendingMultipartUpload pending = _PendingMultipartUpload(
        key,
        uploadId,
      );
      pendingMultipartUploads.add(pending);

      final Response<ListMultipartUploadsResult> listResponse =
          await client.listMultipartUploads(prefix: prefix, maxUploads: 100);
      final bool found = listResponse.data!.uploads.any(
        (UploadInfo upload) => upload.key == key && upload.uploadId == uploadId,
      );
      expect(found, isTrue);

      final Response<dynamic> abortResponse =
          await client.abortMultipartUpload(key, uploadId);
      expect(abortResponse.statusCode, inInclusiveRange(200, 299));
      pendingMultipartUploads.remove(pending);
    });

    test('multipartUpload 高阶接口可完成小型分片文件上传', () async {
      final String key = '${prefix}high-level-multipart-(7).bin';
      objectKeys.add(key);
      final List<int> content = _patternBytes(384 * 1024, seed: 71);
      final File file = File('${tempDirectory.path}/multipart.bin');
      await file.writeAsBytes(content);

      final Response<CompleteMultipartUploadResult> uploadResponse =
          await client.multipartUpload(
        file,
        key,
        numberOfParts: 3,
        maxConcurrency: 2,
      );
      expect(uploadResponse.data!.key, key);

      final Response<dynamic> getResponse = await client.getObject(key);
      expect(_bytesFromResponse(getResponse), content);
    });

    test('deleteObject 可删除普通对象', () async {
      final String key = '${prefix}delete-object-(8).txt';
      const String content = 'delete target';
      objectKeys.add(key);
      await client.putObjectFromString(content, key);

      final Response<dynamic> deleteResponse = await client.deleteObject(key);
      expect(deleteResponse.statusCode, inInclusiveRange(200, 299));
      objectKeys.remove(key);

      final ObjectMeta? metaAfterDelete = await client.getObjectMeta(key);
      expect(metaAfterDelete, isNull);
    });
  });
}

List<int> _bytesFromResponse(Response<dynamic> response) {
  final dynamic data = response.data;
  if (data is List<int>) {
    return data;
  }
  if (data is Uint8List) {
    return data.toList();
  }
  throw StateError('响应体不是字节数组: ${data.runtimeType}');
}

Future<List<int>> _collectStream(Stream<List<int>> stream) async {
  final Completer<List<int>> completer = Completer<List<int>>();
  final BytesBuilder builder = BytesBuilder(copy: false);
  late final StreamSubscription<List<int>> subscription;
  subscription = stream.listen(
    builder.add,
    onError: completer.completeError,
    onDone: () {
      subscription.cancel();
      completer.complete(builder.takeBytes());
    },
    cancelOnError: true,
  );
  return completer.future;
}

List<int> _patternBytes(int length, {required int seed}) {
  return List<int>.generate(length, (int index) => (index * 31 + seed) % 251);
}

class _PendingMultipartUpload {
  const _PendingMultipartUpload(this.key, this.uploadId);

  final String key;
  final String uploadId;
}

class _LiveOssConfig {
  const _LiveOssConfig({
    required this.accessKeyId,
    required this.accessKeySecret,
    required this.bucketName,
    required this.endpoint,
    required this.region,
    this.securityToken,
  });

  final String accessKeyId;
  final String accessKeySecret;
  final String bucketName;
  final String endpoint;
  final String region;
  final String? securityToken;

  static _LiveOssConfig load() {
    final Map<String, String> environment = Platform.environment;
    final String? accessKeyId = _nonEmpty(
      environment['ALIYUN_OSS_ACCESS_KEY_ID'],
    );
    final String? accessKeySecret = _nonEmpty(
      environment['ALIYUN_OSS_ACCESS_KEY_SECRET'],
    );
    final String? bucketName = _nonEmpty(environment['ALIYUN_OSS_BUCKET']);
    final String? endpoint = _nonEmpty(environment['ALIYUN_OSS_ENDPOINT']);
    final String? region = _nonEmpty(environment['ALIYUN_OSS_REGION']);

    if (accessKeyId != null &&
        accessKeySecret != null &&
        bucketName != null &&
        endpoint != null &&
        region != null) {
      return _LiveOssConfig(
        accessKeyId: accessKeyId,
        accessKeySecret: accessKeySecret,
        bucketName: bucketName,
        endpoint: endpoint,
        region: region,
        securityToken: _nonEmpty(environment['ALIYUN_OSS_SECURITY_TOKEN']),
      );
    }

    throw StateError(
      '真实 OSS 测试缺少配置。请设置 ALIYUN_OSS_ACCESS_KEY_ID、'
      'ALIYUN_OSS_ACCESS_KEY_SECRET、ALIYUN_OSS_BUCKET、'
      'ALIYUN_OSS_ENDPOINT、ALIYUN_OSS_REGION。',
    );
  }

  OSSConfig toOssConfig() {
    return OSSConfig.static(
      accessKeyId: accessKeyId,
      accessKeySecret: accessKeySecret,
      securityToken: securityToken,
      bucketName: bucketName,
      endpoint: endpoint,
      region: region,
      enableLogInterceptor: false,
      maxConcurrency: 2,
    );
  }
}

String? _nonEmpty(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
