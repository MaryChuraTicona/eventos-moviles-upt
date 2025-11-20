import 'csv_downloader_stub.dart'
    if (dart.library.html) 'csv_downloader_web.dart';

Future<void> downloadCsv(List<int> bytes, String filename) {
  return downloadCsvImpl(bytes, filename);
}