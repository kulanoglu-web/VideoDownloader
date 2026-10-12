import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';

void main() => runApp(const VideoDownloader());
class VideoDownloader extends StatelessWidget {
  const VideoDownloader({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'VideoDownloader',
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF56D8C7),
        brightness: Brightness.dark,
        surface: const Color(0xFF151B29),
      ),
      scaffoldBackgroundColor: const Color(0xFF0B1020),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF0B1020), centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF202A3B),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF56D8C7), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      ),
      cardTheme: CardThemeData(color: const Color(0xFF172033), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    ),
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
  StreamSubscription<List<int>>? activeYoutubeStream;
  Completer<void>? activeYoutubeWait;
  Completer<void>? cancelSignal;
  bool cancelling = false;
  bool audioOnly = false;
  int preferredHeight = 720;
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
  void cancelDownload() {
    if (!busy) return;
    stopYoutube = true;
    cancelling = true;
    cancel?.cancel('Abgebrochen');
    activeYoutubeStream?.cancel();
    final pending = activeYoutubeWait;
    if (pending != null && !pending.isCompleted) pending.complete();
    final signal = cancelSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    setState(() { busy = false; status = 'Abgebrochen'; downloadPhase = 'Abgebrochen'; });
  }
  Future<T> interruptible<T>(Future<T> operation, Duration timeout) async {
    final signal = cancelSignal;
    if (signal == null) return operation.timeout(timeout);
    final result = await Future.any<Object>([
      operation.timeout(timeout),
      signal.future.then<Object>((_) => throw StateError('Abgebrochen')),
    ]);
    return result as T;
  }
  Future<void> download() async {
    if (busy) return;
    stopYoutube = false;
    cancelling = false;
    cancelSignal = Completer<void>();
    final links = url.text.split(RegExp(r'[\s,]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (links.length > 1) {
      setState(() { itemCount = links.length; currentItem = 0; });
      for (var i = 0; i < links.length; i++) {
        if (stopYoutube && i > 0) break;
        if (mounted) setState(() => currentItem = i + 1);
        final link = Uri.tryParse(links[i]);
        if (link == null || !['http','https'].contains(link.scheme)) { continue; }
        if (isYoutube(link)) { await downloadYoutube(link); }
        else { url.text = links[i]; await downloadDirect(link); }
      }
      if (mounted) setState(() { itemCount = 0; currentItem = 0; });
      return;
    }
    itemCount = 0;
    currentItem = 0;
    final uri = Uri.tryParse(url.text.trim());
    if (uri == null || !['https','http'].contains(uri.scheme) || uri.host.isEmpty) {
      setState(() => status = 'Bitte gültige HTTP(S)-URL eingeben'); return;
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
    setState(() { busy = true; progress = 0; receivedBytes = 0; totalBytes = 0; downloadPhase = 'Videoformate ermitteln'; lastSavedFile = null; status = 'Videoformate werden ermittelt'; });
    final tempFiles = <File>[];
    try {
      final video = await interruptible(youtube.videos.get(uri.toString()), const Duration(seconds: 25));
      final manifest = await interruptible(youtube.videos.streams.getManifest(video.id), const Duration(seconds: 35));
      if (stopYoutube) throw StateError('Abgebrochen');
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
          final done = Completer<void>();
          activeYoutubeWait = done;
          activeYoutubeStream = youtube.videos.streams.get(info)
              .timeout(const Duration(seconds: 20)).listen(
            (chunk) {
              if (stopYoutube) return;
              sink.add(chunk);
              received += chunk.length;
              if (mounted && info.size.totalBytes > 0) {
                setState(() {
                  receivedBytes = received;
                  progress = start + span * (received / info.size.totalBytes).clamp(0.0, 1.0);
                });
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!done.isCompleted) done.completeError(error, stack);
            },
            onDone: () { if (!done.isCompleted) done.complete(); },
            cancelOnError: true,
          );
          await done.future;
          activeYoutubeStream = null;
          activeYoutubeWait = null;
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
      } else if (muxed != null && muxed.videoResolution.height >= (preferredHeight == 0 ? 720 : preferredHeight)) {
        output = await saveStream(muxed, '$base.${muxed.container.name}', 'Video mit Ton wird geladen', 0, 1);
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
      if (mounted && !stopYoutube) { setState(() => status = 'Downloadfehler: $e. Bitte 480p oder 360p versuchen.'); }
      for (final file in tempFiles) {
        if (await file.exists()) await file.delete();
      }
    } finally {
      activeYoutubeStream = null;
      activeYoutubeWait = null;
      if (mounted && !cancelling) setState(() => busy = false);
    }
  }
  @override void dispose() { cancel?.cancel(); youtube.close(); dio.close(); url.dispose(); searchController.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(children: [Icon(Icons.download_for_offline_rounded, color: Color(0xFF56D8C7)), SizedBox(width: 10), Text('VideoDownloader', style: TextStyle(fontWeight: FontWeight.w700))])),
    body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('DEINE MEDIATHEK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, color: Color(0xFF56D8C7))),
      const SizedBox(height: 5),
      const Text('Videos entdecken & speichern', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      const Text('Suche, Qualität wählen, Download starten', style: TextStyle(color: Colors.white60)),
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
          height: 270,
          child: ListView.builder(
            itemCount: searchResults.length,
            itemBuilder: (context, index) {
              final video = searchResults[index];
              return Card(margin: const EdgeInsets.symmetric(vertical: 4), child: ListTile(
                leading: const CircleAvatar(backgroundColor: Color(0xFF243C4A), child: Icon(Icons.play_arrow_rounded, color: Color(0xFF56D8C7))),
                title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(video.author, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.download_rounded, color: Color(0xFF56D8C7)),
                onTap: busy ? null : () {
                  setState(() {
                    url.text = 'https://www.youtube.com/watch?v=${video.id.value}';
                    searchStatus = 'Ausgewählt: ${video.title}';
                  });
                  download();
                },
              ));
            },
          ),
        ),
      const SizedBox(height: 20),
      const Text('DOWNLOAD EINRICHTEN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.4, color: Color(0xFF56D8C7))),
      const SizedBox(height: 10),
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
      FilledButton.icon(onPressed: busy ? null : download, icon: const Icon(Icons.file_download_rounded), label: const Text('Download starten', style: TextStyle(fontWeight: FontWeight.bold))),
      if (busy) OutlinedButton.icon(onPressed: cancelDownload, icon: const Icon(Icons.stop_circle_outlined), label: const Text('Download sofort abbrechen')),
      if (busy) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text('Aktueller Schritt: $status'))),
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
      if (!busy && lastSavedFile != null) ...[
        const Text('Speicherort der letzten Datei:', style: TextStyle(fontWeight: FontWeight.bold)),
        SelectableText(lastSavedFile!),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            final result = await OpenFilex.open(lastSavedFile!);
            if (!context.mounted) return;
            if (result.type != ResultType.done) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Datei konnte nicht geöffnet werden: ${result.message}')));
            }
          },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Datei öffnen'),
        ),
        OutlinedButton.icon(onPressed: () async {
          final file = File(lastSavedFile!);
          if (await file.exists()) {
            await Clipboard.setData(ClipboardData(text: lastSavedFile!));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dateipfad kopiert')));
          }
        }, icon: const Icon(Icons.copy), label: const Text('Dateipfad kopieren')),
      ],
      const SizedBox(height: 12), Text(status),
      const SizedBox(height: 18),
      const Text('DEINE DOWNLOADS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.4, color: Color(0xFF56D8C7))),
      const Text('Aktuell im internen App-Speicher', style: TextStyle(fontSize: 12, color: Colors.white60)),
      SizedBox(height: 220, child: ListView.builder(itemCount: downloadedFiles.length,
        itemBuilder: (context, index) {
          final file = downloadedFiles[index];
          return ListTile(leading: const Icon(Icons.video_file),
            title: Text(file.split(Platform.pathSeparator).last),
            subtitle: Text(file, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(icon: const Icon(Icons.copy),
              onPressed: () => Clipboard.setData(ClipboardData(text: file))));
        })),
    ]))));
}
