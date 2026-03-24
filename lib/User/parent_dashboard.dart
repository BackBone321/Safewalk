import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../auth/auth_service.dart';
import '../login_dashboard/login_page.dart';
import '../utils/google_maps_web_guard.dart';

class ParentDashboardPage extends StatefulWidget {
  const ParentDashboardPage({super.key});

  @override
  State<ParentDashboardPage> createState() => _ParentDashboardPageState();
}

class _ParentDashboardPageState extends State<ParentDashboardPage> {
  int _selectedNavIndex = 0;
  static const String _hf = 'CormorantGaramond';
  static const String _bf = 'JosefinSans';
  static const LatLng _defaultMapCenter = LatLng(14.5995, 120.9842);

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isProfileSheetOpen = false;

  final TextEditingController _profileNameCtrl = TextEditingController();
  final TextEditingController _profilePhoneCtrl = TextEditingController();

  String _parentName = 'Parent';
  String _parentEmail = '';
  String _parentPhone = '';
  String _parentUid = '';
  List<_LinkedStudent> _linkedStudents = const [];

  String _childUid = '';
  String _childName = 'Student';
  String _childPhone = '';
  String _childRoute = 'Main Campus -> Dorm Block C';
  bool _childSessionActive = false;
  double _childDistanceKm = 1.2;

  String _deviceId = 'Not linked';
  String _deviceName = 'No linked device';
  String _deviceLocation = 'Unknown';
  String _deviceStatus = 'offline';
  LatLng? _childDeviceCoordinates;

  bool _alertsEnabled = true;
  bool _smsAlertsEnabled = true;
  bool _emailAlertsEnabled = true;

  bool get _mobileMapLiteMode =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
    _NavItem('Settings', Icons.settings_outlined),
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

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  bool _isValidLatLng(double lat, double lng) {
    return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  LatLng? _coordinatesFromValues(dynamic latValue, dynamic lngValue) {
    final lat = _toDouble(latValue);
    final lng = _toDouble(lngValue);
    if (lat == null || lng == null) return null;
    if (!_isValidLatLng(lat, lng)) return null;
    return LatLng(lat, lng);
  }

  LatLng? _coordinatesFromText(String text) {
    final match = RegExp(
      r'(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)',
    ).firstMatch(text);
    if (match == null) return null;
    final lat = double.tryParse(match.group(1) ?? '');
    final lng = double.tryParse(match.group(2) ?? '');
    if (lat == null || lng == null) return null;
    if (!_isValidLatLng(lat, lng)) return null;
    return LatLng(lat, lng);
  }

  LatLng? _extractDeviceCoordinates(Map<String, dynamic> data) {
    final direct = _coordinatesFromValues(
      data['latitude'] ?? data['lat'],
      data['longitude'] ?? data['lng'] ?? data['lon'],
    );
    if (direct != null) return direct;

    final coordinates = data['coordinates'];
    if (coordinates is Map) {
      final nested = _coordinatesFromValues(
        coordinates['latitude'] ?? coordinates['lat'],
        coordinates['longitude'] ?? coordinates['lng'] ?? coordinates['lon'],
      );
      if (nested != null) return nested;
    }

    final location = data['location'];
    if (location is GeoPoint) {
      return LatLng(location.latitude, location.longitude);
    }
    if (location is String) {
      final parsed = _coordinatesFromText(location);
      if (parsed != null) return parsed;
    }

    return null;
  }

  LatLng? _extractAlertCoordinates(Map<String, dynamic> data) {
    final coordinates = data['coordinates'];
    if (coordinates is GeoPoint) {
      return LatLng(coordinates.latitude, coordinates.longitude);
    }
    if (coordinates is Map) {
      final nested = _coordinatesFromValues(
        coordinates['latitude'] ?? coordinates['lat'],
        coordinates['longitude'] ?? coordinates['lng'] ?? coordinates['lon'],
      );
      if (nested != null) return nested;
    }

    final direct = _coordinatesFromValues(
      data['latitude'] ?? data['lat'],
      data['longitude'] ?? data['lng'] ?? data['lon'],
    );
    if (direct != null) return direct;

    final location = data['location'];
    if (location is String) {
      return _coordinatesFromText(location);
    }
    return null;
  }

  LatLng get _childMapCenter => _childDeviceCoordinates ?? _defaultMapCenter;

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

  Widget _buildWebMapFallback({required String contextLabel}) {
    return Container(
      color: const Color(0xFF830C0C),
      padding: const EdgeInsets.all(14),
      alignment: Alignment.centerLeft,
      child: Text(
        'Google Maps is not ready on Web.\n'
        'Set your API key in web/index.html and reload.\n'
        'Context: $contextLabel',
        style: const TextStyle(
          fontFamily: _bf,
          color: Color(0xFFFFF1B8),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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
      final parentData = parentDoc.data() ?? <String, dynamic>{};
      final parentPhone = (parentData['phoneNumber'] ?? '').toString();
      final normalizedParentPhone = _normalizePhoneForLookup(parentPhone);
      if (!mounted) return;
      setState(() {
        _parentUid = currentUser.uid;
        _parentName = (parentData['fullName'] ?? 'Parent').toString();
        _parentEmail = (parentData['email'] ?? '').toString();
        _parentPhone = parentPhone;
        _alertsEnabled =
            (settingsDoc.data()?['alertsEnabled'] as bool?) ?? true;
        _smsAlertsEnabled =
            (settingsDoc.data()?['smsAlertsEnabled'] as bool?) ?? true;
        _emailAlertsEnabled =
            (settingsDoc.data()?['emailAlertsEnabled'] as bool?) ?? true;
      });

      final linkedStudents = await _fetchLinkedStudents(
        parentUid: currentUser.uid,
        normalizedParentPhone: normalizedParentPhone,
      );
      if (!mounted) return;
      setState(() => _linkedStudents = linkedStudents);

      String configuredChildUid = (settingsDoc.data()?['childUid'] ?? '')
          .toString()
          .trim();
      final hasConfiguredChild = linkedStudents.any(
        (student) => student.uid == configuredChildUid,
      );
      if (!hasConfiguredChild) {
        configuredChildUid = linkedStudents.isNotEmpty
            ? linkedStudents.first.uid
            : '';
      }

      if (configuredChildUid.isNotEmpty) {
        await _loadChildData(configuredChildUid);
      } else if (mounted) {
        setState(() {
          _childUid = '';
          _childName = 'Student';
          _childPhone = '';
          _childRoute = 'Main Campus -> Dorm Block C';
          _childSessionActive = false;
          _childDistanceKm = 0;
          _deviceId = 'Not linked';
          _deviceName = 'No linked device';
          _deviceLocation = 'Unknown';
          _deviceStatus = 'offline';
          _childDeviceCoordinates = null;
        });
      }
    } catch (e) {
      _showActionSnack('Failed to load parent dashboard: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<_LinkedStudent>> _fetchLinkedStudents({
    required String parentUid,
    required String normalizedParentPhone,
  }) async {
    if (parentUid.trim().isEmpty) return const [];

    final byUid = await _firestore
        .collection('parent_student_links')
        .where('parentUid', isEqualTo: parentUid)
        .limit(100)
        .get();

    final byPhone = byUid.docs.isEmpty && normalizedParentPhone.isNotEmpty
        ? await _firestore
              .collection('parent_student_links')
              .where('parentPhoneNormalized', isEqualTo: normalizedParentPhone)
              .limit(100)
              .get()
        : null;

    final docs = byUid.docs.isNotEmpty
        ? byUid.docs
        : (byPhone?.docs ?? const []);
    final uniqueByStudentUid = <String, _LinkedStudent>{};

    for (final doc in docs) {
      final data = doc.data();
      final status = (data['status'] ?? 'accepted').toString().toLowerCase();
      if (status != 'accepted') continue;

      final studentUid = (data['studentUid'] ?? '').toString().trim();
      if (studentUid.isEmpty) continue;

      var studentName = (data['studentName'] ?? '').toString().trim();
      var studentPhone = (data['studentPhone'] ?? '').toString().trim();
      if (studentName.isEmpty || studentPhone.isEmpty) {
        final studentDoc = await _firestore
            .collection('users')
            .doc(studentUid)
            .get();
        if (studentDoc.exists) {
          studentName = studentName.isEmpty
              ? (studentDoc.data()?['fullName'] ?? 'Student').toString()
              : studentName;
          studentPhone = studentPhone.isEmpty
              ? (studentDoc.data()?['phoneNumber'] ?? '').toString()
              : studentPhone;
        }
      }

      uniqueByStudentUid[studentUid] = _LinkedStudent(
        uid: studentUid,
        name: studentName.isEmpty ? 'Student' : studentName,
        phone: studentPhone,
      );
    }

    final result = uniqueByStudentUid.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<void> _sendStudentInvitation({required String studentUid}) async {
    final parentUid = FirebaseAuth.instance.currentUser?.uid;
    if (parentUid == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }

    final targetUid = studentUid.trim();
    if (targetUid.isEmpty) {
      _showActionSnack('Enter a Student UID or phone number.', isError: true);
      return;
    }

    final studentDoc = await _firestore
        .collection('users')
        .doc(targetUid)
        .get();
    if (!studentDoc.exists) {
      _showActionSnack('Student account not found.', isError: true);
      return;
    }
    final role = (studentDoc.data()?['role'] ?? '').toString().toLowerCase();
    if (role != 'student') {
      _showActionSnack('That UID is not a student account.', isError: true);
      return;
    }

    final linkId = '${parentUid}_$targetUid';
    final linkDoc = await _firestore
        .collection('parent_student_links')
        .doc(linkId)
        .get();
    final linkStatus = (linkDoc.data()?['status'] ?? 'accepted')
        .toString()
        .toLowerCase();
    if (linkDoc.exists && linkStatus == 'accepted') {
      _showActionSnack('Student is already linked to your account.');
      return;
    }

    final studentData = studentDoc.data() ?? <String, dynamic>{};
    final studentName = (studentData['fullName'] ?? 'Student').toString();
    final studentPhone = (studentData['phoneNumber'] ?? '').toString();
    final parentPhone = _parentPhone.trim();

    await _firestore.collection('parent_student_invitations').doc(linkId).set({
      'parentUid': parentUid,
      'parentName': _parentName.trim(),
      'parentPhone': parentPhone,
      'parentPhoneNormalized': _normalizePhoneForLookup(parentPhone),
      'studentUid': targetUid,
      'studentName': studentName,
      'studentPhone': studentPhone,
      'studentPhoneNormalized': _normalizePhoneForLookup(studentPhone),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    _showActionSnack('Invitation sent to $studentName.');
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
      _childPhone = childPhone;

      if (walkQuery.docs.isNotEmpty) {
        final walkData = walkQuery.docs.first.data();
        _childSessionActive = true;
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
        final locationField = device['location'];
        _deviceLocation = locationField is GeoPoint
            ? '${locationField.latitude.toStringAsFixed(6)}, ${locationField.longitude.toStringAsFixed(6)}'
            : (locationField ?? 'Unknown').toString();
        _deviceStatus = (device['status'] ?? 'active').toString().toLowerCase();
        _childDeviceCoordinates = _extractDeviceCoordinates(device);
      } else {
        _deviceId = 'Not linked';
        _deviceName = 'No linked device';
        _deviceLocation = 'Unknown';
        _deviceStatus = 'offline';
        _childDeviceCoordinates = null;
      }
    });
  }

  Future<String> _resolveStudentUidFromPhone(String inputPhone) async {
    final rawPhone = inputPhone.trim();
    if (rawPhone.isEmpty) return '';
    final normalizedPhone = _normalizePhoneForLookup(rawPhone);

    var query = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'student')
        .where('phoneNumber', isEqualTo: rawPhone)
        .limit(1)
        .get();

    if (query.docs.isEmpty && normalizedPhone != rawPhone) {
      query = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'student')
          .where('phoneNumber', isEqualTo: normalizedPhone)
          .limit(1)
          .get();
    }

    if (query.docs.isEmpty) return '';
    return query.docs.first.id;
  }

  // ─── Save Methods ──────────────────────────────────────────────

  Future<void> _saveProfile(String fullName, String phoneNumber) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
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
    }
  }

  Future<void> _saveSettings({
    required bool alertsEnabled,
    required bool smsAlertsEnabled,
    required bool emailAlertsEnabled,
    required String childUid,
    String childPhoneNumber = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    try {
      await _firestore.collection('user_settings').doc(uid).set({
        'alertsEnabled': alertsEnabled,
        'smsAlertsEnabled': smsAlertsEnabled,
        'emailAlertsEnabled': emailAlertsEnabled,
        'childUid': childUid.trim(),
        'childPhoneNumber': childPhoneNumber.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _alertsEnabled = alertsEnabled;
        _smsAlertsEnabled = smsAlertsEnabled;
        _emailAlertsEnabled = emailAlertsEnabled;
      });
      final resolvedChildUid = childUid.trim();
      if (resolvedChildUid.isNotEmpty && resolvedChildUid != _childUid) {
        await _loadChildData(resolvedChildUid);
      } else if (resolvedChildUid.isEmpty) {
        setState(() {
          _childUid = '';
          _childName = 'Student';
          _childPhone = '';
          _childSessionActive = false;
          _childDistanceKm = 0;
          _deviceId = 'Not linked';
          _deviceName = 'No linked device';
          _deviceLocation = 'Unknown';
          _deviceStatus = 'offline';
          _childDeviceCoordinates = null;
        });
      }
      _showActionSnack('Settings saved.');
    } catch (e) {
      _showActionSnack('Failed to save settings: $e', isError: true);
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
        _InfoRow('Route', _childRoute),
        _InfoRow('Distance', '${_childDistanceKm.toStringAsFixed(1)} km'),
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
                                  color: AppColors.gold.withValues(alpha: 0.65),
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
                          .where(
                            'parentUid',
                            isEqualTo: _parentUid.isEmpty
                                ? FirebaseAuth.instance.currentUser?.uid ?? ''
                                : _parentUid,
                          )
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
                                  color: AppColors.gold.withValues(alpha: 0.4),
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
                                        ).withValues(alpha: 0.35)
                                      : AppColors.border,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
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
                                                    .withValues(alpha: 0.4),
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
                                            color: AppColors.green.withValues(alpha: 
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
                                    color: AppColors.border.withValues(alpha: 0.5),
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
                                        color: AppColors.gold.withValues(alpha: 0.8),
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
                                        color: AppColors.textSub.withValues(alpha: 
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
                                          color: AppColors.gold.withValues(alpha: 
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
    final inviteStudentUidCtrl = TextEditingController();
    final inviteStudentPhoneCtrl = TextEditingController();
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetCtx) {
          bool localAlerts = _alertsEnabled;
          bool localSms = _smsAlertsEnabled;
          bool localEmail = _emailAlertsEnabled;
          bool isSaving = false;
          bool isSendingInvite = false;
          String selectedChildUid = _childUid;

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
                                    colors: [
                                      AppColors.gold,
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
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
                                onChanged: (v) =>
                                    setSheet(() => localAlerts = v),
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
                                onChanged: (v) =>
                                    setSheet(() => localEmail = v),
                              ),
                              const SizedBox(height: 22),
                              Text(
                                'LINKED STUDENTS',
                                style: TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 9,
                                  letterSpacing: 4,
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_linkedStudents.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Text(
                                    'No linked students yet. Send an invitation below.',
                                    style: TextStyle(
                                      fontFamily: _bf,
                                      fontSize: 11,
                                      color: AppColors.textSub,
                                    ),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _linkedStudents.map((student) {
                                    final selected =
                                        selectedChildUid == student.uid;
                                    final shortUid = student.uid.length > 6
                                        ? student.uid.substring(0, 6)
                                        : student.uid;
                                    return ChoiceChip(
                                      label: Text(
                                        '${student.name} - $shortUid',
                                        style: TextStyle(
                                          fontFamily: _bf,
                                          fontSize: 10,
                                          color: selected
                                              ? AppColors.white
                                              : AppColors.green,
                                        ),
                                      ),
                                      selected: selected,
                                      onSelected: (_) => setSheet(
                                        () => selectedChildUid = student.uid,
                                      ),
                                      selectedColor: AppColors.green,
                                      backgroundColor: AppColors.white,
                                      side: BorderSide(
                                        color: selected
                                            ? AppColors.gold.withValues(alpha: 0.6)
                                            : AppColors.border,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              const SizedBox(height: 16),
                              Text(
                                'INVITE STUDENT',
                                style: TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 9,
                                  letterSpacing: 4,
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _DashLuxuryField(
                                label: 'STUDENT UID',
                                hint: 'Enter student UID',
                                controller: inviteStudentUidCtrl,
                              ),
                              const SizedBox(height: 12),
                              _DashLuxuryField(
                                label: 'OR STUDENT PHONE NUMBER',
                                hint: 'Example: +63 9XXXXXXXXX',
                                controller: inviteStudentPhoneCtrl,
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Student must accept this invitation from their dashboard.',
                                style: TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 10,
                                  color: AppColors.textSub,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: isSendingInvite
                                      ? null
                                      : () async {
                                          setSheet(
                                            () => isSendingInvite = true,
                                          );
                                          try {
                                            final enteredUid =
                                                inviteStudentUidCtrl.text
                                                    .trim();
                                            final enteredPhone =
                                                inviteStudentPhoneCtrl.text
                                                    .trim();
                                            String targetUid = enteredUid;
                                            if (targetUid.isEmpty &&
                                                enteredPhone.isNotEmpty) {
                                              targetUid =
                                                  await _resolveStudentUidFromPhone(
                                                    enteredPhone,
                                                  );
                                            }
                                            if (targetUid.isEmpty) {
                                              _showActionSnack(
                                                'Enter a valid student UID or phone number.',
                                                isError: true,
                                              );
                                              return;
                                            }
                                            await _sendStudentInvitation(
                                              studentUid: targetUid,
                                            );
                                            await _loadDashboard();
                                            if (!sheetCtx.mounted) return;
                                            setSheet(() {
                                              if (selectedChildUid.isEmpty &&
                                                  _linkedStudents.isNotEmpty) {
                                                selectedChildUid =
                                                    _linkedStudents.first.uid;
                                              }
                                              inviteStudentUidCtrl.clear();
                                              inviteStudentPhoneCtrl.clear();
                                            });
                                          } finally {
                                            if (sheetCtx.mounted) {
                                              setSheet(
                                                () => isSendingInvite = false,
                                              );
                                            }
                                          }
                                        },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.green,
                                    side: BorderSide(
                                      color: AppColors.gold.withValues(alpha: 0.55),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                  child: isSendingInvite
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'SEND INVITATION',
                                          style: TextStyle(
                                            fontFamily: _bf,
                                            fontSize: 11,
                                            letterSpacing: 2.2,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 28),
                              SizedBox(
                                width: double.infinity,
                                child: Material(
                                  color: AppColors.green,
                                  child: InkWell(
                                    onTap: isSaving
                                        ? null
                                        : () async {
                                            setSheet(() => isSaving = true);
                                            String selectedPhone = '';
                                            for (final student
                                                in _linkedStudents) {
                                              if (student.uid ==
                                                  selectedChildUid) {
                                                selectedPhone = student.phone;
                                                break;
                                              }
                                            }
                                            await _saveSettings(
                                              alertsEnabled: localAlerts,
                                              smsAlertsEnabled: localSms,
                                              emailAlertsEnabled: localEmail,
                                              childUid: selectedChildUid,
                                              childPhoneNumber: selectedPhone,
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
                                          color: AppColors.gold.withValues(alpha: 
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
    } finally {
      inviteStudentUidCtrl.dispose();
      inviteStudentPhoneCtrl.dispose();
    }
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
        setState(() => _selectedNavIndex = 3);
        return;
      case 'Settings':
        setState(() => _selectedNavIndex = 4);
        return;
      default:
        _showActionSnack('$title tapped');
    }
  }

  Future<void> _onBottomNavTap(int index) async {
    setState(() => _selectedNavIndex = index);
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
                color: AppColors.gold.withValues(alpha: 0.07),
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
                color: AppColors.green.withValues(alpha: 0.05),
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
              child: _buildCurrentTabContent(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_selectedNavIndex) {
      case 1:
        return _buildChildTab();
      case 2:
        return _buildAlertsTab();
      case 3:
        return _buildProfileTab();
      case 4:
        return _buildSettingsTab();
      case 0:
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildHomeTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 20),
        _buildSectionLabel('TOOLS'),
        const SizedBox(height: 10),
        _buildToolList(),
      ],
    );
  }

  Widget _buildChildTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 18),
        _buildSectionLabel('CHILD LOCATION'),
        const SizedBox(height: 10),
        _buildChildMapCard(),
        const SizedBox(height: 16),
        _buildSectionLabel('LINKED DEVICE'),
        const SizedBox(height: 10),
        _buildDashboardPanel(
          title: 'Child & Device',
          subtitle: 'TRACKING OVERVIEW',
          children: [
            _buildDashboardRow('Child', _childName),
            const SizedBox(height: 8),
            _buildDashboardRow('Device', _deviceName),
            const SizedBox(height: 8),
            _buildDashboardRow('Device Status', _deviceStatus.toUpperCase()),
            const SizedBox(height: 8),
            _buildDashboardRow('Location', _deviceLocation),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPanelAction(
                    label: 'CHILD STATUS',
                    onTap: _showChildStatusDialog,
                  ),
                  _buildPanelAction(
                    label: 'DEVICE INFO',
                    onTap: _showDeviceDialog,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAlertsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 18),
        _buildSectionLabel('ALERTS'),
        const SizedBox(height: 10),
        _buildDashboardPanel(
          title: 'Alert Controls',
          subtitle: 'PARENT NOTIFICATIONS',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AlertBadge(
                  label: _alertsEnabled ? 'ALERTS ON' : 'ALERTS OFF',
                  isActive: _alertsEnabled,
                ),
                _AlertBadge(
                  label: _smsAlertsEnabled ? 'SMS ON' : 'SMS OFF',
                  isActive: _smsAlertsEnabled,
                ),
                _AlertBadge(
                  label: _emailAlertsEnabled ? 'EMAIL ON' : 'EMAIL OFF',
                  isActive: _emailAlertsEnabled,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildDashboardRow('Current Route', _childRoute),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPanelAction(
                    label: 'ALERT HISTORY',
                    onTap: _showAlertHistorySheet,
                  ),
                  _buildPanelAction(
                    label: 'ALERT SETTINGS',
                    onTap: _showSettingsDialog,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChildMapCard() {
    final parentUidForAlerts = _parentUid.isEmpty
        ? FirebaseAuth.instance.currentUser?.uid ?? ''
        : _parentUid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _childUid.isEmpty
          ? null
          : _firestore
                .collection('emergency_alerts')
                .where('uid', isEqualTo: _childUid)
                .limit(60)
                .snapshots(),
      builder: (context, snapshot) {
        LatLng? latestSosCoordinate;
        String latestSosLabel = '';
        bool sosIsActive = false;

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final docs =
              snapshot.data!.docs.where((doc) {
                final data = doc.data();
                final alertType = (data['type'] ?? '').toString().toLowerCase();
                final alertParentUid = (data['parentUid'] ?? '').toString();
                return alertType == 'sos' &&
                    (alertParentUid.isEmpty ||
                        alertParentUid == parentUidForAlerts);
              }).toList()..sort((a, b) {
                final aTs = a.data()['timestamp'] as Timestamp?;
                final bTs = b.data()['timestamp'] as Timestamp?;
                return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(
                  aTs?.millisecondsSinceEpoch ?? 0,
                );
              });

          if (docs.isNotEmpty) {
            final latest = docs.first.data();
            latestSosCoordinate = _extractAlertCoordinates(latest);
            sosIsActive =
                (latest['status'] ?? '').toString().toLowerCase() == 'active';
            latestSosLabel = _formatTimestamp(
              latest['timestamp'] as Timestamp?,
            );
          }
        }

        final mapPoint = latestSosCoordinate ?? _childDeviceCoordinates;
        final center = mapPoint ?? _childMapCenter;
        final hasPoint = mapPoint != null;

        final markers = hasPoint
            ? {
                Marker(
                  markerId: const MarkerId('child-location'),
                  position: mapPoint,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    sosIsActive
                        ? BitmapDescriptor.hueRed
                        : BitmapDescriptor.hueAzure,
                  ),
                  infoWindow: InfoWindow(
                    title: sosIsActive ? 'SOS Location' : 'Child Location',
                    snippet: _deviceLocation,
                  ),
                ),
              }
            : <Marker>{};

        final circles = hasPoint
            ? {
                Circle(
                  circleId: const CircleId('child-radius'),
                  center: mapPoint,
                  radius: sosIsActive ? 90 : 45,
                  fillColor: sosIsActive
                      ? const Color(0x55CB392B)
                      : const Color(0x331AA972),
                  strokeColor: sosIsActive
                      ? const Color(0xFFCB392B)
                      : const Color(0xFF1AA972),
                  strokeWidth: 2,
                ),
              }
            : <Circle>{};

        return Container(
          height: 240,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: kIsWeb && !isGoogleMapsJsLoaded()
                      ? _buildWebMapFallback(
                          contextLabel: 'Parent Child Tracking Card',
                        )
                      : GoogleMap(
                          key: ValueKey(
                            'parent-map-${center.latitude}-${center.longitude}-${sosIsActive ? 'sos' : 'track'}',
                          ),
                          initialCameraPosition: CameraPosition(
                            target: center,
                            zoom: hasPoint ? 16 : 12,
                          ),
                          liteModeEnabled: _mobileMapLiteMode,
                          mapType: MapType.normal,
                          markers: markers,
                          circles: circles,
                          myLocationEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          compassEnabled: false,
                          rotateGesturesEnabled: false,
                          tiltGesturesEnabled: false,
                          onMapCreated: (_) {},
                        ),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: sosIsActive
                        ? const Color(0xFF7E1F14)
                        : const Color(0xFF0E5B3C),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    sosIsActive
                        ? 'SOS LOCATION'
                        : hasPoint
                        ? 'LIVE TRACKING'
                        : 'NO LOCATION YET',
                    style: const TextStyle(
                      fontFamily: _bf,
                      color: AppColors.gold,
                      fontSize: 9,
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.02),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sosIsActive
                            ? 'SOS RECEIVED ${latestSosLabel.isEmpty ? '' : '• $latestSosLabel'}'
                            : 'CHILD LAST LOCATION',
                        style: const TextStyle(
                          fontFamily: _bf,
                          color: AppColors.gold,
                          fontSize: 9,
                          letterSpacing: 2.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _deviceLocation,
                        style: const TextStyle(
                          fontFamily: _bf,
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileTab() {
    final linkedPreview = _linkedStudents.isEmpty
        ? 'None'
        : _linkedStudents.take(3).map((student) => student.name).join(', ') +
              (_linkedStudents.length > 3
                  ? ' +${_linkedStudents.length - 3} more'
                  : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 18),
        _buildSectionLabel('PARENT PROFILE'),
        const SizedBox(height: 10),
        _buildDashboardPanel(
          title: _parentName,
          subtitle: 'ACCOUNT DETAILS',
          children: [
            _buildDashboardRow(
              'Email',
              _parentEmail.isEmpty ? '-' : _parentEmail,
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Phone',
              _parentPhone.isEmpty ? '-' : _parentPhone,
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Connected Students',
              _linkedStudents.length.toString(),
            ),
            const SizedBox(height: 8),
            _buildDashboardRow('Student List', linkedPreview),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Active Student',
              _childName.isEmpty ? 'Not set' : _childName,
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Active Student UID',
              _childUid.isEmpty ? 'Not set' : _childUid,
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Active Student Phone',
              _childPhone.isEmpty ? 'Not set' : _childPhone,
            ),
            const SizedBox(height: 14),
            _buildPanelAction(label: 'EDIT PROFILE', onTap: _showProfileDialog),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    final linkedPreview = _linkedStudents.isEmpty
        ? 'None'
        : _linkedStudents.take(3).map((student) => student.name).join(', ') +
              (_linkedStudents.length > 3
                  ? ' +${_linkedStudents.length - 3} more'
                  : '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 18),
        _buildSectionLabel('SETTINGS'),
        const SizedBox(height: 10),
        _buildDashboardPanel(
          title: 'Preferences',
          subtitle: 'PARENT CONTROL PANEL',
          children: [
            _buildDashboardRow(
              'Global Alerts',
              _alertsEnabled ? 'Enabled' : 'Disabled',
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'SMS Alerts',
              _smsAlertsEnabled ? 'Enabled' : 'Disabled',
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Email Alerts',
              _emailAlertsEnabled ? 'Enabled' : 'Disabled',
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Connected Students',
              _linkedStudents.length.toString(),
            ),
            const SizedBox(height: 8),
            _buildDashboardRow('Student List', linkedPreview),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Active Student Name',
              _childName.isEmpty ? 'Not set' : _childName,
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Active Student UID',
              _childUid.isEmpty ? 'Not set' : _childUid,
            ),
            const SizedBox(height: 8),
            _buildDashboardRow(
              'Active Student Phone',
              _childPhone.isEmpty ? 'Not set' : _childPhone,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPanelAction(
                    label: 'OPEN SETTINGS',
                    onTap: _showSettingsDialog,
                  ),
                  _buildPanelAction(
                    label: 'REFRESH DATA',
                    onTap: _loadDashboard,
                    isPrimary: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDashboardPanel({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: TextStyle(
              fontFamily: _bf,
              color: AppColors.goldDark,
              fontSize: 9,
              letterSpacing: 3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontFamily: _hf,
              color: AppColors.green,
              fontSize: 30,
              height: 1,
              fontWeight: FontWeight.w300,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.border, Colors.transparent],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDashboardRow(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: _bf,
              color: AppColors.textSub,
              fontSize: 10,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: _bf,
                color: AppColors.green,
                fontSize: 11,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelAction({
    required String label,
    required Future<void> Function() onTap,
    bool isPrimary = true,
  }) {
    return Material(
      color: isPrimary ? AppColors.green : AppColors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isPrimary
                  ? AppColors.gold.withValues(alpha: 0.45)
                  : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: _bf,
              color: isPrimary ? AppColors.white : AppColors.green,
              fontSize: 10,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
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
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.25), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withValues(alpha: 0.25),
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
                      color: AppColors.gold.withValues(alpha: 0.7),
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
                      color: AppColors.gold.withValues(alpha: 0.3),
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
              color: AppColors.white.withValues(alpha: 0.7),
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
                colors: [AppColors.gold.withValues(alpha: 0.3), Colors.transparent],
              ),
            ),
          ),
        ),
      ],
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
                    color: Colors.black.withValues(alpha: 0.04),
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
            color: AppColors.gold.withValues(alpha: 0.06),
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
                              ? AppColors.green.withValues(alpha: 0.1)
                              : Colors.transparent,
                          shape: BoxShape.circle,
                          border: selected
                              ? Border.all(
                                  color: AppColors.gold.withValues(alpha: 0.3),
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

class _LinkedStudent {
  final String uid;
  final String name;
  final String phone;

  const _LinkedStudent({
    required this.uid,
    required this.name,
    required this.phone,
  });
}

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
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.25), width: 0.8),
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
            ? const Color(0xFFCB392B).withValues(alpha: 0.1)
            : AppColors.cream,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? const Color(0xFFCB392B).withValues(alpha: 0.3)
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

  const _DashLuxuryField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType = TextInputType.text,
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
                    color: AppColors.border.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  keyboardType: widget.keyboardType,
                  obscureText: false,
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
                      color: AppColors.textSub.withValues(alpha: 0.45),
                      fontSize: 13,
                      letterSpacing: 1,
                    ),
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
        color: value ? AppColors.green.withValues(alpha: 0.04) : AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? AppColors.gold.withValues(alpha: 0.5) : AppColors.border,
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
                    ? AppColors.gold.withValues(alpha: 0.4)
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
            activeThumbColor: AppColors.gold,
            activeTrackColor: AppColors.green.withValues(alpha: 0.4),
            inactiveThumbColor: AppColors.textSub,
            inactiveTrackColor: AppColors.cream,
          ),
        ],
      ),
    );
  }
}

