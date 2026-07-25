import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/auth/auth_service.dart';
import 'package:playtogether/profile/profile_service.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/rooms/room_service.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/identity.dart';
import 'package:playtogether/ui/inputs.dart';
import 'package:playtogether/ui/pt_theme.dart';
import 'package:playtogether/ui/responsive.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _nameController = TextEditingController();
  final _codeKey = GlobalKey<PTCodeInputState>();
  int _durationMinutes = 150;
  String _code = '';
  bool _creating = false;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    if (ProfileService.instance.profile == null) {
      // Consume the parked invite even if the profile fetch fails — the join
      // itself doesn't need the profile.
      ProfileService.instance
          .load()
          .catchError((_) => null)
          .whenComplete(_consumePendingJoin);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingJoin());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Invite deep link received before sign-in lands here after login.
  Future<void> _consumePendingJoin() async {
    final code = RoomService.instance.pendingJoinCode;
    if (code == null || !mounted) return;
    RoomService.instance.pendingJoinCode = null;
    await _join(code);
  }

  String get _durationLabel {
    final h = _durationMinutes ~/ 60;
    final m = _durationMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final room = await RoomService.instance.createRoom(
        name: _nameController.text,
        durationMinutes: _durationMinutes,
      );
      if (mounted) context.go('/room/${room.id}');
    } catch (e) {
      if (!mounted) return;
      final code = RoomErrorCode.fromError(e);
      if (code == .guestRoomLimit) {
        await _showGuestLimitDialog();
      } else {
        _snack(code.message);
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _join(String code) async {
    if (code.length != PTCodeInput.length) {
      _snack('Enter the 6-character room code.');
      return;
    }
    setState(() => _joining = true);
    try {
      final room = await RoomService.instance.joinRoom(code);
      if (mounted) context.go('/room/${room.id}');
    } catch (e) {
      if (mounted) {
        _snack(RoomErrorCode.fromError(e).message);
        _codeKey.currentState?.clear();
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _showGuestLimitDialog() async {
    final live = await RoomService.instance.fetchLiveHostedRoom();
    if (!mounted) return;
    await showGlassDialog(
      context: context,
      width: 400,
      builder: (dialogContext) => _GuestLimitDialogBody(
        roomName: live?.name ?? 'Your live room',
        onEnd: () async {
          Navigator.of(dialogContext).pop();
          if (live != null) {
            await RoomService.instance.endRoom(live.id);
            _snack("That's a wrap — your old room has ended.");
          }
        },
        onRejoin: () {
          Navigator.of(dialogContext).pop();
          if (live != null) context.go('/room/${live.id}');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ProfileService.instance.profile;
    final firstName = profile?.displayName.split(' ').first ?? 'there';

    return Scaffold(
      body: AmbientBackground(
        child: ListenableBuilder(
          listenable: ProfileService.instance,
          builder: (context, _) => PTResponsive(
            desktop: (_) => _desktop(firstName),
            portrait: (_) => _portrait(firstName),
            landscape: (_) => _landscape(firstName),
          ),
        ),
      ),
    );
  }

  Widget _desktop(String firstName) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
          child: Row(
            children: [
              const _Wordmark(),
              const Spacer(),
              _profilePill(),
              const SizedBox(width: 12),
              PTIconButton(
                icon: Symbols.logout_rounded,
                iconSize: 20,
                size: 42,
                tooltip: 'Log out',
                onPressed: AuthService.instance.signOut,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 36, bottom: 48),
            child: Column(
              children: [
                Text('Hey $firstName, ready to watch?', style: PTText.display),
                const SizedBox(height: 12),
                Text(
                  'Start a room or hop into one your friends made.',
                  style: PTText.body.copyWith(fontSize: 16, color: PTColors.white(0.55)),
                ),
                const SizedBox(height: 52),
                // IntrinsicHeight: equal-height cards; a bare .stretch Row here
                // would receive unbounded height from the scroll view and crash.
                IntrinsicHeight(
                  child: Row(
                    mainAxisAlignment: .center,
                    crossAxisAlignment: .stretch,
                    spacing: 28,
                    children: [
                      SizedBox(width: 430, child: _createCard()),
                      SizedBox(width: 430, child: _joinCard()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _portrait(String firstName) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 18,
          children: [
            Row(
              children: [
                const _Wordmark(compact: true),
                const Spacer(),
                _avatarButton(),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Hey $firstName,\nready to watch?',
                style: PTText.display.copyWith(fontSize: 26),
              ),
            ),
            _createCard(compact: true),
            _joinCard(compact: true),
          ],
        ),
      ),
    );
  }

  Widget _landscape(String firstName) {
    return SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: 44),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          crossAxisAlignment: .start,
          spacing: 14,
          children: [
            Row(
              children: [
                const _Wordmark(compact: true),
                const SizedBox(width: 10),
                Text('Hey $firstName, ready to watch?', style: PTText.panelHeading),
                const Spacer(),
                _avatarButton(size: 36),
              ],
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: .stretch,
                spacing: 18,
                children: [
                  Expanded(child: _createCard(compact: true, scroll: true)),
                  Expanded(child: _joinCard(compact: true, scroll: true)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profilePill() {
    final profile = ProfileService.instance.profile;
    return GlassPill(
      onTap: () => context.go('/profile'),
      padding: const EdgeInsets.fromLTRB(8, 7, 16, 7),
      child: Row(
        mainAxisSize: .min,
        spacing: 10,
        children: [
          PTAvatar(
            userId: profile?.id ?? '',
            displayName: profile?.displayName ?? '?',
            avatarUrl: profile?.avatarUrl,
            size: 32,
          ),
          Text(
            profile?.displayName ?? '…',
            style: PTText.body.copyWith(fontSize: 14, fontWeight: .w500),
          ),
        ],
      ),
    );
  }

  Widget _avatarButton({double size = 40}) {
    final profile = ProfileService.instance.profile;
    return GestureDetector(
      onTap: () => context.go('/profile'),
      child: PTAvatar(
        userId: profile?.id ?? '',
        displayName: profile?.displayName ?? '?',
        avatarUrl: profile?.avatarUrl,
        size: size,
        ringColor: PTColors.white(0.15),
      ),
    );
  }

  Widget _createCard({bool compact = false, bool scroll = false}) {
    final content = Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: compact ? 18 : 24,
      children: [
        _cardHeader(
          Symbols.add_circle_rounded,
          'Create a room',
          "You'll be the host",
          compact: compact,
        ),
        PTTextField(controller: _nameController, label: 'Room name', hint: 'Friday movie night'),
        Column(
          crossAxisAlignment: .start,
          spacing: 10,
          children: [
            Row(
              children: [
                Text('Duration', style: PTText.caption.copyWith(fontSize: compact ? 12 : 13)),
                const Spacer(),
                Text(
                  _durationLabel,
                  style: PTText.mono.copyWith(fontSize: compact ? 13 : 14, color: PTColors.textAccent),
                ),
              ],
            ),
            PTSlider(
              value: (_durationMinutes - 5) / 235,
              onChanged: (v) =>
                  setState(() => _durationMinutes = 5 + ((v * 235) / 5).round() * 5),
            ),
            if (!compact)
              Row(
                mainAxisAlignment: .spaceBetween,
                children: [
                  Text('5 min', style: PTText.mono.copyWith(fontSize: 11, color: PTColors.white(0.35))),
                  Text('4 hours max', style: PTText.mono.copyWith(fontSize: 11, color: PTColors.white(0.35))),
                ],
              ),
          ],
        ),
        PTButton(
          label: 'Create room',
          icon: Symbols.rocket_launch_rounded,
          loading: _creating,
          onPressed: _creating ? null : _create,
        ),
      ],
    );
    return _card(content, compact: compact, scroll: scroll);
  }

  Widget _joinCard({bool compact = false, bool scroll = false}) {
    final content = Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: compact ? 16 : 24,
      children: [
        _cardHeader(
          Symbols.login_rounded,
          'Join a room',
          'Got a code from a friend?',
          compact: compact,
        ),
        Column(
          crossAxisAlignment: .start,
          spacing: 8,
          children: [
            if (!compact) Text('Room code', style: PTText.caption),
            PTCodeInput(
              key: _codeKey,
              boxHeight: compact ? 52 : 58,
              onChanged: (v) => _code = v,
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: PTColors.primary.withValues(alpha: 0.1),
            border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.22)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            spacing: 10,
            children: [
              const Icon(Symbols.link_rounded, size: 18, color: PTColors.textAccent),
              Expanded(
                child: Text(
                  'Invite links open the room directly — no code needed.',
                  style: PTText.body.copyWith(fontSize: 13, color: PTColors.white(0.65)),
                ),
              ),
            ],
          ),
        ),
        PTButton(
          label: 'Join room',
          trailingIcon: Symbols.arrow_forward_rounded,
          variant: .secondary,
          loading: _joining,
          onPressed: _joining ? null : () => _join(_code),
        ),
      ],
    );
    return _card(content, compact: compact, scroll: scroll);
  }

  Widget _card(Widget content, {required bool compact, required bool scroll}) {
    return GlassPanel(
      radius: compact ? 24 : 26,
      opacity: compact ? 0.55 : 0.5,
      blur: compact ? 28 : 32,
      padding: EdgeInsets.all(compact ? 22 : 34),
      child: scroll ? SingleChildScrollView(child: content) : content,
    );
  }

  Widget _cardHeader(IconData icon, String title, String subtitle, {required bool compact}) {
    return Row(
      spacing: compact ? 12 : 14,
      children: [
        Container(
          width: compact ? 40 : 44,
          height: compact ? 40 : 44,
          decoration: BoxDecoration(
            color: PTColors.primary.withValues(alpha: 0.25),
            border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(compact ? 13 : 14),
          ),
          child: Icon(icon, size: compact ? 21 : 23, fill: 1, color: PTColors.textAccent),
        ),
        Column(
          crossAxisAlignment: .start,
          children: [
            Text(title, style: compact ? PTText.cardHeading.copyWith(fontSize: 17) : PTText.cardHeading),
            Text(
              subtitle,
              style: PTText.caption.copyWith(fontSize: compact ? 12 : 13, fontWeight: .w400),
            ),
          ],
        ),
      ],
    );
  }
}

class _GuestLimitDialogBody extends StatelessWidget {
  const _GuestLimitDialogBody({
    required this.roomName,
    required this.onEnd,
    required this.onRejoin,
  });

  final String roomName;
  final VoidCallback onEnd;
  final VoidCallback onRejoin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Row(
          spacing: 13,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: PTColors.warningBorder.withValues(alpha: 0.12),
                border: Border.all(color: PTColors.warningBorder.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Symbols.hourglass_top_rounded, size: 24, fill: 1, color: PTColors.warning),
            ),
            Text('One room at a time', style: PTText.cardHeading),
          ],
        ),
        Text.rich(
          TextSpan(
            text: 'Guests can host one live room at a time. ',
            children: [
              TextSpan(text: roomName, style: TextStyle(color: PTColors.white(0.85))),
              const TextSpan(
                text: ' is still running — end it first, or sign in with Google to host more.',
              ),
            ],
          ),
          style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.55),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            spacing: 11,
            children: [
              Expanded(
                child: PTButton(label: 'End that room', variant: .secondary, height: 48, onPressed: onEnd),
              ),
              Expanded(child: PTButton(label: 'Rejoin it', height: 48, onPressed: onRejoin)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logo = compact ? 34.0 : 40.0;
    return Row(
      mainAxisSize: .min,
      spacing: compact ? 10 : 14,
      children: [
        Container(
          width: logo,
          height: logo,
          decoration: BoxDecoration(
            gradient: PTColors.brandGradient,
            borderRadius: BorderRadius.circular(logo * 0.32),
            boxShadow: [
              BoxShadow(
                color: PTColors.primary.withValues(alpha: 0.4),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(Icons.play_arrow_rounded, size: logo * 0.55, color: Colors.white),
        ),
        Text(
          'PlayTogether',
          style: TextStyle(
            fontFamily: PTFonts.display,
            fontSize: compact ? 17 : 19,
            fontWeight: .w700,
            letterSpacing: -0.2,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
