import 'dart:convert';
import 'dart:html' as html;

Future<bool> printReportHtmlImpl({
  required String title,
  required String content,
}) async {
  final escapedTitle = _escapeHtml(title);
  final escapedContent = _escapeHtml(content).replaceAll('\n', '<br/>');

  final reportHtml =
      '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$escapedTitle</title>
  <style>
    body { font-family: Arial, sans-serif; padding: 24px; color: #0B2C1E; }
    h1 { font-size: 20px; margin-bottom: 16px; }
    .content { line-height: 1.5; font-size: 13px; }
  </style>
</head>
<body>
  <h1>$escapedTitle</h1>
  <div class="content">$escapedContent</div>
  <script>window.onload = function() { window.focus(); };</script>
</body>
</html>
''';

  final reportUri = Uri.dataFromString(
    reportHtml,
    mimeType: 'text/html',
    encoding: utf8,
  );

  html.window.open(reportUri.toString(), '_blank');
  return true;
}

String _escapeHtml(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
