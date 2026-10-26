import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'file_import_service.dart';

class LanShareFile {
  const LanShareFile({
    required this.name,
    required this.path,
    required this.size,
    required this.extension,
  });

  final String name;
  final String path;
  final int size;
  final String extension;

  factory LanShareFile.fromJson(Map<String, dynamic> json) => LanShareFile(
    name: json['name'] as String,
    path: json['path'] as String,
    size: (json['size'] as num).toInt(),
    extension: (json['extension'] as String).toLowerCase(),
  );

  ImportSource asImportSource(LanShareClient client) => ImportSource(
    name: name,
    size: size,
    openStream: () => client.downloadStream(this),
  );
}

/// Client for the companion Windows LAN sharing script. The QR URL carries a
/// short-lived random token; the app never exposes a listening port itself.
class LanShareClient {
  LanShareClient._({required this.baseUri, required this.token});

  final Uri baseUri;
  final String token;
  final http.Client _http = http.Client();

  static LanShareClient fromQrText(String rawValue) {
    final scanned = Uri.tryParse(rawValue.trim());
    if (scanned == null || scanned.scheme != 'http' || scanned.host.isEmpty) {
      throw const FormatException('二维码不是有效的局域网共享链接');
    }
    final token = scanned.queryParameters['token'];
    if (token == null || token.isEmpty) {
      throw const FormatException('共享链接缺少访问令牌，请重新生成电脑端二维码');
    }
    return LanShareClient._(
      baseUri: Uri(
        scheme: scanned.scheme,
        host: scanned.host,
        port: scanned.port,
      ),
      token: token,
    );
  }

  Uri _endpoint(String path, [Map<String, String> extra = const {}]) =>
      baseUri.replace(path: path, queryParameters: {'token': token, ...extra});

  Future<List<LanShareFile>> listFiles() async {
    final response = await _http
        .get(_endpoint('/api/files'))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('电脑共享服务返回 ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['files'] is! List) {
      throw const FormatException('电脑端返回了无法识别的文件列表');
    }
    return (decoded['files'] as List)
        .whereType<Map<String, dynamic>>()
        .map(LanShareFile.fromJson)
        .toList();
  }

  Stream<List<int>> downloadStream(LanShareFile file) async* {
    final request = http.Request(
      'GET',
      _endpoint('/api/download', {'path': file.path}),
    );
    final response = await _http
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      final message = await response.stream.bytesToString();
      throw HttpException(
        '下载 ${file.name} 失败：HTTP ${response.statusCode} ${message.trim()}',
      );
    }
    yield* response.stream;
  }

  void close() => _http.close();
}
