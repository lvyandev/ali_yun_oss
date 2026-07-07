import 'package:dart_aliyun_oss/dart_aliyun_oss.dart';
import 'package:test/test.dart';

void main() {
  group('OSSClient 多实例支持', () {
    test('可以创建多个相互隔离的客户端实例', () {
      final OSSClient firstClient = OSSClient(
        OSSConfig.static(
          accessKeyId: 'first-access-key',
          accessKeySecret: 'first-secret',
          bucketName: 'first-bucket',
          endpoint: 'oss-cn-hangzhou.aliyuncs.com',
          region: 'cn-hangzhou',
          enableLogInterceptor: false,
        ),
      );
      final OSSClient secondClient = OSSClient(
        OSSConfig.static(
          accessKeyId: 'second-access-key',
          accessKeySecret: 'second-secret',
          bucketName: 'second-bucket',
          endpoint: 'oss-cn-beijing.aliyuncs.com',
          region: 'cn-beijing',
          enableLogInterceptor: false,
        ),
      );

      expect(identical(firstClient, secondClient), isFalse);
      expect(firstClient.config.bucketName, 'first-bucket');
      expect(secondClient.config.bucketName, 'second-bucket');
      expect(
        firstClient.buildOssUri(fileKey: 'demo.txt').host,
        'first-bucket.oss-cn-hangzhou.aliyuncs.com',
      );
      expect(
        secondClient.buildOssUri(fileKey: 'demo.txt').host,
        'second-bucket.oss-cn-beijing.aliyuncs.com',
      );
    });

    test('不同客户端的签名信息使用各自配置', () {
      final DateTime fixedTime = DateTime.utc(2026, 7, 7, 12);
      final OSSClient firstClient = OSSClient(
        OSSConfig.static(
          accessKeyId: 'first-access-key',
          accessKeySecret: 'first-secret',
          bucketName: 'first-bucket',
          endpoint: 'oss-cn-hangzhou.aliyuncs.com',
          region: 'cn-hangzhou',
          enableLogInterceptor: false,
        ),
      );
      final OSSClient secondClient = OSSClient(
        OSSConfig.static(
          accessKeyId: 'second-access-key',
          accessKeySecret: 'second-secret',
          bucketName: 'second-bucket',
          endpoint: 'oss-cn-beijing.aliyuncs.com',
          region: 'cn-beijing',
          enableLogInterceptor: false,
        ),
      );

      final String firstSignedUrl = firstClient.signedUrl(
        'demo.txt',
        dateTime: fixedTime,
      );
      final String secondSignedUrl = secondClient.signedUrl(
        'demo.txt',
        dateTime: fixedTime,
      );
      final Map<String, dynamic> firstHeaders = firstClient.createSignedHeaders(
        method: 'GET',
        fileKey: 'demo.txt',
        baseHeaders: <String, dynamic>{},
        dateTime: fixedTime,
      );
      final Map<String, dynamic> secondHeaders =
          secondClient.createSignedHeaders(
        method: 'GET',
        fileKey: 'demo.txt',
        baseHeaders: <String, dynamic>{},
        dateTime: fixedTime,
      );

      expect(firstSignedUrl, contains('first-bucket'));
      expect(firstSignedUrl, contains('OSSAccessKeyId=first-access-key'));
      expect(secondSignedUrl, contains('second-bucket'));
      expect(secondSignedUrl, contains('OSSAccessKeyId=second-access-key'));
      expect(
        firstHeaders['Authorization'] as String,
        contains('first-access-key'),
      );
      expect(
        secondHeaders['Authorization'] as String,
        contains('second-access-key'),
      );
    });

    test('兼容 init 入口允许重复创建并更新默认实例', () {
      final OSSClient firstClient = OSSClient.init(
        OSSConfig.static(
          accessKeyId: 'legacy-first-key',
          accessKeySecret: 'legacy-first-secret',
          bucketName: 'legacy-first-bucket',
          endpoint: 'oss-cn-hangzhou.aliyuncs.com',
          region: 'cn-hangzhou',
          enableLogInterceptor: false,
        ),
      );
      final OSSClient secondClient = OSSClient.init(
        OSSConfig.static(
          accessKeyId: 'legacy-second-key',
          accessKeySecret: 'legacy-second-secret',
          bucketName: 'legacy-second-bucket',
          endpoint: 'oss-cn-shanghai.aliyuncs.com',
          region: 'cn-shanghai',
          enableLogInterceptor: false,
        ),
      );

      expect(identical(firstClient, secondClient), isFalse);
      expect(firstClient.config.bucketName, 'legacy-first-bucket');
      expect(secondClient.config.bucketName, 'legacy-second-bucket');
      expect(identical(OSSClient.instance, secondClient), isTrue);
    });

    test('每个客户端拥有独立的请求管理器', () {
      final OSSClient firstClient = OSSClient(OSSConfig.forTest());
      final OSSClient secondClient = OSSClient(
        OSSConfig.forTest(bucketName: 'another-bucket'),
      );

      firstClient.requestManager.getToken('same-key');

      expect(firstClient.requestManager.isRequestActive('same-key'), isTrue);
      expect(secondClient.requestManager.isRequestActive('same-key'), isFalse);
    });

    test('dispose 只清理当前客户端管理的请求', () {
      final OSSClient firstClient = OSSClient(OSSConfig.forTest());
      final OSSClient secondClient = OSSClient(
        OSSConfig.forTest(bucketName: 'another-bucket'),
      );

      firstClient.requestManager.getToken('request-key');
      secondClient.requestManager.getToken('request-key');

      firstClient.dispose();

      expect(
        firstClient.requestManager.isRequestActive('request-key'),
        isFalse,
      );
      expect(
        secondClient.requestManager.isRequestActive('request-key'),
        isTrue,
      );
      secondClient.dispose();
    });
  });
}
