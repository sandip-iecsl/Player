import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_colors.dart';
import '../../data/services/local_chat_service.dart';

class SecretConfigurationScreen extends StatefulWidget {
  const SecretConfigurationScreen({super.key});

  @override
  State<SecretConfigurationScreen> createState() => _SecretConfigurationScreenState();
}

class _SecretConfigurationScreenState extends State<SecretConfigurationScreen> {
  SharedPreferences? _prefs;
  bool _isLoading = true;
  bool _isSaving = false;
  final _chatService = LocalChatService();

  bool _overrideState = false;
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _linkedinController = TextEditingController();
  bool _showContactState = true;
  bool _showLinkedinState = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    if (_prefs != null) {
      _overrideState = _prefs!.getBool('local_override_enabled') ?? false;
      final savedDisplayName = _prefs!.getString('user_name')?.trim();
      final overrideName = _prefs!.getString('local_override_creator_name')?.trim();
      _nameController.text = (savedDisplayName != null && savedDisplayName.isNotEmpty)
          ? savedDisplayName
          : ((overrideName != null && overrideName.isNotEmpty) ? overrideName : '');
      _contactController.text =
          _prefs!.getString('local_override_contact_number') ?? '8972966158';
      _linkedinController.text = _prefs!.getString('local_override_linkedin_url') ??
          'https://www.linkedin.com/in/sandipan-bhunia/';
      _showContactState = _prefs!.getBool('local_override_show_contact') ?? true;
      _showLinkedinState = _prefs!.getBool('local_override_show_linkedin') ?? true;
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _linkedinController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    if (_prefs == null || _isSaving) return;

    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Name cannot be empty!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      await _prefs!.setBool('local_override_enabled', _overrideState);
      await _prefs!.setString('local_override_creator_name', newName);
      await _prefs!.setString('user_name', newName);
      await _prefs!.setString(
          'local_override_contact_number', _contactController.text.trim());
      await _prefs!.setString(
          'local_override_linkedin_url', _linkedinController.text.trim());
      await _prefs!.setBool('local_override_show_contact', _showContactState);
      await _prefs!.setBool('local_override_show_linkedin', _showLinkedinState);

      // Update Firestore so this user appears in chat lists
      try {
        await _chatService.registerUser(newName);
        debugPrint('[Config] ✅ User registered/updated in Firestore: $newName');
      } catch (e) {
        debugPrint('[Config] ⚠️ Failed to register user in Firestore: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
        // Small delay so the snackbar is briefly visible before popping
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('[Config] ❌ Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 14),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A2A2A), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.neonPink, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final horizontalPadding = screenWidth > 600 ? screenWidth * 0.1 : 20.0;

    return PopScope(
      canPop: !_isSaving, // Block back during save to prevent partial writes
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0A0A),
          elevation: 0,
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: _isSaving ? null : () => Navigator.pop(context),
          ),
          title: const Text(
            'Configuration',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          actions: [
            // Quick save action in app bar
            TextButton(
              onPressed: _isSaving ? null : _saveSettings,
              child: Text(
                'Save',
                style: TextStyle(
                  color: _isSaving ? Colors.grey : AppColors.neonPink,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: AppColors.neonPink),
              )
            : SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 20,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header info ────────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.neonPink.withOpacity(0.2)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                color: AppColors.neonPink, size: 18),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'These changes are local to this device only. They override cloud config without affecting other devices.',
                                style:
                                    TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Section: Profile ───────────────────────────────
                      _sectionLabel('Profile'),
                      const SizedBox(height: 12),

                      TextField(
                        controller: _nameController,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration('Display Name'),
                      ),
                      const SizedBox(height: 14),

                      TextField(
                        controller: _contactController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration('Contact (SMS) Number'),
                      ),
                      const SizedBox(height: 14),

                      TextField(
                        controller: _linkedinController,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        decoration: _inputDecoration('LinkedIn Profile URL'),
                      ),
                      const SizedBox(height: 28),

                      // ── Section: Visibility ────────────────────────────
                      _sectionLabel('Home Screen Visibility'),
                      const SizedBox(height: 8),

                      _switchTile(
                        title: 'Show Contact Button',
                        subtitle: 'Display SMS/chat button on Home Screen',
                        value: _showContactState,
                        onChanged: (val) =>
                            setState(() => _showContactState = val),
                      ),
                      const SizedBox(height: 4),
                      _switchTile(
                        title: 'Show LinkedIn Button',
                        subtitle: 'Display LinkedIn button on Home Screen',
                        value: _showLinkedinState,
                        onChanged: (val) =>
                            setState(() => _showLinkedinState = val),
                      ),
                      const SizedBox(height: 28),

                      // ── Section: Advanced ──────────────────────────────
                      _sectionLabel('Advanced'),
                      const SizedBox(height: 8),

                      _switchTile(
                        title: 'Enable Local Overrides',
                        subtitle:
                            'Bypass Firestore cloud config on this device',
                        value: _overrideState,
                        onChanged: (val) =>
                            setState(() => _overrideState = val),
                      ),
                      const SizedBox(height: 40),

                      // ── Save & Exit button ─────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveSettings,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.neonPink,
                            disabledBackgroundColor:
                                AppColors.neonPink.withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                            shadowColor: AppColors.neonPink.withOpacity(0.4),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.save_rounded,
                                        color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Save & Exit',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
        label.toUpperCase(),
        style: TextStyle(
          color: AppColors.neonPink,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.4,
        ),
      );

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: SwitchListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
          value: value,
          activeColor: AppColors.neonPink,
          onChanged: onChanged,
        ),
      );
}
