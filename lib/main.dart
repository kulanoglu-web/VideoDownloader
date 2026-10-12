import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
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
  bool stopYoutube = false;
  bool audioOnly = false;
  final youtube = YoutubeExplode();
  bool isYoutube(Uri uri) => const ['youtu.be','youtube.com','www.youtube.com','m.youtube.com','music.youtube.com'].contains(uri.host.toLowerCase());
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
      if (mounted) {
        setState(() {
          downloadedFiles
            ..clear()
            ..addAll(entries.map((entity) => entity.path));
        });
      }
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
    if (isYoutube(uri)) { await downloadYoutube(uri); return; }
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
  Future<void> downloadYoutube(Uri uri) async {
    setState(() { busy = true; stopYoutube = false; progress = 0; lastSavedFile = null; status = 'YouTube-Informationen werden geladen'; });
    File? target;
    IOSink? sink;
    try {
      final video = await youtube.videos.get(uri.toString());
      if (stopYoutube) return;
      final manifest = await youtube.videos.streams.getManifest(video.id);
      if (stopYoutube) return;
      final info = audioOnly
          ? (manifest.audioOnly.isNotEmpty ? manifest.audioOnly.withHighestBitrate() : null)
          : (manifest.muxed.isNotEmpty ? manifest.muxed.withHighestVideoQuality() : null);
      if (info == null) {
        throw StateError(audioOnly ? 'Kein Audiostream verfügbar' : 'Kein kombinierter Videostream verfügbar');
      }
      final directory = await getApplicationDocumentsDirectory();
      final extension = info.container.name;
      final filename = '${video.id.value}.$extension';
      target = File('${directory.path}${Platform.pathSeparator}$filename');
      sink = target.openWrite();
      var received = 0;
      final total = info.size.totalBytes;
      if (mounted) setState(() => status = 'Lade: ${video.title}');
      await for (final chunk in youtube.videos.streams.get(info)) {
        if (stopYoutube) break;
        sink.add(chunk);
        received += chunk.length;
        if (mounted && total > 0) {
          setState(() => progress = (received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (stopYoutube) {
        await target.delete();
        if (mounted) setState(() => status = 'Abgebrochen');
      } else if (mounted) {
        setState(() {
          lastSavedFile = target!.path;
          downloadedFiles.remove(target.path);
          downloadedFiles.insert(0, target.path);
          status = 'Gespeichert: ${target.path}';
          progress = 1;
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = 'YouTube-Fehler: $e');
      if (sink != null) {
        await sink.close();
        if (target != null && await target.exists()) await target.delete();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override void dispose() { cancel?.cancel(); youtube.close(); dio.close(); url.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('VideoDownloader')),
    body: Padding(padding: const EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Werbefrei · Lokal · Ohne Konto'),
      const SizedBox(height: 20),
      TextField(controller: url, decoration: const InputDecoration(
        border: OutlineInputBorder(), labelText: 'Video-URL oder direkter Medienlink')),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(
        onPressed: busy ? null : pasteLink,
        icon: const Icon(Icons.content_paste), label: const Text('Link einfügen'))),
      SwitchListTile(title: const Text('Nur Audio herunterladen'), value: audioOnly,
        onChanged: busy ? null : (value) => setState(() => audioOnly = value)),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : download, child: const Text('Herunterladen')),
      if (busy) TextButton(onPressed: () { stopYoutube = true; cancel?.cancel('Abgebrochen'); }, child: const Text('Abbrechen')),
      const SizedBox(height: 16),
      LinearProgressIndicator(value: busy && progress == 0 ? null : progress),
      if (busy && progress > 0) Text('${(progress * 100).toStringAsFixed(0)} %'),
      if (!busy && lastSavedFile != null)
        OutlinedButton.icon(onPressed: () async {
          final file = File(lastSavedFile!);
          if (await file.exists()) {
            await Clipboard.setData(ClipboardData(text: lastSavedFile!));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
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
