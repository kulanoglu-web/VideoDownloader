import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() => runApp(const VideoDownloader());
class VideoDownloader extends StatelessWidget {
  const VideoDownloader({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'VideoDownloader', theme: ThemeData.dark(useMaterial3: true),
    home: const DownloadScreen(), debugShowCheckedModeBanner: false);
}
class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key});
  @override State<DownloadScreen> createState() => _DownloadScreenState();
}
class _DownloadScreenState extends State<DownloadScreen> {
  final url = TextEditingController();
  final dio = Dio();
  CancelToken? cancel;
  double progress = 0;
  bool busy = false;
  String status = 'Direkten, erlaubten Medienlink einfügen';
  Future<void> download() async {
    final uri = Uri.tryParse(url.text.trim());
    if (uri == null || !['https','http'].contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => status = 'Bitte gültige HTTP(S)-URL eingeben'); return;
    }
    final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (!RegExp(r'\.(mp4|m4a|mp3|webm|mov)$', caseSensitive: false).hasMatch(fileName)) {
      setState(() => status = 'Aktuell werden nur direkte Mediendatei-URLs unterstützt'); return;
    }
    setState(() { busy = true; progress = 0; status = 'Download läuft'; });
    cancel = CancelToken();
    try {
      final directory = await getApplicationDocumentsDirectory();
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final destination = '${directory.path}${Platform.pathSeparator}$safeName';
      await dio.downloadUri(uri, destination, cancelToken: cancel,
        onReceiveProgress: (received, total) {
          if (mounted && total > 0) setState(() => progress = received / total);
        });
      if (mounted) setState(() => status = 'Gespeichert: $destination');
    } on DioException catch (e) {
      if (mounted) setState(() => status = CancelToken.isCancel(e) ? 'Abgebrochen' : 'Fehler: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => status = 'Fehler: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override void dispose() { cancel?.cancel(); dio.close(); url.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('VideoDownloader')),
    body: Padding(padding: const EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Werbefrei · Lokal · Ohne Konto'),
      const SizedBox(height: 20),
      TextField(controller: url, decoration: const InputDecoration(
        border: OutlineInputBorder(), labelText: 'Direkter Medienlink')),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : download, child: const Text('Herunterladen')),
      if (busy) TextButton(onPressed: () => cancel?.cancel('Abgebrochen'), child: const Text('Abbrechen')),
      const SizedBox(height: 16),
      LinearProgressIndicator(value: busy && progress == 0 ? null : progress),
      const SizedBox(height: 12), Text(status),
    ])));
}
