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
  dart_aliyun_oss: ^1.1.0
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

### Using Custom Domain (CNAME)

If you have bound a custom domain to your OSS bucket, you can use it instead of the default OSS endpoint:

```dart
// Initialize OSS client with custom domain
final oss = OSSClient.init(
  OSSConfig.static(
    endpoint: 'img.example.com', // Your custom domain
    region: 'cn-hangzhou',
    accessKeyId: 'your-access-key-id',
    accessKeySecret: 'your-access-key-secret',
    bucketName: 'your-bucket-name',
    cname: true, // Enable custom domain
  ),
);
```

**Prerequisites for using custom domain:**
- You must have bound your custom domain to the OSS bucket in the Alibaba Cloud console
- You must have added a CNAME record pointing your custom domain to the OSS endpoint
- When using custom domain, bucket-level operations (like `listBuckets`) are not available

### Simple Upload

The SDK supports uploading different types of data:

#### Upload File

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

#### Upload String Content

```dart
Future<void> uploadString() async {
  const String content = '''
This is a text file uploaded from string content.
Supports multi-line text content.
Timestamp: 2024-01-01 12:00:00
''';

  await oss.putObjectFromString(
    content,
    'example/text_content.txt',
    params: OSSRequestParams(
      onSendProgress: (int count, int total) {
        print('String upload progress: ${(count / total * 100).toStringAsFixed(2)}%');
      },
    ),
  );
}
```

#### Upload Byte Array

```dart
import 'dart:typed_data';

Future<void> uploadBytes() async {
  // Create sample byte array (e.g., binary data)
  final Uint8List bytes = Uint8List.fromList([
    // File header (simulating PNG file header)
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    // Some sample data
    ...List<int>.generate(1024, (index) => index % 256),
  ]);

  await oss.putObjectFromBytes(
    bytes,
    'example/binary_data.bin',
    params: OSSRequestParams(
      onSendProgress: (int count, int total) {
        print('Bytes upload progress: ${(count / total * 100).toStringAsFixed(2)}%');
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

### Resumable Upload

`resumableUpload` is built on Alibaba Cloud OSS Multipart Upload APIs. Save the
checkpoint from `onCheckpoint`, then pass it back as `checkpoint` when retrying.

```dart
Future<void> resumableUpload() async {
  final file = File('path/to/large/file.mp4');
  final ossObjectKey = 'videos/large_file.mp4';
  final checkpointFile = File('path/to/large_file.oss_checkpoint.json');

  OSSMultipartUploadCheckpoint? checkpoint;
  if (checkpointFile.existsSync()) {
    checkpoint = OSSMultipartUploadCheckpoint.fromJson(
      jsonDecode(await checkpointFile.readAsString()) as Map<String, dynamic>,
    );
  }

  final response = await oss.resumableUpload(
    file,
    ossObjectKey,
    checkpoint: checkpoint,
    onCheckpoint: (OSSMultipartUploadCheckpoint checkpoint) async {
      await checkpointFile.writeAsString(jsonEncode(checkpoint.toJson()));
    },
    params: OSSRequestParams(
      onSendProgress: (int count, int total) {
        print('Resumable progress: ${(count / total * 100).toStringAsFixed(2)}%');
      },
    ),
  );

  if (response.statusCode != null && response.statusCode! < 300) {
    if (checkpointFile.existsSync()) {
      await checkpointFile.delete();
    }
  }
}
```

By default, `resumableUpload` keeps the `uploadId` and uploaded parts after a
failure so the next call can resume. Set `abortOnError: true` if failed uploads
should be cleaned up immediately. Incomplete Multipart Upload tasks occupy OSS
storage, so production systems should provide cleanup logic or configure a
Bucket lifecycle rule for expired incomplete uploads.

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

### Using STS Temporary Tokens

STS (Security Token Service) provides temporary credentials for secure access to OSS resources. This SDK supports both static STS tokens and dynamic token refresh.

#### Method 1: Static STS Token

```dart
// Initialize client with static STS temporary token
final OSSConfig configWithSTS = OSSConfig.static(
  accessKeyId: 'STS.your-sts-access-key-id',
  accessKeySecret: 'your-sts-access-key-secret',
  securityToken: 'your-sts-security-token', // STS temporary security token
  bucketName: 'your-bucket-name',
  endpoint: 'oss-cn-hangzhou.aliyuncs.com',
  region: 'cn-hangzhou',
);

final OSSClient ossWithSTS = OSSClient.init(configWithSTS);

// Upload file using STS temporary token
await ossWithSTS.putObject(
  File('path/to/file.txt'),
  'example/file.txt',
);
```

#### Method 2: Dynamic STS Token Refresh (Recommended)

```dart
// STS Token Manager for automatic token refresh
class StsTokenManager {
  String? _accessKeyId;
  String? _accessKeySecret;
  String? _securityToken;
  DateTime? _expireTime;

  String get accessKeyId {
    _refreshIfNeeded();
    return _accessKeyId!;
  }

  String get accessKeySecret {
    _refreshIfNeeded();
    return _accessKeySecret!;
  }

  String? get securityToken {
    _refreshIfNeeded();
    return _securityToken;
  }

  void _refreshIfNeeded() {
    if (_expireTime == null ||
        DateTime.now().isAfter(_expireTime!.subtract(Duration(minutes: 5)))) {
      _refreshStsToken();
    }
  }

  void _refreshStsToken() {
    // Call your STS service to get new temporary credentials
    // Replace this with actual STS API call
    _accessKeyId = 'STS.new_access_key_id';
    _accessKeySecret = 'new_access_key_secret';
    _securityToken = 'new_security_token';
    _expireTime = DateTime.now().add(Duration(hours: 1));
  }
}

// Initialize client with dynamic STS token refresh
final stsManager = StsTokenManager();
final OSSClient ossWithDynamicSTS = OSSClient.init(
  OSSConfig(
    accessKeyIdProvider: () => stsManager.accessKeyId,
    accessKeySecretProvider: () => stsManager.accessKeySecret,
    securityTokenProvider: () => stsManager.securityToken,
    bucketName: 'your-bucket-name',
    endpoint: 'oss-cn-hangzhou.aliyuncs.com',
    region: 'cn-hangzhou',
  ),
);

// The client will automatically use refreshed tokens for all operations
await ossWithDynamicSTS.putObject(
  File('path/to/file.txt'),
  'example/file.txt',
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
