import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'add_device_page.dart';
import '../auth/auth_service.dart';
import '../login_dashboard/login_page.dart';
import '../utils/google_maps_web_guard.dart';
import '../services/notification_service.dart';
import '../services/print_service.dart';
import '../services/system_admin_service.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final AuthService _authService = AuthService();
  final SystemAdminService _systemAdminService = SystemAdminService();
  final NotificationService _notificationService = NotificationService();


  String _selectedFilter = 'all';
  String _searchText = '';
  int _selectedMenuIndex = 0;

  static const LatLng _defaultMapCenter = LatLng(14.5995, 120.9842);
  static final Set<Factory<OneSequenceGestureRecognizer>>
  _mapGestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  final List<_AdminMenuItem> _menuItems = const [
    _AdminMenuItem('User Management', Icons.people_alt_outlined),
    _AdminMenuItem('Device Management', Icons.memory_outlined),
    _AdminMenuItem('Emergency Alerts', Icons.warning_amber_rounded),
    _AdminMenuItem('Login Activity', Icons.login_outlined),
    _AdminMenuItem('Logout', Icons.logout_rounded),
  ];

  @override
  void dispose() {

    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : AppColors.green,
      ),
    );
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
    if (location is GeoPoint) {
      return LatLng(location.latitude, location.longitude);
    }
    return null;
  }

  String _formatCoordinateValue(LatLng? value) {
    if (value == null) return 'Unknown';
    return '${value.latitude.toStringAsFixed(6)}, ${value.longitude.toStringAsFixed(6)}';
  }

  String _resolveAlertSenderName(Map<String, dynamic> data) {
    final fullName = (data['fullName'] ?? '').toString().trim();
    if (fullName.isNotEmpty) return fullName;
    final studentName = (data['studentName'] ?? '').toString().trim();
    if (studentName.isNotEmpty) return studentName;
    final userName = (data['userName'] ?? '').toString().trim();
    if (userName.isNotEmpty) return userName;
    final email = (data['email'] ?? '').toString().trim();
    if (email.isNotEmpty) return email;
    return 'Unknown sender';
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
          color: Color(0xFFFFF1B8),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Do you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;
    await _logout();
  }

  Future<void> _changePasswordDialog(
    String uid,
    String userName,
    String email,
  ) async {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool isLoading = false;
    bool obscureNew = true;
    bool obscureConfirm = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: AppColors.border.withOpacity(0.5)),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CHANGE PASSWORD',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 4,
                  color: AppColors.gold.withOpacity(0.9),
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                userName,
                style: const TextStyle(
                  fontFamily: 'CormorantGaramond',
                  fontSize: 22,
                  fontWeight: FontWeight.w300,
                  color: AppColors.green,
                ),
              ),
              Text(
                email,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSub,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: newPassCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    hintText: 'Minimum 6 characters',
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.green),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.offWhite,
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textSub,
                        size: 20,
                      ),
                      onPressed: () => setDialogState(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: confirmPassCtrl,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border.withOpacity(0.6)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.green),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.offWhite,
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textSub,
                        size: 20,
                      ),
                      onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSub),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.green,
                foregroundColor: AppColors.goldLt,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
              ),
              onPressed: isLoading
                  ? null
                  : () async {
                      final newPass = newPassCtrl.text.trim();
                      final confirmPass = confirmPassCtrl.text.trim();

                      if (newPass.length < 6) {
                        _showMessage('Password must be at least 6 characters.', isError: true);
                        return;
                      }
                      if (newPass != confirmPass) {
                        _showMessage('Passwords do not match.', isError: true);
                        return;
                      }

                      setDialogState(() => isLoading = true);
                      try {
                        final callable = FirebaseFunctions.instance
                            .httpsCallable('updateUserPassword');
                        await callable.call({
                          'uid': uid,
                          'newPassword': newPass,
                        });
                        if (mounted) Navigator.pop(context);
                        _showMessage('Password updated for $userName.');
                      } on FirebaseFunctionsException catch (e) {
                        _showMessage(
                          e.message ?? 'Failed to update password.',
                          isError: true,
                        );
                      } catch (e) {
                        _showMessage('Error: $e', isError: true);
                      } finally {
                        setDialogState(() => isLoading = false);
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.goldLt,
                      ),
                    )
                  : const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: Stack(
        children: [
          const Positioned.fill(child: _AdminBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildTopBar(),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Column(
                      children: [
                        _buildSummaryRow(),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Row(
                            children: [
                              _buildMenuPanel(),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: _buildContentArea(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton:
          _menuItems[_selectedMenuIndex].title == 'Device Management'
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.green,
              foregroundColor: AppColors.goldLt,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddDevicePage()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text(
                'ADD DEVICE',
                style: TextStyle(letterSpacing: 2),
              ),
            )
          : null,
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.green,
            border: Border.all(color: AppColors.gold, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: AppColors.green.withOpacity(0.18),
                blurRadius: 16,
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'SW',
              style: TextStyle(
                fontFamily: 'CormorantGaramond',
                fontSize: 16,
                fontWeight: FontWeight.w300,
                color: AppColors.gold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'SAFEWALK ADMIN',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 4,
            color: AppColors.goldDark,
            fontWeight: FontWeight.w400,
          ),
        ),
        const Spacer(),
      ],
    );
  }




  Widget _buildSummaryRow() {
    return Row(
      children: [
        _LuxurySummaryCard(
          title: 'USERS',
          icon: Icons.people_outline,
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
        ),
        const SizedBox(width: 12),
        _LuxurySummaryCard(
          title: 'DEVICES',
          icon: Icons.memory_outlined,
          stream: FirebaseFirestore.instance.collection('devices').snapshots(),
        ),
        const SizedBox(width: 12),
        _LuxurySummaryCard(
          title: 'ALERTS',
          icon: Icons.warning_amber_rounded,
          stream: FirebaseFirestore.instance
              .collection('emergency_alerts')
              .snapshots(),
        ),
        const SizedBox(width: 12),
        _LuxurySummaryCard(
          title: 'LOGINS',
          icon: Icons.login_outlined,
          stream: FirebaseFirestore.instance
              .collection('login_logs')
              .snapshots(),
        ),
      ],
    );
  }

  Widget _buildMenuPanel() {
    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
              ),
            ),
            child: Text(
              'ADMIN MENU',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 4,
                color: AppColors.gold.withOpacity(0.9),
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: _menuItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = _menuItems[index];
                final isSelected = _selectedMenuIndex == index;

                return InkWell(
                  onTap: () {
                    if (item.title == 'Logout') {
                      _confirmLogout();
                    } else {
                      setState(() {
                        _selectedMenuIndex = index;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.green.withOpacity(0.08)
                          : AppColors.offWhite,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.gold
                            : AppColors.border.withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.icon,
                          color: isSelected
                              ? AppColors.green
                              : AppColors.textSub,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? AppColors.green
                                  : AppColors.textMain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentArea() {
    final title = _menuItems[_selectedMenuIndex].title;
    switch (title) {
      case 'User Management':
        return _buildUserManagement();
      case 'Device Management':
        return _buildDeviceManagement();
      case 'Emergency Alerts':
        return _buildEmergencyAlerts();
      case 'Login Activity':
        return _buildLoginActivity();
      default:
        return _buildUserManagement();
    }
  }

  Widget _buildUserManagement() {
    return _LuxuryPanel(
      title: 'REGISTERED USERS',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No registered users found.',
                style: TextStyle(color: AppColors.textSub),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data();

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  border: Border.all(color: AppColors.border.withOpacity(0.5)),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.green.withOpacity(0.08),
                        border: Border.all(color: AppColors.gold),
                      ),
                      child: const Icon(Icons.person, color: AppColors.green),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (data['fullName'] ?? 'No Name').toString(),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.green,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _MiniTag(
                                label: 'Role: ${data['role'] ?? 'unknown'}',
                              ),
                              _MiniTag(
                                label: 'Email: ${data['email'] ?? 'No Email'}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Phone: ${data['phoneNumber'] ?? 'No phone number'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textMain,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Change Password button
                    Tooltip(
                      message: 'Change Password',
                      child: IconButton(
                        icon: const Icon(
                          Icons.lock_reset_rounded,
                          color: AppColors.goldDark,
                        ),
                        onPressed: () => _changePasswordDialog(
                          docs[index].id,
                          (data['fullName'] ?? 'User').toString(),
                          (data['email'] ?? '').toString(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDeviceManagement() {
    return _LuxuryPanel(
      title: 'REGISTERED DEVICES',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('devices')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No devices found.',
                style: TextStyle(color: AppColors.textSub),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final data = docs[index].data();

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  border: Border.all(color: AppColors.border.withOpacity(0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.green.withOpacity(0.08),
                            border: Border.all(color: AppColors.gold),
                          ),
                          child: const Icon(
                            Icons.memory,
                            color: AppColors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            data['deviceName'] ?? 'No Name',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Device ID: ${data['deviceId'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Phone: ${data['phoneNumber'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Location: ${data['location'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Status: ${data['status'] ?? ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: (data['status'] ?? '') == 'active'
                            ? Colors.green.shade700
                            : AppColors.textSub,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmergencySosMap(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sosDocs =
        docs.where((doc) {
          final type = (doc.data()['type'] ?? '').toString().toLowerCase();
          return type == 'sos';
        }).toList()..sort((a, b) {
          final aTs = a.data()['timestamp'] as Timestamp?;
          final bTs = b.data()['timestamp'] as Timestamp?;
          return (bTs?.millisecondsSinceEpoch ?? 0).compareTo(
            aTs?.millisecondsSinceEpoch ?? 0,
          );
        });

    final latestBySender =
        <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in sosDocs) {
      final data = doc.data();
      final senderUid = (data['uid'] ?? data['studentUid'] ?? '').toString();
      final key = senderUid.trim().isEmpty ? doc.id : senderUid.trim();
      latestBySender.putIfAbsent(key, () => doc);
    }

    final markers = <Marker>{};
    final circles = <Circle>{};
    LatLng? firstPoint;
    for (final entry in latestBySender.entries) {
      final data = entry.value.data();
      final point = _extractAlertCoordinates(data);
      if (point == null) continue;
      firstPoint ??= point;
      final sender = _resolveAlertSenderName(data);
      final isActive =
          (data['status'] ?? '').toString().toLowerCase() == 'active';
      final pointLabel = _formatCoordinateValue(point);
      markers.add(
        Marker(
          markerId: MarkerId('admin-sos-${entry.key}'),
          position: point,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isActive ? BitmapDescriptor.hueRed : BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(title: '$sender - SOS', snippet: pointLabel),
        ),
      );
      circles.add(
        Circle(
          circleId: CircleId('admin-sos-circle-${entry.key}'),
          center: point,
          radius: isActive ? 90 : 60,
          fillColor: isActive
              ? const Color(0x55CB392B)
              : const Color(0x35CB6D2B),
          strokeColor: isActive
              ? const Color(0xFFCB392B)
              : const Color(0xFFCB6D2B),
          strokeWidth: 2,
        ),
      );
    }

    final markerCount = markers.length;
    final latestData = sosDocs.isNotEmpty ? sosDocs.first.data() : null;
    final latestSender = latestData == null
        ? 'Unknown sender'
        : _resolveAlertSenderName(latestData);
    final latestLabel = latestData == null
        ? ''
        : _formatTimestamp(latestData['timestamp'] as Timestamp?);
    final latestPoint = latestData == null
        ? null
        : _extractAlertCoordinates(latestData);
    final center = firstPoint ?? latestPoint ?? _defaultMapCenter;
    final hasPoint = markerCount > 0;
    final footerTitle = hasPoint
        ? 'LATEST SOS: $latestSender${latestLabel.isEmpty ? '' : ' | $latestLabel'}'
        : 'NO SOS LOCATION YET';
    final footerLocation = hasPoint
        ? _formatCoordinateValue(latestPoint ?? firstPoint)
        : 'Waiting for SOS coordinates';

    return Container(
      height: 240,
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              child: kIsWeb && !isGoogleMapsJsLoaded()
                  ? _buildWebMapFallback(contextLabel: 'Admin SOS Map')
                  : GoogleMap(
                      key: ValueKey(
                        'admin-sos-map-${center.latitude}-${center.longitude}-$markerCount',
                      ),
                      initialCameraPosition: CameraPosition(
                        target: center,
                        zoom: hasPoint ? 15 : 12,
                      ),
                      mapType: MapType.normal,
                      gestureRecognizers: _mapGestureRecognizers,
                      zoomGesturesEnabled: true,
                      scrollGesturesEnabled: true,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF7E1F14),
                border: Border.all(color: AppColors.gold.withOpacity(0.3)),
              ),
              child: Text(
                markerCount > 0 ? '$markerCount SOS MARKERS' : 'NO SOS MARKERS',
                style: const TextStyle(
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
                    Colors.black.withOpacity(0.02),
                    Colors.black.withOpacity(0.72),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    footerTitle,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 9,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    footerLocation,
                    style: const TextStyle(
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
  }

  Widget _buildEmergencyAlerts() {
    return _LuxuryPanel(
      title: 'EMERGENCY ALERTS',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('emergency_alerts')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No emergency alerts found.',
                style: TextStyle(color: AppColors.textSub),
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: _buildEmergencySosMap(docs),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final sender = _resolveAlertSenderName(data);
                    final locationText = (data['location'] ?? 'Unknown')
                        .toString();
                    final status = (data['status'] ?? 'unknown')
                        .toString()
                        .toUpperCase();
                    final timestamp = _formatTimestamp(
                      data['timestamp'] as Timestamp?,
                    );

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red.shade700,
                            size: 28,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (data['message'] ?? 'Emergency Alert')
                                      .toString(),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Sender: $sender',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMain,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Location: $locationText',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMain,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Status: $status | Time: $timestamp',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMain,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoginActivity() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('login_logs')
        .orderBy('timestamp', descending: true);

    if (_selectedFilter != 'all') {
      query = query.where('status', isEqualTo: _selectedFilter);
    }

    return Column(
      children: [
        _buildFilterBar(),
        const SizedBox(height: 16),
        Expanded(
          child: _LuxuryPanel(
            title: 'LOGIN RECORDS',
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs.where((doc) {
                  final email = (doc.data()['email'] ?? '')
                      .toString()
                      .toLowerCase();
                  return email.contains(_searchText.toLowerCase());
                }).toList();

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No login records found.',
                      style: TextStyle(color: AppColors.textSub),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final status = (data['status'] ?? '').toString();
                    final isSuccess = status == 'success';

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.offWhite,
                        border: Border.all(
                          color: AppColors.border.withOpacity(0.5),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.shadow,
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSuccess
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              border: Border.all(
                                color: isSuccess
                                    ? Colors.green.shade200
                                    : Colors.red.shade200,
                              ),
                            ),
                            child: Icon(
                              isSuccess ? Icons.check : Icons.close,
                              color: isSuccess ? Colors.green : Colors.red,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['email'] ?? 'No Email',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.green,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _MiniTag(
                                      label:
                                          'Role: ${data['role'] ?? 'unknown'}',
                                    ),
                                    _MiniTag(
                                      label: 'Status: ${data['status'] ?? ''}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Location: ${data['location'] ?? 'Unknown'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMain,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Device: ${data['deviceId'] ?? 'Unknown'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMain,
                                  ),
                                ),
                                if ((data['error'] ?? '')
                                    .toString()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Error: ${data['error']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }



  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _AdminSearchField(
              hint: 'Search email address',
              onChanged: (value) {
                setState(() => _searchText = value);
              },
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.offWhite,
              border: Border.all(color: AppColors.border.withOpacity(0.5)),
            ),
            child: DropdownButton<String>(
              value: _selectedFilter,
              underline: const SizedBox(),
              dropdownColor: AppColors.white,
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All')),
                DropdownMenuItem(value: 'success', child: Text('Success')),
                DropdownMenuItem(value: 'failed', child: Text('Failed')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedFilter = value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }


}

class _AdminMenuItem {
  final String title;
  final IconData icon;

  const _AdminMenuItem(this.title, this.icon);
}



class _LuxurySummaryCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Stream<QuerySnapshot> stream;

  const _LuxurySummaryCard({
    required this.title,
    required this.icon,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snapshot) {
            final count = snapshot.data?.docs.length ?? 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.green, size: 20),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 4,
                    color: AppColors.gold.withOpacity(0.9),
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    color: AppColors.green,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LuxuryPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const _LuxuryPanel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border.withOpacity(0.5)),
              ),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 4,
                color: AppColors.gold.withOpacity(0.9),
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AdminSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const _AdminSearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textSub),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search, color: AppColors.green),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;

  const _MiniTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textSub),
      ),
    );
  }
}



class _AdminBackground extends StatelessWidget {
  const _AdminBackground();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AdminVinesPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _AdminVinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    final vine = Paint()
      ..color = AppColors.green.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final leaf = Paint()
      ..color = AppColors.gold.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final left = Path()
      ..moveTo(w * 0.03, h)
      ..cubicTo(w * 0.03, h * 0.80, w * 0.01, h * 0.65, w * 0.05, h * 0.48)
      ..cubicTo(w * 0.08, h * 0.34, w * 0.01, h * 0.18, w * 0.06, 0);

    final right = Path()
      ..moveTo(w * 0.97, h)
      ..cubicTo(w * 0.97, h * 0.82, w * 0.99, h * 0.68, w * 0.94, h * 0.50)
      ..cubicTo(w * 0.90, h * 0.34, w * 0.98, h * 0.18, w * 0.93, 0);

    canvas.drawPath(left, vine);
    canvas.drawPath(right, vine);

    void drawLeaf(Offset center, double rx, double ry) {
      canvas.drawOval(
        Rect.fromCenter(center: center, width: rx, height: ry),
        leaf,
      );
    }

    drawLeaf(Offset(w * 0.035, h * 0.78), 14, 8);
    drawLeaf(Offset(w * 0.055, h * 0.58), 12, 7);
    drawLeaf(Offset(w * 0.028, h * 0.36), 13, 8);
    drawLeaf(Offset(w * 0.95, h * 0.74), 14, 8);
    drawLeaf(Offset(w * 0.93, h * 0.52), 12, 7);
    drawLeaf(Offset(w * 0.965, h * 0.30), 13, 8);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// keep same color theme used by your login page
class AppColors {
  static const white = Color(0xFFFFFFFF);
  static const offWhite = Color(0xFFF7F5F0);
  static const cream = Color(0xFFF0EBE0);
  static const gold = Color(0xFFC9A551);
  static const goldDark = Color(0xFFA8843A);
  static const goldLt = Color(0xFFE8D08A);
  static const green = Color(0xFF0B2C1E);
  static const greenMid = Color(0xFF134D33);
  static const bright = Color(0xFF2CA86E);
  static const border = Color(0x55C9A551);
  static const glass = Color(0xFFFFFFFF);
  static const shadow = Color(0x14000000);
  static const textMain = Color(0xFF1A1A1A);
  static const textSub = Color(0xFF888880);
}
