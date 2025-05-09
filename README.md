# Alibaba Cloud OSS Dart SDK

[English](README.md) | [中文](README_zh.md)

This is a Dart client SDK for Alibaba Cloud Object Storage Service (OSS), providing simple and easy-to-use APIs to access Alibaba Cloud OSS services.

## Features

- File upload and download
- Large file multipart upload
- Upload and download progress monitoring
- Multipart upload management operations (list, abort, etc.)
- Support for both V1 and V4 signature algorithms

## Installation

```yaml
dependencies:
  dart_aliyun_oss: ^1.0.1
```

Then run:

```bash
dart pub get
```

## Usage Examples

### Initialization

```dart
import 'package:dart_aliyun_oss/dart_aliyun_oss.dart';

// Initialize OSS client
final oss = OSSClient.init(
  OSSConfig(
    endpoint: 'your-endpoint.aliyuncs.com', // e.g. oss-cn-hangzhou.aliyuncs.com
    region: 'your-region', // e.g. cn-hangzhou
    accessKeyId: 'your-access-key-id',
    accessKeySecret: 'your-access-key-secret',
    bucketName: 'your-bucket-name',
  ),
);
```

### Simple Upload

```dart
Future<void> uploadFile() async {
  final file = File('path/to/your/file.txt');
  await oss.putObject(
    file,
    'example/file.txt', // OSS object key
    params: OSSRequestParams(
      onSendProgress: (int count, int total) {
        print('Upload progress: ${(count / total * 100).toStringAsFixed(2)}%');
      },
    ),
  );
}
```

### Download File

```dart
Future<void> downloadFile() async {
  final ossObjectKey = 'example/file.txt';
  final downloadPath = 'path/to/save/file.txt';

  final response = await oss.getObject(
    ossObjectKey,
    params: OSSRequestParams(
      onReceiveProgress: (int count, int total) {
        print('Download progress: ${(count / total * 100).toStringAsFixed(2)}%');
      },
    ),
  );

  final File downloadFile = File(downloadPath);
  await downloadFile.parent.create(recursive: true);
  await downloadFile.writeAsBytes(response.data);
}
```

### Multipart Upload

```dart
Future<void> multipartUpload() async {
  final file = File('path/to/large/file.mp4');
  final ossObjectKey = 'videos/large_file.mp4';

  final completeResponse = await oss.multipartUpload(
    file,
    ossObjectKey,
    params: OSSRequestParams(
      onSendProgress: (count, total) {
        print('Overall progress: ${(count / total * 100).toStringAsFixed(2)}%');
      },
    ),
  );

  print('Multipart upload completed successfully!');
}
```

### Using Query Parameters

```dart
// List parts of a multipart upload with query parameters
final response = await oss.listParts(
  'example/large_file.mp4',
  'your-upload-id',
  params: OSSRequestParams(
    queryParameters: {
      'max-parts': 100,
      'part-number-marker': 5,
    },
  ),
);

// Get object with specific version using query parameters
final response = await oss.getObject(
  'example/file.txt',
  params: OSSRequestParams(
    queryParameters: {
      'versionId': 'your-version-id',
    },
  ),
);
```

### Generate Signed URL

```dart
// Generate a signed URL with V1 signature algorithm
final String signedUrlV1 = oss.signedUrl(
  'example/test.txt',
  method: 'GET',
  expires: 3600, // URL expires in 1 hour
  isV1Signature: true,
);

// Generate a signed URL with V4 signature algorithm
final String signedUrlV4 = oss.signedUrl(
  'example/test.txt',
  method: 'GET',
  expires: 3600,
  isV1Signature: false,
);
```

## More Examples

For more examples, please refer to the `example/example.dart` file.

## Notes

- Do not hardcode your AccessKey information in production code. It is recommended to use environment variables or other secure credential management methods.

- When using multipart upload, if the upload process is interrupted, make sure to call the `abortMultipartUpload` method to clean up incomplete multipart uploads.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
