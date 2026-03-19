import 'print_service_stub.dart'
    if (dart.library.html) 'print_service_web.dart';

Future<bool> printReportHtml({required String title, required String content}) {
  return printReportHtmlImpl(title: title, content: content);
}
