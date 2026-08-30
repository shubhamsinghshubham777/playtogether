import 'dart:async';

import 'package:synctogether/rooms/room_models.dart';

/// How far a member has got towards having the room's canonical media loaded.
/// Declaration order is the rank — "more ready" compares by [index], which is
/// what resolves a multi-device user to a single status.
enum ReadyStatus {
  none,
  selecting,
  loading,
  ready;

  static ReadyStatus fromWire(String? value) => switch (value) {
    'selecting' => .selecting,
    'loading' => .loading,
    'ready' => .ready,
    _ => .none,
  };

  String get wire => name;
}

class PresentMember {
  const PresentMember({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.joinedAt,
    this.avatarUrl,
    this.readyStatus = .none,
    this.loadedFileName,
    this.privacyMode = false,
  });

  final String userId;
  final String displayName;
  final String role;
  final DateTime joinedAt;
  final String? avatarUrl;

  /// A client that predates the readiness gate sends no status, which reads as
  /// [ReadyStatus.none] and holds the gate shut — the accepted trade-off.
  final ReadyStatus readyStatus;

  /// Basename this member actually has open, for the "they have `weird.mp4`" copy.
  final String? loadedFileName;

  final bool privacyMode;

  bool get isHost => role == 'host';
  bool get isReady => readyStatus == .ready;

  PresentMember withPrivacyMode(bool value) => PresentMember(
    userId: userId,
    displayName: displayName,
    role: role,
    joinedAt: joinedAt,
    avatarUrl: avatarUrl,
    readyStatus: readyStatus,
    loadedFileName: loadedFileName,
    privacyMode: value,
  );
}

/// Tri-state on purpose: before the first presence sync we simply don't know
/// who is in the room, and rendering that as `closed` flashes the waiting
/// overlay on every entry.
enum GateState { indeterminate, open, closed }

class ChatMessage {
  const ChatMessage({
    required this.senderId,
    required this.displayName,
    required this.content,
    required this.sentAt,
  });

  final String senderId;
  final String displayName;
  final String content;
  final DateTime sentAt;
}

enum RemoteActionKind { play, pause, seek }

/// A user-initiated remote playback action, surfaced for attribution UI. Only
/// emitted for genuine play/pause/seek broadcasts — never for mechanical
/// `state_response` application or `position_sync` drift correction, so
/// late-join and drift never read as someone touching the controls.
class RemoteAction {
  const RemoteAction({required this.senderId, required this.kind, this.position});

  final String senderId;
  final RemoteActionKind kind;
  final Duration? position;
}

/// History rows carry DB timestamps while live broadcasts carry sender-clock
/// timestamps, so exact keys don't exist — fuzzy-match to dedupe. Broadcasts
/// never replay, so this reload is the only way messages sent while we were
/// disconnected ever arrive.
const kChatMergeWindow = Duration(seconds: 10);

bool chatMessagesMatch(ChatMessage a, ChatMessage b) =>
    a.senderId == b.senderId &&
    a.content == b.content &&
    a.sentAt.difference(b.sentAt).abs() <= kChatMergeWindow;

void mergeChatHistory(List<ChatMessage> into, List<ChatMessage> history) {
  for (final h in history) {
    if (!into.any((m) => chatMessagesMatch(m, h))) into.add(h);
  }
  into.sort((a, b) => a.sentAt.compareTo(b.sentAt));
}

/// `ready` only means "something is open" — the name comparison is the gate's
/// job, which is what lets the UI tell "still loading" apart from "loaded the
/// wrong thing".
bool memberSatisfiesGate(PresentMember member, RoomMedia media) {
  if (!member.isReady) return false;
  if (media.kind == .local && member.loadedFileName != media.name) return false;
  return true;
}

bool memberClearsGate(PresentMember member, RoomMedia media, Set<String> waived) =>
    memberSatisfiesGate(member, media) || waived.contains(member.userId);

/// Nobody may start or scrub until every present member has the room's
/// canonical media loaded.
GateState evaluateGateState({
  required bool hasPresenceSynced,
  required RoomMedia media,
  required List<PresentMember> members,
  Set<String> waived = const {},
  String mediaUploadState = 'none',
}) {
  if (!hasPresenceSynced) return .indeterminate;
  if (!media.isSet) return .closed;
  if (mediaUploadState == 'uploading') return .closed;
  if (members.isEmpty) return .indeterminate;
  return members.every((m) => memberClearsGate(m, media, waived)) ? .open : .closed;
}

/// Everyone the room is still waiting on, for overlay/banner copy.
List<PresentMember> gateBlockersOf(
  RoomMedia media,
  List<PresentMember> members, {
  Set<String> waived = const {},
}) => media.isSet ? members.where((m) => !memberClearsGate(m, media, waived)).toList() : const [];

/// What the gate derives from a state change. Only the authority acts on it,
/// else the room gets one pause per member.
enum GateTransition { pause, resume }

GateTransition? gateTransitionFor({
  required GateState previous,
  required GateState next,
  required bool isAuthority,
  required bool roomPlaying,
  required bool pausedByGate,
}) {
  if (!isAuthority) return null;
  if (next == GateState.closed && previous == GateState.open) {
    // The decision is room-level: when the host opens a new file their own
    // player stops while everyone else plays on, and that is exactly when the
    // gate must pause — so it cannot be made from our own `isPlaying`.
    return roomPlaying ? GateTransition.pause : null;
  }
  if (next == GateState.open && previous == GateState.closed && pausedByGate) {
    return GateTransition.resume;
  }
  return null;
}

/// Our own position is only meaningful if we still have the room's media
/// loaded. If we are the one holding the gate up we have just opened something
/// else and sit at 0 — resuming everyone there would throw the room back to the
/// start. A null held position simply skips the realignment seek.
Duration? gateHeldPosition({
  required String? subjectUserId,
  required String userId,
  required Duration? Function() position,
}) => subjectUserId == userId ? null : position();

bool shouldAutoReopenLocalFile({
  required RoomMedia media,
  required String? storedFileName,
  required bool storedFileExists,
  required String? loadedFileName,
  required bool isPickerOpen,
}) {
  if (media.kind != .local || media.name == null) return false;
  if (isPickerOpen) return false;
  if (loadedFileName == media.name) return false;
  if (storedFileName != media.name) return false;
  return storedFileExists;
}

Duration playablePosition(Duration reported) => reported < Duration.zero ? Duration.zero : reported;

const kResumeTailWindow = Duration(seconds: 15);

Duration? resumeSeekPosition({required Duration? held, required Duration? mediaDuration}) {
  if (held == null || held <= Duration.zero) return null;
  if (mediaDuration != null && mediaDuration > Duration.zero) {
    if (held >= mediaDuration - kResumeTailWindow) return null;
    return held;
  }
  return held;
}

/// Host if present, else the earliest joiner; user id breaks ties so every
/// client elects the same person.
String? authorityAmong(Iterable<PresentMember> candidates) {
  if (candidates.isEmpty) return null;
  final host = candidates.where((m) => m.isHost).firstOrNull;
  if (host != null) return host.userId;
  return candidates.reduce((a, b) {
    final cmp = a.joinedAt.compareTo(b.joinedAt);
    if (cmp != 0) return cmp < 0 ? a : b;
    return a.userId.compareTo(b.userId) < 0 ? a : b;
  }).userId;
}

/// Collapses a channel's presence payloads to one entry per user. A user with
/// two devices counts once; of their devices the most-ready wins, so a second
/// idle device can't drag them back below the gate. Everything else in the
/// payload is per-user, not per-device, so picking a winner loses nothing.
List<PresentMember> mergePresence(
  Iterable<Map<String, dynamic>> payloads, {
  DateTime Function()? now,
}) {
  final clock = now ?? DateTime.now;
  final byUser = <String, PresentMember>{};
  final privateEverywhere = <String, bool>{};
  for (final p in payloads) {
    final uid = p['user_id'] as String?;
    if (uid == null) continue;
    final private = p['privacy_mode'] as bool? ?? false;
    privateEverywhere[uid] = (privateEverywhere[uid] ?? true) && private;
    final member = PresentMember(
      userId: uid,
      displayName: p['display_name'] as String? ?? 'Watcher',
      avatarUrl: p['avatar_url'] as String?,
      role: p['role'] as String? ?? 'member',
      joinedAt: DateTime.tryParse(p['joined_at'] as String? ?? '') ?? clock(),
      readyStatus: ReadyStatus.fromWire(p['ready_status'] as String?),
      loadedFileName: p['loaded_file_name'] as String?,
      privacyMode: private,
    );
    final existing = byUser[uid];
    if (existing == null || member.readyStatus.index > existing.readyStatus.index) {
      byUser[uid] = member;
    }
  }
  return [
    for (final entry in byUser.entries)
      entry.value.withPrivacyMode(privateEverywhere[entry.key] ?? false),
  ]..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
}

/// Last-action-wins ordering, and the monotonic stamp that makes it work.
class SyncOrdering {
  SyncOrdering({required this.userId, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final String userId;
  final DateTime Function() _now;

  int _lastIssued = 0;
  int _lastApplied = 0;

  int get lastApplied => _lastApplied;

  /// Strictly increasing per sender. [shouldApply] drops anything with
  /// `timestamp <= lastApplied`, and a wall-clock millisecond is not
  /// fine-grained enough: `_playPause` broadcasts play *and* seek in one
  /// synchronous block, so both stamped `DateTime.now()` and receivers silently
  /// dropped the second one. Every broadcast must stamp itself from here.
  int nextTimestamp() {
    final now = _now().millisecondsSinceEpoch;
    _lastIssued = now > _lastIssued ? now : _lastIssued + 1;
    return _lastIssued;
  }

  bool shouldApply(Map<String, dynamic> payload) {
    final senderId = payload['senderId'] as String;
    final timestamp = payload['timestamp'] as int;
    // self:false should exclude own events; defensive double-check.
    if (senderId == userId) return false;
    if (timestamp <= _lastApplied) return false;
    _lastApplied = timestamp;
    return true;
  }
}

bool presencePayloadsMatch(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key)) return false;
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

class TrailingThrottle<T> {
  TrailingThrottle({
    this.interval = const Duration(milliseconds: 250),
    this.maxCalls,
    this.window = const Duration(milliseconds: 250),
    this.equals,
    DateTime Function()? now,
    Timer Function(Duration, void Function())? schedule,
  }) : _now = now ?? DateTime.now,
       _schedule = schedule ?? Timer.new;

  final Duration interval;
  final int? maxCalls;
  final Duration window;
  final bool Function(T, T)? equals;
  final DateTime Function() _now;
  final Timer Function(Duration, void Function()) _schedule;

  final _sendTimes = <int>[];
  Timer? _flushTimer;
  T? _queued;
  bool _hasQueued = false;
  T? _lastSent;
  bool _hasSent = false;
  bool _waiveSpacing = false;
  bool _disposed = false;

  bool get hasPending => _hasQueued;

  int _deferralMs(int now) {
    _sendTimes.removeWhere((t) => now - t >= window.inMilliseconds);
    var wait = 0;
    if (_sendTimes.isNotEmpty && !_waiveSpacing) {
      final spacing = interval.inMilliseconds - (now - _sendTimes.last);
      if (spacing > wait) wait = spacing;
    }
    final budget = maxCalls;
    if (budget != null && _sendTimes.length >= budget) {
      final freeAt = window.inMilliseconds - (now - _sendTimes.first);
      if (freeAt > wait) wait = freeAt;
    }
    return wait;
  }

  bool _isRedundant(T value) => _hasSent && (equals?.call(_lastSent as T, value) ?? false);

  void _emit(T value, int now, void Function(T) send) {
    _waiveSpacing = false;
    _sendTimes.add(now);
    _lastSent = value;
    _hasSent = true;
    send(value);
  }

  void submit(T value, void Function(T) send) {
    if (_disposed) return;
    if (_isRedundant(value)) {
      discardPending();
      return;
    }
    final now = _now().millisecondsSinceEpoch;
    final wait = _deferralMs(now);
    if (wait <= 0) {
      _emit(value, now, send);
      return;
    }
    _queued = value;
    _hasQueued = true;
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = _schedule(Duration(milliseconds: wait), () => _flush(send));
  }

  void _flush(void Function(T) send) {
    if (!_hasQueued) return;
    final queued = _queued as T;
    _queued = null;
    _hasQueued = false;
    if (_disposed) return;
    if (_isRedundant(queued)) return;
    final now = _now().millisecondsSinceEpoch;
    _deferralMs(now);
    _emit(queued, now, send);
  }

  void discardPending() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _queued = null;
    _hasQueued = false;
  }

  void renew() {
    discardPending();
    _lastSent = null;
    _hasSent = false;
    _waiveSpacing = true;
  }

  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
  }
}

typedef ReactionThrottle = TrailingThrottle<String>;
