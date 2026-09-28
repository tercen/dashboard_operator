import 'package:sci_http_client/content_codec.dart';
import 'package:sci_http_client/error.dart';
import 'package:sci_http_client/http_client.dart' as http_api;

/// A stored user document exactly as the server sent it, decoded to a map
/// and nothing more.
///
/// Tag edits go through this, not the pinned client's typed `User`: that
/// model drops every field it does not know, and sending it back would wipe
/// those fields on the server. Here the document goes back as it came, with
/// only `tags` replaced.
class UserDocument {
  final Map<String, dynamic> json;
  UserDocument(Map json) : json = Map<String, dynamic>.from(json);

  String get id => '${json['id'] ?? ''}';
  String get rev => '${json['rev'] ?? ''}';

  /// The stored tags that are non-empty strings, in their stored order,
  /// each once: a tag stored twice is one chip.
  List<String> get tags => {
        for (final t in (json['tags'] as List?) ?? const [])
          if (t is String && t.isNotEmpty) t,
      }.toList();

  /// This document with [removed] taken out of `tags` and [added] put at the
  /// end; every other key, and its place, as stored. A removed tag goes
  /// wherever it is stored; an added one already stored is not added again.
  /// A stored entry that is not a tag this page shows (null, a number) is
  /// left where it is.
  UserDocument withTagEdit(
      {Set<String> removed = const {}, List<String> added = const []}) {
    final stored = (json['tags'] as List?) ?? const [];
    final copy = Map<String, dynamic>.from(json);
    copy['tags'] = [
      for (final t in stored)
        if (!removed.contains(t)) t,
      for (final t in added)
        if (!stored.contains(t)) t,
    ];
    return UserDocument(copy);
  }
}

/// The trimmed tag an admin typed, or why it is not added: empty, or
/// already in [current].
({String? tag, String? problem}) checkNewTag(
    String typed, List<String> current) {
  final tag = typed.trim();
  if (tag.isEmpty) return (tag: null, problem: 'A tag cannot be empty');
  if (current.contains(tag)) {
    return (tag: null, problem: '"$tag" is already a tag');
  }
  return (tag: tag, problem: null);
}

/// The generic `api/v1/user` get and update, carried raw. The server's
/// update checks the document's `rev`: a document changed since it was
/// read is refused with a conflict (409), which is raised, never retried.
class UserDocumentApi {
  final Uri base;
  final http_api.HttpClient client;
  final ContentCodec codec;

  UserDocumentApi(this.base, this.client, {ContentCodec? codec})
      : codec = codec ?? ContentCodec.tson();

  Uri get _uri => http_api.HttpClient.ResolveUri(base, 'api/v1/user');

  /// GET api/v1/user?id= — the stored document.
  Future<UserDocument> get(String id) async {
    final response = await client.get(
        _uri.replace(queryParameters: {'id': id, 'useFactory': 'true'}),
        responseType: codec.responseType);
    if (response.statusCode != 200) throw _serviceError(response);
    final decoded = codec.decode(response.body);
    if (decoded is! Map) {
      throw ServiceError(
          500, 'user.decode', 'unexpected payload ${decoded.runtimeType}');
    }
    return UserDocument(decoded);
  }

  /// POST api/v1/user — stores [document] as it is, rev included. Returns
  /// the new rev.
  Future<String> update(UserDocument document) async {
    final response = await client.post(_uri,
        headers: codec.contentTypeHeader,
        responseType: codec.responseType,
        body: codec.encode(document.json));
    if (response.statusCode != 200) throw _serviceError(response);
    final decoded = codec.decode(response.body);
    return decoded is List && decoded.isNotEmpty ? '${decoded.first}' : '';
  }

  ServiceError _serviceError(http_api.Response response) {
    final status = response.statusCode ?? 0;
    try {
      final m = codec.decode(response.body) as Map;
      return ServiceError(status, '${m['error']}', '${m['reason']}');
    } catch (_) {
      return ServiceError(status, 'user.api', 'HTTP $status');
    }
  }
}
