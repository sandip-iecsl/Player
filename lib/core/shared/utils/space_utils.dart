import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Utilities for deterministic relationship space resolution and Drive folder naming.
class SpaceUtils {
  /// Normalizes an identifier (e.g. UID or email) by trimming whitespace and converting to lowercase.
  static String normalizeIdentifier(String identifier) {
    return identifier.trim().toLowerCase();
  }

  /// Normalizes an email address.
  static String normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  /// Generates a deterministic, symmetric shared space ID for two users.
  /// Invariant: `getSharedSpaceId(A, B) == getSharedSpaceId(B, A)`.
  static String getSharedSpaceId(String userA, String userB) {
    final normA = normalizeIdentifier(userA);
    final normB = normalizeIdentifier(userB);

    if (normA.isEmpty || normB.isEmpty) {
      throw ArgumentError('User identifiers cannot be empty when generating a shared space ID.');
    }

    if (normA == normB) {
      throw ArgumentError('Cannot create a relationship space with oneself ($normA).');
    }

    final sorted = [normA, normB]..sort();
    final combined = '${sorted[0]}#${sorted[1]}';
    final bytes = utf8.encode(combined);
    final digest = sha256.convert(bytes);
    
    // Prefix with space_ and use first 20 hex characters for readability and uniqueness
    return 'space_${digest.toString().substring(0, 20)}';
  }

  /// Returns the canonical Google Drive folder name for a given space ID.
  static String getSpaceFolderName(String spaceId) {
    return 'YouAndMe_Space_$spaceId';
  }
}
