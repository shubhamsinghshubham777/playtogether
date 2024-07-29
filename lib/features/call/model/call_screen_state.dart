import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';

// required: associates our `call_screen_state.dart` with the code generated by Freezed
part 'call_screen_state.freezed.dart';
// optional: Since our CallScreenState class is serializable, we must add this line.
// But if CallScreenState was not serializable, we could skip it.
part 'call_screen_state.g.dart';

@freezed
class CallScreenState with _$CallScreenState {
  const factory CallScreenState({
    required String? videoName,
    required bool isPlayingVideo,
    required int currentVideoMillis,
    required String? chatMessage,
  }) = _CallScreenState;

  factory CallScreenState.fromJson(Map<String, Object?> json) =>
      _$CallScreenStateFromJson(json);
}
