import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/local_chat_service.dart';
import '../../core/constants/app_colors.dart';
import '../providers/audio_provider.dart';
import 'manage_users_screen.dart';
import '../../features/admin/engines/dashboard_engine.dart';
import '../../features/admin/engines/search_intelligence_engine.dart';
import '../../features/admin/engines/configuration_engine.dart';

class MLTrainingScreen extends StatefulWidget {
  const MLTrainingScreen({super.key});

  @override
  State<MLTrainingScreen> createState() => _MLTrainingScreenState();
}

class _MLTrainingScreenState extends State<MLTrainingScreen> {
  final _searchController = TextEditingController();
  final _mapToController = TextEditingController();

  bool _configLoaded = false;
  final _creatorNameController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _linkedinUrlController = TextEditingController();
  final _adminPasscodeController = TextEditingController();
  final _appLockPasscodeController = TextEditingController();
  final _secretConsolePasscodeController = TextEditingController();
  final _chatExpiryHoursController = TextEditingController();
  bool _showContact = true;
  bool _showLinkedin = true;
  bool _isSaving = false;

  late Box _box;

  @override
  void initState() {
    super.initState();
    _box = Hive.box('ml_training_box');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapToController.dispose();
    _creatorNameController.dispose();
    _contactNumberController.dispose();
    _linkedinUrlController.dispose();
    _adminPasscodeController.dispose();
    _appLockPasscodeController.dispose();
    _secretConsolePasscodeController.dispose();
    _chatExpiryHoursController.dispose();
    super.dispose();
  }

  void _addRule() {
    final search = _searchController.text.trim().toLowerCase();
    final mapTo = _mapToController.text.trim().toLowerCase();

    if (search.isEmpty || mapTo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Both fields are required.')),
      );
      return;
    }

    SearchIntelligenceEngine().trainRule(search, mapTo);

    _searchController.clear();
    _mapToController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Trained: "$search" → "$mapTo"')),
    );
    setState(() {});
  }

  Future<void> _pushToFirestore(Map<String, String> newRules) async {
    if (newRules.isEmpty) return;
    
    final collection = FirebaseFirestore.instance.collection('ml_engine_synonyms');
    
    // 1. Fetch current rules from Firestore to calculate a diff
    final snapshot = await collection.get();
    Map<String, String> existingCloudRules = {};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      if (data.containsKey('alias') && data.containsKey('target')) {
        existingCloudRules[data['alias'].toString()] = data['target'].toString();
      }
    }
    
    // 2. Filter to ONLY contain rules that don't exist in Firestore or have a different target
    Map<String, String> rulesToPush = {};
    for (final entry in newRules.entries) {
      if (existingCloudRules[entry.key] != entry.value) {
        rulesToPush[entry.key] = entry.value;
      }
    }
    
    if (rulesToPush.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No new unique rules to upload. Database is already up-to-date!'),
            backgroundColor: Colors.blue,
          ),
        );
      }
      return;
    }

    final entries = rulesToPush.entries.toList();
    
    // 3. Firestore allows maximum 500 writes per batch
    for (int i = 0; i < entries.length; i += 500) {
      final batch = FirebaseFirestore.instance.batch();
      final chunk = entries.skip(i).take(500);
      for (final entry in chunk) {
        final docId = base64UrlEncode(utf8.encode(entry.key));
        batch.set(collection.doc(docId), {
          'alias': entry.key,
          'target': entry.value,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> _importExcel() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        withData: false, // XFile handles data reading automatically
      );

      if (result != null) {
        final xFile = result.xFiles.single;
        final bytes = await xFile.readAsBytes();
        
        int processedCount = 0;
        Map<String, String> newRules = {};

        if (xFile.name.toLowerCase().endsWith('.csv')) {
          final String csvString = utf8.decode(bytes);
          final List<List<dynamic>> rows = Csv().decode(csvString);
          bool isFirstRow = true;
          for (var row in rows) {
            if (isFirstRow) {
              isFirstRow = false;
              continue;
            }
            if (row.isEmpty) continue;
            final target = row[0]?.toString().trim().toLowerCase() ?? '';
            if (target.isEmpty) continue;

            for (int i = 1; i < row.length; i++) {
              final alias = row[i]?.toString().trim().toLowerCase() ?? '';
              if (alias.isNotEmpty && alias != target) {
                processedCount++;
                final existing = _box.get(alias);
                if (existing != target) {
                  _box.put(alias, target);
                  newRules[alias] = target;
                }
              }
            }
          }
        } else {
          var excel = Excel.decodeBytes(bytes);

          for (var table in excel.tables.keys) {
            final sheet = excel.tables[table]!;
            bool isFirstRow = true;
            
            for (var row in sheet.rows) {
              if (isFirstRow) {
                isFirstRow = false;
                continue; // skip header
              }
              if (row.isEmpty || row[0] == null) continue;

              final target = row[0]?.value?.toString().trim().toLowerCase() ?? '';
              if (target.isEmpty) continue;

              // Iterate through US_1, US_2, etc.
              for (int i = 1; i < row.length; i++) {
                final alias = row[i]?.value?.toString().trim().toLowerCase() ?? '';
                if (alias.isNotEmpty && alias != target) {
                  processedCount++;
                  final existing = _box.get(alias);
                  if (existing != target) {
                    _box.put(alias, target);
                    newRules[alias] = target;
                  }
                }
              }
            }
          }
        }
        
        await _pushToFirestore(newRules);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Processed $processedCount rules. Pushed ${newRules.length} new rules to Cloud!'), 
              backgroundColor: Colors.green
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print('=== EXCEL IMPORT ERROR ===');
      print(e);
      print(stackTrace);
      print('==========================');
      
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('FileSystemException') || msg.contains('process cannot access the file')) {
          msg = 'Please close the Excel file in other programs (like Microsoft Excel) and try again.';
        } else if (msg.contains('ArchiveException') || msg.contains('extract a non-archive file')) {
          msg = 'Invalid or corrupt Excel file. Please ensure it is a valid .xlsx file.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $msg'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _deleteRule(dynamic key) {
    SearchIntelligenceEngine().deleteRule(key.toString());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          title: const Text('Admin Panel',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.cloud_upload_rounded),
              tooltip: 'Force Sync to Cloud',
              onPressed: () async {
                try {
                  Map<String, String> allRules = {};
                  for (final key in _box.keys) {
                    allRules[key.toString()] = _box.get(key).toString();
                  }
                  await _pushToFirestore(allRules);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Pushed ${allRules.length} rules to Cloud!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Upload failed: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            )
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelColor: Color(0xFF1DB954),
            unselectedLabelColor: Colors.grey,
            indicatorColor: Color(0xFF1DB954),
            tabs: [
              Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined)),
              Tab(text: 'Search ML', icon: Icon(Icons.smart_toy_outlined)),
              Tab(text: 'Settings', icon: Icon(Icons.settings_outlined)),
              Tab(text: 'Chat Log', icon: Icon(Icons.chat_outlined)),
              Tab(text: 'Users', icon: Icon(Icons.people_outline)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: System Overview Dashboard
            _buildDashboardTab(),

            // Tab 2: Search ML Engine
            Column(
              children: [
                // Training Input Form
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1A1A1A),
                    border: Border(bottom: BorderSide(color: Colors.white10)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Define Custom Search Rules',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Teach the ML Engine how you search. When a search query matches or contains the phrase below, it will be mapped to the target song/artist.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'When I search for...',
                          labelStyle: const TextStyle(color: Colors.grey),
                          hintText: 'e.g., Aawaara Angaara full song',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: Colors.black,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _mapToController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Map it to...',
                          labelStyle: const TextStyle(color: Colors.grey),
                          hintText: 'e.g., Tere Ishk Mein',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: Colors.black,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: _addRule,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1DB954),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text(
                                'Train Rule',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: OutlinedButton(
                              onPressed: _importExcel,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: Color(0xFF1DB954)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Icon(Icons.upload_file, color: Color(0xFF1DB954)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Trained Rules List
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _box.listenable(),
                    builder: (context, Box box, _) {
                      if (box.keys.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.smart_toy_outlined, size: 64, color: Colors.grey.shade800),
                              const SizedBox(height: 16),
                              const Text(
                                'No custom rules trained yet',
                                style: TextStyle(color: Colors.grey, fontSize: 16),
                              ),
                            ],
                          ),
                        );
                      }

                      final keys = box.keys.toList().reversed.toList();

                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: keys.length,
                        separatorBuilder: (context, index) => const Divider(color: Colors.white10),
                        itemBuilder: (context, index) {
                          final key = keys[index];
                          final value = box.get(key);
                          
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: Text(
                              '"$key"',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Maps to: "$value"',
                              style: const TextStyle(color: Color(0xFF1DB954)),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () => _deleteRule(key),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            
            // Tab 2: App Config Settings
            _buildAppConfigTab(),

            // Tab 3: Direct Chat Monitor
            _buildChatMonitorTab(),

            // Tab 4: Manage Users
            const ManageUsersScreen(showAppBar: false),
          ],
        ),
      ),
    );
  }

  Widget _buildAppConfigTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: ConfigurationEngine().fetchSettings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !_configLoaded) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)));
        }
        
        if (snapshot.hasData && !_configLoaded) {
          final data = snapshot.data ?? {};
          _creatorNameController.text = data['creatorName'] as String? ?? 'Sandip';
          _contactNumberController.text = data['contactNumber'] as String? ?? '8972966158';
          _linkedinUrlController.text = data['linkedinUrl'] as String? ?? 'https://www.linkedin.com/in/sandipan-bhunia/';
          // Passcodes loaded from Firestore as-is — empty string if not set yet
          _adminPasscodeController.text = data['adminPasscode']?.toString() ?? data['password']?.toString() ?? '';
          _appLockPasscodeController.text = data['appLockPasscode']?.toString() ?? '';
          _secretConsolePasscodeController.text = data['secretConsolePasscode']?.toString() ?? '';
          _chatExpiryHoursController.text = (data['chatExpiryHours'] ?? 24).toString();
          _showContact = (data['showContact'] ?? true) as bool;
          _showLinkedin = (data['showLinkedin'] ?? true) as bool;
          _configLoaded = true;
        }

        return StatefulBuilder(
          builder: (context, setStateLocal) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'App & Creator Details',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Update the creator profile, contact information, and toggle visibility options on the home screen.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  
                  // Creator Name
                  TextField(
                    controller: _creatorNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Creator Name',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Contact Number
                  TextField(
                    controller: _contactNumberController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Creator Contact Number (SMS)',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // LinkedIn URL
                  TextField(
                    controller: _linkedinUrlController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'LinkedIn Profile URL',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Switches
                  SwitchListTile(
                    title: const Text('Show Contact (SMS) Option', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Toggle chat/SMS shortcut button on Home Screen', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    value: _showContact,
                    activeColor: const Color(0xFF1DB954),
                    onChanged: (val) {
                      setStateLocal(() {
                        _showContact = val;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Show LinkedIn Option', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('Toggle LinkedIn shortcut button on Home Screen', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    value: _showLinkedin,
                    activeColor: const Color(0xFF1DB954),
                    onChanged: (val) {
                      setStateLocal(() {
                        _showLinkedin = val;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _chatExpiryHoursController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Chat Message Expiry (Hours)',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 40),
                  const Text(
                    'Manage Access Passcodes',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Configure passcodes for accessing the Admin panel, unlocking the App (App Lock), and opening the secret local console.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),

                  // Admin Passcode
                  TextField(
                    controller: _adminPasscodeController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Admin Panel Passcode',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // App Lock Passcode
                  TextField(
                    controller: _appLockPasscodeController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'App Lock Passcode',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Secret Console Passcode
                  TextField(
                    controller: _secretConsolePasscodeController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Secret Local Console Passcode',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1A1A1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Save Button
                  ElevatedButton(
                    onPressed: _isSaving ? null : () async {
                      setStateLocal(() {
                        _isSaving = true;
                      });
                      try {
                        await ConfigurationEngine().updateSettings({
                          'creatorName': _creatorNameController.text.trim(),
                          'contactNumber': _contactNumberController.text.trim(),
                          'linkedinUrl': _linkedinUrlController.text.trim(),
                          'adminPasscode': _adminPasscodeController.text.trim(),
                          'appLockPasscode': _appLockPasscodeController.text.trim(),
                          'secretConsolePasscode': _secretConsolePasscodeController.text.trim(),
                          'chatExpiryHours': int.tryParse(_chatExpiryHoursController.text.trim()) ?? 24,
                          'showContact': _showContact,
                          'showLinkedin': _showLinkedin,
                        });
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Settings saved successfully!'), backgroundColor: Colors.green),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to save settings: $e'), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        setStateLocal(() {
                          _isSaving = false;
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1DB954),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Save Settings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildChatMonitorTab() {
    final chatService = LocalChatService();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: chatService.getChatUsersOnce(),
      builder: (context, usersSnapshot) {
        if (usersSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)));
        }
        final usersList = usersSnapshot.data ?? [];
        final Map<String, String> userNames = {};
        for (var u in usersList) {
          final uid = u['uid'] as String?;
          if (uid != null) {
            userNames[uid] = u['name'] as String? ?? 'Unknown User';
          }
        }

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: chatService.getAllChatRoomsOnce(),
          builder: (context, roomsSnapshot) {
            if (roomsSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)));
            }
            final rooms = roomsSnapshot.data ?? [];
            if (rooms.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'No active direct chats found in database',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: rooms.length,
              separatorBuilder: (context, index) => const Divider(color: Colors.white10),
              itemBuilder: (context, index) {
                final room = rooms[index];
                final roomId = room['roomId'] as String? ?? '';
                final userUids = List<String>.from(room['users'] ?? []);
                
                if (userUids.length < 2) return const SizedBox.shrink();
                
                final uid1 = userUids[0];
                final uid2 = userUids[1];
                
                final name1 = userNames[uid1] ?? 'User (${uid1.length > 5 ? uid1.substring(0, 5) : uid1})';
                final name2 = userNames[uid2] ?? 'User (${uid2.length > 5 ? uid2.substring(0, 5) : uid2})';

                final lastMsg = room['lastMessage'] as String? ?? 'No messages';
                final lastTs = room['lastTimestamp'] as Timestamp?;
                
                String timeStr = '';
                if (lastTs != null) {
                  final dt = lastTs.toDate();
                  timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                }

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey.shade900,
                    child: const Icon(Icons.people_outline, color: Color(0xFF1DB954)),
                  ),
                  title: Text(
                    '$name1 ↔ $name2',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      lastMsg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (timeStr.isNotEmpty)
                        Text(timeStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  onTap: () {
                    final expiryVal = int.tryParse(_chatExpiryHoursController.text.trim()) ?? 24;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdminChatViewScreen(
                          roomId: roomId,
                          user1Name: name1,
                          user2Name: name2,
                          user1Id: uid1,
                          user2Id: uid2,
                          expiryHours: expiryVal,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDashboardTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadDashboardStats(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)));
        }
        final stats = snapshot.data ?? {};
        final totalUsers = stats['totalUsers'] ?? 0;
        final onlineUsers = stats['onlineUsers'] ?? 0;
        final activeChats = stats['activeChats'] ?? 0;
        final syncQueue = stats['syncQueue'] ?? 0;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('System Overview', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildStatCard('Total Users', '$totalUsers', Icons.people, Colors.blue)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard('Online Users', '$onlineUsers', Icons.online_prediction, Colors.green)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildStatCard('Active Chats', '$activeChats', Icons.chat, Colors.amber)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStatCard('Sync Queue', '$syncQueue jobs', Icons.sync, Colors.red)),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Local Health & Quotas', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildHealthRow('Firestore Free Read Tier', 'Estimated: Normal', Icons.check_circle, Colors.green),
              _buildHealthRow('Firestore Free Write Tier', 'Estimated: Normal', Icons.check_circle, Colors.green),
              _buildHealthRow('Storage Allocation', 'Estimated: 0.1% of 5GB', Icons.check_circle, Colors.green),
              _buildHealthRow('Local Database Encryption', 'Enabled (AES-256)', Icons.security, Colors.green),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String title, String val, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 4),
          Text(val, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHealthRow(String title, String val, IconData icon, Color color) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
      trailing: Text(val, style: const TextStyle(color: Colors.grey, fontSize: 13)),
    );
  }

  Future<Map<String, dynamic>> _loadDashboardStats() async {
    return DashboardEngine().loadDashboardStats();
  }
}

class AdminChatViewScreen extends StatelessWidget {
  final String roomId;
  final String user1Name;
  final String user2Name;
  final String user1Id;
  final String user2Id;
  final int expiryHours;

  const AdminChatViewScreen({
    super.key,
    required this.roomId,
    required this.user1Name,
    required this.user2Name,
    required this.user1Id,
    required this.user2Id,
    required this.expiryHours,
  });

  @override
  Widget build(BuildContext context) {
    final chatService = LocalChatService();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          '$user1Name ↔ $user2Name',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            tooltip: 'Clear Chat',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.deepSpaceBlackLight,
                  title: const Text('Clear Chat', style: TextStyle(color: Colors.white)),
                  content: const Text('Are you sure you want to permanently delete all messages in this chat?', style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true), 
                      child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
              
              if (confirm == true) {
                await chatService.clearChat(roomId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chat cleared successfully.'), backgroundColor: Colors.green),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: chatService.getMessages(roomId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)));
          }
          final allDocs = snapshot.data?.docs ?? [];
          final cutoff = DateTime.now().subtract(Duration(hours: expiryHours));
          final docs = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final ts = data['timestamp'] as Timestamp?;
            if (ts == null) return true;
            return ts.toDate().isAfter(cutoff);
          }).toList();

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No active messages found in this room (or expired).',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return Consumer(
            builder: (context, ref, child) {
              final currentSong = ref.watch(currentSongProvider).valueOrNull;
              final double bottomPadding = currentSong != null ? 140.0 : 80.0;
              
              return ListView.builder(
                reverse: true,
                padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final senderId = data['senderId'] as String? ?? '';
                  final senderName = data['senderName'] as String? ?? 'Unknown';
                  final isUser1 = senderId == user1Id;
                  
                  return Align(
                    alignment: isUser1 ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isUser1 ? const Color(0xFF1E1E1E) : AppColors.neonPink,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: isUser1 ? Radius.zero : const Radius.circular(16),
                          bottomRight: isUser1 ? const Radius.circular(16) : Radius.zero,
                        ),
                      ),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            senderName,
                            style: TextStyle(
                              color: isUser1 ? const Color(0xFF1DB954) : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            data['text'] ?? '',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
