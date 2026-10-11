
import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/profile_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback? onClose;
  final bool isDialog;

  const ProfileScreen({super.key, this.onClose, this.isDialog = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late ProfileService _profileService;

  String _userName = '';
  String _userEmail = '';
  String _userLRN = '';
  String _userAddress = '';
  String _userRole = '';
  String _userCharacter = 'boy';
  Uint8List? _profilePhoto;
  Uint8List? _pendingProfilePhoto;
  bool _isEditing = false;
  bool _isDialogOpen = false;
  bool _isSavingProfile = false;
  double? _photoUploadProgress;
  String? _saveStatus;

  late TextEditingController _nameController;
  late TextEditingController _addressController;

  @override
  void initState() {
    super.initState();
    _profileService = ProfileService();
    _nameController = TextEditingController();
    _addressController = TextEditingController();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final profile = await _profileService.loadProfile();
      if (!mounted) return;

      setState(() {
        _userName = profile['name'] ?? '';
        _userEmail = profile['email'] ?? '';
        _userRole = profile['role'] ?? '';
        _userLRN = profile['lrn'] ?? '';
        _userAddress = profile['address'] ?? '';
        _userCharacter = profile['character'] == 'girl' ? 'girl' : 'boy';

        _nameController.text = _userName;
        _addressController.text = _userAddress;
      });

      try {
        final photoFile = await _profileService
            .getProfilePhoto(profilePhotoUrl: profile['profilePhotoUrl'])
            .timeout(
              const Duration(seconds: 20),
            );
        if (mounted && photoFile != null) {
          setState(() => _profilePhoto = photoFile);
        }
      } catch (error, stackTrace) {
        debugPrint('Unable to load profile photo: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } catch (error, stackTrace) {
      debugPrint('Unable to load profile: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load your saved profile.')),
      );
    }
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final imagePicker = ImagePicker();
      final pickedFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 320,
        maxHeight: 320,
        imageQuality: 50,
      );

      if (pickedFile != null && mounted) {
        final photoBytes = await pickedFile.readAsBytes();
        if (photoBytes.length > 600 * 1024) {
          throw ArgumentError('Profile photos must be 600 KB or smaller.');
        }
        setState(() {
          _pendingProfilePhoto = photoBytes;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Unable to update profile photo: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_profilePhotoErrorMessage(error)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _profilePhotoErrorMessage(Object error) {
    if (error is ArgumentError) {
      return 'The selected image is too large. Choose a smaller photo (600 KB or less) and try again.';
    }
    if (error is! FirebaseException) {
      if (error is TimeoutException) {
        return 'Saving the photo timed out. Check your connection and Firestore access, then retry.';
      }
      return 'Photo upload failed: $error';
    }

    final code = error.code.replaceFirst(
      RegExp(r'^(storage|cloud_firestore)/'),
      '',
    );
    switch (code) {
      case 'unauthenticated':
        return 'Your session expired. Log in again, then retry the upload.';
      case 'permission-denied':
        return 'Firestore denied saving the photo. Check that the signed-in user can update their profilePhotoUrl field.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Firebase could not save the photo right now. Check your internet connection and retry.';
      case 'resource-exhausted':
        return 'The profile photo is too large for Firestore. Choose a smaller image and retry.';
      default:
        return 'Could not save the photo (${error.code}). Please retry.';
    }
  }

  Future<void> _saveProfile() async {
    if (_isSavingProfile) return;
    if (_nameController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter your name'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _isSavingProfile = true;
      _photoUploadProgress = null;
      _saveStatus = _pendingProfilePhoto == null
          ? 'Saving profile details...'
          : 'Saving profile and photo...';
    });

    try {
      await _profileService.saveProfile(
        name: _nameController.text,
        email: _userEmail,
        role: _userRole,
        address: _addressController.text,
        photoBytes: _pendingProfilePhoto,
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _saveStatus = status);
        },
      );
    } catch (error, stackTrace) {
      debugPrint('Unable to save profile changes: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      final photoSaveFailed = _pendingProfilePhoto != null;
      setState(() {
        _isSavingProfile = false;
        _photoUploadProgress = null;
        _saveStatus = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            photoSaveFailed
                ? 'Could not save your profile and photo. Your selected photo is still available to retry.'
                : 'Could not save your profile details. Please try again.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      if (photoSaveFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_profilePhotoErrorMessage(error)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _userName = _nameController.text;
      _userAddress = _addressController.text;
      _profilePhoto = _pendingProfilePhoto ?? _profilePhoto;
      _isEditing = false;
      _isSavingProfile = false;
      _pendingProfilePhoto = null;
      _photoUploadProgress = null;
      _saveStatus = null;
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Colors.green),
    );
  }

  void _logout() {
    if (_isDialogOpen) return; // Prevent multiple dialogs

    _isDialogOpen = true;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _isDialogOpen = false;
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => _confirmLogout(context),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((_) {
      _isDialogOpen = false;
    });
  }

  Future<void> _confirmLogout(BuildContext dialogContext) async {
    Navigator.pop(dialogContext);
    try {
      await _profileService.clearProfile();
      if (!mounted) return;
      await Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (error, stackTrace) {
      debugPrint('Unable to sign out: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not log out. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileContent = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: const Color(0xFFF3D5AA),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 24),
                      if (_isEditing)
                        TextButton(
                          onPressed: _isSavingProfile
                              ? null
                              : () {
                                  setState(() {
                                    _isEditing = false;
                                    _pendingProfilePhoto = null;
                                  });
                                  _nameController.text = _userName;
                                  _addressController.text = _userAddress;
                                },
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                                color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                        )
                      else
                        const SizedBox(width: 24),
                      const SizedBox(width: 24),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Profile Photo
                  GestureDetector(
                    onTap: _isEditing && !_isSavingProfile
                        ? _pickProfilePhoto
                        : null,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: const Color(0xFFECB56E),
                          backgroundImage:
                              (_pendingProfilePhoto ?? _profilePhoto) != null
                                  ? MemoryImage(
                                      _pendingProfilePhoto ?? _profilePhoto!,
                                    )
                                  : null,
                          child: _pendingProfilePhoto == null &&
                                  _profilePhoto == null
                              ? ClipOval(
                                  child: Center(
                                    child: SizedBox(
                                      width: 50,
                                      height: 100,
                                      child: ClipRect(
                                        child: OverflowBox(
                                          alignment: Alignment.topLeft,
                                          minWidth: 0,
                                          maxWidth: 300,
                                          minHeight: 0,
                                          maxHeight: 400,
                                          child: Image.asset(
                                            _userCharacter == 'girl'
                                                ? 'assets/images/player/character2.png'
                                                : 'assets/images/player/character.png',
                                            width: 300,
                                            height: 400,
                                            fit: BoxFit.fill,
                                            errorBuilder: (
                                              context,
                                              error,
                                              stackTrace,
                                            ) =>
                                                Text(
                                              _userName.isEmpty
                                                  ? 'S'
                                                  : _userName[0].toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 32,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        if (_isSavingProfile && _pendingProfilePhoto != null)
                          Positioned.fill(
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 42,
                                    height: 42,
                                    child: CircularProgressIndicator(
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  if (_photoUploadProgress != null)
                                    Text(
                                      '${(_photoUploadProgress! * 100).round()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          )
                        else if (_isEditing)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Display name or edit field
                  if (_isEditing)
                    TextField(
                      controller: _nameController,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2B3B5A),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Enter your name',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    )
                  else
                    Text(
                      _userName.isEmpty ? 'Your Profile' : _userName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2B3B5A),
                      ),
                    ),
                  const SizedBox(height: 24),
                  // Info fields
                  _buildInfoRow('Email', _userEmail, readOnly: true),
                  const SizedBox(height: 12),
                  _buildInfoRow('Grade',
                      _userRole.isEmpty ? 'N/A' : _userRole.toUpperCase(),
                      readOnly: true),
                  const SizedBox(height: 12),
                  _buildInfoRow('LRN', _userLRN, readOnly: true),
                  const SizedBox(height: 12),
                  if (_isEditing)
                    _buildEditableField('Address', _addressController)
                  else
                    _buildInfoRow('Address', _userAddress),
                  const SizedBox(height: 26),
                  if (_isEditing)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isSavingProfile ? null : _saveProfile,
                        child: _isSavingProfile
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _saveStatus ?? 'Saving changes...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (_photoUploadProgress != null) ...[
                                    const SizedBox(height: 8),
                                    LinearProgressIndicator(
                                      value: _photoUploadProgress,
                                      backgroundColor: Colors.white30,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${((_photoUploadProgress ?? 0) * 100).round()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ] else if (_pendingProfilePhoto != null) ...[
                                    const SizedBox(height: 8),
                                    const LinearProgressIndicator(
                                      backgroundColor: Colors.white30,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1976D2),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => setState(() => _isEditing = true),
                            child: const Text(
                              'Edit Profile',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _logout,
                            child: const Text(
                              'Logout',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: widget.onClose ??
                                () => Navigator.maybePop(context),
                            child: const Text(
                              'Close',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.isDialog) {
      return profileContent;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F2847),
      body: SafeArea(
        child: profileContent,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool readOnly = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value.isEmpty ? 'N/A' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBBBBB), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              isDense: true,
              hintText: 'Enter $label',
            ),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }
}
