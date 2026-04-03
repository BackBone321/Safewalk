import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../auth/auth_service.dart';
import '../login_dashboard/login_page.dart';
import '../utils/google_maps_web_guard.dart';

class UserDashboardPage extends StatefulWidget {
  const UserDashboardPage({super.key});

  @override
  State<UserDashboardPage> createState() => _UserDashboardPageState();
}

class _UserDashboardPageState extends State<UserDashboardPage> {
  int _selectedNavIndex = 0;
  static const String _hf = 'CormorantGaramond';
  static const String _bf = 'JosefinSans';
  static const LatLng _defaultMapCenter = LatLng(14.5995, 120.9842);
  static final Set<Factory<OneSequenceGestureRecognizer>> _mapGestureRecognizers =
      <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isProfileSheetOpen = false;

  final TextEditingController _profileNameCtrl = TextEditingController();
  final TextEditingController _profilePhoneCtrl = TextEditingController();

  String _fullName = 'Student';
  String _email = '';
  String _phoneNumber = '';
  String _studentUid = '';
  final String _activeRoute = 'Main Campus -> Dorm Block C';

  String _deviceId = 'Not linked';
  String _deviceName = 'No linked device';
  String _deviceLocation = 'Unknown';
  String _deviceStatus = 'offline';
  LatLng? _deviceCoordinates;
  BitmapDescriptor? _sosMarkerIcon;
  GoogleMapController? _routeMapController;
  LatLng? _nextMapFocusPoint;
  LatLng? _lastFocusedMapPoint;

  bool _alertsEnabled = true;
  bool _safeModeEnabled = true;
  bool _locationSharingEnabled = true;
  String _linkedParentUid = '';
  String _linkedParentPhone = '';
  String _linkedParentName = '';
  List<_ParentInvitation> _pendingInvitations = const [];
  bool _isLoadingInvitations = false;

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
      subtitle: 'Edit personal information',
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
    _NavItem('Map', Icons.map_outlined),
    _NavItem('Device', Icons.smartphone_outlined),
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
    if (location is GeoPoint) {
      return LatLng(location.latitude, location.longitude);
    }
    if (location is String) {
      return _coordinatesFromText(location);
    }

    return null;
  }

  String _formatCoordinateLabel(LatLng? point) {
    if (point == null) return 'Not available';
    return '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
  }

  String get _activeStudentUid {
    if (_studentUid.isNotEmpty) return _studentUid;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  _SosMapState _resolveSosMapState(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sosDocs =
        docs.where((doc) {
          final data = doc.data();
          final type = (data['type'] ?? '').toString().toLowerCase();
          return type == 'sos';
        }).toList()..sort((a, b) {
          final aTs = a.data()['timestamp'] as Timestamp?;
          final bTs = b.data()['timestamp'] as Timestamp?;
          final aClientTs = a.data()['clientTimestamp'] as Timestamp?;
          final bClientTs = b.data()['clientTimestamp'] as Timestamp?;
          final aMs =
              aTs?.millisecondsSinceEpoch ?? aClientTs?.millisecondsSinceEpoch ?? 0;
          final bMs =
              bTs?.millisecondsSinceEpoch ?? bClientTs?.millisecondsSinceEpoch ?? 0;
          return bMs.compareTo(aMs);
        });

    if (sosDocs.isEmpty) return const _SosMapState();

    final latest = sosDocs.first.data();
    final coordinate = _extractAlertCoordinates(latest);
    final status = (latest['status'] ?? '').toString().toLowerCase();
    final locationText = (latest['location'] ?? '').toString().trim();
    return _SosMapState(
      coordinate: coordinate,
      isActive: status == 'active',
      timestampLabel: _formatTimestamp(latest['timestamp'] as Timestamp?),
      areaLabel: locationText.isEmpty
          ? _formatCoordinateLabel(coordinate)
          : locationText,
    );
  }

  LatLng get _mapCenter => _deviceCoordinates ?? _defaultMapCenter;

  bool get _hasDeviceCoordinates => _deviceCoordinates != null;

  String get _mapCoordinateLabel {
    return _formatCoordinateLabel(_deviceCoordinates);
  }

  bool get _mobileMapLiteMode =>
      false;

  bool _isSamePoint(LatLng a, LatLng b) {
    const tolerance = 0.00001;
    return (a.latitude - b.latitude).abs() <= tolerance &&
        (a.longitude - b.longitude).abs() <= tolerance;
  }

  void _focusRouteMapOnPoint(LatLng point, {double zoom = 16, bool force = false}) {
    final controller = _routeMapController;
    if (controller == null) return;

    if (!force &&
        _lastFocusedMapPoint != null &&
        _isSamePoint(_lastFocusedMapPoint!, point)) {
      return;
    }

    _lastFocusedMapPoint = point;
    controller
        .animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: point, zoom: zoom),
          ),
        )
        .catchError((_) {});

    if (_nextMapFocusPoint != null && _isSamePoint(_nextMapFocusPoint!, point)) {
      _nextMapFocusPoint = null;
    }
  }

  Future<Uint8List> _buildSosMarkerBytes({int size = 144}) async {
    final markerSize = size.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, markerSize, markerSize),
    );

    final center = Offset(markerSize / 2, markerSize * 0.38);
    final topRadius = markerSize * 0.22;
    final bodyColor = const Color(0xFFF21D2F);
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.18)
      ..style = PaintingStyle.fill;
    final pinPaint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.fill;

    final shadowPath = Path()
      ..moveTo(center.dx, markerSize * 0.92)
      ..lineTo(center.dx - topRadius * 0.62, center.dy + topRadius * 0.68)
      ..lineTo(center.dx + topRadius * 0.62, center.dy + topRadius * 0.68)
      ..close();
    canvas.drawCircle(
      Offset(center.dx, center.dy + markerSize * 0.012),
      topRadius,
      shadowPaint,
    );
    canvas.drawPath(shadowPath, shadowPaint);

    final pinPath = Path()
      ..moveTo(center.dx, markerSize * 0.88)
      ..lineTo(center.dx - topRadius * 0.58, center.dy + topRadius * 0.62)
      ..lineTo(center.dx + topRadius * 0.58, center.dy + topRadius * 0.62)
      ..close();
    canvas.drawCircle(center, topRadius, pinPaint);
    canvas.drawPath(pinPath, pinPaint);
    canvas.drawCircle(
      center,
      topRadius * 0.47,
      Paint()..color = Colors.white,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      return Uint8List(0);
    }
    return bytes.buffer.asUint8List();
  }

  Future<void> _prepareMapMarkers() async {
    try {
      final bytes = await _buildSosMarkerBytes();
      if (bytes.isEmpty) return;
      final icon = BitmapDescriptor.fromBytes(bytes);
      if (!mounted) return;
      setState(() => _sosMarkerIcon = icon);
    } catch (_) {
      // Keep default marker fallback when custom marker generation fails.
    }
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
    _prepareMapMarkers();
    _loadDashboard();
  }

  @override
  void dispose() {
    _routeMapController?.dispose();
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
      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final settingsDoc = await _firestore
          .collection('user_settings')
          .doc(currentUser.uid)
          .get();
      if (!mounted) return;
      setState(() {
        _studentUid = currentUser.uid;
        _fullName = (userDoc.data()?['fullName'] ?? 'Student').toString();
        _email = (userDoc.data()?['email'] ?? '').toString();
        _phoneNumber = (userDoc.data()?['phoneNumber'] ?? '').toString();
        _alertsEnabled =
            (settingsDoc.data()?['alertsEnabled'] as bool?) ?? true;
        _safeModeEnabled =
            (settingsDoc.data()?['safeModeEnabled'] as bool?) ?? true;
        _locationSharingEnabled =
            (settingsDoc.data()?['locationSharingEnabled'] as bool?) ?? true;
      });
      await _loadLinkedDevice();
      await _loadLinkedParent();
      await _loadPendingInvitations();
    } catch (e) {
      _showActionSnack('Failed to load dashboard data: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLinkedDevice() async {
    if (_phoneNumber.trim().isEmpty) return;
    final rawPhone = _phoneNumber.trim();
    final normalizedPhone = _normalizePhoneForLookup(rawPhone);
    var q = await _firestore
        .collection('devices')
        .where('phoneNumber', isEqualTo: rawPhone)
        .limit(1)
        .get();
    if (q.docs.isEmpty && normalizedPhone != rawPhone) {
      q = await _firestore
          .collection('devices')
          .where('phoneNumber', isEqualTo: normalizedPhone)
          .limit(1)
          .get();
    }
    if (q.docs.isEmpty) {
      if (!mounted) return;
      setState(() {
        _deviceId = 'Not linked';
        _deviceName = 'No linked device';
        _deviceLocation = 'Unknown';
        _deviceStatus = 'offline';
        _deviceCoordinates = null;
      });
      return;
    }
    final data = q.docs.first.data();
    final locationField = data['location'];
    if (!mounted) return;
    setState(() {
      _deviceId = (data['deviceId'] ?? '').toString().isEmpty
          ? q.docs.first.id
          : (data['deviceId'] ?? q.docs.first.id).toString();
      _deviceName = (data['deviceName'] ?? 'Emergency Device').toString();
      _deviceLocation = locationField is GeoPoint
          ? '${locationField.latitude.toStringAsFixed(6)}, ${locationField.longitude.toStringAsFixed(6)}'
          : (locationField ?? 'Unknown').toString();
      _deviceStatus = (data['status'] ?? 'active').toString().toLowerCase();
      _deviceCoordinates = _extractDeviceCoordinates(data);
    });
  }

  Future<void> _loadLinkedParent() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    final normalizedStudentPhone = _normalizePhoneForLookup(_phoneNumber);
    final linkQuery = await _firestore
        .collection('parent_student_links')
        .where('studentUid', isEqualTo: currentUid)
        .limit(50)
        .get();

    var acceptedDocs = linkQuery.docs.where((doc) {
      final status = (doc.data()['status'] ?? 'accepted')
          .toString()
          .toLowerCase();
      return status == 'accepted';
    }).toList();

    if (acceptedDocs.isEmpty && normalizedStudentPhone.isNotEmpty) {
      final byPhoneQuery = await _firestore
          .collection('parent_student_links')
          .where('studentPhoneNormalized', isEqualTo: normalizedStudentPhone)
          .limit(50)
          .get();
      acceptedDocs = byPhoneQuery.docs.where((doc) {
        final status = (doc.data()['status'] ?? 'accepted')
            .toString()
            .toLowerCase();
        return status == 'accepted';
      }).toList();
    }

    if (!mounted) return;
    if (acceptedDocs.isEmpty) {
      setState(() {
        _linkedParentUid = '';
        _linkedParentPhone = '';
        _linkedParentName = '';
      });
      return;
    }

    acceptedDocs.sort((a, b) {
      final aTs = (a.data()['updatedAt'] ?? a.data()['linkedAt']) as Timestamp?;
      final bTs = (b.data()['updatedAt'] ?? b.data()['linkedAt']) as Timestamp?;
      return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(
        aTs?.millisecondsSinceEpoch ?? 0,
      );
    });

    final link = acceptedDocs.first.data();
    final parentUid = (link['parentUid'] ?? '').toString();
    final parentPhone = (link['parentPhone'] ?? '').toString();
    String parentName = (link['parentName'] ?? '').toString();
    if (parentName.trim().isEmpty && parentUid.trim().isNotEmpty) {
      final parentDoc = await _firestore
          .collection('users')
          .doc(parentUid)
          .get();
      parentName = (parentDoc.data()?['fullName'] ?? '').toString();
    }

    if (!mounted) return;
    setState(() {
      _linkedParentUid = parentUid;
      _linkedParentPhone = parentPhone;
      _linkedParentName = parentName;
    });
  }

  Future<void> _loadPendingInvitations() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;

    if (mounted) setState(() => _isLoadingInvitations = true);
    try {
      final normalizedStudentPhone = _normalizePhoneForLookup(_phoneNumber);
      final byUid = await _firestore
          .collection('parent_student_invitations')
          .where('studentUid', isEqualTo: currentUid)
          .limit(50)
          .get();

      final byPhone = byUid.docs.isEmpty && normalizedStudentPhone.isNotEmpty
          ? await _firestore
                .collection('parent_student_invitations')
                .where(
                  'studentPhoneNormalized',
                  isEqualTo: normalizedStudentPhone,
                )
                .limit(50)
                .get()
          : null;

      final docs = byUid.docs.isNotEmpty
          ? byUid.docs
          : (byPhone?.docs ?? const []);

      final invitations = <_ParentInvitation>[];
      for (final doc in docs) {
        final data = doc.data();
        final status = (data['status'] ?? 'pending').toString().toLowerCase();
        if (status != 'pending') continue;

        final parentUid = (data['parentUid'] ?? '').toString().trim();
        if (parentUid.isEmpty) continue;

        final studentUid =
            (data['studentUid'] ?? currentUid).toString().trim().isEmpty
            ? currentUid
            : (data['studentUid'] ?? currentUid).toString().trim();

        invitations.add(
          _ParentInvitation(
            id: doc.id,
            parentUid: parentUid,
            parentName: (data['parentName'] ?? 'Parent').toString().trim(),
            parentPhone: (data['parentPhone'] ?? '').toString().trim(),
            studentUid: studentUid,
            createdAt: data['createdAt'] as Timestamp?,
          ),
        );
      }

      invitations.sort((a, b) {
        return (b.createdAt?.millisecondsSinceEpoch ?? 0).compareTo(
          a.createdAt?.millisecondsSinceEpoch ?? 0,
        );
      });

      if (!mounted) return;
      setState(() => _pendingInvitations = invitations);
    } catch (e) {
      _showActionSnack('Failed to load parent invitations: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingInvitations = false);
    }
  }

  Future<void> _acceptInvitation(_ParentInvitation invitation) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    final invitationStudentUid = invitation.studentUid.trim();
    final studentUid = invitationStudentUid.isEmpty
        ? (_studentUid.isEmpty ? user.uid : _studentUid)
        : invitationStudentUid;
    final parentUid = invitation.parentUid.trim();
    if (parentUid.isEmpty) {
      _showActionSnack('Invalid invitation.', isError: true);
      return;
    }

    final invitationDocId = invitation.id.trim().isEmpty
        ? '${parentUid}_$studentUid'
        : invitation.id.trim();
    final linkDocId = '${parentUid}_$studentUid';
    final parentPhone = invitation.parentPhone.trim();

    try {
      final batch = _firestore.batch();
      final invitationRef = _firestore
          .collection('parent_student_invitations')
          .doc(invitationDocId);
      batch.set(invitationRef, {
        'status': 'accepted',
        'studentUid': studentUid,
        'studentName': _fullName.trim(),
        'studentPhone': _phoneNumber.trim(),
        'studentPhoneNormalized': _normalizePhoneForLookup(_phoneNumber),
        'updatedAt': FieldValue.serverTimestamp(),
        'respondedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final linkRef = _firestore
          .collection('parent_student_links')
          .doc(linkDocId);
      batch.set(linkRef, {
        'parentUid': parentUid,
        'parentName': invitation.parentName.trim(),
        'parentPhone': parentPhone,
        'parentPhoneNormalized': _normalizePhoneForLookup(parentPhone),
        'studentUid': studentUid,
        'studentName': _fullName.trim(),
        'studentPhone': _phoneNumber.trim(),
        'studentPhoneNormalized': _normalizePhoneForLookup(_phoneNumber),
        'status': 'accepted',
        'linkedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      await _loadLinkedParent();
      await _loadPendingInvitations();
      _showActionSnack('Invitation accepted.');
    } catch (e) {
      _showActionSnack('Failed to accept invitation: $e', isError: true);
    }
  }

  Future<void> _rejectInvitation(_ParentInvitation invitation) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    final invitationStudentUid = invitation.studentUid.trim();
    final studentUid = invitationStudentUid.isEmpty
        ? (_studentUid.isEmpty ? user.uid : _studentUid)
        : invitationStudentUid;
    final parentUid = invitation.parentUid.trim();
    if (parentUid.isEmpty) {
      _showActionSnack('Invalid invitation.', isError: true);
      return;
    }
    final invitationDocId = invitation.id.trim().isEmpty
        ? '${parentUid}_$studentUid'
        : invitation.id.trim();

    try {
      await _firestore
          .collection('parent_student_invitations')
          .doc(invitationDocId)
          .set({
            'status': 'rejected',
            'studentUid': studentUid,
            'studentName': _fullName.trim(),
            'studentPhone': _phoneNumber.trim(),
            'studentPhoneNormalized': _normalizePhoneForLookup(_phoneNumber),
            'updatedAt': FieldValue.serverTimestamp(),
            'respondedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await _loadPendingInvitations();
      _showActionSnack('Invitation rejected.');
    } catch (e) {
      _showActionSnack('Failed to reject invitation: $e', isError: true);
    }
  }

  // ─── Actions ───────────────────────────────────────────────────

  Future<void> _createSosAlert() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    try {
      await _loadLinkedParent();
      await _loadLinkedDevice();
      if (_linkedParentUid.trim().isEmpty) {
        _showActionSnack(
          'No linked parent yet. Accept a parent invitation in Settings first.',
          isError: true,
        );
        return;
      }

      final mapPoint =
          _deviceCoordinates ?? _coordinatesFromText(_deviceLocation) ?? _mapCenter;
      final locationGeoPoint = GeoPoint(mapPoint.latitude, mapPoint.longitude);
      final locationLabel =
          _deviceLocation.trim().isEmpty ||
              _deviceLocation.trim().toLowerCase() == 'unknown'
          ? _formatCoordinateLabel(mapPoint)
          : _deviceLocation;

      await _firestore.collection('emergency_alerts').add({
        'uid': user.uid,
        'studentUid': user.uid,
        'fullName': _fullName,
        'email': _email,
        'phoneNumber': _phoneNumber,
        'parentUid': _linkedParentUid,
        'parentPhoneNumber': _linkedParentPhone,
        'type': 'sos',
        'severity': 'high',
        'status': 'active',
        'message': 'SOS button pressed by $_fullName.',
        'location': locationLabel,
        'coordinates': locationGeoPoint,
        'triggeredBy': 'student_dashboard',
        'clientTimestamp': Timestamp.now(),
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _selectedNavIndex = 1;
          _nextMapFocusPoint = mapPoint;
        });
      }
      _showActionSnack('SOS sent to your linked parent.');
    } catch (e) {
      _showActionSnack('Failed to send SOS alert: $e', isError: true);
    }
  }

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
        _fullName = fullName.trim();
        _phoneNumber = phoneNumber.trim();
      });
      await _loadLinkedDevice();
      await _loadLinkedParent();
      await _loadPendingInvitations();
      _showActionSnack('Profile updated.');
    } catch (e) {
      _showActionSnack('Failed to update profile: $e', isError: true);
    }
  }

  Future<void> _saveSettings({
    required bool alertsEnabled,
    required bool safeModeEnabled,
    required bool locationSharingEnabled,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showActionSnack('Please login again.', isError: true);
      return;
    }
    try {
      await _firestore.collection('user_settings').doc(uid).set({
        'alertsEnabled': alertsEnabled,
        'safeModeEnabled': safeModeEnabled,
        'locationSharingEnabled': locationSharingEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _alertsEnabled = alertsEnabled;
        _safeModeEnabled = safeModeEnabled;
        _locationSharingEnabled = locationSharingEnabled;
      });
      _showActionSnack('Settings saved.');
    } catch (e) {
      _showActionSnack('Failed to save settings: $e', isError: true);
    }
  }

  // ─── LUXURY DIALOGS ────────────────────────────────────────────

  Future<void> _showLocationDialog({
    LatLng? mapPoint,
    bool sosIsActive = false,
    String areaLabel = '',
    String sosTimestampLabel = '',
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final effectivePoint = mapPoint ?? _deviceCoordinates;
            final center = effectivePoint ?? _defaultMapCenter;
            final hasPoint = effectivePoint != null;
            final focusLabel = areaLabel.isEmpty ? _deviceLocation : areaLabel;

            Widget infoTile(String label, String value) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontFamily: _bf,
                          fontSize: 9,
                          letterSpacing: 2.8,
                          color: AppColors.gold,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: _bf,
                          fontSize: 12,
                          letterSpacing: 0.4,
                          color: AppColors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.86,
              minChildSize: 0.6,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: AppColors.offWhite,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.green,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.gold,
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.location_on_outlined,
                              color: AppColors.gold,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'LIVE MAP',
                                style: TextStyle(
                                  fontFamily: _bf,
                                  fontSize: 9,
                                  letterSpacing: 4,
                                  color: AppColors.gold,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Location Info',
                                style: TextStyle(
                                  fontFamily: _hf,
                                  fontSize: 32,
                                  height: 1,
                                  color: AppColors.green,
                                  fontWeight: FontWeight.w300,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: sosIsActive
                                  ? const Color(0xFF7E1F14)
                                  : hasPoint
                                  ? const Color(0xFF0F5A3E)
                                  : const Color(0xFF6C757D),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              sosIsActive
                                  ? 'SOS ACTIVE'
                                  : hasPoint
                                  ? 'TRACKING'
                                  : 'NO COORDS',
                              style: const TextStyle(
                                fontFamily: _bf,
                                color: AppColors.white,
                                fontSize: 9,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: SizedBox(
                          height: 220,
                          child: kIsWeb && !isGoogleMapsJsLoaded()
                              ? _buildWebMapFallback(
                                  contextLabel: 'Student Location Sheet',
                                )
                              : GoogleMap(
                                  key: ValueKey(
                                    'sheet-map-${center.latitude}-${center.longitude}-${sosIsActive ? 'sos' : 'track'}',
                                  ),
                                  initialCameraPosition: CameraPosition(
                                    target: center,
                                    zoom: hasPoint ? 16 : 12,
                                  ),
                                  liteModeEnabled: _mobileMapLiteMode,
                                  mapType: MapType.normal,
                                  gestureRecognizers: _mapGestureRecognizers,
                                  zoomGesturesEnabled: true,
                                  scrollGesturesEnabled: true,
                                  markers: hasPoint
                                      ? {
                                          Marker(
                                            markerId: const MarkerId(
                                              'sheet-device',
                                            ),
                                            position: center,
                                            icon: sosIsActive
                                                ? (_sosMarkerIcon ??
                                                      BitmapDescriptor.defaultMarkerWithHue(
                                                        BitmapDescriptor.hueRed,
                                                      ))
                                                : BitmapDescriptor.defaultMarkerWithHue(
                                                    BitmapDescriptor.hueAzure,
                                                  ),
                                            infoWindow: InfoWindow(
                                              title: sosIsActive
                                                  ? 'SOS Location'
                                                  : _deviceName,
                                              snippet: focusLabel,
                                            ),
                                          ),
                                        }
                                      : <Marker>{},
                                  circles: hasPoint
                                      ? {
                                          Circle(
                                            circleId: const CircleId(
                                              'sheet-radius',
                                            ),
                                            center: center,
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
                                      : <Circle>{},
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
                      const SizedBox(height: 12),
                      Text(
                        'Google Maps live preview',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: _bf,
                          fontSize: 9,
                          letterSpacing: 1,
                          color: AppColors.textSub.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 14),
                      infoTile('ROUTE', _activeRoute),
                      const SizedBox(height: 10),
                      infoTile('MAP FOCUS', focusLabel),
                      const SizedBox(height: 10),
                      infoTile(
                        'SOS STATUS',
                        sosIsActive
                            ? 'Active${sosTimestampLabel.isEmpty ? '' : ' - $sosTimestampLabel'}'
                            : 'Not active',
                      ),
                      const SizedBox(height: 10),
                      infoTile('COORDINATES', _formatCoordinateLabel(effectivePoint)),
                      const SizedBox(height: 10),
                      infoTile(
                        'LOCATION SHARING',
                        _locationSharingEnabled ? 'Enabled' : 'Disabled',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: Material(
                          color: AppColors.green,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              await _loadLinkedDevice();
                              if (!mounted) return;
                              setSheetState(() {});
                              _showActionSnack('Location info refreshed.');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.gold.withOpacity(0.65),
                                ),
                              ),
                              child: const Text(
                                'REFRESH',
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
                );
              },
            );
          },
        );
      },
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
        await _loadLinkedDevice();
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
              // Gold top accent
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
                    // Header
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
                    // Rows
                    ...rows.map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showActionSnack('Please login again.', isError: true);
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
                              'EMERGENCY LOGS',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            Text(
                              'Alert History',
                              style: const TextStyle(
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
                          .where('uid', isEqualTo: uid)
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
      ..text = _fullName
      ..selection = TextSelection.collapsed(offset: _fullName.length);
    _profilePhoneCtrl
      ..text = _phoneNumber
      ..selection = TextSelection.collapsed(offset: _phoneNumber.length);

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
                        // Gold top accent line
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
                              // Header label + title
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
                                    TextSpan(text: 'Personal\n'),
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
                                          _fullName.isNotEmpty
                                              ? _fullName[0].toUpperCase()
                                              : 'S',
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
                                  'STUDENT',
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

                              // Gold divider
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

                              // Email display (read-only)
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
                                      _email.isEmpty ? 'Not set' : _email,
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

                              // Full name field
                              _DashLuxuryField(
                                label: 'FULL NAME',
                                hint: 'Enter your full name',
                                controller: _profileNameCtrl,
                              ),
                              const SizedBox(height: 20),

                              // Phone field
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
    await _loadPendingInvitations();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        bool localAlerts = _alertsEnabled;
        bool localSafeMode = _safeModeEnabled;
        bool localLocationSharing = _locationSharingEnabled;
        bool isSaving = false;
        bool isHandlingInvitation = false;
        String invitationActionId = '';

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
                            Text(
                              'SAFETY & ALERTS',
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
                              title: 'Safe Mode',
                              subtitle: 'Enhanced safety monitoring',
                              icon: Icons.shield_outlined,
                              value: localSafeMode,
                              onChanged: (v) =>
                                  setSheet(() => localSafeMode = v),
                            ),
                            const SizedBox(height: 10),
                            _DashSettingsTile(
                              title: 'Location Sharing',
                              subtitle: 'Share GPS with guardians & admin',
                              icon: Icons.location_on_outlined,
                              value: localLocationSharing,
                              onChanged: (v) =>
                                  setSheet(() => localLocationSharing = v),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              'PARENT INVITATIONS',
                              style: TextStyle(
                                fontFamily: _bf,
                                fontSize: 9,
                                letterSpacing: 4,
                                color: AppColors.gold,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildDeviceRow(
                              'Pending Requests',
                              _pendingInvitations.length.toString(),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _isLoadingInvitations
                                    ? null
                                    : () async {
                                        await _loadPendingInvitations();
                                        if (sheetCtx.mounted) setSheet(() {});
                                      },
                                child: Text(
                                  _isLoadingInvitations
                                      ? 'Refreshing...'
                                      : 'Refresh Invitations',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    fontSize: 10,
                                    letterSpacing: 1,
                                    color: AppColors.green,
                                  ),
                                ),
                              ),
                            ),
                            if (_isLoadingInvitations)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  child: CircularProgressIndicator(
                                    color: AppColors.gold,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else if (_pendingInvitations.isEmpty)
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
                                  'No pending invitations right now.',
                                  style: TextStyle(
                                    fontFamily: _bf,
                                    fontSize: 11,
                                    color: AppColors.textSub,
                                  ),
                                ),
                              )
                            else
                              Column(
                                children: _pendingInvitations.map((invite) {
                                  final isBusy =
                                      isHandlingInvitation &&
                                      invitationActionId == invite.id;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        10,
                                        12,
                                        10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            invite.parentName.isEmpty
                                                ? 'Parent'
                                                : invite.parentName,
                                            style: TextStyle(
                                              fontFamily: _bf,
                                              color: AppColors.green,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            invite.parentPhone.isEmpty
                                                ? 'No phone provided'
                                                : invite.parentPhone,
                                            style: TextStyle(
                                              fontFamily: _bf,
                                              color: AppColors.textSub,
                                              fontSize: 11,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Received ${_formatTimestamp(invite.createdAt)}',
                                            style: TextStyle(
                                              fontFamily: _bf,
                                              color: AppColors.textSub,
                                              fontSize: 10,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              OutlinedButton(
                                                onPressed: isBusy
                                                    ? null
                                                    : () async {
                                                        setSheet(() {
                                                          isHandlingInvitation =
                                                              true;
                                                          invitationActionId =
                                                              invite.id;
                                                        });
                                                        try {
                                                          await _rejectInvitation(
                                                            invite,
                                                          );
                                                          if (sheetCtx
                                                              .mounted) {
                                                            setSheet(() {});
                                                          }
                                                        } finally {
                                                          if (sheetCtx
                                                              .mounted) {
                                                            setSheet(() {
                                                              isHandlingInvitation =
                                                                  false;
                                                              invitationActionId =
                                                                  '';
                                                            });
                                                          }
                                                        }
                                                      },
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      AppColors.textSub,
                                                  side: BorderSide(
                                                    color: AppColors.border,
                                                  ),
                                                ),
                                                child: const Text('Reject'),
                                              ),
                                              ElevatedButton(
                                                onPressed: isBusy
                                                    ? null
                                                    : () async {
                                                        setSheet(() {
                                                          isHandlingInvitation =
                                                              true;
                                                          invitationActionId =
                                                              invite.id;
                                                        });
                                                        try {
                                                          await _acceptInvitation(
                                                            invite,
                                                          );
                                                          if (sheetCtx
                                                              .mounted) {
                                                            setSheet(() {});
                                                          }
                                                        } finally {
                                                          if (sheetCtx
                                                              .mounted) {
                                                            setSheet(() {
                                                              isHandlingInvitation =
                                                                  false;
                                                              invitationActionId =
                                                                  '';
                                                            });
                                                          }
                                                        }
                                                      },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      AppColors.green,
                                                  foregroundColor:
                                                      AppColors.white,
                                                ),
                                                child: isBusy
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      )
                                                    : const Text('Accept'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
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
                                          await _saveSettings(
                                            alertsEnabled: localAlerts,
                                            safeModeEnabled: localSafeMode,
                                            locationSharingEnabled:
                                                localLocationSharing,
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
  // ─── Tool Handlers ─────────────────────────────────────────────

  Future<void> _handleToolTap(String title) async {
    switch (title) {
      case 'Device Connection':
        await _showDeviceDialog();
        return;
      case 'Alert History':
        await _showAlertHistorySheet();
        return;
      case 'Profile':
        setState(() => _selectedNavIndex = 4);
        return;
      case 'Settings':
        setState(() => _selectedNavIndex = 5);
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
            top: -70,
            left: -30,
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
            top: 140,
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
        return _buildMapTab();
      case 2:
        return _buildDeviceTab();
      case 3:
        return _buildAlertsTab();
      case 4:
        return _buildProfileTab();
      case 5:
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
        const SizedBox(height: 16),
        _buildRouteCard(),
        const SizedBox(height: 18),
        _buildSectionLabel('DEVICE STATUS'),
        const SizedBox(height: 10),
        _buildDeviceCard(),
        const SizedBox(height: 20),
        _buildSectionLabel('TOOLS'),
        const SizedBox(height: 10),
        _buildToolList(),
      ],
    );
  }

  Widget _buildMapTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _activeStudentUid.isEmpty
          ? null
          : _firestore
                .collection('emergency_alerts')
                .where('uid', isEqualTo: _activeStudentUid)
                .limit(60)
                .snapshots(),
      builder: (context, snapshot) {
        final docs =
            snapshot.data?.docs ??
            <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final sosState = _resolveSosMapState(docs);
        final mapPoint =
            sosState.coordinate ?? _nextMapFocusPoint ?? _deviceCoordinates;
        final hasPoint = mapPoint != null;
        if (sosState.coordinate != null && _nextMapFocusPoint != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _nextMapFocusPoint = null);
          });
        }
        final trackingLabel = sosState.isActive
            ? 'SOS active'
            : hasPoint
            ? 'Active'
            : 'No coordinates';
        final fallbackAreaLabel =
            _deviceLocation.trim().isEmpty ||
                _deviceLocation.trim().toLowerCase() == 'unknown'
            ? _formatCoordinateLabel(mapPoint)
            : _deviceLocation;
        final mapAreaLabel = sosState.areaLabel.isEmpty
            ? fallbackAreaLabel
            : sosState.areaLabel;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeroCard(),
            const SizedBox(height: 16),
            _buildSectionLabel('LIVE MAP'),
            const SizedBox(height: 10),
            _buildRouteCard(
              mapPoint: mapPoint,
              sosIsActive: sosState.isActive,
              areaLabel: mapAreaLabel,
            ),
            const SizedBox(height: 14),
            _buildDashboardPanel(
              title: 'Map Overview',
              subtitle: 'LOCATION TRACKING',
              children: [
                _buildDeviceRow('Coordinates', _formatCoordinateLabel(mapPoint)),
                const SizedBox(height: 8),
                _buildDeviceRow('Tracking', trackingLabel),
                const SizedBox(height: 8),
                _buildDeviceRow('Map Focus', mapAreaLabel),
                const SizedBox(height: 8),
                _buildDeviceRow('Device', _deviceName),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPanelAction(
                      label: 'OPEN MAP SHEET',
                      onTap: () => _showLocationDialog(
                        mapPoint: mapPoint,
                        sosIsActive: sosState.isActive,
                        areaLabel: mapAreaLabel,
                        sosTimestampLabel: sosState.timestampLabel,
                      ),
                    ),
                    _buildPanelAction(
                      label: 'REFRESH DEVICE',
                      onTap: _loadLinkedDevice,
                      isPrimary: false,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 16),
        _buildSectionLabel('DEVICE'),
        const SizedBox(height: 10),
        _buildDeviceCard(),
        const SizedBox(height: 14),
        _buildDashboardPanel(
          title: 'Connection Status',
          subtitle: 'EMERGENCY DEVICE',
          children: [
            _buildDeviceRow('Device Name', _deviceName),
            const SizedBox(height: 8),
            _buildDeviceRow('Device ID', _deviceId),
            const SizedBox(height: 8),
            _buildDeviceRow('Status', _deviceStatus.toUpperCase()),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'GPS Sharing',
              _locationSharingEnabled ? 'Enabled' : 'Disabled',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPanelAction(
                  label: 'VIEW DETAILS',
                  onTap: _showDeviceDialog,
                ),
                _buildPanelAction(
                  label: 'REFRESH',
                  onTap: _loadLinkedDevice,
                  isPrimary: false,
                ),
              ],
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
        const SizedBox(height: 16),
        _buildSectionLabel('ALERT CENTER'),
        const SizedBox(height: 10),
        _buildDashboardPanel(
          title: 'Emergency Actions',
          subtitle: 'ALERTS & SAFETY',
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
                  label: _safeModeEnabled ? 'SAFE MODE ON' : 'SAFE MODE OFF',
                  isActive: _safeModeEnabled,
                ),
                _AlertBadge(
                  label: _locationSharingEnabled ? 'GPS ON' : 'GPS OFF',
                  isActive: _locationSharingEnabled,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildDeviceRow('Current Location', _deviceLocation),
            const SizedBox(height: 8),
            _buildDeviceRow('Route', _activeRoute),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Linked Parent Name',
              _linkedParentName.isEmpty ? 'Not linked' : _linkedParentName,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Linked Parent',
              _linkedParentPhone.isEmpty ? 'Not linked' : _linkedParentPhone,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPanelAction(label: 'SEND SOS', onTap: _createSosAlert),
                _buildPanelAction(
                  label: 'ALERT HISTORY',
                  onTap: _showAlertHistorySheet,
                  isPrimary: false,
                ),
                _buildPanelAction(
                  label: 'ALERT SETTINGS',
                  onTap: _showSettingsDialog,
                  isPrimary: false,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProfileTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 16),
        _buildSectionLabel('PROFILE'),
        const SizedBox(height: 10),
        _buildDashboardPanel(
          title: _fullName,
          subtitle: 'STUDENT ACCOUNT',
          children: [
            _buildDeviceRow(
              'Student UID',
              _studentUid.isEmpty ? 'Unavailable' : _studentUid,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow('Email', _email.isEmpty ? '-' : _email),
            const SizedBox(height: 8),
            _buildDeviceRow('Phone', _phoneNumber.isEmpty ? '-' : _phoneNumber),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Linked Device',
              _deviceId == 'Not linked' ? 'Not linked' : _deviceName,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow('Current Route', _activeRoute),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Parent UID',
              _linkedParentUid.isEmpty ? 'Not linked' : _linkedParentUid,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Parent Name',
              _linkedParentName.isEmpty ? 'Not linked' : _linkedParentName,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Parent Phone',
              _linkedParentPhone.isEmpty ? 'Not linked' : _linkedParentPhone,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Pending Invitations',
              _pendingInvitations.length.toString(),
            ),
            const SizedBox(height: 14),
            _buildPanelAction(label: 'EDIT PROFILE', onTap: _showProfileDialog),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroCard(),
        const SizedBox(height: 16),
        _buildSectionLabel('SETTINGS'),
        const SizedBox(height: 10),
        _buildDashboardPanel(
          title: 'Preferences',
          subtitle: 'STUDENT CONTROLS',
          children: [
            _buildDeviceRow(
              'Student UID',
              _studentUid.isEmpty ? 'Unavailable' : _studentUid,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow('Alerts', _alertsEnabled ? 'Enabled' : 'Disabled'),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Safe Mode',
              _safeModeEnabled ? 'Enabled' : 'Disabled',
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Location Sharing',
              _locationSharingEnabled ? 'Enabled' : 'Disabled',
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Parent Link',
              _linkedParentUid.isEmpty ? 'Not linked' : 'Connected',
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Parent Name',
              _linkedParentName.isEmpty ? 'Not linked' : _linkedParentName,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Parent Contact',
              _linkedParentPhone.isEmpty ? 'Not linked' : _linkedParentPhone,
            ),
            const SizedBox(height: 8),
            _buildDeviceRow(
              'Pending Invitations',
              _pendingInvitations.length.toString(),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildPanelAction(
                  label: 'OPEN SETTINGS',
                  onTap: _showSettingsDialog,
                ),
                _buildPanelAction(
                  label: 'REFRESH',
                  onTap: _loadDashboard,
                  isPrimary: false,
                ),
              ],
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
            color: Colors.black.withOpacity(0.05),
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
                  ? AppColors.gold.withOpacity(0.45)
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
                    'STUDENT',
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

          // Good morning + name
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
            _fullName,
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
                label: _locationSharingEnabled ? 'GPS Active' : 'GPS Paused',
                dotColor: _locationSharingEnabled
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
                label: _safeModeEnabled ? 'Safe Mode On' : 'Safe Mode Off',
                dotColor: _safeModeEnabled
                    ? const Color(0xFF4ADE80)
                    : const Color(0xFFFF7F7F),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard({
    LatLng? mapPoint,
    bool sosIsActive = false,
    String areaLabel = '',
  }) {
    final effectivePoint = mapPoint ?? _deviceCoordinates;
    final center = effectivePoint ?? _defaultMapCenter;
    final hasPoint = effectivePoint != null;
    final focusLabel = areaLabel.isEmpty ? _deviceLocation : areaLabel;
    final requestedFocusPoint = _nextMapFocusPoint ?? effectivePoint;
    if (requestedFocusPoint != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusRouteMapOnPoint(
          requestedFocusPoint,
          zoom: hasPoint ? 16 : 12,
        );
      });
    }
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
                  ? _buildWebMapFallback(contextLabel: 'Student Route Card')
                  : GoogleMap(
                      key: ValueKey(
                        'route-map-${center.latitude}-${center.longitude}-${sosIsActive ? 'sos' : hasPoint ? 'track' : 'none'}',
                      ),
                      initialCameraPosition: CameraPosition(
                        target: center,
                        zoom: hasPoint ? 16 : 12,
                      ),
                      liteModeEnabled: _mobileMapLiteMode,
                      mapType: MapType.normal,
                      gestureRecognizers: _mapGestureRecognizers,
                      zoomGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                      markers: hasPoint
                          ? {
                              Marker(
                                markerId: const MarkerId('route-device'),
                                position: center,
                                icon: sosIsActive
                                    ? (_sosMarkerIcon ??
                                          BitmapDescriptor.defaultMarkerWithHue(
                                            BitmapDescriptor.hueRed,
                                          ))
                                    : BitmapDescriptor.defaultMarkerWithHue(
                                        BitmapDescriptor.hueAzure,
                                      ),
                                infoWindow: InfoWindow(
                                  title: sosIsActive
                                      ? 'SOS Location'
                                      : _deviceName,
                                  snippet: focusLabel,
                                ),
                              ),
                            }
                          : <Marker>{},
                      circles: hasPoint
                          ? {
                              Circle(
                                circleId: const CircleId('route-radius'),
                                center: center,
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
                          : <Circle>{},
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      compassEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      onMapCreated: (controller) {
                        _routeMapController?.dispose();
                        _routeMapController = controller;
                        final focusPoint = _nextMapFocusPoint ?? effectivePoint;
                        if (focusPoint != null) {
                          _focusRouteMapOnPoint(
                            focusPoint,
                            zoom: hasPoint ? 16 : 12,
                            force: true,
                          );
                        }
                      },
                    ),
            ),
          ),
          Positioned(
            top: 14,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: sosIsActive
                    ? const Color(0xFF7E1F14)
                    : const Color(0xFF0E5B3C),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.gold.withOpacity(0.3),
                  width: 0.5,
                ),
              ),
              child: Text(
                sosIsActive ? 'SOS MAP' : 'LIVE MAP',
                style: TextStyle(
                  fontFamily: _bf,
                  color: AppColors.gold,
                  fontSize: 10,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            top: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: sosIsActive
                    ? const Color(0xFF7E1F14)
                    : hasPoint
                    ? const Color(0xFF0F5A3E)
                    : const Color(0xFF6C757D),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 7,
                    color: sosIsActive
                        ? const Color(0xFFFF9F9F)
                        : hasPoint
                        ? const Color(0xFF5DF0A0)
                        : const Color(0xFFF6D38E),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    sosIsActive
                        ? 'SOS ACTIVE'
                        : hasPoint
                        ? 'TRACKING'
                        : 'NO COORDS',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.white,
                      fontSize: 9,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                    Colors.black.withOpacity(0.02),
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTIVE ROUTE',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: AppColors.gold,
                      fontSize: 9,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _activeRoute,
                    style: const TextStyle(
                      fontFamily: _bf,
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasPoint
                        ? (sosIsActive
                              ? 'SOS pinned at ${_formatCoordinateLabel(effectivePoint)}'
                              : '$_deviceName at ${_formatCoordinateLabel(effectivePoint)}')
                        : 'Waiting for device coordinates. Save location as "lat, lng".',
                    style: const TextStyle(
                      fontFamily: _bf,
                      color: Color(0xFFE8ECE9),
                      fontSize: 10,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sosIsActive
                        ? focusLabel
                        : 'Google Maps tracking view',
                    style: TextStyle(
                      fontFamily: _bf,
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
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

  Widget _buildDeviceCard() {
    final isLinked = _deviceId != 'Not linked';
    final isOnline = _deviceStatus == 'active' || _deviceStatus == 'online';

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
                      'Device',
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
                      'Connection',
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
                      isLinked
                          ? 'Your emergency device is linked to this account.'
                          : 'No emergency device linked yet.',
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
                      color: isOnline
                          ? const Color(0xFF60CC8A)
                          : const Color(0xFFFF7F7F),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isOnline ? 'Online' : 'Offline',
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
          _buildDeviceRow('Device Name', _deviceName),
          const SizedBox(height: 8),
          _buildDeviceRow('Device ID', _deviceId),
          const SizedBox(height: 8),
          _buildDeviceRow('Location', _deviceLocation),
          const SizedBox(height: 8),
          _buildDeviceRow(
            'GPS Sharing',
            _locationSharingEnabled ? 'Enabled' : 'Disabled',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: AppColors.green,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _showDeviceDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.gold.withOpacity(0.5)),
                  ),
                  child: Text(
                    'VIEW DEVICE',
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

  Widget _buildDeviceRow(String label, String value) {
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

class _ParentInvitation {
  final String id;
  final String parentUid;
  final String parentName;
  final String parentPhone;
  final String studentUid;
  final Timestamp? createdAt;

  const _ParentInvitation({
    required this.id,
    required this.parentUid,
    required this.parentName,
    required this.parentPhone,
    required this.studentUid,
    required this.createdAt,
  });
}

class _SosMapState {
  final LatLng? coordinate;
  final bool isActive;
  final String timestampLabel;
  final String areaLabel;

  const _SosMapState({
    this.coordinate,
    this.isActive = false,
    this.timestampLabel = '',
    this.areaLabel = '',
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
                    color: AppColors.border.withOpacity(0.6),
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
                      color: AppColors.textSub.withOpacity(0.45),
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
            activeThumbColor: AppColors.gold,
            activeTrackColor: AppColors.green.withOpacity(0.4),
            inactiveThumbColor: AppColors.textSub,
            inactiveTrackColor: AppColors.cream,
          ),
        ],
      ),
    );
  }
}
