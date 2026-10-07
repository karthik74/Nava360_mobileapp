// Fake Dio backend for the visual-preview harness: answers every request from
// a list of (method, path-regex) routes, wrapping data in the backend's
// {"success":true,"message":null,"data":...} envelope.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Wrap a fixture value in Raw(...) to send it WITHOUT the envelope.
class Raw {
  const Raw(this.body, {this.status = 200});
  final Object? body;
  final int status;
}

typedef FixtureFn = Object? Function(RequestOptions req, RegExpMatch m);

class _Route {
  _Route(this.method, this.pattern, this.fn);
  final String method; // '*' = any
  final RegExp pattern;
  final FixtureFn fn;
}

class FakeApi implements HttpClientAdapter {
  final List<_Route> _routes = [];

  /// "METHOD /path?query" of requests no route matched (defaults served).
  final Set<String> unmatched = {};

  /// Every request seen, in order ("METHOD /path?query").
  final List<String> seen = [];

  /// Registers a route. [path] is a regex matched against the full request
  /// path (anchored). Later registrations win, so tests can override.
  void on(String method, String path, FixtureFn fn) {
    _routes.add(_Route(method.toUpperCase(), RegExp('^$path\$'), fn));
  }

  void get(String path, Object? data) => on('GET', path, (_, __) => data);
  void getFn(String path, FixtureFn fn) => on('GET', path, fn);
  void post(String path, Object? data) => on('POST', path, (_, __) => data);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final method = options.method.toUpperCase();
    final path = options.uri.path;
    final q = options.uri.query;
    final label = '$method $path${q.isEmpty ? '' : '?$q'}';
    seen.add(label);

    // Binary downloads (photos, PDFs): 404 so UIs fall back to initials etc.
    if (options.responseType == ResponseType.bytes ||
        options.responseType == ResponseType.stream) {
      return ResponseBody.fromBytes(Uint8List(0), 404);
    }

    Object? data;
    var matched = false;
    for (final r in _routes.reversed) {
      if (r.method != '*' && r.method != method) continue;
      final m = r.pattern.firstMatch(path);
      if (m == null) continue;
      data = r.fn(options, m);
      matched = true;
      break;
    }
    if (!matched) {
      unmatched.add(label);
      data = _defaultFor(method, path, options.uri.queryParameters);
      debugPrint('[pro_preview] unmatched $label');
    }

    final int status;
    final Object? body;
    if (data is Raw) {
      status = data.status;
      body = data.body;
    } else {
      status = 200;
      body = {'success': true, 'message': null, 'data': data};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  static Object? _defaultFor(
      String method, String path, Map<String, String> query) {
    if (method != 'GET') return <String, Object?>{};
    final paged = query.containsKey('page') ||
        query.containsKey('size') ||
        path.endsWith('/paged') ||
        path.endsWith('/page');
    if (paged) return page(const []);
    final last = path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
    final listy = last.endsWith('s') ||
        const {'mine', 'my', 'list', 'all', 'team', 'history', 'pending'}
            .contains(last);
    if (listy && !last.endsWith('status') && !last.endsWith('stats')) {
      return const <Object?>[];
    }
    return <String, Object?>{};
  }

  @override
  void close({bool force = false}) {}
}

/// Spring Data page.
Map<String, Object?> page(List<Object?> content, {int size = 20}) => {
      'content': content,
      'totalElements': content.length,
      'totalPages': content.isEmpty ? 0 : 1,
      'number': 0,
      'size': size,
      'first': true,
      'last': true,
      'numberOfElements': content.length,
      'empty': content.isEmpty,
    };
