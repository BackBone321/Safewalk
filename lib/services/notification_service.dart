import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import '../config/emailjs_config.dart';
import '../config/sms_config.dart';

class NotificationService {
  NotificationService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  bool get isEmailConfigured =>
      EmailJsConfig.serviceId.isNotEmpty &&
      EmailJsConfig.templateId.isNotEmpty &&
      EmailJsConfig.publicKey.isNotEmpty;

  bool get isSmsConfigured => SmsGatewayConfig.isConfigured;

  Future<void> sendEmailNotification({
    required String toEmail,
    required String toName,
    required String subject,
    required String message,
    String triggeredBy = 'system',
  }) async {
    final targetEmail = toEmail.trim().toLowerCase();
    final targetName = toName.trim().isEmpty ? 'SafeWalk User' : toName.trim();

    if (!isEmailConfigured) {
      await _logEmail(
        toEmail: targetEmail,
        subject: subject,
        status: 'not_configured',
        error: 'EmailJS configuration is missing.',
        triggeredBy: triggeredBy,
      );
      throw StateError('Email notifications are not configured.');
    }

    final payload = <String, dynamic>{
      'service_id': EmailJsConfig.serviceId,
      'template_id': EmailJsConfig.templateId,
      'user_id': EmailJsConfig.publicKey,
      'template_params': <String, dynamic>{
        'to_email': targetEmail,
        'to_name': targetName,
        'subject': subject,
        'message': message,
        'email': targetEmail,
        'user_email': targetEmail,
        'recipient_email': targetEmail,
        'name': targetName,
      },
    };

    final response = await http.post(
      Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    final success = response.statusCode >= 200 && response.statusCode < 300;
    await _logEmail(
      toEmail: targetEmail,
      subject: subject,
      status: success ? 'sent' : 'failed',
      providerStatusCode: response.statusCode,
      providerResponse: response.body,
      triggeredBy: triggeredBy,
      error: success ? null : 'Email send failed (${response.statusCode})',
    );

    if (!success) {
      throw Exception(
        'Email send failed with status ${response.statusCode}: ${response.body}',
      );
    }
  }

  Future<void> sendSmsNotification({
    required String phoneNumber,
    required String message,
    String triggeredBy = 'system',
    String? alertId,
  }) async {
    final targetPhone = phoneNumber.trim();

    if (!isSmsConfigured) {
      await _logSms(
        phoneNumber: targetPhone,
        message: message,
        status: 'not_configured',
        error: 'SMS gateway configuration is missing.',
        triggeredBy: triggeredBy,
        alertId: alertId,
      );
      throw StateError(
        'SMS notifications are not configured. Set lib/config/sms_config.dart first.',
      );
    }

    final payload = <String, dynamic>{
      'to': targetPhone,
      'message': message,
      'sender': SmsGatewayConfig.senderId,
    };

    final headers = <String, String>{
      'Content-Type': 'application/json',
      SmsGatewayConfig.authHeaderName:
          '${SmsGatewayConfig.authHeaderValuePrefix}${SmsGatewayConfig.apiKey}',
    };

    final response = await http.post(
      Uri.parse(SmsGatewayConfig.endpoint),
      headers: headers,
      body: jsonEncode(payload),
    );

    final success = response.statusCode >= 200 && response.statusCode < 300;
    await _logSms(
      phoneNumber: targetPhone,
      message: message,
      status: success ? 'sent' : 'failed',
      providerStatusCode: response.statusCode,
      providerResponse: response.body,
      triggeredBy: triggeredBy,
      alertId: alertId,
      error: success ? null : 'SMS send failed (${response.statusCode})',
    );

    if (!success) {
      throw Exception(
        'SMS send failed with status ${response.statusCode}: ${response.body}',
      );
    }
  }

  /// Text every guardian. One failure does not stop the rest of the list.
  Future<SmsBroadcastResult> broadcastSms({
    required List<String> phoneNumbers,
    required String message,
    String triggeredBy = 'emergency_alert',
    String? alertId,
  }) async {
    final targets = <String>[];
    final seen = <String>{};
    for (final raw in phoneNumbers) {
      final phone = raw.trim();
      if (phone.isEmpty || seen.contains(phone)) continue;
      seen.add(phone);
      targets.add(phone);
    }
    if (targets.isEmpty) {
      return const SmsBroadcastResult(
        status: 'no_recipients',
        sent: 0,
        failed: 0,
      );
    }

    var sent = 0;
    var failed = 0;
    for (final phone in targets) {
      if (!isSmsConfigured) {
        await _logSms(
          phoneNumber: phone,
          message: message,
          status: 'not_configured',
          error: 'SMS gateway configuration is missing.',
          triggeredBy: triggeredBy,
          alertId: alertId,
        );
        failed++;
        continue;
      }
      try {
        await sendSmsNotification(
          phoneNumber: phone,
          message: message,
          triggeredBy: triggeredBy,
          alertId: alertId,
        );
        sent++;
      } catch (_) {
        failed++;
      }
    }

    final status = !isSmsConfigured
        ? 'not_configured'
        : sent == 0
        ? 'failed'
        : failed == 0
        ? 'sent'
        : 'partial';
    return SmsBroadcastResult(status: status, sent: sent, failed: failed);
  }

  Future<void> _logEmail({
    required String toEmail,
    required String subject,
    required String status,
    String? error,
    int? providerStatusCode,
    String? providerResponse,
    required String triggeredBy,
  }) {
    return _firestore.collection('email_logs').add({
      'toEmail': toEmail,
      'subject': subject,
      'status': status,
      'error': error ?? '',
      'providerStatusCode': providerStatusCode,
      'providerResponse': providerResponse ?? '',
      'triggeredBy': triggeredBy,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _logSms({
    required String phoneNumber,
    required String message,
    required String status,
    String? error,
    int? providerStatusCode,
    String? providerResponse,
    required String triggeredBy,
    String? alertId,
  }) {
    return _firestore.collection('sms_logs').add({
      'phoneNumber': phoneNumber,
      'message': message,
      'status': status,
      'error': error ?? '',
      'providerStatusCode': providerStatusCode,
      'providerResponse': providerResponse ?? '',
      'triggeredBy': triggeredBy,
      'alertId': alertId ?? '',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}

class SmsBroadcastResult {
  final String status;
  final int sent;
  final int failed;

  const SmsBroadcastResult({
    required this.status,
    required this.sent,
    required this.failed,
  });
}
