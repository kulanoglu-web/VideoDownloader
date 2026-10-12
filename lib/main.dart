import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
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
        RegExp(r'\.(mp4|m4a|mp3|webm|mov|mkv)$', caseSensitive: false)
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
    setState(() { busy = true; stopYoutube = false; progress = 0; lastSavedFile = null; status = 'Videoformate werden ermittelt'; });
    final tempFiles = <File>[];
    try {
      final video = await youtube.videos.get(uri.toString());
      final manifest = await youtube.videos.streams.getManifest(video.id);
      if (stopYoutube) return;
      final directory = await getApplicationDocumentsDirectory();
      final base = '${directory.path}${Platform.pathSeparator}${video.id.value}';
      final audio = manifest.audioOnly.isNotEmpty ? manifest.audioOnly.withHighestBitrate() : null;
      final hd = manifest.videoOnly.isNotEmpty ? (manifest.videoOnly.toList()..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height))).first : null;
      final muxed = manifest.muxed.isNotEmpty ? (manifest.muxed.toList()..sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height))).first : null;
      Future<File> saveStream(StreamInfo info, String path, String description, double start, double span) async {
        final file = File(path);
        tempFiles.add(file);
        final sink = file.openWrite();
        var received = 0;
        try {
          if (mounted) setState(() => status = description);
          await for (final chunk in youtube.videos.streams.get(info)) {
            if (stopYoutube) break;
            sink.add(chunk);
            received += chunk.length;
            if (mounted && info.size.totalBytes > 0) {
              setState(() => progress = start + span * (received / info.size.totalBytes).clamp(0.0, 1.0));
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (stopYoutube) throw StateError('Abgebrochen');
        return file;
      }
      late File output;
      if (audioOnly) {
        if (audio == null) throw StateError('Kein Audiostream verfügbar');
        output = await saveStream(audio, '$base.${audio.container.name}', 'Audio wird geladen', 0, 1);
      } else if (hd != null && audio != null) {
        final videoFile = await saveStream(hd, '$base.video.${hd.container.name}', 'HD-Video wird geladen', 0, 0.7);
        final audioFile = await saveStream(audio, '$base.audio.${audio.container.name}', 'Ton wird geladen', 0.7, 0.25);
        output = File('$base.${hd.container.name == 'mp4' ? 'mp4' : 'mkv'}');
        if (mounted) setState(() { status = 'HD-Video und Ton werden zusammengefügt'; progress = 0.95; });
        String quote(String value) => '"${value.replaceAll('"', r'\\"')}"';
        final session = await FFmpegKit.execute('-y -i ${quote(videoFile.path)} -i ${quote(audioFile.path)} -map 0:v:0 -map 1:a:0 -c copy ${quote(output.path)}');
        final code = await session.getReturnCode();
        if (!ReturnCode.isSuccess(code)) throw StateError('Zusammenfügen fehlgeschlagen: ${await session.getOutput()}');
      } else if (muxed != null) {
        output = await saveStream(muxed, '$base.${muxed.container.name}', 'Video wird geladen', 0, 1);
      } else {
        throw StateError('Kein unterstützter Videostream verfügbar');
      }
      if (stopYoutube) throw StateError('Abgebrochen');
      for (final file in tempFiles) {
        if (file.path != output.path && await file.exists()) await file.delete();
      }
      if (mounted) {
        setState(() {
        lastSavedFile = output.path;
        downloadedFiles.remove(output.path);
        downloadedFiles.insert(0, output.path);
        status = 'Gespeichert: ${output.path}';
        progress = 1;
        });
      }
    } catch (e) {
      if (mounted) { setState(() => status = 'Downloadfehler: $e'); }
      for (final file in tempFiles) {
        if (await file.exists()) await file.delete();
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
