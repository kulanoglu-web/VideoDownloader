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
  final searchController = TextEditingController();
  List<Video> searchResults = [];
  bool searching = false;
  String searchStatus = '';
  final dio = Dio();
  CancelToken? cancel;
  bool stopYoutube = false;
  bool audioOnly = false;
  int preferredHeight = 0;
  static const qualityChoices = <int, String>{0: 'Beste verfügbar', 2160: '4K · 2160p', 1440: '1440p', 1080: 'Full HD · 1080p', 720: 'HD · 720p', 480: '480p', 360: '360p', 240: '240p'};
  final youtube = YoutubeExplode();
  bool isYoutube(Uri uri) => const ['youtu.be','youtube.com','www.youtube.com','m.youtube.com','music.youtube.com'].contains(uri.host.toLowerCase());
  double progress = 0;
  int receivedBytes = 0;
  int totalBytes = 0;
  String downloadPhase = '';
  int currentItem = 0;
  int itemCount = 0;
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
  Future<void> searchYoutube() async {
    final query = searchController.text.trim();
    if (query.isEmpty || searching) return;
    setState(() {
      searching = true;
      searchStatus = 'YouTube wird durchsucht ...';
      searchResults = [];
    });
    try {
      final results = await youtube.search.search(query);
      if (!mounted) return;
      setState(() {
        searchResults = results.take(15).toList();
        searchStatus = searchResults.isEmpty ? 'Keine Videos gefunden' : '${searchResults.length} Videos gefunden';
      });
    } catch (e) {
      if (mounted) setState(() => searchStatus = 'Suche fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }
  Future<void> download() async {
    final links = url.text.split(RegExp(r'[\\s,]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (links.length > 1) {
      setState(() { itemCount = links.length; currentItem = 0; });
      for (var i = 0; i < links.length; i++) {
        if (stopYoutube && i > 0) break;
        if (mounted) setState(() => currentItem = i + 1);
        final link = Uri.tryParse(links[i]);
        if (link == null || ![\'http\',\'https\'].contains(link.scheme)) continue;
        if (isYoutube(link)) { await downloadYoutube(link); }
        else { url.text = links[i]; await downloadDirect(link); }
      }
      if (mounted) setState(() { itemCount = 0; currentItem = 0; });
      return;
    }
    itemCount = 0;
    currentItem = 0;
    final uri = Uri.tryParse(url.text.trim());
    if (uri == null || ![\'https\',\'http\'].contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => status = \'Bitte gültige HTTP(S)-URL eingeben\'); return;
    }
    if (isYoutube(uri)) { await downloadYoutube(uri); return; }
    await downloadDirect(uri);
  }
  Future<void> downloadDirect(Uri uri) async {
    final fileName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
    if (!RegExp(r'\.(mp4|m4a|mp3|webm|mov)$', caseSensitive: false).hasMatch(fileName)) {
      setState(() => status = 'Aktuell werden nur direkte Mediendatei-URLs unterstützt'); return;
    }
    setState(() { busy = true; progress = 0; receivedBytes = 0; totalBytes = 0; downloadPhase = 'Direktdownload'; lastSavedFile = null; status = 'Download läuft'; });
    cancel = CancelToken();
    try {
      final directory = await getApplicationDocumentsDirectory();
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final destination = '${directory.path}${Platform.pathSeparator}$safeName';
      await dio.downloadUri(uri, destination, cancelToken: cancel,
        onReceiveProgress: (received, total) {
          if (mounted) setState(() { receivedBytes = received; totalBytes = total; if (total > 0) progress = received / total; });
        });
      if (mounted) setState(() { lastSavedFile = destination; downloadedFiles.remove(destination); downloadedFiles.insert(0, destination); status = 'Gespeichert: $destination'; });
    } on DioException catch (e) {
      if (mounted) setState(() => status = CancelToken.isCancel(e) ? 'Abgebrochen' : 'Fehler: ${e.message}');
    } catch (e) {
      if (mounted) setState(() => status = 'Fehler: $e');
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> downloadYoutube(Uri uri) async {
    setState(() { busy = true; stopYoutube = false; progress = 0; receivedBytes = 0; totalBytes = 0; downloadPhase = 'Videoformate ermitteln'; lastSavedFile = null; status = 'Videoformate werden ermittelt'; });
    final tempFiles = <File>[];
    try {
      final video = await youtube.videos.get(uri.toString());
      final manifest = await youtube.videos.streams.getManifest(video.id);
      if (stopYoutube) return;
      final directory = await getApplicationDocumentsDirectory();
      final base = '${directory.path}${Platform.pathSeparator}${video.id.value}';
      final audio = manifest.audioOnly.isNotEmpty ? manifest.audioOnly.withHighestBitrate() : null;
      VideoStreamInfo? selectVideo(List<VideoStreamInfo> streams) {
        if (streams.isEmpty) return null;
        streams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
        if (preferredHeight == 0) return streams.first;
        for (final stream in streams) {
          if (stream.videoResolution.height <= preferredHeight) return stream;
        }
        return streams.last;
      }
      final hd = selectVideo(manifest.videoOnly.toList());
      final muxed = selectVideo(manifest.muxed.toList());
      Future<File> saveStream(StreamInfo info, String path, String description, double start, double span) async {
        final file = File(path);
        tempFiles.add(file);
        final sink = file.openWrite();
        var received = 0;
        try {
          if (mounted) setState(() { status = description; downloadPhase = description; receivedBytes = 0; totalBytes = info.size.totalBytes; });
          await for (final chunk in youtube.videos.streams.get(info)) {
            if (stopYoutube) break;
            sink.add(chunk);
            received += chunk.length;
            if (mounted && info.size.totalBytes > 0) {
              setState(() { receivedBytes = received; progress = start + span * (received / info.size.totalBytes).clamp(0.0, 1.0); });
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
        if (mounted) setState(() { status = 'HD-Video und Ton werden zusammengefügt'; downloadPhase = 'Zusammenfügen'; receivedBytes = 0; totalBytes = 0; progress = 0.95; });
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
  @override void dispose() { cancel?.cancel(); youtube.close(); dio.close(); url.dispose(); searchController.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('VideoDownloader')),
    body: Padding(padding: const EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Werbefrei · Lokal · Ohne Konto'),
      const SizedBox(height: 12),
      TextField(
        controller: searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => searchYoutube(),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: 'Auf YouTube suchen',
          suffixIcon: IconButton(
            tooltip: 'Suchen',
            onPressed: searching ? null : searchYoutube,
            icon: const Icon(Icons.search),
          ),
        ),
      ),
      if (searching) const LinearProgressIndicator(),
      if (searchStatus.isNotEmpty) Text(searchStatus),
      if (searchResults.isNotEmpty)
        SizedBox(
          height: 230,
          child: ListView.builder(
            itemCount: searchResults.length,
            itemBuilder: (context, index) {
              final video = searchResults[index];
              return ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(video.author, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.download),
                onTap: busy ? null : () {
                  setState(() {
                    url.text = 'https://www.youtube.com/watch?v=${video.id.value}';
                    searchStatus = 'Ausgewählt: ${video.title}';
                  });
                  download();
                },
              );
            },
          ),
        ),
      const SizedBox(height: 12),
      TextField(controller: url, minLines: 1, maxLines: 4, decoration: const InputDecoration(
        border: OutlineInputBorder(), labelText: 'Video-Links (mehrere mit Leerzeichen oder Zeilenumbruch)')),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(
        onPressed: busy ? null : pasteLink,
        icon: const Icon(Icons.content_paste), label: const Text('Link einfügen'))),
      DropdownButtonFormField<int>(
        initialValue: preferredHeight,
        decoration: const InputDecoration(labelText: 'Videoqualität', border: OutlineInputBorder()),
        items: qualityChoices.entries.map((entry) => DropdownMenuItem<int>(
          value: entry.key, child: Text(entry.value))).toList(),
        onChanged: busy || audioOnly ? null : (value) => setState(() => preferredHeight = value ?? 0),
      ),
      SwitchListTile(title: const Text('Nur Audio herunterladen'), value: audioOnly,
        onChanged: busy ? null : (value) => setState(() => audioOnly = value)),
      const SizedBox(height: 16),
      FilledButton(onPressed: busy ? null : download, child: const Text('Herunterladen')),
      if (busy) TextButton(onPressed: () { stopYoutube = true; cancel?.cancel('Abgebrochen'); }, child: const Text('Abbrechen')),
      const SizedBox(height: 16),
      if (busy) ...[
        LinearProgressIndicator(value: progress == 0 ? null : progress),
        const SizedBox(height: 6),
        Text('${(progress * 100).toStringAsFixed(1)} % · $downloadPhase'
            '${itemCount > 1 ? ' · Video $currentItem von $itemCount' : ''}'),
        if (totalBytes > 0)
          Text('${(receivedBytes / 1048576).toStringAsFixed(1)} MB von '
              '${(totalBytes / 1048576).toStringAsFixed(1)} MB'),
      ],
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
