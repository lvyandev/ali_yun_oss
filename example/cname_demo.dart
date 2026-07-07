// ignore_for_file: avoid_print, avoid_redundant_argument_values

import 'package:dart_aliyun_oss/dart_aliyun_oss.dart';

/// 自定义域名（CNAME）功能演示
///
/// 本示例展示如何使用自定义域名功能，包括：
/// 1. 配置自定义域名
/// 2. 生成使用自定义域名的URL
/// 3. 生成使用自定义域名的签名URL
/// 4. 对比标准域名和自定义域名的差异
void main() async {
  print('=== 阿里云OSS自定义域名（CNAME）功能演示 ===\n');

  // 演示配置
  const String accessKeyId = 'demo-access-key-id';
  const String accessKeySecret = 'demo-access-key-secret';
  const String bucketName = 'my-bucket';
  const String region = 'cn-hangzhou';
  const String standardEndpoint = 'oss-cn-hangzhou.aliyuncs.com';
  const String customDomain = 'img.example.com';
  const String testFile = 'images/demo.jpg';

  print('1. 标准OSS域名配置演示');
  print('=' * 50);

  // 标准配置
  final OSSConfig standardConfig = OSSConfig.static(
    accessKeyId: accessKeyId,
    accessKeySecret: accessKeySecret,
    bucketName: bucketName,
    endpoint: standardEndpoint,
    region: region,
    cname: false, // 使用标准OSS域名
  );

  print('配置信息：');
  print('  - Endpoint: ${standardConfig.endpoint}');
  print('  - Bucket: ${standardConfig.bucketName}');
  print('  - CNAME: ${standardConfig.cname}');
  print('  - 完整配置: $standardConfig\n');

  // 初始化客户端（标准域名）
  final OSSClient standardClient = OSSClient(standardConfig);

  // 生成标准URL
  final Uri standardUri = standardClient.buildOssUri(fileKey: testFile);
  print('生成的标准URL：');
  print('  ${standardUri.toString()}\n');

  // 生成标准签名URL（V1）
  final String standardSignedUrlV1 = standardClient.signedUrl(
    testFile,
    isV1Signature: true,
  );
  print('生成的标准签名URL（V1）：');
  print('  ${standardSignedUrlV1.substring(0, 100)}...\n');

  // 生成标准签名URL（V4）
  final String standardSignedUrlV4 = standardClient.signedUrl(
    testFile,
    isV1Signature: false,
  );
  print('生成的标准签名URL（V4）：');
  print('  ${standardSignedUrlV4.substring(0, 100)}...\n');

  print('2. 自定义域名（CNAME）配置演示');
  print('=' * 50);

  // 自定义域名配置
  final OSSConfig cnameConfig = OSSConfig.static(
    accessKeyId: accessKeyId,
    accessKeySecret: accessKeySecret,
    bucketName: bucketName,
    endpoint: customDomain, // 使用自定义域名
    region: region,
    cname: true, // 启用自定义域名
  );

  print('配置信息：');
  print('  - Endpoint: ${cnameConfig.endpoint}');
  print('  - Bucket: ${cnameConfig.bucketName}');
  print('  - CNAME: ${cnameConfig.cname}');
  print('  - 完整配置: $cnameConfig\n');

  print('3. 自定义域名URL生成演示');
  print('=' * 50);

  // 直接使用签名工具生成自定义域名URL（V1）
  final Uri cnameUriV1 = AliOssV1SignUtils.signatureUri(
    accessKeyId: accessKeyId,
    accessKeySecret: accessKeySecret,
    endpoint: customDomain,
    method: 'GET',
    bucket: bucketName,
    key: testFile,
    cname: true, // 启用自定义域名
  );
  print('自定义域名签名URL（V1）：');
  print('  ${cnameUriV1.toString()}\n');

  // 直接使用签名工具生成自定义域名URL（V4）
  final Uri cnameUriV4 = AliOssV4SignUtils.signatureUri(
    accessKeyId: accessKeyId,
    accessKeySecret: accessKeySecret,
    endpoint: customDomain,
    region: region,
    method: 'GET',
    bucket: bucketName,
    key: testFile,
    cname: true, // 启用自定义域名
  );
  print('自定义域名签名URL（V4）：');
  print('  ${cnameUriV4.toString()}\n');

  print('4. 域名对比分析');
  print('=' * 50);
  print('标准OSS域名格式：');
  print('  - 格式：{bucket}.{endpoint}');
  print('  - 示例：$bucketName.$standardEndpoint');
  print('  - 特点：包含bucket信息，支持所有OSS操作\n');

  print('自定义域名格式：');
  print('  - 格式：{custom-domain}');
  print('  - 示例：$customDomain');
  print('  - 特点：隐藏bucket信息，仅支持对象操作\n');

  print('5. 使用自定义域名的前提条件');
  print('=' * 50);
  print('1. 在阿里云OSS控制台绑定自定义域名到指定Bucket');
  print('2. 添加CNAME记录将自定义域名指向OSS端点');
  print('3. 确保自定义域名已正确解析到OSS服务');
  print('4. 注意：使用自定义域名时无法使用listBuckets等Bucket级别操作\n');

  print('6. 配置示例代码');
  print('=' * 50);
  print('''
// 使用自定义域名的配置示例
final config = OSSConfig.static(
  accessKeyId: 'your-access-key-id',
  accessKeySecret: 'your-access-key-secret',
  bucketName: 'your-bucket-name',
  endpoint: 'img.example.com', // 您的自定义域名
  region: 'cn-hangzhou',
  cname: true, // 启用自定义域名
);

final oss = OSSClient(config);

// 生成使用自定义域名的URL
final uri = oss.buildOssUri(fileKey: 'path/to/file.jpg');
// 结果：https://img.example.com/path/to/file.jpg

// 生成使用自定义域名的签名URL
final signedUrl = oss.signedUrl('path/to/file.jpg');
// 结果：https://img.example.com/path/to/file.jpg?OSSAccessKeyId=...&Signature=...
''');

  print('\n=== 演示完成 ===');
}
