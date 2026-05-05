import 'dart:io';

import 'package:dio/dio.dart';

class FileUploadResult {
  const FileUploadResult({
    required this.fileId,
    required this.storedPath,
    required this.sizeBytes,
    this.expiresAt,
  });

  final String fileId;
  final String storedPath;
  final int sizeBytes;
  final String? expiresAt;
}

class FileUploadService {
  const FileUploadService(this._dio);

  final Dio _dio;

  Future<FileUploadResult> uploadFile({
    required String ownerUserId,
    required String filePath,
  }) async {
    final fileName = filePath.split(Platform.pathSeparator).last;
    final formData = FormData.fromMap({
      'owner_user_id': ownerUserId,
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/files/upload',
      data: formData,
    );
    final data = response.data ?? const <String, dynamic>{};
    return FileUploadResult(
      fileId: data['file_id'] as String? ?? '',
      storedPath: data['stored_path'] as String? ?? '',
      sizeBytes: data['size_bytes'] as int? ?? 0,
      expiresAt: data['expires_at'] as String?,
    );
  }

  Future<void> deleteFile(String fileId) async {
    await _dio.delete<void>('/files/$fileId');
  }
}
