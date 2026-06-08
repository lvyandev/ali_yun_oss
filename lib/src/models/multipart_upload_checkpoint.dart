import 'dart:io';

import 'part_info.dart';

/// 分片断点续传检查点。
///
/// OSS 的断点续传依赖客户端保存 [uploadId] 以及已成功上传分片的
/// [PartInfo.partNumber] 和 [PartInfo.eTag]。该模型只描述可序列化状态，
/// 不绑定具体的文件存储位置，调用方可以通过 [toJson] 和 [fromJson]
/// 自行保存到文件、数据库或偏好存储。
class OSSMultipartUploadCheckpoint {
  /// 创建断点续传检查点。
  const OSSMultipartUploadCheckpoint({
    required this.objectKey,
    required this.uploadId,
    required this.fileSize,
    required this.fileLastModified,
    required this.partSize,
    required this.uploadedParts,
  });

  /// 基于本地文件创建检查点。
  factory OSSMultipartUploadCheckpoint.fromFile({
    required File file,
    required String objectKey,
    required String uploadId,
    required int partSize,
    List<PartInfo> uploadedParts = const <PartInfo>[],
  }) {
    final FileStat stat = file.statSync();
    return OSSMultipartUploadCheckpoint(
      objectKey: objectKey,
      uploadId: uploadId,
      fileSize: stat.size,
      fileLastModified: stat.modified.toUtc().millisecondsSinceEpoch,
      partSize: partSize,
      uploadedParts: uploadedParts,
    );
  }

  /// 从 JSON 数据恢复检查点。
  factory OSSMultipartUploadCheckpoint.fromJson(Map<String, dynamic> json) {
    final List<dynamic> partsJson =
        json['uploadedParts'] as List<dynamic>? ?? <dynamic>[];
    return OSSMultipartUploadCheckpoint(
      objectKey: json['objectKey'] as String,
      uploadId: json['uploadId'] as String,
      fileSize: json['fileSize'] as int,
      fileLastModified: json['fileLastModified'] as int,
      partSize: json['partSize'] as int,
      uploadedParts: partsJson.map((dynamic item) {
        final Map<String, dynamic> partJson = item as Map<String, dynamic>;
        return PartInfo(
          eTag: partJson['eTag'] as String,
          lastModified: partJson['lastModified'] as String? ?? '',
          partNumber: partJson['partNumber'] as int,
          size: partJson['size'] as int? ?? 0,
        );
      }).toList(),
    );
  }

  /// OSS 对象键。
  final String objectKey;

  /// OSS Multipart Upload 事件 ID。
  final String uploadId;

  /// 创建检查点时的本地文件大小。
  final int fileSize;

  /// 创建检查点时的本地文件最后修改时间，UTC 毫秒时间戳。
  final int fileLastModified;

  /// 分片大小，恢复时必须与原上传保持一致。
  final int partSize;

  /// 已成功上传的分片信息。
  final List<PartInfo> uploadedParts;

  /// 检查当前本地文件是否仍匹配该检查点。
  bool matchesFile(File file, String expectedObjectKey) {
    if (objectKey != expectedObjectKey || !file.existsSync()) {
      return false;
    }
    final FileStat stat = file.statSync();
    return stat.size == fileSize &&
        stat.modified.toUtc().millisecondsSinceEpoch == fileLastModified;
  }

  /// 转换为可持久化 JSON。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'objectKey': objectKey,
      'uploadId': uploadId,
      'fileSize': fileSize,
      'fileLastModified': fileLastModified,
      'partSize': partSize,
      'uploadedParts': uploadedParts.map((PartInfo part) {
        return <String, dynamic>{
          'partNumber': part.partNumber,
          'eTag': part.eTag,
          'lastModified': part.lastModified,
          'size': part.size,
        };
      }).toList(),
    };
  }

  /// 创建包含部分修改的新检查点。
  OSSMultipartUploadCheckpoint copyWith({
    String? objectKey,
    String? uploadId,
    int? fileSize,
    int? fileLastModified,
    int? partSize,
    List<PartInfo>? uploadedParts,
  }) {
    return OSSMultipartUploadCheckpoint(
      objectKey: objectKey ?? this.objectKey,
      uploadId: uploadId ?? this.uploadId,
      fileSize: fileSize ?? this.fileSize,
      fileLastModified: fileLastModified ?? this.fileLastModified,
      partSize: partSize ?? this.partSize,
      uploadedParts: uploadedParts ?? this.uploadedParts,
    );
  }

  @override
  String toString() {
    return 'OSSMultipartUploadCheckpoint(objectKey: $objectKey, '
        'uploadId: $uploadId, fileSize: $fileSize, '
        'fileLastModified: $fileLastModified, partSize: $partSize, '
        'uploadedParts: ${uploadedParts.length})';
  }
}
