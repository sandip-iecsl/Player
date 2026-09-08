import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EncryptionHelper {
  static const String _encryptionKey = 'hive_encryption_secure_key';

  /// Gets the Hive Aes Cipher key for secure database storage.
  /// If the key does not exist, it is generated and cached locally in SharedPreferences.
  static Future<HiveAesCipher> getHiveCipher() async {
    final prefs = await SharedPreferences.getInstance();
    final String? keyBase64 = prefs.getString(_encryptionKey);

    List<int> keyBytes;
    if (keyBase64 == null) {
      // Generate a new cryptographically secure 256-bit key
      final secureKey = Hive.generateSecureKey();
      keyBytes = secureKey;
      
      // Store it in SharedPreferences base64 encoded
      final String secureKeyBase64 = base64Encode(secureKey);
      await prefs.setString(_encryptionKey, secureKeyBase64);
    } else {
      keyBytes = base64Decode(keyBase64);
    }

    return HiveAesCipher(keyBytes);
  }
}
