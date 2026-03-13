import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../login_dashboard/login_page.dart';

class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => _AddDevicePageState();
}

class _AddDevicePageState extends State<AddDevicePage> {
  final _deviceIdCtrl = TextEditingController();
  final _deviceNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();

  bool _isSaving = false;

  bool _isValidPhilippineMobile(String value) {
    final regex = RegExp(r'^(09\d{9}|\+639\d{9})$');
    return regex.hasMatch(value);
  }

  Future<void> _saveDevice() async {
    final deviceId = _deviceIdCtrl.text.trim();
    final deviceName = _deviceNameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final location = _locationCtrl.text.trim();

    if (deviceId.isEmpty ||
        deviceName.isEmpty ||
        phone.isEmpty ||
        location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please complete all fields.')),
      );
      return;
    }

    if (!_isValidPhilippineMobile(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid Philippine mobile number like 09123456789'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance.collection('devices').add({
        'deviceId': deviceId,
        'deviceName': deviceName,
        'phoneNumber': phone,
        'location': location,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device added successfully.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save device: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _deviceIdCtrl.dispose();
    _deviceNameCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.offWhite,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.green),
        title: const Text(
          'Add IoT Device',
          style: TextStyle(color: AppColors.green),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.white,
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DEVICE REGISTRATION',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 5,
                    color: AppColors.gold.withOpacity(0.9),
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Add\nDevice',
                  style: TextStyle(
                    fontFamily: 'CormorantGaramond',
                    fontSize: 34,
                    fontWeight: FontWeight.w300,
                    height: 1.1,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: 24),
                _AdminTextField(
                  label: 'DEVICE ID',
                  hint: 'SW-001',
                  controller: _deviceIdCtrl,
                ),
                const SizedBox(height: 20),
                _AdminTextField(
                  label: 'DEVICE NAME',
                  hint: 'Emergency Button 1',
                  controller: _deviceNameCtrl,
                ),
                const SizedBox(height: 20),
                _AdminTextField(
                  label: 'PHILIPPINE MOBILE NUMBER',
                  hint: '09123456789',
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 20),
                _AdminTextField(
                  label: 'LOCATION',
                  hint: 'Gate 1',
                  controller: _locationCtrl,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveDevice,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: AppColors.goldLt,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(color: AppColors.gold),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator()
                        : const Text(
                            'SAVE DEVICE',
                            style: TextStyle(letterSpacing: 3),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminTextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;

  const _AdminTextField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 4,
            color: AppColors.gold.withOpacity(0.9),
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.offWhite,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(2),
              borderSide: BorderSide(
                color: AppColors.border.withOpacity(0.5),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(2),
              borderSide: BorderSide(
                color: AppColors.border.withOpacity(0.5),
              ),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(2)),
              borderSide: BorderSide(
                color: AppColors.gold,
                width: 1.2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }
}