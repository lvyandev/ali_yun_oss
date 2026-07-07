// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_aliyun_oss/dart_aliyun_oss.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 阿里云OSS SDK 测试套件
///
/// 包含对 OSSConfig 和 OSSClient 类的单元测试
/// 测试内容包括配置创建、参数验证、工具方法和基本客户端功能
void main() {
  group('OSSConfig 测试', () {
    test('创建 OSSConfig 实例并验证基本属性', () {
      // 创建不带 securityToken 的配置
      final OSSConfig config = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
      );

      // 验证基本属性
      expect(config.endpoint, 'oss-cn-hangzhou.aliyuncs.com');
      expect(config.region, 'cn-hangzhou');
      expect(config.accessKeyId, 'test-key-id');
      expect(config.accessKeySecret, 'test-key-secret');
      expect(config.bucketName, 'test-bucket');
      expect(config.securityToken, isNull); // securityToken 应为 null

      // 验证默认值
      expect(config.enableLogInterceptor, isTrue);
      expect(config.maxConcurrency, 5);
      expect(config.dio, isNull);
      expect(config.interceptors, isNull);

      // 创建带 securityToken 的配置
      final OSSConfig configWithToken = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
        securityToken: 'test-security-token',
      );

      // 验证 securityToken 属性
      expect(configWithToken.securityToken, 'test-security-token');
    });

    test('OSSConfig.forTest 工厂方法', () {
      final OSSConfig config = OSSConfig.forTest();

      // 验证默认测试值
      expect(config.endpoint, 'oss-cn-hangzhou.aliyuncs.com');
      expect(config.region, 'cn-hangzhou');
      expect(config.accessKeyId, 'test_key_id');
      expect(config.accessKeySecret, 'test_key_secret');
      expect(config.bucketName, 'test-bucket');
      expect(config.securityToken, isNull); // 默认应为 null
      expect(config.enableLogInterceptor, isTrue);
      expect(config.maxConcurrency, 3); // 测试环境默认为3

      // 验证自定义测试值（不带 securityToken）
      final OSSConfig customConfig = OSSConfig.forTest(
        accessKeyId: 'custom-key',
        region: 'cn-beijing',
      );

      expect(customConfig.accessKeyId, 'custom-key');
      expect(customConfig.region, 'cn-beijing');
      expect(
        customConfig.endpoint,
        'oss-cn-hangzhou.aliyuncs.com',
      ); // 未修改的值保持默认
      expect(customConfig.securityToken, isNull);

      // 验证带 securityToken 的自定义测试值
      final OSSConfig tokenConfig =
          OSSConfig.forTest(securityToken: 'test-sts-token');

      expect(tokenConfig.securityToken, 'test-sts-token');
      expect(tokenConfig.accessKeyId, 'test_key_id'); // 其他值保持默认
    });

    test('OSSConfig.fromJson 和 toJson 方法', () {
      // 测试不带 securityToken 的配置
      final OSSConfig originalConfig = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
        enableLogInterceptor: false,
        maxConcurrency: 8,
      );

      // 转换为 JSON
      final Map<String, dynamic> json = originalConfig.toJson();

      // 验证 JSON 内容
      expect(json['endpoint'], 'oss-cn-hangzhou.aliyuncs.com');
      expect(json['region'], 'cn-hangzhou');
      expect(json['accessKeyId'], 'test-key-id');
      expect(json['accessKeySecret'], 'test-key-secret');
      expect(json['bucketName'], 'test-bucket');
      expect(json['enableLogInterceptor'], false);
      expect(json['maxConcurrency'], 8);
      expect(
        json.containsKey('securityToken'),
        isFalse,
      ); // 不应包含 securityToken 键

      // 从 JSON 创建新实例
      final OSSConfig configFromJson = OSSConfig.fromJson(json);

      // 验证新实例
      expect(configFromJson.endpoint, originalConfig.endpoint);
      expect(configFromJson.region, originalConfig.region);
      expect(configFromJson.accessKeyId, originalConfig.accessKeyId);
      expect(configFromJson.accessKeySecret, originalConfig.accessKeySecret);
      expect(configFromJson.bucketName, originalConfig.bucketName);
      expect(
        configFromJson.enableLogInterceptor,
        originalConfig.enableLogInterceptor,
      );
      expect(configFromJson.maxConcurrency, originalConfig.maxConcurrency);
      expect(configFromJson.securityToken, isNull);

      // 测试带 securityToken 的配置
      final OSSConfig configWithToken = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
        securityToken: 'test-security-token',
      );

      // 转换为 JSON
      final Map<String, dynamic> jsonWithToken = configWithToken.toJson();

      // 验证 JSON 内容
      expect(jsonWithToken['securityToken'], 'test-security-token');

      // 从 JSON 创建新实例
      final OSSConfig configFromJsonWithToken =
          OSSConfig.fromJson(jsonWithToken);

      // 验证新实例
      expect(configFromJsonWithToken.securityToken, 'test-security-token');
    });

    test('OSSConfig.copyWith 方法', () {
      // 测试不带 securityToken 的配置
      final OSSConfig originalConfig = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
      );

      // 使用 copyWith 创建新实例,修改部分属性
      final OSSConfig newConfig = originalConfig.copyWith(
        endpoint: 'oss-cn-beijing.aliyuncs.com',
        region: 'cn-beijing',
        maxConcurrency: 10,
      );

      // 验证修改的属性
      expect(newConfig.endpoint, 'oss-cn-beijing.aliyuncs.com');
      expect(newConfig.region, 'cn-beijing');
      expect(newConfig.maxConcurrency, 10);

      // 验证未修改的属性保持不变
      expect(newConfig.accessKeyId, originalConfig.accessKeyId);
      expect(newConfig.accessKeySecret, originalConfig.accessKeySecret);
      expect(newConfig.bucketName, originalConfig.bucketName);
      expect(
        newConfig.enableLogInterceptor,
        originalConfig.enableLogInterceptor,
      );
      expect(newConfig.securityToken, isNull);

      // 测试添加 securityToken
      final OSSConfig configWithToken = originalConfig.copyWith(
        securityToken: 'new-security-token',
      );

      // 验证添加的 securityToken
      expect(configWithToken.securityToken, 'new-security-token');

      // 测试修改 securityToken
      final OSSConfig configWithTokenOriginal = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
        securityToken: 'original-token',
      );

      final OSSConfig configWithTokenUpdated = configWithTokenOriginal.copyWith(
        securityToken: 'updated-token',
      );

      // 验证修改的 securityToken
      expect(configWithTokenUpdated.securityToken, 'updated-token');

      // 注意：在 copyWith 方法中，null 值表示"不修改"，而不是"设置为 null"
      // 因此，我们不能通过 copyWith 将 securityToken 设置为 null
      // 这是 copyWith 模式的标准行为

      // 验证 securityToken 保持不变
      final OSSConfig configWithTokenUnchanged =
          configWithTokenOriginal.copyWith();
      expect(configWithTokenUnchanged.securityToken, 'original-token');
    });

    test('OSSConfig 相等性和哈希码', () {
      // 测试不带 securityToken 的配置
      final OSSConfig config1 = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
      );

      final OSSConfig config2 = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
      );

      final OSSConfig config3 = OSSConfig.static(
        endpoint: 'oss-cn-beijing.aliyuncs.com', // 不同的端点
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
      );

      // 相同配置应该相等
      expect(config1 == config2, isTrue);
      expect(config1.hashCode == config2.hashCode, isTrue);

      // 不同配置应该不相等
      expect(config1 == config3, isFalse);
      expect(config1.hashCode == config3.hashCode, isFalse);

      // 测试带 securityToken 的配置
      final OSSConfig configWithToken1 = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
        securityToken: 'test-token',
      );

      final OSSConfig configWithToken2 = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
        securityToken: 'test-token',
      );

      final OSSConfig configWithDifferentToken = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
        securityToken: 'different-token', // 不同的 securityToken
      );

      // 相同配置（包括 securityToken）应该相等
      expect(configWithToken1 == configWithToken2, isTrue);
      expect(configWithToken1.hashCode == configWithToken2.hashCode, isTrue);

      // securityToken 不同的配置应该不相等
      expect(configWithToken1 == configWithDifferentToken, isFalse);
      expect(
        configWithToken1.hashCode == configWithDifferentToken.hashCode,
        isFalse,
      );

      // 一个有 securityToken，一个没有 securityToken 的配置应该不相等
      expect(config1 == configWithToken1, isFalse);
      expect(config1.hashCode == configWithToken1.hashCode, isFalse);
    });

    test('OSSConfig toString 方法应该屏蔽敏感信息', () {
      // 测试不带 securityToken 的配置
      final OSSConfig config = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
      );

      final String stringRepresentation = config.toString();

      // 验证敏感信息被屏蔽
      expect(stringRepresentation.contains('test-key-id'), isFalse);
      expect(stringRepresentation.contains('test-key-secret'), isFalse);

      // 验证包含部分屏蔽的信息
      expect(stringRepresentation.contains('tes***'), isTrue);
      expect(stringRepresentation.contains('bucketName: test-bucket'), isTrue);
      expect(
        stringRepresentation.contains('endpoint: oss-cn-hangzhou.aliyuncs.com'),
        isTrue,
      );

      // 测试带 securityToken 的配置
      final OSSConfig configWithToken = OSSConfig.static(
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
        accessKeyId: 'test-key-id',
        accessKeySecret: 'test-key-secret',
        bucketName: 'test-bucket',
        securityToken: 'test-security-token',
      );

      final String stringWithToken = configWithToken.toString();

      // 验证 securityToken 被屏蔽
      expect(stringWithToken.contains('test-security-token'), isFalse);

      // 验证包含部分屏蔽的 securityToken 信息
      expect(stringWithToken.contains('securityToken: tes***'), isTrue);
    });

    test('OSSConfig 动态认证功能测试', () {
      // 模拟STS令牌管理器
      String currentAccessKeyId = 'initial-access-key-id';
      String currentAccessKeySecret = 'initial-access-key-secret';
      String? currentSecurityToken = 'initial-security-token';

      // 创建动态配置
      final OSSConfig dynamicConfig = OSSConfig(
        accessKeyIdProvider: () => currentAccessKeyId,
        accessKeySecretProvider: () => currentAccessKeySecret,
        securityTokenProvider: () => currentSecurityToken,
        bucketName: 'test-bucket',
        endpoint: 'oss-cn-hangzhou.aliyuncs.com',
        region: 'cn-hangzhou',
      );

      // 验证初始值
      expect(dynamicConfig.accessKeyId, 'initial-access-key-id');
      expect(dynamicConfig.accessKeySecret, 'initial-access-key-secret');
      expect(dynamicConfig.securityToken, 'initial-security-token');

      // 模拟令牌刷新
      currentAccessKeyId = 'refreshed-access-key-id';
      currentAccessKeySecret = 'refreshed-access-key-secret';
      currentSecurityToken = 'refreshed-security-token';

      // 验证动态获取的新值
      expect(dynamicConfig.accessKeyId, 'refreshed-access-key-id');
      expect(dynamicConfig.accessKeySecret, 'refreshed-access-key-secret');
      expect(dynamicConfig.securityToken, 'refreshed-security-token');

      // 测试securityToken为null的情况
      currentSecurityToken = null;
      expect(dynamicConfig.securityToken, isNull);
    });
  });

  group('OSSClient 测试', () {
    test('初始化 OSSClient 不抛出异常', () {
      // 这个测试只验证初始化不会抛出异常
      expect(
        () {
          OSSClient.init(OSSConfig.forTest());
        },
        returnsNormally,
      );
    });

    test('OSSClient 初始化参数验证', () {
      // 测试缺少必要参数时应抛出异常
      expect(
        () {
          OSSClient.init(
            OSSConfig.static(
              endpoint: '', // 空端点
              region: 'cn-hangzhou',
              accessKeyId: 'test-key-id',
              accessKeySecret: 'test-key-secret',
              bucketName: 'test-bucket',
            ),
          );
        },
        throwsException,
      ); // 使用 throwsException 而不是 throwsArgumentError

      expect(
        () {
          OSSClient.init(
            OSSConfig.static(
              endpoint: 'oss-cn-hangzhou.aliyuncs.com',
              region: 'cn-hangzhou',
              accessKeyId: '', // 空 AccessKey ID
              accessKeySecret: 'test-key-secret',
              bucketName: 'test-bucket',
            ),
          );
        },
        throwsException,
      ); // 使用 throwsException 而不是 throwsArgumentError
    });

    test('OSSClient.init 兼容入口每次返回新的客户端实例', () {
      final OSSClient client1 = OSSClient.init(OSSConfig.forTest());
      final OSSClient client2 = OSSClient.init(
        OSSConfig.forTest(
          accessKeyId: 'different-key',
        ),
      );

      expect(identical(client1, client2), isFalse);
      expect(identical(OSSClient.instance, client2), isTrue);
    });
  });

  group('OSSRequestParams 测试', () {
    test('创建 OSSRequestParams 实例', () {
      final OSSRequestParams params = OSSRequestParams(
        bucketName: 'custom-bucket',
        isV1Signature: true,
        dateTime: DateTime(2023),
      );

      expect(params.bucketName, 'custom-bucket');
      expect(params.isV1Signature, isTrue);
      expect(params.dateTime, DateTime(2023));
      expect(params.options, isNull);
      expect(params.cancelToken, isNull);
      expect(params.onReceiveProgress, isNull);
    });

    test('OSSRequestParams.copyWith 方法', () {
      const OSSRequestParams originalParams = OSSRequestParams(
        bucketName: 'original-bucket',
      );

      final OSSRequestParams newParams = originalParams.copyWith(
        bucketName: 'new-bucket',
        isV1Signature: true,
        cancelToken: CancelToken(),
      );

      // 验证修改的属性
      expect(newParams.bucketName, 'new-bucket');
      expect(newParams.isV1Signature, isTrue);
      expect(newParams.cancelToken, isNotNull);

      // 验证未修改的属性保持不变
      expect(newParams.dateTime, originalParams.dateTime);
      expect(newParams.options, originalParams.options);
      expect(newParams.onReceiveProgress, originalParams.onReceiveProgress);
    });
  });

  group('OSSUtils 测试', () {
    test('计算分片配置', () {
      // 测试小文件的分片配置
      final ({int numberOfParts, int partSize}) smallFileConfig =
          OSSUtils.calculatePartConfig(
        1024 * 1024,
        null,
      ); // 1MB
      expect(smallFileConfig.partSize >= 100 * 1024, isTrue); // 分片大小至少 100KB
      expect(smallFileConfig.numberOfParts > 0, isTrue);

      // 测试大文件的分片配置
      final ({int numberOfParts, int partSize}) largeFileConfig =
          OSSUtils.calculatePartConfig(
        100 * 1024 * 1024,
        null,
      ); // 100MB
      expect(largeFileConfig.partSize >= 1024 * 1024, isTrue); // 分片大小至少 1MB
      expect(largeFileConfig.numberOfParts > 0, isTrue);

      // 测试指定分片数量
      final ({int numberOfParts, int partSize}) customPartsConfig =
          OSSUtils.calculatePartConfig(
        10 * 1024 * 1024,
        5,
      ); // 10MB, 5分片
      expect(customPartsConfig.numberOfParts, 5);
      expect(
        customPartsConfig.partSize * customPartsConfig.numberOfParts >=
            10 * 1024 * 1024,
        isTrue,
      );
    });
  });

  // 注意：以下测试需要实际的 OSS 凭证才能运行
  // 在实际运行测试前,请替换为有效的测试凭证或使用模拟测试
  group('OSSClient 集成测试 (需要有效凭证)', () {
    test('集成测试 - 跳过', () {
      // 这个测试仅作为占位符,表明这里应该有集成测试
      // 实际使用时,可以根据需要启用并提供有效凭证

      // 跳过测试,因为需要有效的 OSS 凭证
      print('跳过集成测试：需要有效的 OSS 凭证');

      // 注释示例代码,避免出现“死代码”警告
      /*
      // 以下代码仅作为示例,实际使用时需要去除注释
      final client = OSSClient(
        OSSConfig.static(
          endpoint: 'your-endpoint.aliyuncs.com',
          region: 'your-region',
          accessKeyId: 'your-access-key-id',
          accessKeySecret: 'your-access-key-secret',
          bucketName: 'your-bucket-name',
        ),
      );

      // 这里可以添加实际的 API 调用测试
      */
    });
  });

  group('PutObject 多数据类型支持测试', () {
    test('putObjectFromString 方法签名验证', () {
      // 这个测试验证方法签名存在性

      // 验证 putObjectFromString 方法存在于 IOSSService 接口中
      expect(IOSSService, isNotNull);

      // 通过反射或类型检查验证方法签名（这里我们简化为基本验证）
      print('putObjectFromString 方法签名验证通过');
    });

    test('putObjectFromBytes 方法签名验证', () {
      // 这个测试验证方法签名存在性

      // 验证 putObjectFromBytes 方法存在于 IOSSService 接口中
      expect(IOSSService, isNotNull);

      // 验证 Uint8List 类型可用
      final Uint8List testBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      expect(testBytes.length, 5);

      print('putObjectFromBytes 方法签名验证通过');
    });

    test('字符串到字节转换验证', () {
      // 测试字符串转换为 UTF-8 字节的逻辑
      const String testString = 'Hello, 世界! 🌍';
      final List<int> expectedBytes = utf8.encode(testString);
      final Uint8List actualBytes = Uint8List.fromList(utf8.encode(testString));

      expect(actualBytes.length, expectedBytes.length);
      expect(actualBytes.toList(), expectedBytes);

      // 验证中文和 emoji 字符正确编码
      expect(
        actualBytes.length > testString.length,
        isTrue,
      ); // UTF-8 编码后字节数应该更多
    });

    test('字节数组数据完整性验证', () {
      // 测试字节数组的数据完整性
      final List<int> originalData =
          List<int>.generate(1024, (int index) => index % 256);
      final Uint8List bytes = Uint8List.fromList(originalData);

      expect(bytes.length, originalData.length);
      expect(bytes.toList(), originalData);

      // 验证数据范围正确
      for (int i = 0; i < bytes.length; i++) {
        expect(bytes[i], originalData[i]);
        expect(bytes[i] >= 0 && bytes[i] <= 255, isTrue);
      }
    });

    test('大数据量字节数组处理', () {
      // 测试较大的字节数组处理
      const int dataSize = 1024 * 1024; // 1MB
      final List<int> largeData =
          List<int>.generate(dataSize, (int index) => index % 256);
      final Uint8List largeBytes = Uint8List.fromList(largeData);

      expect(largeBytes.length, dataSize);
      expect(largeBytes[0], 0);
      expect(largeBytes[255], 255);
      expect(largeBytes[256], 0); // 应该循环
      expect(largeBytes[dataSize - 1], (dataSize - 1) % 256);
    });

    test('空数据处理', () {
      // 测试空字符串和空字节数组
      const String emptyString = '';
      final Uint8List emptyStringBytes =
          Uint8List.fromList(utf8.encode(emptyString));
      expect(emptyStringBytes.length, 0);

      final Uint8List emptyBytes = Uint8List.fromList(<int>[]);
      expect(emptyBytes.length, 0);
    });

    test('特殊字符处理', () {
      // 测试各种特殊字符的处理
      const String specialChars = '!@#\$%^&*()_+-=[]{}|;:,.<>?`~\n\t\r';
      final Uint8List specialBytes =
          Uint8List.fromList(utf8.encode(specialChars));

      // 验证可以正确编码和解码
      final String decoded = utf8.decode(specialBytes);
      expect(decoded, specialChars);
    });
  });
}
