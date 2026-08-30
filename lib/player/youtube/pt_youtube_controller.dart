import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:synctogether/diagnostics.dart';

enum PTYtPlayerState { unknown, unstarted, ended, playing, paused, buffering, cued }

PTYtPlayerState _stateFromCode(num? code) => switch (code?.toInt()) {
  -1 => PTYtPlayerState.unstarted,
  0 => PTYtPlayerState.ended,
  1 => PTYtPlayerState.playing,
  2 => PTYtPlayerState.paused,
  3 => PTYtPlayerState.buffering,
  5 => PTYtPlayerState.cued,
  _ => PTYtPlayerState.unknown,
};

const _kReadyDeadline = Duration(seconds: 20);
const _kSeekPositionHold = Duration(milliseconds: 400);

class PTYouTubeController extends ChangeNotifier {
  PTYouTubeController(this._videoId) {
    unawaited(_serve());
  }

  String _videoId;
  String get videoId => _videoId;

  String? _servedVideoId;

  HttpServer? _server;
  InAppWebViewController? _web;
  Timer? _readyDeadline;
  bool _disposed = false;
  bool _pageRequested = false;
  bool _commandFailureReported = false;
  DateTime _positionHoldUntil = DateTime.fromMillisecondsSinceEpoch(0);

  Uri? _pageUrl;
  Uri? get pageUrl => _pageUrl;

  bool _isReady = false;
  bool get isReady => _isReady;

  PTYtPlayerState _playerState = .unknown;
  PTYtPlayerState get playerState => _playerState;

  Duration _position = Duration.zero;
  Duration get position => _position;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  int? _errorCode;
  int? get errorCode => _errorCode;
  bool get hasError => _errorCode != null;

  int _volume = 100;

  Future<void> _serve() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_disposed) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen((request) {
        if (request.uri.path != '/') {
          request.response.statusCode = HttpStatus.notFound;
          request.response.close();
          return;
        }
        _pageRequested = true;
        _servedVideoId = _videoId;
        trace('player page requested', category: 'youtube');
        request.response
          ..headers.contentType = ContentType.html
          ..write(_pageHtml(server.port, _videoId));
        request.response.close();
      });
      _pageUrl = Uri.parse('http://localhost:${server.port}/');
      trace('serving player', category: 'youtube', data: {'url': '$_pageUrl'});
      _armReadyDeadline();
      notifyListeners();
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting the YouTube loopback server');
    }
  }

  void _armReadyDeadline() {
    _readyDeadline?.cancel();
    _readyDeadline = Timer(_kReadyDeadline, () {
      if (_disposed || _isReady) return;
      reportNonFatal(
        StateError(
          'The YouTube embed was not ready after ${_kReadyDeadline.inSeconds}s '
          '(webview attached: ${_web != null}, page requested: $_pageRequested)',
        ),
        StackTrace.current,
        during: 'loading the YouTube player',
      );
    });
  }

  void attach(InAppWebViewController web) {
    _web = web;
    web.addJavaScriptHandler(handlerName: 'ytReady', callback: _onReady);
    web.addJavaScriptHandler(handlerName: 'ytState', callback: _onStateChange);
    web.addJavaScriptHandler(handlerName: 'ytTick', callback: _onTick);
    web.addJavaScriptHandler(handlerName: 'ytError', callback: _onError);
  }

  Map<String, dynamic> _payload(List<dynamic> args) {
    if (args.isEmpty) return const {};
    final first = args.first;
    return first is Map ? first.cast<String, dynamic>() : const {};
  }

  void _onReady(List<dynamic> args) {
    if (_disposed) return;
    _readyDeadline?.cancel();
    _isReady = true;
    _applySnapshot(_payload(args));
    trace('player ready', category: 'youtube', data: {'videoId': _videoId});
    _push('ptVolume($_volume)');
    if (_servedVideoId != null && _servedVideoId != _videoId) {
      _push("ptLoad('$_videoId')");
    }
    notifyListeners();
  }

  void _onStateChange(List<dynamic> args) {
    if (_disposed) return;
    final data = _payload(args);
    _playerState = _stateFromCode(data['state'] as num?);
    _applySnapshot(data);
    notifyListeners();
  }

  void _onTick(List<dynamic> args) {
    if (_disposed) return;
    final before = (_position, _duration);
    _applySnapshot(_payload(args));
    if (before != (_position, _duration)) notifyListeners();
  }

  void _onError(List<dynamic> args) {
    if (_disposed) return;
    _errorCode = (_payload(args)['code'] as num?)?.toInt() ?? -1;
    notifyListeners();
  }

  void _applySnapshot(Map<String, dynamic> data) {
    final seconds = (data['duration'] as num?)?.toDouble() ?? 0;
    if (seconds > 0) _duration = Duration(milliseconds: (seconds * 1000).round());
    if (DateTime.now().isBefore(_positionHoldUntil)) return;
    final at = (data['position'] as num?)?.toDouble() ?? 0;
    _position = Duration(milliseconds: (at * 1000).round());
  }

  void play() => _push('ptPlay()');

  void pause() => _push('ptPause()');

  void seekTo(Duration position) {
    if (_disposed) return;
    _position = position;
    _positionHoldUntil = DateTime.now().add(_kSeekPositionHold);
    _push('ptSeek(${position.inMilliseconds / 1000})');
    notifyListeners();
  }

  void setVolume(int volume) {
    _volume = volume.clamp(0, 100);
    _push('ptVolume($_volume)');
  }

  void loadVideo(String videoId) {
    if (_disposed || videoId == _videoId) return;
    _videoId = videoId;
    _position = Duration.zero;
    _duration = Duration.zero;
    _errorCode = null;
    _playerState = .unstarted;
    _push("ptLoad('$videoId')");
    notifyListeners();
  }

  Future<void> _push(String js) async {
    final web = _web;
    if (web == null || _disposed) return;
    try {
      await web.evaluateJavascript(source: js);
    } catch (e, s) {
      if (_disposed || _commandFailureReported) return;
      _commandFailureReported = true;
      reportNonFatal(e, s, during: 'sending a command to the YouTube embed');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _readyDeadline?.cancel();
    _server?.close(force: true);
    _web = null;
    super.dispose();
  }

  String _pageHtml(int port, String videoId) =>
      '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  html, body { margin: 0; padding: 0; height: 100%; background: transparent; overflow: hidden; }
  body { pointer-events: none; }
  #player, iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
</style>
</head>
<body>
<div id="player"></div>
<script src="https://www.youtube.com/iframe_api"></script>
<script>
var player = null;
var ready = false;
var ticker = null;

function post(name, data) {
  var bridge = window.flutter_inappwebview;
  if (bridge && bridge.callHandler) { bridge.callHandler(name, data); }
}

function snapshot() {
  if (!player || !player.getCurrentTime) { return { position: 0, duration: 0 }; }
  return {
    position: player.getCurrentTime() || 0,
    duration: player.getDuration() || 0
  };
}

function onYouTubeIframeAPIReady() {
  player = new YT.Player('player', {
    host: 'https://www.youtube-nocookie.com',
    videoId: '$videoId',
    playerVars: {
      autoplay: 0,
      controls: 0,
      rel: 0,
      iv_load_policy: 3,
      disablekb: 1,
      playsinline: 1,
      modestbranding: 1,
      fs: 0,
      cc_load_policy: 1,
      cc_lang_pref: 'en',
      vq: 'hd1080',
      enablejsapi: 1,
      origin: 'http://localhost:$port'
    },
    events: {
      onReady: function () {
        ready = true;
        post('ytReady', snapshot());
        startTicker();
      },
      onStateChange: function (event) {
        var data = snapshot();
        data.state = event.data;
        post('ytState', data);
      },
      onError: function (event) {
        post('ytError', { code: event.data });
      }
    }
  });
}

function startTicker() {
  if (ticker) { return; }
  ticker = setInterval(function () { post('ytTick', snapshot()); }, 250);
}

function ptPlay() { if (ready) { player.playVideo(); } }
function ptPause() { if (ready) { player.pauseVideo(); } }
function ptSeek(seconds) { if (ready) { player.seekTo(seconds, true); } }
function ptVolume(level) { if (ready) { player.setVolume(level); } }
function ptLoad(id) {
  if (ready) { player.cueVideoById({ videoId: id, suggestedQuality: 'hd1080' }); }
}
</script>
</body>
</html>
''';
}
