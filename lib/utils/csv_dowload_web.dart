// lib/utils/csv_download_web.dart
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

/// Descarga un archivo CSV en el navegador (solo web).
void downloadCsvOnWeb(List<int> bytes, String filename) {
  final blob = html.Blob([bytes], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';

  html.document.body?.append(anchor);
  anchor.click();

  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
