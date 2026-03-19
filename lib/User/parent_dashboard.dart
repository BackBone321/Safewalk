import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth/auth_service.dart';
import '../login_dashboard/login_page.dart';

class ParentDashboardPage extends StatefulWidget {
  const ParentDashboardPage({super.key});

  @override
  State<ParentDashboardPage> createState() => _ParentDashboardPageState();
}

class _ParentDashboardPageState extends State<ParentDashboardPage> {
  int _selectedNavIndex = 0;
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isSavingProfile = false;
  bool _isSavingSettings = false;

  String _parentName = 'Parent';
  String _parentEmail = '';
  String _parentPhone = '';

  String _childUid = '';
  String _childName = 'Student';
  String _childRoute = 'Main Campus -> Dorm Block C';
  bool _childSessionActive = false;
  DateTime? _childSessionStartedAt;
  double _childDistanceKm = 1.2;

  String _deviceId = 'Not linked';
  String _deviceName = 'No linked device';
  String _deviceLocation = 'Unknown';
  String _deviceStatus = 'offline';

  bool _alertsEnabled = true;
  bool _smsAlertsEnabled = true;
  bool _emailAlertsEnabled = true;

  final List<_ToolItem> _tools = const [
    _ToolItem(
      title: 'Device Connection',
      subtitle: 'Check your linked emergency device',
      icon: Icons.smartphone_rounded,
      iconColor: Color(0xFF1E7E55),
      iconBg: Color(0xFFEAF5EF),
    ),
    _ToolItem(
      title: 'Alert History',
      subtitle: 'Recent alerts and emergency logs',
      icon: Icons.history,
      iconColor: Color(0xFF9C7A24),
      iconBg: Color(0xFFFAF3DF),
    ),
    _ToolItem(
      title: 'Profile',
      subtitle: 'Edit parent information',
      icon: Icons.person_outline,
      iconColor: Color(0xFF4156B8),
      iconBg: Color(0xFFEFF2FF),
    ),
    _ToolItem(
      title: 'Settings',
      subtitle: 'Preferences and account settings',
      icon: Icons.settings_outlined,
      iconColor: Color(0xFF6E6D67),
      iconBg: Color(0xFFF2F1ED),
    ),
  ];

  final List<_NavItem> _navItems = const [
    _NavItem('Home', Icons.home_outlined),
    _NavItem('Child', Icons.shield_outlined),
    _NavItem('Alerts', Icons.notifications_none_rounded),
    _NavItem('Profile', Icons.person_outline),
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  String _normalizePhoneForLookup(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+|-'), '');
    if (cleaned.startsWith('+')) return cleaned;
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      return '+$cleaned';
    }
    return cleaned;
  }

  String get _elapsedLabel {
    if (!_childSessionActive || _childSessionStartedAt == null) return '--';
    final duration = DateTime.now().difference(_childSessionStartedAt!);
    return '${duration.inMinutes} min';
  }

  String get _routeMetric {
    final route = _childRoute.split('->').first.trim();
    if (route.isEmpty) return 'Campus';
    return route.length > 10 ? '${route.substring(0, 10)}.' : route;
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown time';
    final dt = timestamp.toDate().toLocal();
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$month/$day ${dt.year} $hour:$minute';
  }

  void _showActionSnack(String label, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        backgroundColor: isError ? Colors.red.shade700 : AppColors.green,
      ),
    );
  }

  Future<void> _loadDashboard() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }

    try {
      final parentDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      final settingsDoc = await _firestore.collection('user_settings').doc(currentUser.uid).get();

      if (!mounted) return;
      setState(() {
        _parentName = (parentDoc.data()?['fullName'] ?? 'Parent').toString();
        _parentEmail = (parentDoc.data()?['email'] ?? '').toString();
        _parentPhone = (parentDoc.data()?['phoneNumber'] ?? '').toString();
        _alertsEnabled = (settingsDoc.data()?['alertsEnabled'] as bool?) ?? true;
        _smsAlertsEnabled = (settingsDoc.data()?['smsAlertsEnabled'] as bool?) ?? true;
        _emailAlertsEnabled = (settingsDoc.data()?['emailAlertsEnabled'] as bool?) ?? true;
      });

      String configuredChildUid = (settingsDoc.data()?['childUid'] ?? '').toString();
      if (configuredChildUid.isEmpty) {
        final childQuery = await _firestore
            .collection('users')
            .where('role', isEqualTo: 'student')
            .limit(1)
            .get();
        if (childQuery.docs.isNotEmpty) {
          configuredChildUid = childQuery.docs.first.id;
        }
      }

      if (configuredChildUid.isNotEmpty) {
        await _loadChildData(configuredChildUid);
      }
    } catch (e) {
      _showActionSnack('Failed to load parent dashboard: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadChildData(String childUid) async {
    final childDoc = await _firestore.collection('users').doc(childUid).get();
    if (!childDoc.exists) return;

    final childData = childDoc.data() ?? <String, dynamic>{};
    final childName = (childData['fullName'] ?? 'Student').toString();
    final childPhone = (childData['phoneNumber'] ?? '').toString();
    final rawPhone = childPhone.trim();
    final normalizedPhone = _normalizePhoneForLookup(rawPhone);

    var deviceQuery = await _firestore
        .collection('devices')
        .where('phoneNumber', isEqualTo: rawPhone)
        .limit(1)
        .get();

    if (deviceQuery.docs.isEmpty && normalizedPhone != rawPhone) {
      deviceQuery = await _firestore
          .collection('devices')
          .where('phoneNumber', isEqualTo: normalizedPhone)
          .limit(1)
          .get();
    }

    final walkQuery = await _firestore
        .collection('walk_sessions')
        .where('uid', isEqualTo: childUid)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (!mounted) return;
    setState(() {
      _childUid = childUid;
      _childName = childName;

      if (walkQuery.docs.isNotEmpty) {
        final walkData = walkQuery.docs.first.data();
        _childSessionActive = true;
        _childSessionStartedAt = (walkData['startAt'] as Timestamp?)?.toDate();
        _childRoute = (walkData['route'] ?? _childRoute).toString();
        _childDistanceKm = (walkData['distanceKm'] as num?)?.toDouble() ?? _childDistanceKm;
      } else {
        _childSessionActive = false;
      }

      if (deviceQuery.docs.isNotEmpty) {
        final device = deviceQuery.docs.first.data();
        _deviceId = (device['deviceId'] ?? deviceQuery.docs.first.id).toString();
        _deviceName = (device['deviceName'] ?? 'Emergency Device').toString();
        _deviceLocation = (device['location'] ?? 'Unknown').toString();
        _deviceStatus = (device['status'] ?? 'active').toString().toLowerCase();
      } else {
        _deviceId = 'Not linked';
        _deviceName = 'No linked device';
        _deviceLocation = 'Unknown';
        _deviceStatus = 'offline';
      }
    });
  }

  Future<void> _showChildStatusDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Child Status'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Child: $_childName'),
              const SizedBox(height: 6),
              Text('Session: ${_childSessionActive ? 'Active' : 'Inactive'}'),
              const SizedBox(height: 6),
              Text('Route: $_childRoute'),
              const SizedBox(height: 6),
              Text('Elapsed: $_elapsedLabel'),
              const SizedBox(height: 6),
              Text('Distance: ${_childDistanceKm.toStringAsFixed(1)} km'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSessionDetailsDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Session Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Child: $_childName'),
              const SizedBox(height: 6),
              Text('Status: ${_childSessionActive ? 'Active' : 'Inactive'}'),
              const SizedBox(height: 6),
              Text('Route: $_childRoute'),
              const SizedBox(height: 6),
              Text('Elapsed: $_elapsedLabel'),
              const SizedBox(height: 6),
              Text('Distance: ${_childDistanceKm.toStringAsFixed(1)} km'),
              const SizedBox(height: 6),
              Text('Last device location: $_deviceLocation'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDeviceDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Child Device Connection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Device name: $_deviceName'),
              const SizedBox(height: 6),
              Text('Device ID: $_deviceId'),
              const SizedBox(height: 6),
              Text('Location: $_deviceLocation'),
              const SizedBox(height: 6),
              Text('Status: ${_deviceStatus.toUpperCase()}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                if (_childUid.isNotEmpty) {
                  await _loadChildData(_childUid);
                }
                _showActionSnack('Device status refreshed.');
              },
              child: const Text('Refresh'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAlertHistorySheet() async {
    if (_childUid.isEmpty) {
      _showActionSnack('No linked student account found.', isError: true);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8D8D8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '$_childName Alerts',
                    style: const TextStyle(
                      fontSize: 22,
                      color: AppColors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _firestore
                          .collection('emergency_alerts')
                          .where('uid', isEqualTo: _childUid)
                          .limit(100)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Failed to load alerts: ${snapshot.error}'),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final docs = snapshot.data!.docs.toList()
                          ..sort((a, b) {
                            final aTs = a.data()['timestamp'] as Timestamp?;
                            final bTs = b.data()['timestamp'] as Timestamp?;
                            return (bTs?.millisecondsSinceEpoch ?? 0)
                                .compareTo(aTs?.millisecondsSinceEpoch ?? 0);
                          });
                        if (docs.isEmpty) {
                          return const Center(
                            child: Text('No alerts found for this student.'),
                          );
                        }

                        return ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final data = docs[index].data();
                            final status = (data['status'] ?? 'unknown').toString();
                            final message = (data['message'] ?? 'No details').toString();
                            final timestamp = data['timestamp'] as Timestamp?;
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.warning_amber_rounded,
                                        size: 18,
                                        color: Color(0xFFCB392B),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          message,
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          await _firestore
                                              .collection('emergency_alerts')
                                              .doc(docs[index].id)
                                              .set({
                                            'status': 'acknowledged',
                                            'ackBy': FirebaseAuth.instance.currentUser?.uid ?? '',
                                            'ackAt': FieldValue.serverTimestamp(),
                                          }, SetOptions(merge: true));
                                        },
                                        child: const Text('Acknowledge'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text('Status: $status'),
                                  const SizedBox(height: 2),
                                  Text('Time: ${_formatTimestamp(timestamp)}'),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveProfile(String fullName, String phoneNumber) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }

    setState(() => _isSavingProfile = true);
    try {
      await _firestore.collection('users').doc(uid).set({
        'fullName': fullName.trim(),
        'phoneNumber': phoneNumber.trim(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _parentName = fullName.trim();
        _parentPhone = phoneNumber.trim();
      });
      _showActionSnack('Profile updated.');
    } catch (e) {
      _showActionSnack('Failed to update profile: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSavingProfile = false);
      }
    }
  }

  Future<void> _showProfileDialog() async {
    final nameCtrl = TextEditingController(text: _parentName);
    final phoneCtrl = TextEditingController(text: _parentPhone);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Email: $_parentEmail',
                  style: const TextStyle(color: Color(0xFF6E7A73)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _isSavingProfile
                  ? null
                  : () async {
                      await _saveProfile(nameCtrl.text, phoneCtrl.text);
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                    },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveSettings({
    required bool alertsEnabled,
    required bool smsAlertsEnabled,
    required bool emailAlertsEnabled,
    required String childUid,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }

    setState(() => _isSavingSettings = true);
    try {
      await _firestore.collection('user_settings').doc(uid).set({
        'alertsEnabled': alertsEnabled,
        'smsAlertsEnabled': smsAlertsEnabled,
        'emailAlertsEnabled': emailAlertsEnabled,
        'childUid': childUid.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _alertsEnabled = alertsEnabled;
        _smsAlertsEnabled = smsAlertsEnabled;
        _emailAlertsEnabled = emailAlertsEnabled;
      });

      if (childUid.trim().isNotEmpty && childUid.trim() != _childUid) {
        await _loadChildData(childUid.trim());
      }
      _showActionSnack('Settings saved.');
    } catch (e) {
      _showActionSnack('Failed to save settings: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSavingSettings = false);
      }
    }
  }

  Future<void> _showSettingsDialog() async {
    var localAlerts = _alertsEnabled;
    var localSms = _smsAlertsEnabled;
    var localEmail = _emailAlertsEnabled;
    final childUidCtrl = TextEditingController(text: _childUid);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable alerts'),
                    value: localAlerts,
                    onChanged: (value) => setDialogState(() => localAlerts = value),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('SMS alerts'),
                    value: localSms,
                    onChanged: (value) => setDialogState(() => localSms = value),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Email alerts'),
                    value: localEmail,
                    onChanged: (value) => setDialogState(() => localEmail = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: childUidCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Linked Student UID',
                      helperText: 'Leave empty to keep current linked student.',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: _isSavingSettings
                      ? null
                      : () async {
                          await _saveSettings(
                            alertsEnabled: localAlerts,
                            smsAlertsEnabled: localSms,
                            emailAlertsEnabled: localEmail,
                            childUid: childUidCtrl.text.trim().isEmpty
                                ? _childUid
                                : childUidCtrl.text.trim(),
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _handleToolTap(String title) async {
    switch (title) {
      case 'Device Connection':
        await _showDeviceDialog();
        return;
      case 'Alert History':
        await _showAlertHistorySheet();
        return;
      case 'Profile':
        await _showProfileDialog();
        return;
      case 'Settings':
        await _showSettingsDialog();
        return;
      default:
        _showActionSnack('$title tapped');
    }
  }

  Future<void> _onBottomNavTap(int index) async {
    setState(() => _selectedNavIndex = index);
    final label = _navItems[index].label;
    switch (label) {
      case 'Child':
        await _showChildStatusDialog();
        return;
      case 'Alerts':
        await _showAlertHistorySheet();
        return;
      case 'Profile':
        await _showProfileDialog();
        return;
      default:
        return;
    }
  }

  Future<void> _logout() async {
    try {
      await _authService.signOut();
    } catch (_) {
      // Continue logout navigation even if sign out throws.
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.offWhite,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.green),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroCard(),
              const SizedBox(height: 18),
              _buildSectionLabel('CURRENT SESSION'),
              const SizedBox(height: 10),
              _buildSessionCard(),
              const SizedBox(height: 18),
              _buildSectionLabel('TOOLS'),
              const SizedBox(height: 10),
              _buildToolList(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF05412B), Color(0xFF042D1F)],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFD9B255)),
                    ),
                    child: const Center(
                      child: Text(
                        'SW',
                        style: TextStyle(
                          color: Color(0xFFD9B255),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SafeWalk',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'MOTHER',
                        style: TextStyle(
                          color: Color(0xFF9DB2A9),
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E5B3C),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF2D8760)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Color(0xFF5DF0A0), size: 8),
                    SizedBox(width: 6),
                    Text(
                      'ONLINE',
                      style: TextStyle(
                        color: Color(0xFF5DF0A0),
                        fontSize: 13,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: _logout,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF124733),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFF0F5F2),
                    size: 21,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Good morning,',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _parentName,
            style: const TextStyle(
              color: Color(0xFFD9B255),
              fontSize: 44,
              height: 1,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: _childSessionActive ? 'Student Online' : 'Student Offline',
                dotColor: _childSessionActive
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFFF7F7F),
              ),
              _StatusPill(
                label: _deviceId == 'Not linked' ? 'Device Unlinked' : 'Device Linked',
                dotColor: _deviceId == 'Not linked'
                    ? const Color(0xFFFF7F7F)
                    : const Color(0xFFFFD166),
              ),
              _StatusPill(
                label: _alertsEnabled ? 'Alerts Enabled' : 'Alerts Paused',
                dotColor: _alertsEnabled
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFFF7F7F),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFB6AEA2),
        fontSize: 17,
        letterSpacing: 5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildSessionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Safe Walk Session',
                      style: TextStyle(
                        color: AppColors.green,
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _childSessionActive
                          ? 'Location sharing is active'
                          : 'No active walk session',
                      style: const TextStyle(
                        color: Color(0xFF6E7A73),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8F6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFCEE4D9)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 8,
                      color: _childSessionActive
                          ? const Color(0xFF60CC8A)
                          : const Color(0xFFFF7F7F),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _childSessionActive ? 'Active' : 'Inactive',
                      style: const TextStyle(
                        color: AppColors.green,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: AppColors.border.withValues(alpha: 0.55), height: 1),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _MetricCell(value: _routeMetric, label: 'ROUTE'),
              ),
              Expanded(
                child: _MetricCell(value: _elapsedLabel, label: 'ELAPSED'),
              ),
              Expanded(
                child: _MetricCell(
                  value: '${_childDistanceKm.toStringAsFixed(1)} km',
                  label: 'DISTANCE',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _showSessionDetailsDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text(
                'VIEW DETAILS',
                style: TextStyle(
                  fontSize: 21,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolList() {
    return Column(
      children: _tools
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => _handleToolTap(item.title),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: item.iconBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(item.icon, color: item.iconColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: AppColors.green,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle,
                              style: const TextStyle(
                                color: Color(0xFF6E7A73),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFFB5B2AA)),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_navItems.length, (index) {
            final item = _navItems[index];
            final selected = index == _selectedNavIndex;

            return Expanded(
              child: InkWell(
                onTap: () => _onBottomNavTap(index),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFE5ECE8)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.icon,
                          size: 21,
                          color: selected
                              ? AppColors.green
                              : const Color(0xFFA6A49D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: selected
                              ? AppColors.green
                              : const Color(0xFFA6A49D),
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final String value;
  final String label;

  const _MetricCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: AppColors.green,
            fontSize: 33,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFB5AEA1),
            fontSize: 14,
            letterSpacing: 3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color dotColor;

  const _StatusPill({required this.label, required this.dotColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF164837),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2B6851)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: dotColor, size: 7),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFEAF2ED),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  const _ToolItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });
}

class _NavItem {
  final String label;
  final IconData icon;

  const _NavItem(this.label, this.icon);
}
