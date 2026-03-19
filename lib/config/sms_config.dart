class SmsGatewayConfig {
  // Configure these values based on your SMS provider (Twilio, Semaphore, etc.).
  // Example endpoint: https://api.semaphore.co/api/v4/messages
  static const String endpoint = '';
  static const String apiKey = '';
  static const String senderId = 'SAFEWALK';

  // Most providers use Authorization: Bearer <token>.
  // Change this if your provider expects a different header.
  static const String authHeaderName = 'Authorization';
  static const String authHeaderValuePrefix = 'Bearer ';

  static bool get isConfigured => endpoint.isNotEmpty && apiKey.isNotEmpty;
}
