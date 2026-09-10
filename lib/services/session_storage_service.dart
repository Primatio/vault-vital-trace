import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/polar_sample.dart';
import '../models/session_metadata.dart';
import '../models/session_summary.dart';

class _UploadFile {
  const _UploadFile({
    required this.field,
    required this.localName,
    this.sentName,
  });

  final String field;
  final String localName;
  final String? sentName;
}

class SessionStorageService {
  static const sessionsRootName = 'sessions';

  Future<Directory> sessionsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, sessionsRootName));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  String buildFolderName({
    required DateTime startUtc,
    required String subjectId,
  }) {
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(startUtc.toLocal());
    final safeSubject = subjectId
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final subject = safeSubject.isEmpty ? 'unknown' : safeSubject;
    return 'session_${stamp}_$subject';
  }

  Future<Directory> createSessionDirectory(String folderName) async {
    final root = await sessionsRoot();
    final dir = Directory(p.join(root.path, folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> writeMetadata(Directory dir, SessionMetadata metadata) async {
    final file = File(p.join(dir.path, 'metadata.json'));
    await file.writeAsString(metadata.toJsonString());
    return file;
  }

  Future<File> writePolarCsv(
    Directory dir,
    List<PolarSample> samples,
  ) async {
    final file = File(p.join(dir.path, 'polar_data.csv'));
    final buffer = StringBuffer()..writeln(PolarSample.csvHeader);
    for (final sample in samples) {
      buffer.writeln(sample.toCsvRow());
    }
    await file.writeAsString(buffer.toString());
    return file;
  }

  Future<File> writeFaceTracking(
    Directory dir,
    List<FaceTrackingEvent> events,
  ) async {
    final file = File(p.join(dir.path, 'face_tracking.json'));
    final payload = {
      'event_count': events.length,
      'events': events.map((e) => e.toJson()).toList(),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    return file;
  }

  Future<File?> moveVideoIntoSession({
    required Directory dir,
    required String sourcePath,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    final dest = File(p.join(dir.path, 'video.mp4'));
    if (await dest.exists()) {
      await dest.delete();
    }
    return source.rename(dest.path);
  }

  Future<List<SessionSummary>> listSessions() async {
    final root = await sessionsRoot();
    final entries = root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));

    final sessions = <SessionSummary>[];
    for (final dir in entries) {
      final summary = await loadSessionSummary(dir);
      if (summary != null) {
        sessions.add(summary);
      }
    }
    return sessions;
  }

  Future<SessionSummary?> loadSessionSummary(Directory dir) async {
    final metadataFile = File(p.join(dir.path, 'metadata.json'));
    if (!await metadataFile.exists()) {
      return null;
    }

    try {
      final metadata = SessionMetadata.fromJsonString(
        await metadataFile.readAsString(),
      );
      final video = File(p.join(dir.path, 'video.mp4'));
      final polar = File(p.join(dir.path, 'polar_data.csv'));
      final preview = File(p.join(dir.path, 'preview.jpg'));

      return SessionSummary(
        metadata: metadata,
        directoryPath: dir.path,
        hasVideo: await video.exists(),
        hasPolarData: await polar.exists(),
        hasMetadata: true,
        hasPreview: await preview.exists(),
        videoBytes: await video.exists() ? await video.length() : null,
        polarBytes: await polar.exists() ? await polar.length() : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteSession(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<void> shareSession(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return;

    final files = dir
        .listSync()
        .whereType<File>()
        .map((f) => XFile(f.path))
        .toList();

    if (files.isEmpty) return;

    await SharePlus.instance.share(
      ShareParams(
        files: files,
        subject: p.basename(directoryPath),
        text: 'Vault rPPG session: ${p.basename(directoryPath)}',
      ),
    );
  }

  // Configured via .env (see .env.example). NOTE: localhost refers to the
  // device itself, not your dev machine, so a real phone must target your
  // computer's LAN IP. Update SESSION_UPLOAD_URL if your machine's IP changes
  // (e.g. after reconnecting to Wi-Fi).
  static const _apiKeyHeader = 'x-api-key';

  String get _sessionUploadUrl {
    final url = dotenv.env['SESSION_UPLOAD_URL'];
    if (url == null || url.isEmpty) {
      throw StateError(
        'SESSION_UPLOAD_URL is not set. Copy .env.example to .env and fill it in.',
      );
    }
    return url;
  }

  // Must match API_KEY in the vault-vital-trace-api .env, sent in the header
  // named by API_KEY_HEADER (defaults to x-api-key).
  String get _apiKey {
    final key = dotenv.env['SESSION_UPLOAD_API_KEY'];
    if (key == null || key.isEmpty) {
      throw StateError(
        'SESSION_UPLOAD_API_KEY is not set. Copy .env.example to .env and fill it in.',
      );
    }
    return key;
  }

  // Maps the local session file to the multipart field name the API expects
  // (see UPLOAD_FIELDS in the API). The API validates by the extension of the
  // sent filename, so the video is uploaded as .mov.
  static const _uploadFields = <_UploadFile>[
    _UploadFile(field: 'videoFile', localName: 'video.mp4', sentName: 'video.mov'),
    _UploadFile(field: 'jsonFile1', localName: 'metadata.json'),
    _UploadFile(field: 'jsonFile2', localName: 'face_tracking.json'),
    _UploadFile(field: 'csvFile', localName: 'polar_data.csv'),
  ];

  Future<void> uploadSession({
    required String directoryPath,
    required String sessionId,
  }) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) {
      throw StateError('Session directory does not exist');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(_sessionUploadUrl),
    );
    request.headers[_apiKeyHeader] = _apiKey;
    request.fields['sessionId'] = sessionId;

    for (final spec in _uploadFields) {
      final file = File(p.join(dir.path, spec.localName));
      if (!await file.exists()) {
        throw StateError('Missing required file for upload: ${spec.localName}');
      }
      request.files.add(
        await http.MultipartFile.fromPath(
          spec.field,
          file.path,
          filename: spec.sentName ?? spec.localName,
        ),
      );
    }

    final response = await request.send();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw HttpException(
        'Upload failed (${response.statusCode}): $body',
      );
    }
  }

  Future<Map<String, int>> fileSizes(String directoryPath) async {
    final dir = Directory(directoryPath);
    final result = <String, int>{};
    if (!await dir.exists()) return result;
    for (final entity in dir.listSync()) {
      if (entity is File) {
        result[p.basename(entity.path)] = await entity.length();
      }
    }
    return result;
  }
}
