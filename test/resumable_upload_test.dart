import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_aliyun_oss/dart_aliyun_oss.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  group('断点续传上传', () {
    late _SwitchingOssAdapter switchingAdapter;
    late OSSClient client;
    late Directory tempDirectory;

    setUpAll(() {
      switchingAdapter = _SwitchingOssAdapter();
      client = _initClient(switchingAdapter);
    });

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'dart-aliyun-oss-resumable-',
      );
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('复用 checkpoint 时跳过已上传分片并按升序完成上传', () async {
      final File file = File('${tempDirectory.path}/large.bin');
      await file.writeAsBytes(_patternBytes(300 * 1024));
      final _RecordingOssAdapter adapter = _RecordingOssAdapter(
        initialRemoteParts: <int, String>{1: '"etag-part-1"'},
      );
      switchingAdapter.current = adapter;
      final List<OSSMultipartUploadCheckpoint> checkpoints =
          <OSSMultipartUploadCheckpoint>[];
      final OSSMultipartUploadCheckpoint checkpoint =
          OSSMultipartUploadCheckpoint.fromFile(
        file: file,
        objectKey: 'uploads/large.bin',
        uploadId: 'existing-upload-id',
        partSize: 100 * 1024,
        uploadedParts: <PartInfo>[
          PartInfo.forComplete(1, '"etag-part-1"'),
        ],
      );

      final Response<CompleteMultipartUploadResult> response =
          await client.resumableUpload(
        file,
        'uploads/large.bin',
        checkpoint: checkpoint,
        maxConcurrency: 1,
        onCheckpoint: checkpoints.add,
      );

      expect(response.data!.key, 'uploads/large.bin');
      expect(adapter.initiateRequests, 0);
      expect(adapter.uploadedPartNumbers, <int>[2, 3]);
      expect(adapter.completedPartNumbers, <int>[1, 2, 3]);
      expect(checkpoints, isNotEmpty);
      expect(checkpoints.last.uploadId, 'existing-upload-id');
      expect(
        checkpoints.last.uploadedParts.map((PartInfo part) {
          return part.partNumber;
        }),
        containsAllInOrder(<int>[1, 2, 3]),
      );
    });

    test('失败时默认保留 uploadId，不自动 abort', () async {
      final File file = File('${tempDirectory.path}/failure.bin');
      await file.writeAsBytes(_patternBytes(220 * 1024));
      final _RecordingOssAdapter adapter = _RecordingOssAdapter(
        failOnPartNumbers: <int>{2},
      );
      switchingAdapter.current = adapter;

      await expectLater(
        client.resumableUpload(
          file,
          'uploads/failure.bin',
          partSize: 110 * 1024,
          maxConcurrency: 1,
        ),
        throwsA(isA<OSSException>()),
      );

      expect(adapter.abortRequests, 0);
      expect(adapter.uploadedPartNumbers, <int>[1, 2]);
    });

    test('abortOnError 为 true 时失败会主动清理 uploadId', () async {
      final File file = File('${tempDirectory.path}/abort.bin');
      await file.writeAsBytes(_patternBytes(220 * 1024));
      final _RecordingOssAdapter adapter = _RecordingOssAdapter(
        failOnPartNumbers: <int>{2},
      );
      switchingAdapter.current = adapter;

      await expectLater(
        client.resumableUpload(
          file,
          'uploads/abort.bin',
          partSize: 110 * 1024,
          maxConcurrency: 1,
          abortOnError: true,
        ),
        throwsA(isA<OSSException>()),
      );

      expect(adapter.abortRequests, 1);
    });
  });
}

OSSClient _initClient(HttpClientAdapter adapter) {
  final Dio dio = Dio();
  dio.httpClientAdapter = adapter;
  return OSSClient.init(
    OSSConfig.static(
      accessKeyId: 'test-access-key-id',
      accessKeySecret: 'test-access-key-secret',
      bucketName: 'test-bucket',
      endpoint: 'oss-cn-hangzhou.aliyuncs.com',
      region: 'cn-hangzhou',
      dio: dio,
      enableLogInterceptor: false,
      maxConcurrency: 1,
    ),
  );
}

List<int> _patternBytes(int length) {
  return List<int>.generate(length, (int index) => index % 251);
}

class _RecordingOssAdapter implements HttpClientAdapter {
  _RecordingOssAdapter({
    Map<int, String>? initialRemoteParts,
    Set<int>? failOnPartNumbers,
  })  : _remoteParts = <int, String>{...?initialRemoteParts},
        _failOnPartNumbers = failOnPartNumbers ?? <int>{};

  final Map<int, String> _remoteParts;
  final Set<int> _failOnPartNumbers;

  int abortRequests = 0;
  int initiateRequests = 0;
  final List<int> uploadedPartNumbers = <int>[];
  final List<int> completedPartNumbers = <int>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Uri uri = options.uri;
    final String method = options.method.toUpperCase();
    if (method == 'POST' && uri.queryParameters.containsKey('uploads')) {
      initiateRequests++;
      return _xmlResponse('''
<InitiateMultipartUploadResult>
  <Bucket>test-bucket</Bucket>
  <Key>${uri.pathSegments.join('/')}</Key>
  <UploadId>new-upload-id</UploadId>
</InitiateMultipartUploadResult>
''');
    }

    if (method == 'GET' && uri.queryParameters.containsKey('uploadId')) {
      return _xmlResponse(_listPartsXml(uri));
    }

    if (method == 'PUT' &&
        uri.queryParameters.containsKey('partNumber') &&
        uri.queryParameters.containsKey('uploadId')) {
      final int partNumber = int.parse(uri.queryParameters['partNumber']!);
      uploadedPartNumbers.add(partNumber);
      await requestStream?.drain<void>();
      if (_failOnPartNumbers.contains(partNumber)) {
        return ResponseBody.fromString(
          '<Error><Code>RequestTimeout</Code></Error>',
          500,
        );
      }
      final String eTag = '"etag-part-$partNumber"';
      _remoteParts[partNumber] = eTag;
      return ResponseBody.fromString(
        '',
        200,
        headers: <String, List<String>>{
          'ETag': <String>[eTag],
        },
      );
    }

    if (method == 'POST' && uri.queryParameters.containsKey('uploadId')) {
      final List<int> partNumbers = await _readCompletePartNumbers(
        requestStream,
      );
      completedPartNumbers.addAll(partNumbers);
      return _xmlResponse('''
<CompleteMultipartUploadResult>
  <Location>https://test-bucket.oss-cn-hangzhou.aliyuncs.com/${uri.pathSegments.join('/')}</Location>
  <Bucket>test-bucket</Bucket>
  <Key>${uri.pathSegments.join('/')}</Key>
  <ETag>"complete-etag"</ETag>
</CompleteMultipartUploadResult>
''');
    }

    if (method == 'DELETE' && uri.queryParameters.containsKey('uploadId')) {
      abortRequests++;
      return ResponseBody.fromString('', 204);
    }

    return ResponseBody.fromString(
      '<Error><Code>NotImplemented</Code></Error>',
      501,
    );
  }

  ResponseBody _xmlResponse(String xml) {
    return ResponseBody.fromString(
      xml,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/xml'],
      },
    );
  }

  String _listPartsXml(Uri uri) {
    final String partsXml =
        _remoteParts.entries.map((MapEntry<int, String> entry) {
      return '''
  <Part>
    <PartNumber>${entry.key}</PartNumber>
    <LastModified>2026-06-08T00:00:00.000Z</LastModified>
    <ETag>${entry.value}</ETag>
    <Size>102400</Size>
  </Part>''';
    }).join('\n');

    return '''
<ListPartsResult>
  <Bucket>test-bucket</Bucket>
  <Key>${uri.pathSegments.join('/')}</Key>
  <UploadId>${uri.queryParameters['uploadId']}</UploadId>
  <PartNumberMarker>0</PartNumberMarker>
  <MaxParts>1000</MaxParts>
  <IsTruncated>false</IsTruncated>
$partsXml
</ListPartsResult>
''';
  }

  Future<List<int>> _readCompletePartNumbers(
    Stream<Uint8List>? requestStream,
  ) async {
    if (requestStream == null) {
      return <int>[];
    }
    final List<int> bytes = <int>[];
    await for (final Uint8List chunk in requestStream) {
      bytes.addAll(chunk);
    }
    final String xml = utf8.decode(bytes);
    return RegExp(r'<PartNumber>(\d+)</PartNumber>')
        .allMatches(xml)
        .map((RegExpMatch match) => int.parse(match.group(1)!))
        .toList();
  }
}

class _SwitchingOssAdapter implements HttpClientAdapter {
  _RecordingOssAdapter? current;

  @override
  void close({bool force = false}) {
    current?.close(force: force);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final _RecordingOssAdapter? adapter = current;
    if (adapter == null) {
      return Future<ResponseBody>.value(
        ResponseBody.fromString(
          '<Error><Code>NoAdapter</Code></Error>',
          500,
        ),
      );
    }
    return adapter.fetch(options, requestStream, cancelFuture);
  }
}
