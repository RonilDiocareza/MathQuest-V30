import 'dart:async';
import 'dart:convert';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';

/// Service to manage user profile data including image storage and persistence
class ProfileService {
  static final ProfileService _instance = ProfileService._internal();

  factory ProfileService() {
    return _instance;
  }

  ProfileService._internal();

  static const String _nameKey = 'current_user_name';
  static const String _emailKey = 'current_user_email';
  static const String _roleKey = 'current_user_role';
  static const String _lrnKey = 'current_user_lrn';
  static const String _addressKey = 'current_user_address';
  static const String _legacyProfilePhotoDataKey =
      'current_user_profile_photo_data';
  static const int _maxProfilePhotoSize = 600 * 1024;

  String _keyForUser(String key, String uid) => '${key}_$uid';

  /// Save user profile information
  Future<void> saveProfile({
    required String name,
    required String email,
    required String role,
    required String address,
    Uint8List? photoBytes,
    ValueChanged<String>? onStatus,
  }) async {
    if (photoBytes != null) _validateProfilePhoto(photoBytes);
    final photoDataUrl =
        photoBytes == null ? null : _profilePhotoDataUrl(photoBytes);
    onStatus?.call(
      photoBytes == null
          ? 'Saving profile details...'
          : 'Saving profile and photo...',
    );
    await AuthService.updateCurrentProfile(
      name: name,
      address: address,
      profilePhotoUrl: photoDataUrl,
    ).timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException(
        'Saving profile changes timed out after 20 seconds.',
      ),
    );
    final user = AuthService.currentUser;
    if (user == null) throw StateError('Not signed in.');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyForUser(_nameKey, user.uid), name);
    await prefs.setString(_keyForUser(_emailKey, user.uid), email);
    await prefs.setString(_keyForUser(_roleKey, user.uid), role);
    await prefs.setString(_keyForUser(_addressKey, user.uid), address);
  }

  /// Load user profile information
  Future<Map<String, String>> loadProfile() async {
    final user = AuthService.currentUser;
    final account =
        user == null ? null : await AuthService.getAccount(user.uid);
    final prefs = await SharedPreferences.getInstance();
    final uid = user?.uid;
    return {
      'name': account?.name ??
          (uid == null ? null : prefs.getString(_keyForUser(_nameKey, uid))) ??
          '',
      'email': account?.email ??
          user?.email ??
          (uid == null ? null : prefs.getString(_keyForUser(_emailKey, uid))) ??
          '',
      'role': account?.role ??
          (uid == null ? null : prefs.getString(_keyForUser(_roleKey, uid))) ??
          '',
      'lrn': account?.lrn ??
          (uid == null ? null : prefs.getString(_keyForUser(_lrnKey, uid))) ??
          '',
      'address': account?.address ??
          (uid == null
              ? null
              : prefs.getString(_keyForUser(_addressKey, uid))) ??
          '',
      'character': account?.character == 'girl' ? 'girl' : 'boy',
      'profilePhotoUrl': account?.profilePhotoUrl ?? '',
    };
  }

  /// Save a compressed profile photo with the signed-in user's Firestore profile.
  Future<String> saveProfilePhoto(
    Uint8List photoBytes, {
    ValueChanged<String>? onStatus,
  }) async {
    final user = AuthService.currentUser;
    if (user == null) throw StateError('Not signed in.');
    _validateProfilePhoto(photoBytes);

    onStatus?.call('Saving photo to your account...');
    final photoDataUrl = _profilePhotoDataUrl(photoBytes);
    await AuthService.updateCurrentProfilePhotoUrl(photoDataUrl)
        .timeout(const Duration(seconds: 20));

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyProfilePhotoDataKey);
    return photoDataUrl;
  }

  void _validateProfilePhoto(Uint8List photoBytes) {
    if (photoBytes.isEmpty) {
      throw ArgumentError('The selected image is empty.');
    }
    if (photoBytes.length > _maxProfilePhotoSize) {
      throw ArgumentError(
        'Profile photos must be 600 KB or smaller.',
      );
    }
  }

  String _profilePhotoDataUrl(Uint8List photoBytes) =>
      'data:${_imageContentType(photoBytes)};base64,${base64Encode(photoBytes)}';

  String _imageContentType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  /// Fetch the signed-in user's cloud photo, migrating an older local photo once.
  Future<Uint8List?> getProfilePhoto({String? profilePhotoUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final user = AuthService.currentUser;

    final storedPhoto = profilePhotoUrl ??
        (user == null
            ? ''
            : (await AuthService.getAccount(user.uid))?.profilePhotoUrl ?? '');
    if (storedPhoto.startsWith('data:image/')) {
      final separatorIndex = storedPhoto.indexOf(',');
      if (separatorIndex < 0) {
        throw FormatException('The saved profile photo data is invalid.');
      }
      final photoBytes =
          base64Decode(storedPhoto.substring(separatorIndex + 1));
      if (photoBytes.length > _maxProfilePhotoSize) {
        throw FormatException('The saved profile photo is too large.');
      }
      return photoBytes;
    }

    if (storedPhoto.isNotEmpty) {
      try {
        final bytes = await FirebaseStorage.instance
            .refFromURL(storedPhoto)
            .getData(5 * 1024 * 1024)
            .timeout(const Duration(seconds: 10));
        if (bytes == null) {
          throw StateError('The stored profile photo is empty.');
        }
        return bytes;
      } on FirebaseException catch (error, stackTrace) {
        debugPrint('Unable to download the cloud profile photo: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    final photoKey = user == null
        ? _legacyProfilePhotoDataKey
        : _keyForUser(_legacyProfilePhotoDataKey, user.uid);
    final photoData = prefs.getString(photoKey) ??
        (user == null ? null : prefs.getString(_legacyProfilePhotoDataKey));
    if (photoData == null || photoData.isEmpty) return null;

    final photoBytes = base64Decode(photoData);
    if (user != null && storedPhoto.isEmpty) {
      try {
        await saveProfilePhoto(photoBytes);
      } on FirebaseException catch (error, stackTrace) {
        debugPrint('Unable to migrate the local profile photo: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
    return photoBytes;
  }

  /// Delete profile photo
  Future<void> deleteProfilePhoto() async {
    final user = AuthService.currentUser;
    if (user == null) throw StateError('Not signed in.');
    final account = await AuthService.getAccount(user.uid);
    final photoUrl = account?.profilePhotoUrl ?? '';
    if (photoUrl.isNotEmpty && !photoUrl.startsWith('data:image/')) {
      await FirebaseStorage.instance.refFromURL(photoUrl).delete();
    }
    await AuthService.updateCurrentProfilePhotoUrl('');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyForUser(_legacyProfilePhotoDataKey, user.uid));
  }

  /// Sign out without deleting the account's persistent cloud profile.
  Future<void> clearProfile() async {
    await AuthService.signOut();
  }
}
