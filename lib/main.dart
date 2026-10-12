import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/services.dart';

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
  String? lastSavedFile;
  final List<String> downloadedFiles = [];
  @override void initState() {
    super.initState();
    loadHistory();
  }
  Future<void> loadHistory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final entries = await directory.list().where((entity) =>
        entity is File &&
        RegExp(r'\.(mp4|m4a|mp3|webm|mov)$', caseSensitive: false)
            .hasMatch(entity.path)).toList();
      if (mounted) setState(() {
        downloadedFiles
          ..clear()
          ..addAll(entries.map((entity) => entity.path));
      });
    } catch (_) {
      // History is optional; downloads remain usable.
    }
  }
  Future<void> pasteLink() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) setState(() => url.text = data!.text!.trim());
  }
  Future<void> download() async {
    final uri = Uri.tryParse(url.text.trim());
    if (uri == null || !['https','http'].contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => status = 'Bitte gültige HTTP(S)-URL eingeben'); return;
    }
    final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (!RegExp(r'\.(mp4|m4a|mp3|webm|mov)$', caseSensitive: false).hasMatch(fileName)) {
      setState(() => status = 'Aktuell werden nur direkte Mediendatei-URLs unterstützt'); return;
    }
    setState(() { busy = true; progress = 0; lastSavedFile = null; status = 'Download läuft'; });
    cancel = CancelToken();
    try {
      final directory = await getApplicationDocumentsDirectory();
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final destination = '${directory.path}${Platform.pathSeparator}$safeName';
      await dio.downloadUri(uri, destination, cancelToken: cancel,
        onReceiveProgress: (received, total) {
          if (mounted && total > 0) setState(() => progress = received / total);
        });
      if (mounted) setState(() { lastSavedFile = destination; downloadedFiles.remove(destination); downloadedFiles.insert(0, destination); status = 'Gespeichert: $destination'; });
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
      Align(alignment: Alignment.centerRight, child: TextButton.icon(
        onPressed: busy ? null : pasteLink,
        icon: const Icon(Icons.content_paste), label: const Text('Link einfügen'))),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : download, child: const Text('Herunterladen')),
      if (busy) TextButton(onPressed: () => cancel?.cancel('Abgebrochen'), child: const Text('Abbrechen')),
      const SizedBox(height: 16),
      LinearProgressIndicator(value: busy && progress == 0 ? null : progress),
      if (busy && progress > 0) Text('${(progress * 100).toStringAsFixed(0)} %'),
      if (!busy && lastSavedFile != null)
        OutlinedButton.icon(onPressed: () async {
          final file = File(lastSavedFile!);
          if (await file.exists()) {
            await Clipboard.setData(ClipboardData(text: lastSavedFile!));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dateipfad kopiert')));
          }
        }, icon: const Icon(Icons.copy), label: const Text('Dateipfad kopieren')),
      const SizedBox(height: 12), Text(status),
      const SizedBox(height: 18),
      const Text('Downloads dieser Sitzung', style: TextStyle(fontWeight: FontWeight.bold)),
      Expanded(child: ListView.builder(itemCount: downloadedFiles.length,
        itemBuilder: (context, index) {
          final file = downloadedFiles[index];
          return ListTile(leading: const Icon(Icons.video_file),
            title: Text(file.split(Platform.pathSeparator).last),
            subtitle: Text(file, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(ClipboardData(text: file))));
        })),
    ])));
}
, caseSensitive: false).hasMatch(entity.path)).toList();
    if (mounted) setState(() {
      downloadedFiles.clear();
      downloadedFiles.addAll(entries.map((e) => e.path));
    });
  }
  Future<void> pasteLink() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) setState(() => url.text = data!.text!.trim());
  }
  Future<void> download() async {
    final uri = Uri.tryParse(url.text.trim());
    if (uri == null || !['https','http'].contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => status = 'Bitte gültige HTTP(S)-URL eingeben'); return;
    }
    final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (!RegExp(r'\.(mp4|m4a|mp3|webm|mov)$', caseSensitive: false).hasMatch(fileName)) {
      setState(() => status = 'Aktuell werden nur direkte Mediendatei-URLs unterstützt'); return;
    }
    setState(() { busy = true; progress = 0; lastSavedFile = null; status = 'Download läuft'; });
    cancel = CancelToken();
    try {
      final directory = await getApplicationDocumentsDirectory();
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final destination = '${directory.path}${Platform.pathSeparator}$safeName';
      await dio.downloadUri(uri, destination, cancelToken: cancel,
        onReceiveProgress: (received, total) {
          if (mounted && total > 0) setState(() => progress = received / total);
        });
      if (mounted) setState(() { lastSavedFile = destination; downloadedFiles.insert(0, destination); status = 'Gespeichert: $destination'; });
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
      Align(alignment: Alignment.centerRight, child: TextButton.icon(
        onPressed: busy ? null : pasteLink,
        icon: const Icon(Icons.content_paste), label: const Text('Link einfügen'))),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : download, child: const Text('Herunterladen')),
      if (busy) TextButton(onPressed: () => cancel?.cancel('Abgebrochen'), child: const Text('Abbrechen')),
      const SizedBox(height: 16),
      LinearProgressIndicator(value: busy && progress == 0 ? null : progress),
      if (busy && progress > 0) Text('${(progress * 100).toStringAsFixed(0)} %'),
      if (!busy && lastSavedFile != null)
        OutlinedButton.icon(onPressed: () async {
          final file = File(lastSavedFile!);
          if (await file.exists()) {
            await Clipboard.setData(ClipboardData(text: lastSavedFile!));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dateipfad kopiert')));
          }
        }, icon: const Icon(Icons.copy), label: const Text('Dateipfad kopieren')),
      const SizedBox(height: 12), Text(status),
      const SizedBox(height: 18),
      const Text('Downloads dieser Sitzung', style: TextStyle(fontWeight: FontWeight.bold)),
      Expanded(child: ListView.builder(itemCount: downloadedFiles.length,
        itemBuilder: (context, index) {
          final file = downloadedFiles[index];
          return ListTile(leading: const Icon(Icons.video_file),
            title: Text(file.split(Platform.pathSeparator).last),
            subtitle: Text(file, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(ClipboardData(text: file))));
        })),
    ])));
}
