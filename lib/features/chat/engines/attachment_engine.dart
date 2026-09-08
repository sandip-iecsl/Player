import 'dart:io';

class AttachmentEngine {
  static final AttachmentEngine _instance = AttachmentEngine._internal();
  factory AttachmentEngine() => _instance;
  AttachmentEngine._internal();

  /// Mock uploads a file to a simulated storage service.
  /// If storage plugin is added later, this can perform real Firebase Storage uploads.
  Future<String> uploadAttachment(File file, String roomId) async {
    // Simulate network latency
    await Future.delayed(const Duration(seconds: 1));

    // Expose a mock CDN URL or a local file URI
    final fileName = file.path.split('/').last;
    return 'https://aura-player-storage.mock/attachments/$roomId/$fileName';
  }
}
