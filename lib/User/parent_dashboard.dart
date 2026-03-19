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
  static const String _hf = 'CormorantGaramond';
  static const String _bf = 'JosefinSans';

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isSavingProfile = false;
  bool _isSavingSettings = false;
  bool _isProfileSheetOpen = false;

  final TextEditingController _profileNameCtrl = TextEditingController();
  final TextEditingController _profilePhoneCtrl = TextEditingController();

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

  // ─── Helpers ──────────────────────────────────────────────────

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
    final d = DateTime.now().difference(_childSessionStartedAt!);
    return '${d.inMinutes} min';
  }

  String get _routeMetric {
    final r = _childRoute.split('->').first.trim();
    if (r.isEmpty) return 'Campus';
    return r.length > 10 ? '${r.substring(0, 10)}.' : r;
  }

  String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return 'Unknown time';
    final dt = ts.toDate().toLocal();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$m/$d ${dt.year} $h:$min';
  }

  void _showActionSnack(String label, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          label,
          style: const TextStyle(fontFamily: _bf, letterSpacing: 0.5),
        ),
        backgroundColor: isError ? Colors.red.shade700 : AppColors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─── Data Loading ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  @override
  void dispose() {
    _profileNameCtrl.dispose();
    _profilePhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      return;
    }
    try {
      final parentDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final settingsDoc = await _firestore
          .collection('user_settings')
          .doc(currentUser.uid)
          .get();
      if (!mounted) return;
      setState(() {
        _parentName = (parentDoc.data()?['fullName'] ?? 'Parent').toString();
        _parentEmail = (parentDoc.data()?['email'] ?? '').toString();
        _parentPhone = (parentDoc.data()?['phoneNumber'] ?? '').toString();
        _alertsEnabled =
            (settingsDoc.data()?['alertsEnabled'] as bool?) ?? true;
        _smsAlertsEnabled =
            (settingsDoc.data()?['smsAlertsEnabled'] as bool?) ?? true;
        _emailAlertsEnabled =
            (settingsDoc.data()?['emailAlertsEnabled'] as bool?) ?? true;
      });

      String configuredChildUid = (settingsDoc.data()?['childUid'] ?? '')
          .toString();
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
      if (mounted) setState(() => _isLoading = false);
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
        _childDistanceKm =
            (walkData['distanceKm'] as num?)?.toDouble() ?? _childDistanceKm;
      } else {
        _childSessionActive = false;
      }

      if (deviceQuery.docs.isNotEmpty) {
        final device = deviceQuery.docs.first.data();
        _deviceId = (device['deviceId'] ?? deviceQuery.docs.first.id)
            .toString();
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

  // ─── Save Methods ──────────────────────────────────────────────

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
      if (mounted) setState(() => _isSavingProfile = false);
    }
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
      if (mounted) setState(() => _isSavingSettings = false);
    }
  }

  // ─── LUXURY SHEETS ─────────────────────────────────────────────

  Future<void> _showChildStatusDialog() async {
    await _showLuxuryInfoSheet(
      title: 'Child Status',
      subtitle: 'STUDENT MONITOR',
      icon: Icons.shield_outlined,
      rows: [
        _InfoRow('Child', _childName),
        _InfoRow('Session', _childSessionActive ? 'Active' : 'Inactive'),
        _InfoRow('Route', _childRoute),
        _InfoRow('Elapsed', _elapsedLabel),
        _InfoRow('Distance', '${_childDistanceKm.toStringAsFixed(1)} km'),
      ],
    );
  }

  Future<void> _showSessionDetailsDialog() async {
    await _showLuxuryInfoSheet(
      title: 'Session Details',
      subtitle: 'WALK SESSION',
      icon: Icons.directions_walk_outlined,
      rows: [
        _InfoRow('Child', _childName),
        _InfoRow('Status', _childSessionActive ? 'Active' : 'Inactive'),
        _InfoRow('Route', _childRoute),
        _InfoRow('Elapsed', _elapsedLabel),
        _InfoRow('Distance', '${_childDistanceKm.toStringAsFixed(1)} km'),
        _InfoRow('Last Location', _deviceLocation),
      ],
    );
  }

  Future<void> _showDeviceDialog() async {
    await _showLuxuryInfoSheet(
      title: 'Device Connection',
      subtitle: 'LINKED DEVICE',
      icon: Icons.smartphone_rounded,
      rows: [
        _InfoRow('Device Name', _deviceName),
        _InfoRow('Device ID', _deviceId),
        _InfoRow('Location', _deviceLocation),
        _InfoRow('Status', _deviceStatus.toUpperCase()),
      ],
      actionLabel: 'REFRESH',
      onAction: () async {
        if (_childUid.isNotEmpty) await _loadChildData(_childUid);
        _showActionSnack('Device status refreshed.');
      },
    );
  }

  Future<void> _showLuxuryInfoSheet({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<_InfoRow> rows,
    String? actionLabel,
    Future<void> Function()? onAction,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.offWhite,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 1,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      AppColors.gold,
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.green,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.gold, width: 1),
                          ),
                          child: Icon(icon, color: AppColors.gold, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title,
                              style: const TextStyle(
                                fontFamily: _hf,
                                fontSize: 28,
                                height: 1,
                                color: AppColors.green,
                                fontWeight: FontWeight.w300,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.gold, Colors.transparent],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...rows.map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.label,
                                style: const TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  row.value,
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontFamily: _bf,
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                    color: AppColors.green,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (actionLabel != null && onAction != null)
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: AppColors.green,
                          child: InkWell(
                            onTap: () async {
                              Navigator.pop(ctx);
                              await onAction();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.gold.withOpacity(0.65),
                                ),
                              ),
                              child: Text(
                                actionLabel,
                                style: const TextStyle(
                                  fontFamily: _bf,
                                  color: AppColors.white,
                                  letterSpacing: 4,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Text(
                          'CLOSE',
                          style: TextStyle(
                            fontFamily: _bf,
                            fontSize: 9,
                            letterSpacing: 3,
                            color: AppColors.textSub,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.55,
          maxChildSize: 0.95,
          expand: false,
          builder: (ctx2, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.offWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  Container(
                    height: 1,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.gold,
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.green,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.gold,
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(
                            Icons.history,
                            color: AppColors.gold,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$_childName · ALERTS',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const Text(
                              'Alert History',
                              style: TextStyle(
                                fontFamily: _hf,
                                fontSize: 26,
                                height: 1,
                                color: AppColors.green,
                                fontWeight: FontWeight.w300,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.gold, Colors.transparent],
                        ),
                      ),
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
                            child: Text(
                              'Failed to load alerts: ${snapshot.error}',
                              style: const TextStyle(fontFamily: _bf),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.gold,
                            ),
                          );
                        }
                        final docs = snapshot.data!.docs.toList()
                          ..sort((a, b) {
                            final aTs = a.data()['timestamp'] as Timestamp?;
                            final bTs = b.data()['timestamp'] as Timestamp?;
                            return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(
                              aTs?.millisecondsSinceEpoch ?? 0,
                            );
                          });
                        if (docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_outline,
                                  size: 48,
                                  color: AppColors.gold.withOpacity(0.4),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No alerts found.',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    color: AppColors.textSub,
                                    fontSize: 13,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final data = docs[i].data();
                            final status = (data['status'] ?? 'unknown')
                                .toString();
                            final message = (data['message'] ?? 'No details')
                                .toString();
                            final timestamp = data['timestamp'] as Timestamp?;
                            final isActive = status == 'active';
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isActive
                                      ? const Color(
                                          0xFFCB392B,
                                        ).withOpacity(0.35)
                                      : AppColors.border,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: isActive
                                              ? const Color(0xFFFFEEEC)
                                              : AppColors.cream,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.warning_amber_rounded,
                                          size: 17,
                                          color: isActive
                                              ? const Color(0xFFCB392B)
                                              : AppColors.textSub,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          message,
                                          style: const TextStyle(
                                            fontFamily: _bf,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: AppColors.green,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _AlertBadge(
                                        label: status.toUpperCase(),
                                        isActive: isActive,
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatTimestamp(timestamp),
                                        style: TextStyle(
                                          fontFamily: _bf,
                                          fontSize: 10,
                                          letterSpacing: 1,
                                          color: AppColors.textSub,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isActive) ...[
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Material(
                                        color: AppColors.green,
                                        borderRadius: BorderRadius.circular(8),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          onTap: () async {
                                            await _firestore
                                                .collection('emergency_alerts')
                                                .doc(docs[i].id)
                                                .set({
                                                  'status': 'acknowledged',
                                                  'ackBy':
                                                      FirebaseAuth
                                                          .instance
                                                          .currentUser
                                                          ?.uid ??
                                                      '',
                                                  'ackAt':
                                                      FieldValue.serverTimestamp(),
                                                }, SetOptions(merge: true));
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: AppColors.gold
                                                    .withOpacity(0.4),
                                              ),
                                            ),
                                            child: Text(
                                              'ACKNOWLEDGE',
                                              style: TextStyle(
                                                fontFamily: _bf,
                                                color: AppColors.white,
                                                letterSpacing: 3,
                                                fontSize: 10,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
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

  // ─── LUXURY PROFILE SHEET ──────────────────────────────────────

  Future<void> _showProfileDialog() async {
    if (_isProfileSheetOpen || !mounted) return;
    _isProfileSheetOpen = true;
    _profileNameCtrl
      ..text = _parentName
      ..selection = TextSelection.collapsed(offset: _parentName.length);
    _profilePhoneCtrl
      ..text = _parentPhone
      ..selection = TextSelection.collapsed(offset: _parentPhone.length);

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          bool isSaving = false;
          return StatefulBuilder(
            builder: (context, setSheet) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 1,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                AppColors.gold,
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EDIT PROFILE',
                                style: TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 9,
                                  letterSpacing: 4,
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              const SizedBox(height: 6),
                              RichText(
                                text: const TextSpan(
                                  style: TextStyle(
                                    fontFamily: _hf,
                                    fontSize: 34,
                                    height: 1.05,
                                    color: AppColors.green,
                                    fontWeight: FontWeight.w300,
                                  ),
                                  children: [
                                    TextSpan(text: 'Parent\n'),
                                    TextSpan(
                                      text: 'Information',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: AppColors.goldDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Avatar
                              Center(
                                child: Stack(
                                  alignment: Alignment.bottomRight,
                                  children: [
                                    Container(
                                      width: 76,
                                      height: 76,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.green,
                                        border: Border.all(
                                          color: AppColors.gold,
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.green.withOpacity(
                                              0.2,
                                            ),
                                            blurRadius: 20,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          _parentName.isNotEmpty
                                              ? _parentName[0].toUpperCase()
                                              : 'P',
                                          style: const TextStyle(
                                            fontFamily: _hf,
                                            fontSize: 32,
                                            color: AppColors.gold,
                                            fontWeight: FontWeight.w300,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.gold,
                                        border: Border.all(
                                          color: AppColors.offWhite,
                                          width: 2,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.edit,
                                        size: 11,
                                        color: AppColors.green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: Text(
                                  'PARENT / GUARDIAN',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    fontSize: 9,
                                    letterSpacing: 4,
                                    color: AppColors.textSub,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              Container(
                                height: 1,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.gold,
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Email read-only
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.cream,
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(
                                    color: AppColors.border.withOpacity(0.5),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'EMAIL ADDRESS',
                                      style: TextStyle(
                                        fontFamily: _bf,
                                        fontSize: 9,
                                        letterSpacing: 4,
                                        color: AppColors.gold.withOpacity(0.8),
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      _parentEmail.isEmpty
                                          ? 'Not set'
                                          : _parentEmail,
                                      style: TextStyle(
                                        fontFamily: _bf,
                                        fontSize: 14,
                                        letterSpacing: 0.5,
                                        color: AppColors.textSub,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Read-only · Contact admin to change',
                                      style: TextStyle(
                                        fontFamily: _bf,
                                        fontSize: 9,
                                        letterSpacing: 1,
                                        color: AppColors.textSub.withOpacity(
                                          0.6,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              _DashLuxuryField(
                                label: 'FULL NAME',
                                hint: 'Enter your full name',
                                controller: _profileNameCtrl,
                              ),
                              const SizedBox(height: 20),

                              _DashLuxuryField(
                                label: 'PHONE NUMBER',
                                hint: 'e.g. 09XXXXXXXXX',
                                controller: _profilePhoneCtrl,
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 32),

                              // Save button
                              SizedBox(
                                width: double.infinity,
                                child: Material(
                                  color: AppColors.green,
                                  child: InkWell(
                                    onTap: isSaving
                                        ? null
                                        : () async {
                                            setSheet(() => isSaving = true);
                                            await _saveProfile(
                                              _profileNameCtrl.text,
                                              _profilePhoneCtrl.text,
                                            );
                                            if (sheetCtx.mounted) {
                                              Navigator.pop(sheetCtx);
                                            }
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: AppColors.gold.withOpacity(
                                            0.65,
                                          ),
                                        ),
                                      ),
                                      child: isSaving
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: AppColors.gold,
                                              ),
                                            )
                                          : Text(
                                              'SAVE CHANGES',
                                              style: TextStyle(
                                                fontFamily: _bf,
                                                color: AppColors.white,
                                                letterSpacing: 4,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Center(
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(sheetCtx),
                                  child: Text(
                                    'CANCEL',
                                    style: TextStyle(
                                      fontFamily: _bf,
                                      fontSize: 9,
                                      letterSpacing: 3,
                                      color: AppColors.textSub,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _isProfileSheetOpen = false;
    }
  }

  // ─── LUXURY SETTINGS SHEET ─────────────────────────────────────

  Future<void> _showSettingsDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        bool localAlerts = _alertsEnabled;
        bool localSms = _smsAlertsEnabled;
        bool localEmail = _emailAlertsEnabled;
        bool isSaving = false;
        final childUidCtrl = TextEditingController(text: _childUid);

        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 1,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              AppColors.gold,
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PREFERENCES',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 6),
                            RichText(
                              text: const TextSpan(
                                style: TextStyle(
                                  fontFamily: _hf,
                                  fontSize: 34,
                                  height: 1.05,
                                  color: AppColors.green,
                                  fontWeight: FontWeight.w300,
                                ),
                                children: [
                                  TextSpan(text: 'Account\n'),
                                  TextSpan(
                                    text: 'Settings',
                                    style: TextStyle(
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.goldDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              height: 1,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppColors.gold, Colors.transparent],
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),

                            // Section: Notifications
                            Text(
                              'NOTIFICATIONS',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 14),

                            _DashSettingsTile(
                              title: 'Enable Alerts',
                              subtitle: 'Receive emergency notifications',
                              icon: Icons.notifications_outlined,
                              value: localAlerts,
                              onChanged: (v) => setSheet(() => localAlerts = v),
                            ),
                            const SizedBox(height: 10),

                            _DashSettingsTile(
                              title: 'SMS Alerts',
                              subtitle: 'Receive alerts via SMS',
                              icon: Icons.sms_outlined,
                              value: localSms,
                              onChanged: (v) => setSheet(() => localSms = v),
                            ),
                            const SizedBox(height: 10),

                            _DashSettingsTile(
                              title: 'Email Alerts',
                              subtitle: 'Receive alerts via email',
                              icon: Icons.email_outlined,
                              value: localEmail,
                              onChanged: (v) => setSheet(() => localEmail = v),
                            ),

                            const SizedBox(height: 22),

                            // Section: Child Link
                            Text(
                              'LINKED STUDENT',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Current child display
                            if (_childName.isNotEmpty && _childUid.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.green.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.gold.withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.green,
                                        border: Border.all(
                                          color: AppColors.gold,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          _childName.isNotEmpty
                                              ? _childName[0].toUpperCase()
                                              : 'S',
                                          style: const TextStyle(
                                            fontFamily: _hf,
                                            fontSize: 16,
                                            color: AppColors.gold,
                                            fontWeight: FontWeight.w300,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _childName,
                                          style: const TextStyle(
                                            fontFamily: _bf,
                                            fontSize: 14,
                                            letterSpacing: 0.5,
                                            color: AppColors.green,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          'Currently linked student',
                                          style: TextStyle(
                                            fontFamily: _bf,
                                            fontSize: 10,
                                            color: AppColors.textSub,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Spacer(),
                                    Icon(
                                      Icons.verified,
                                      color: AppColors.gold.withOpacity(0.7),
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 12),

                            _DashLuxuryField(
                              label: 'CHANGE STUDENT UID',
                              hint: 'Leave blank to keep current',
                              controller: childUidCtrl,
                            ),

                            const SizedBox(height: 28),

                            // Save button
                            SizedBox(
                              width: double.infinity,
                              child: Material(
                                color: AppColors.green,
                                child: InkWell(
                                  onTap: isSaving
                                      ? null
                                      : () async {
                                          setSheet(() => isSaving = true);
                                          await _saveSettings(
                                            alertsEnabled: localAlerts,
                                            smsAlertsEnabled: localSms,
                                            emailAlertsEnabled: localEmail,
                                            childUid:
                                                childUidCtrl.text.trim().isEmpty
                                                ? _childUid
                                                : childUidCtrl.text.trim(),
                                          );
                                          childUidCtrl.dispose();
                                          if (sheetCtx.mounted) {
                                            Navigator.pop(sheetCtx);
                                          }
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppColors.gold.withOpacity(0.65),
                                      ),
                                    ),
                                    child: isSaving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: AppColors.gold,
                                            ),
                                          )
                                        : Text(
                                            'SAVE SETTINGS',
                                            style: TextStyle(
                                              fontFamily: _bf,
                                              color: AppColors.white,
                                              letterSpacing: 4,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Center(
                              child: GestureDetector(
                                onTap: () => Navigator.pop(sheetCtx),
                                child: Text(
                                  'CANCEL',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    fontSize: 9,
                                    letterSpacing: 3,
                                    color: AppColors.textSub,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Handlers ─────────────────────────────────────────────────

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
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  // ─── BUILD ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.offWhite,
        body: Center(child: CircularProgressIndicator(color: AppColors.gold)),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: Stack(
        children: [
          // Background blobs
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withOpacity(0.07),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -80,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.green.withOpacity(0.05),
              ),
            ),
          ),
          // Top accent bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.green, AppColors.bright, AppColors.gold],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroCard(),
                  const SizedBox(height: 20),
                  _buildSectionLabel('CURRENT SESSION'),
                  const SizedBox(height: 10),
                  _buildSessionCard(),
                  const SizedBox(height: 20),
                  _buildSectionLabel('TOOLS'),
                  const SizedBox(height: 10),
                  _buildToolList(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF05412B), Color(0xFF042D1F)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.gold.withOpacity(0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.green,
                  border: Border.all(color: AppColors.gold, width: 1.4),
                ),
                child: Center(
                  child: Text(
                    'SW',
                    style: TextStyle(
                      fontFamily: _hf,
                      color: AppColors.gold,
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SafeWalk',
                    style: TextStyle(
                      fontFamily: _hf,
                      color: AppColors.white,
                      fontSize: 22,
                      height: 1,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  Text(
                    'PARENT / GUARDIAN',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.gold.withOpacity(0.7),
                      fontSize: 9,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E5B3C),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF2D8760)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, color: Color(0xFF5DF0A0), size: 7),
                    const SizedBox(width: 6),
                    Text(
                      'ONLINE',
                      style: TextStyle(
                        fontFamily: _bf,
                        color: const Color(0xFF5DF0A0),
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _logout,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF124733),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.gold.withOpacity(0.3),
                      width: 0.8,
                    ),
                  ),
                  child: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFF0F5F2),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Good morning,',
            style: TextStyle(
              fontFamily: _bf,
              color: AppColors.white.withOpacity(0.7),
              fontSize: 13,
              letterSpacing: 1,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _parentName,
            style: TextStyle(
              fontFamily: _hf,
              color: AppColors.gold,
              fontSize: 44,
              height: 1,
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusPill(
                label: _childSessionActive
                    ? 'Student Online'
                    : 'Student Offline',
                dotColor: _childSessionActive
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFFF7F7F),
              ),
              _StatusPill(
                label: _deviceId == 'Not linked'
                    ? 'Device Unlinked'
                    : 'Device Linked',
                dotColor: _deviceId == 'Not linked'
                    ? const Color(0xFFFF7F7F)
                    : AppColors.goldLt,
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
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: _bf,
            color: AppColors.textSub,
            fontSize: 9,
            letterSpacing: 4,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.gold.withOpacity(0.3), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Safe Walk',
                      style: TextStyle(
                        fontFamily: _hf,
                        color: AppColors.green,
                        fontSize: 36,
                        height: 1,
                        fontWeight: FontWeight.w300,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      'Session',
                      style: TextStyle(
                        fontFamily: _hf,
                        color: AppColors.goldDark,
                        fontSize: 28,
                        height: 1.1,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _childSessionActive
                          ? 'Monitoring $_childName'
                          : 'No active walk session',
                      style: TextStyle(
                        fontFamily: _bf,
                        color: AppColors.textSub,
                        fontSize: 11,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8F6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 7,
                      color: _childSessionActive
                          ? const Color(0xFF60CC8A)
                          : const Color(0xFFFF7F7F),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _childSessionActive ? 'Active' : 'Inactive',
                      style: TextStyle(
                        fontFamily: _bf,
                        color: AppColors.green,
                        fontSize: 11,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.border,
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _showSessionDetailsDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.gold.withOpacity(0.5)),
                  ),
                  child: Text(
                    'VIEW DETAILS',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.white,
                      fontSize: 11,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
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
      children: _tools.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => _handleToolTap(item.title),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: item.iconBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, color: item.iconColor, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontFamily: _bf,
                            color: AppColors.green,
                            fontSize: 14,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            fontFamily: _bf,
                            color: AppColors.textSub,
                            fontSize: 11,
                            letterSpacing: 0.3,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.offWhite,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSub,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: AppColors.gold.withOpacity(0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
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
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.green.withOpacity(0.1)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: AppColors.gold.withOpacity(0.3),
                                  width: 0.5,
                                )
                              : null,
                        ),
                        child: Icon(
                          item.icon,
                          size: 20,
                          color: selected
                              ? AppColors.green
                              : const Color(0xFFA6A49D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontFamily: _bf,
                          color: selected
                              ? AppColors.green
                              : const Color(0xFFA6A49D),
                          fontSize: 9,
                          letterSpacing: 1,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w300,
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

// ─────────────────────────────────────────────────────────────────
//  Data models
// ─────────────────────────────────────────────────────────────────

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
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

// ─────────────────────────────────────────────────────────────────
//  Reusable Widgets
// ─────────────────────────────────────────────────────────────────

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
            fontFamily: 'CormorantGaramond',
            color: AppColors.green,
            fontSize: 32,
            height: 1,
            fontWeight: FontWeight.w300,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'JosefinSans',
            color: AppColors.textSub,
            fontSize: 9,
            letterSpacing: 3,
            fontWeight: FontWeight.w300,
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
        border: Border.all(color: AppColors.gold.withOpacity(0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: dotColor, size: 6),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'JosefinSans',
              color: Color(0xFFEAF2ED),
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertBadge extends StatelessWidget {
  final String label;
  final bool isActive;
  const _AlertBadge({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFFCB392B).withOpacity(0.1)
            : AppColors.cream,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? const Color(0xFFCB392B).withOpacity(0.3)
              : AppColors.border,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'JosefinSans',
          fontSize: 9,
          letterSpacing: 2,
          color: isActive ? const Color(0xFFCB392B) : AppColors.textSub,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Luxury Input Field (matches login page style)
// ─────────────────────────────────────────────────────────────────

class _DashLuxuryField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final bool obscure;
  final Widget? suffixIcon;

  const _DashLuxuryField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.suffixIcon,
  });

  @override
  State<_DashLuxuryField> createState() => _DashLuxuryFieldState();
}

class _DashLuxuryFieldState extends State<_DashLuxuryField>
    with SingleTickerProviderStateMixin {
  late AnimationController _lineAnim;
  late Animation<double> _lineWidth;

  @override
  void initState() {
    super.initState();
    _lineAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _lineWidth = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _lineAnim, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _lineAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) =>
          hasFocus ? _lineAnim.forward() : _lineAnim.reverse(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              fontFamily: 'JosefinSans',
              fontSize: 9,
              letterSpacing: 4,
              color: AppColors.gold,
              fontWeight: FontWeight.w300,
            ),
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: AppColors.border.withOpacity(0.6),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  keyboardType: widget.keyboardType,
                  obscureText: widget.obscure,
                  style: const TextStyle(
                    fontFamily: 'JosefinSans',
                    fontSize: 14,
                    letterSpacing: 1,
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w300,
                  ),
                  cursorColor: AppColors.gold,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    hintStyle: TextStyle(
                      fontFamily: 'JosefinSans',
                      color: AppColors.textSub.withOpacity(0.45),
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
                    suffixIcon: widget.suffixIcon,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _lineWidth,
                  builder: (_, __) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _lineWidth.value,
                      child: Container(height: 1.2, color: AppColors.gold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
//  Luxury Settings Toggle Tile
// ─────────────────────────────────────────────────────────────────

class _DashSettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DashSettingsTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: value ? AppColors.green.withOpacity(0.04) : AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? AppColors.gold.withOpacity(0.5) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: value ? AppColors.green : AppColors.cream,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: value
                    ? AppColors.gold.withOpacity(0.4)
                    : AppColors.border,
                width: 0.8,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: value ? AppColors.gold : AppColors.textSub,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'JosefinSans',
                    fontSize: 13,
                    letterSpacing: 0.5,
                    color: value ? AppColors.green : AppColors.textMain,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'JosefinSans',
                    fontSize: 10,
                    letterSpacing: 0.3,
                    color: AppColors.textSub,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.gold,
            activeTrackColor: AppColors.green.withOpacity(0.4),
            inactiveThumbColor: AppColors.textSub,
            inactiveTrackColor: AppColors.cream,
          ),
        ],
      ),
    );
  }
}
