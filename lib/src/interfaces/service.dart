import 'dart:async';
import 'dart:io';

import 'package:dart_aliyun_oss/src/models/models.dart';
import 'package:dio/dio.dart';

// 定义回调类型 (如果尚未定义)
typedef PartProgressCallback = void Function(
  int partNumber,
  int count,
  int total,
);

/// 分片断点续传检查点回调。
typedef MultipartUploadCheckpointCallback = FutureOr<void> Function(
  OSSMultipartUploadCheckpoint checkpoint,
);

mixin IOSSService {
  // -------------------- 基础操作 Section --------------------

  /// 删除OSS对象
  ///
  /// 该方法用于从阿里云OSS删除指定的对象。
  ///
  /// 补充说明：
  /// - 返回的响应体中包含文件内容的字节数组
  /// - 可以通过 [params] 中的 [onReceiveProgress] 回调监控下载进度
  /// - 对于大文件,建议使用流式下载或分片下载
  /// - 如果文件不存在,将抛出 [OSSErrorType.notFound] 类型的异常
  ///
  /// 参数：
  /// - [fileKey] 要删除的文件对象的键值（路径）
  /// - [versionId] 可选的版本
  /// - [params] 可选的请求参数,包含进度回调、超时设置等
  Future<Response<dynamic>> deleteObject(
    String fileKey, {
    String? versionId,
    OSSRequestParams? params,
  });

  /// 获取OSS对象
  ///
  /// 该方法用于从阿里云OSS下载指定的文件对象。
  ///
  /// 补充说明：
  /// - 返回的响应体中包含文件内容的字节数组
  /// - 可以通过 [params] 中的 [onReceiveProgress] 回调监控下载进度
  /// - 对于大文件,建议使用流式下载或分片下载
  /// - 如果文件不存在,将抛出 [OSSErrorType.notFound] 类型的异常
  ///
  /// 参数：
  /// - [fileKey] 要下载的文件对象的键值（路径）
  /// - [params] 可选的请求参数,包含进度回调、超时设置等
  Future<Response<dynamic>> getObject(
    String fileKey, {
    OSSRequestParams? params,
  });

  /// 获取OSS对象元数据信息
  ///
  /// 该方法用于从阿里云OSS获取指定的对象元数据信息。
  ///
  /// 参数：
  /// - [fileKey] 要下载的文件对象的键值（路径）
  /// - [params] 可选的请求参数,包含进度回调、超时设置等
  Future<ObjectMeta?> getObjectMeta(
    String fileKey, {
    OSSRequestParams? params,
  });

  /// 上传对象到OSS
  ///
  /// 该方法用于将本地文件上传到阿里云OSS。
  ///
  /// 补充说明：
  /// - 适用于小文件上传（建议小于100MB）
  /// - 对于大文件,建议使用 [multipartUpload] 方法
  /// - 采用流式上传,避免将整个文件加载到内存
  /// - 可以通过 [onSendProgress] 回调监控上传进度
  /// - 如果文件已存在,将被覆盖（除非存储空间开启了版本控制）
  ///
  /// 参数：
  /// - [file] 要上传的本地文件
  /// - [fileKey] 上传到OSS的对象键值（路径）
  /// - [params] 可选的请求参数,如自定义头部、超时设置等
  Future<Response<dynamic>> putObject(
    File file,
    String fileKey, {
    OSSRequestParams? params,
  });

  // -------------------- 基础操作 Section End --------------------

  // -------------------- 分片上传 Section --------------------

  /// 使用Multipart Upload模式传输数据前,您必须先调用InitiateMultipartUpload接口来通知OSS初始化一个Multipart Upload事件。
  ///
  /// - [fileKey] 上传文件的key
  ///
  /// 注意事项
  ///
  /// - 调用接口会返回一个OSS服务器创建的全局唯一的Upload ID,用于标识本次Multipart Upload事件。您可以根据这个ID来发起相关的操作,例如中止Multipart Upload、查询Multipart Upload等。
  /// - 初始化Multipart Upload请求不影响已存在的同名Object。
  /// - InitiateMultipartUpload操作计算认证签名时,需要添加?uploads到CanonicalizedResource中。
  ///
  /// 补充说明：
  /// - 这是分片上传流程的第一步,必须在上传分片前调用
  /// - 返回的 [InitiateMultipartUploadResult] 包含了 uploadId,需要保存以用于后续操作
  /// - 如果不再需要这个分片上传,应调用 [abortMultipartUpload] 清理资源
  /// - 可以通过 [params] 设置各种元数据和存储类型等属性
  /// - 初始化后,如果长时间不上传分片,服务器可能会清理这个分片上传任务
  Future<Response<InitiateMultipartUploadResult>> initiateMultipartUpload(
    String fileKey, {
    OSSRequestParams? params,
  });

  /// 初始化一个MultipartUpload后,调用UploadPart接口根据指定的Object名和uploadId来分块（Part）上传数据。
  ///
  /// - [fileKey] 上传文件的 Object Key
  /// - [partData] 上传的数据
  /// - [partNumber] 每一个上传的Part都有一个标识它的号码（partNumber）。取值：1~10000
  /// - [uploadId] 本次分片上传事件的 Upload ID
  /// - [params] 可选的请求参数，可以通过 params.onSendProgress 设置上传进度回调
  ///
  /// 注意事项
  ///
  /// - 调用UploadPart接口上传Part数据前,必须先调用InitiateMultipartUpload接口来获取OSS服务器生成的uploadId。
  /// - 如果使用同一个partNumber上传了新的数据,则OSS上已有的partNumber对应的Part数据将被覆盖。
  /// - OSS会将服务器端收到Part数据的MD5值放在ETag头返回给用户。
  /// - 如果调用InitiateMultipartUpload接口时,指定了x-oss-server-side-encryption请求头,则会对上传的Part进行加密编码,并在UploadPart响应头中返回x-oss-server-side-encryption头,其值表明该Part的服务器端加密算法。更多信息,请参见InitiateMultipartUpload。
  ///
  /// 补充说明：
  /// - 这是分片上传流程的第二步,必须在初始化分片上传后调用
  /// - 返回的响应头中包含 ETag,需要保存以用于完成分片上传
  /// - 分片可以并行上传,但需要注意控制并发数量以避免资源耗尽
  /// - 如果上传失败,可以重试上传同一分片,成功的分片不需要重新上传
  /// - 对于大文件,建议使用 [multipartUpload] 方法,它会自动处理分片上传的所有步骤
  /// - 当使用 [List<int>] 类型的 [partData] 时,请注意内存使用,避免大分片导致内存溢出
  Future<Response<dynamic>> uploadPart(
    String fileKey,
    List<int> partData,
    int partNumber,
    String uploadId, {
    OSSRequestParams? params,
  });

  /// 在将所有数据Part都上传完成后,您必须调用CompleteMultipartUpload接口来完成整个文件的分片上传。
  ///
  /// - [fileKey] 上传文件的 Object Key
  /// - [uploadId] 本次分片上传事件的 Upload ID (String 类型)
  /// - [parts] 所有已上传分片的列表 (包含 PartNumber 和 ETag)
  /// - [encodingType] 指定对返回的Key进行编码,目前只支持URL编码。
  /// Key使用UTF-8字符,但XML 1.0标准不支持解析一些控制字符,例如ASCII码值从0到10的字符。当Key中包含XML 1.0标准不支持的控制字符时,您可以通过指定Encoding-type对返回的Key进行编码。
  ///
  /// 注意事项
  ///
  /// 调用CompleteMultipartUpload操作时,用户必须提供所有有效的Part列表（包括PartNumber和ETag）。OSS收到用户提交的Part列表后,会逐一验证每个Part的有效性。当所有的Part验证通过后,OSS将把这些Part组合成一个完整的Object。
  /// - 确认Part的大小
  /// 在调用CompleteMultipartUpload时会确认除最后一个Part以外所有Part的大小是否都大于或等于100 KB,并检查用户提交的Part列表中的每一个PartNumber和ETag。因此,在上传Part时,客户端除了需要记录Part号码外,还需要记录每次上传Part成功后服务器返回的ETag值。
  /// - 处理请求
  /// 由于OSS处理CompleteMultipartUpload请求时会持续一定的时间。在这段时间内,如果客户端与OSS之间连接中断,OSS仍会继续处理该请求。
  /// - PartNumber
  /// 服务端在调用CompleteMultipartUpload接口时会对PartNumber做校验。
  /// PartNumber取值为1~10000。PartNumber可以不连续,但必须升序排列。例如第一个Part的PartNumber是1,第二个Part的PartNumber可以是5。
  /// - UploadId
  /// 同一个Object可以同时拥有不同的UploadId,当Complete一个UploadId后,此UploadId将无效,但该Object的其他UploadId不受影响。
  /// - x-oss-server-side-encryption请求头
  /// 如果调用InitiateMultipartUpload接口时,指定了x-oss-server-side-encryption请求头,则在CompleteMultipartUpload的响应头中返回x-oss-server-side-encryption,其值表示该Object的服务器端加密算法。
  ///
  /// 补充说明：
  /// - 这是分片上传流程的最后一步,必须在所有分片上传完成后调用
  /// - [parts] 列表必须包含所有已上传分片的 PartNumber 和 ETag,并且按 PartNumber 升序排列
  /// - 返回的 [CompleteMultipartUploadResult] 包含了文件的访问 URL 和 ETag
  /// - 如果完成操作失败,应调用 [abortMultipartUpload] 清理服务器资源
  /// - 完成操作可能需要一定时间,尤其是对于大文件或分片数量多的情况
  /// - 对于大文件,建议使用 [multipartUpload] 方法,它会自动处理分片上传的所有步骤
  Future<Response<CompleteMultipartUploadResult>> completeMultipartUpload(
    String fileKey,
    String uploadId,
    List<PartInfo> parts, {
    String? encodingType,
    OSSRequestParams? params,
  });

  /// 用于取消MultipartUpload事件并删除对应的Part数据。
  ///
  /// - [uploadId] 上传文件的key
  ///
  /// 注意事项
  /// - 获取uploadId
  /// 调用AbortMultipartUpload接口时,需获取相应的uploadId。
  /// - uploadId对应的分片未上传完成
  /// 调用AbortMultipartUpload接口过程中,如果所属的某些Part仍然在上传,则此次取消操作将无法删除这些Part。
  /// - uploadId对应的分片已上传完成
  ///   - 且在已调用CompleteMultipartUpload接口将分片合成完整的Object的情况下,此次调用AbortMultipartUpload接口不会删除任何分片或者Object,且报错NoSuchUpload,原因是在已完成CompleteMultipartUpload操作后无法再使用该uploadId进行任何操作。
  ///   - 在未调用CompleteMultipartUpload接口将分片合成完整的Object的情况下,此时调用AbortMultipartUpload接口仅删除已上传的分片。
  /// - 降低存储费用
  /// 建议您及时完成分片上传或者取消分片上传,原因是已上传但未完成或未取消的分片会占用存储空间,从而产生存储费用。
  ///
  /// 补充说明：
  /// - 这个方法用于清理未完成的分片上传,释放服务器资源
  /// - 在以下情况应调用此方法：
  ///   - 当分片上传过程中出错或被取消时
  ///   - 当不再需要继续上传已初始化的分片时
  ///   - 当应用程序退出前,需要清理未完成的上传时
  /// - 如果不调用此方法,未完成的分片会一直占用存储空间并产生费用
  /// - 对于使用 [multipartUpload] 方法的情况,如果上传失败,会自动尝试调用此方法清理资源
  Future<Response<dynamic>> abortMultipartUpload(
    String fileKey,
    String uploadId, {
    OSSRequestParams? params,
  });

  /// 列举所有执行中的Multipart Upload事件,即已经初始化但还未完成（Complete）或者还未中止（Abort）的Multipart Upload事件。
  ///
  /// - [delimiter] 用于对Object名称进行分组的字符。所有名称包含指定的前缀且首次出现delimiter字符之间的Object作为一组元素CommonPrefixes。
  /// - [encodingType] 指定对返回的内容进行编码,指定编码的类型。Delimiter、KeyMarker、Prefix、NextKeyMarker和Key使用UTF-8字符,但XML 1.0标准不支持解析一些控制字符,例如ASCII值从0到10的字符。对于包含XML 1.0标准不支持的控制字符,可以通过指定encoding-type对返回的Delimiter、KeyMarker、Prefix、NextKeyMarker和Key进行编码。
  /// - [keyMarker] 与upload-id-marker参数配合使用,用于指定返回结果的起始位置。
  ///   - 如果未设置upload-id-marker参数,查询结果中包含所有Object名称的字典序大于key-marker参数值的Multipart Upload事件。
  ///   - 如果设置了upload-id-marker参数,查询结果中包含：
  ///      - 所有Object名称的字典序大于key-marker参数值的Multipart Upload事件。
  ///      - Object名称等于key-marker参数值,但是UploadId比upload-id-marker参数值大的Multipart Upload事件。
  /// - [maxUploads] 限定此次返回Multipart Upload事件的最大个数,默认值为1000。最大值为1000。
  /// - [prefix] 限定返回的Object Key必须以prefix作为前缀。注意使用prefix查询时,返回的Key中仍会包含prefix。
  /// - [uploadIdMarker] 与key-marker参数配合使用,用于指定返回结果的起始位置。
  ///   - 如果未设置key-marker参数,则OSS会忽略upload-id-marker参数。
  ///   - 如果设置了key-marker参数,查询结果中包含：
  ///      - 所有Object名称的字典序大于key-marker参数值的Multipart Upload事件。
  ///      - Object名称等于key-marker参数值,但是UploadId比upload-id-marker参数值大的Multipart Upload事件。
  Future<Response<ListMultipartUploadsResult>> listMultipartUploads({
    String? delimiter,
    String? encodingType,
    String? keyMarker,
    int? maxUploads,
    String? prefix,
    String? uploadIdMarker,
    OSSRequestParams? params,
  });

  /// 用于列举指定Upload ID所属的所有已经上传成功Part。
  ///
  /// - [uploadId] 上传文件的key
  /// - [encodingType] 指定对返回的内容进行编码,指定编码的类型。Key使用UTF-8字符,但XML 1.0标准不支持解析一些控制字符,比如ASCII值从0到10的字符。对于Key中包含XML 1.0标准不支持的控制字符,可以通过指定Encoding-type对返回的Key进行编码。
  /// - [maxParts] 规定在OSS响应中的最大Part数目。默认值为1000。最大值为1000。
  /// - [partNumberMarker] 指定List的起始位置,只有Part Number数目大于该参数的Part会被列出。
  ///
  /// 注意事项
  /// - OSS的返回结果按照Part号码升序排列。
  /// - 建议使用本地记录的数据生成Part列表,不推荐使用ListParts返回结果中的Part Number和ETag值生成已经上传成功的Part列表。原因是通过UploadID上传的Part可能存在被误覆盖的风险,在执行CompleteMultipartUpload操作之前可能需要删除部分不需要的Part,或者网络传输可能存在错误导致OSS接收到的Part数据可能不符合预期,如果本地没有记录各个Part对应的PartNumber以及ETag数据,将无法从ListParts返回结果中找到符合预期的Part数据,最终无法验证OSS上的Part数据与原始上传内容的一致性和完整性。
  Future<Response<ListPartsResult>> listParts(
    String fileKey,
    String uploadId, {
    String? encodingType,
    int? maxParts,
    int? partNumberMarker,
    OSSRequestParams? params,
  });

  /// 使用分片上传方式上传文件。
  ///
  /// 自动处理初始化、分片上传、完成或中止的整个流程。
  ///
  /// [file] 要上传的本地文件。
  /// [ossObjectKey] 上传到 OSS 的对象键（路径）。
  /// [numberOfParts] (可选) 期望的分片数量。如果提供,会根据 OSS 限制（大小、数量）进行调整。
  ///                 如果不提供,会根据文件大小自动计算合适的分片数。
  /// [maxConcurrency] 最大并发上传数,默认为 5。
  /// [onPartProgress] (可选) 单个分片上传进度回调 (分片号, 已发送字节数, 分片总字节数)。
  /// [cancelToken] (可选) 用于取消请求的 CancelToken。
  /// [params] (可选) 额外的请求参数,例如自定义头部。
  ///
  /// 返回 [CompleteMultipartUploadResult] 包含上传成功后的信息。
  /// 如果上传失败或被取消,将抛出异常,并尝试中止分片上传。
  ///
  /// 补充说明：
  /// - 该方法是大文件上传的推荐方式,特别适用于超过100MB的文件
  /// - 内部实现了并发控制、错误处理和资源清理等复杂逻辑
  /// - 如果上传过程中出错,会自动尝试中止分片上传以释放服务器资源
  /// - 分片大小会根据文件大小自动调整,以实现最佳上传效率
  /// - 对于移动网络环境,建议调整 [maxConcurrency] 为较小的值（如 3）
  /// - 如果需要取消上传,可以调用 [cancelToken.cancel()]
  ///
  /// 使用示例：
  /// ```dart
  /// final file = File('large_video.mp4');
  /// final cancelToken = CancelToken();
  ///
  /// try {
  ///   final result = await ossClient.multipartUpload(
  ///     file,
  ///     'videos/large_video.mp4',
  ///     maxConcurrency: 3,
  ///     params: OSSRequestParams(
  ///       onSendProgress: (count, total) {
  ///         print('总进度: ${(count / total * 100).toStringAsFixed(2)}%');
  ///       },
  ///     ),
  ///     cancelToken: cancelToken,
  ///   );
  ///   print('上传成功: ${result.data?.location}');
  /// } catch (e) {
  ///   print('上传失败: $e');
  /// }
  ///
  /// // 如果需要取消上传
  /// // cancelToken.cancel();
  /// ```
  Future<Response<CompleteMultipartUploadResult>> multipartUpload(
    File file,
    String ossObjectKey, {
    int maxConcurrency = 5,
    int? numberOfParts,
    PartProgressCallback? onPartProgress, // 分片进度
    CancelToken? cancelToken,
    OSSRequestParams? params,
  });

  /// 使用断点续传方式上传文件。
  ///
  /// 该方法基于 OSS Multipart Upload API 实现。调用方应在 [onCheckpoint]
  /// 中持久化检查点，并在下次调用时通过 [checkpoint] 传回，从而跳过已经
  /// 成功上传的分片。
  ///
  /// [abortOnError] 默认为 false，表示上传失败后保留 uploadId 和已上传分片
  /// 供下次恢复；设置为 true 时，失败会主动调用 [abortMultipartUpload]
  /// 清理 OSS 侧未完成分片。
  Future<Response<CompleteMultipartUploadResult>> resumableUpload(
    File file,
    String ossObjectKey, {
    OSSMultipartUploadCheckpoint? checkpoint,
    int? partSize,
    int maxConcurrency = 5,
    PartProgressCallback? onPartProgress,
    MultipartUploadCheckpointCallback? onCheckpoint,
    bool abortOnError = false,
    CancelToken? cancelToken,
    OSSRequestParams? params,
  });

  // -------------------- 分片上传 Section End --------------------

  /// 列举Bucket中的Object列表（V2版本）
  ///
  /// 此方法实现了ListObjectsV2（GetBucketV2）接口，用于分页列举Bucket中的Object。
  /// 可以通过各种参数来控制返回结果的范围和格式。
  ///
  /// 参数说明：
  ///   - [delimiter]: 对Object名字进行分组的字符。所有Object名字包含指定的前缀，
  ///     第一次出现delimiter字符之间的Object作为一组元素（即CommonPrefixes）。
  ///     默认值：无
  ///     示例：设置为"/"可以模拟文件夹结构
  ///
  ///   - [startAfter]: 设定从startAfter之后按字母排序开始返回Object。
  ///     startAfter用来实现分页显示效果，参数的长度必须小于1024字节。
  ///     做条件查询时，即使startAfter在列表中不存在，也会从符合startAfter字母排序的下一个开始打印。
  ///     默认值：无
  ///
  ///   - [continuationToken]: 指定List操作需要从此token开始。
  ///     您可从ListObjectsV2（GetBucketV2）结果中的NextContinuationToken获取此token。
  ///     默认值：无
  ///
  ///   - [maxKeys]: 指定返回Object的最大数。
  ///     取值：大于0小于等于1000
  ///     默认值：100
  ///     说明：
  ///     1. 如果因为maxKeys的设定无法一次完成列举，返回结果会附加NextContinuationToken
  ///        作为下一次列举的continuationToken。
  ///     2. 返回的Object数量不保证达到设定的maxKeys。出现这种情况时，需要从返回结果中
  ///        获取NextContinuationToken作为下一次列举的continuationToken。
  ///
  ///   - [prefix]: 限定返回文件的Key必须以prefix作为前缀。
  ///     如果把prefix设为某个文件夹名，则列举以此prefix开头的文件，即该文件夹下递归的所有文件和子文件夹。
  ///     在设置prefix的基础上，将delimiter设置为正斜线（/）时，返回值就只列举该文件夹下的文件，
  ///     文件夹下的子文件夹名返回在CommonPrefixes中，子文件夹下递归的所有文件和文件夹不显示。
  ///     示例：
  ///     一个Bucket中有三个Object，分别为fun/test.jpg、fun/movie/001.avi和fun/movie/007.avi。
  ///     如果设定prefix为fun/，则返回三个Object；
  ///     如果在prefix设置为fun/的基础上，将delimiter设置为正斜线（/），
  ///     则返回fun/test.jpg和fun/movie/。
  ///     说明：
  ///     1. 参数的长度必须小于1024字节。
  ///     2. 设置prefix参数时，不能以正斜线（/）开头。
  ///     3. 如果prefix参数置空，则默认列举Bucket内的所有Object。
  ///     4. 使用prefix查询时，返回的Key中仍会包含prefix。
  ///     默认值：无
  ///
  ///   - [fetchOwner]: 指定是否在返回结果中包含owner信息。
  ///     合法值：true、false
  ///     true：表示返回结果中包含owner信息。
  ///     false：表示返回结果中不包含owner信息。
  ///     默认值：false
  ///
  /// 返回值：
  ///   返回[Future<ListBucketResultV2>]，包含列举结果和分页信息。
  ///
  /// 异常：
  ///   可能会抛出以下异常：
  ///   - [ArgumentError] 当参数不符合要求时
  ///   - [ServiceException] 当服务端返回错误时
  ///   - [NetworkException] 当网络连接出现问题时
  ///
  /// 示例：
  /// ```dart
  /// final result = await listBucketResultV2(
  ///   delimiter: '/',
  ///   maxKeys: 100,
  ///   prefix: 'photos/',
  ///   fetchOwner: true,
  /// );
  /// print('Objects: ${result.contents?.length}');
  /// print('Common prefixes: ${result.commonPrefixes?.length}');
  /// ```
  Future<Response<ListBucketResultV2>> listBucketResultV2({
    String? delimiter,
    String? startAfter,
    String? continuationToken,
    int? maxKeys,
    String? prefix,
    bool fetchOwner = false,
    OSSRequestParams? params,
  });
}
