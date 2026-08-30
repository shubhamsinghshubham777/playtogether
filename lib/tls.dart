import 'dart:io';

import 'package:flutter/services.dart';
import 'package:synctogether/diagnostics.dart';

/// Widens the set of CA roots the app trusts, and names the certificate behind
/// any handshake that still fails.
///
/// Both halves exist because of one Windows failure: `CERTIFICATE_VERIFY_FAILED:
/// unable to get local issuer certificate` reaching Supabase from a release
/// build. Dart snapshots the Windows ROOT store rather than building chains
/// through CryptoAPI, so roots Windows would have installed on demand never
/// arrive (dart-lang/sdk#52266, open). Shipping Mozilla's root program —
/// `assets/ca/cacert.pem`, refreshed by `tool/update_ca_bundle.py` — closes that
/// hole without waiting on the SDK.
///
/// **The bundle is added to the platform's roots, never substituted for them.**
/// `withTrustedRoots: true` is what keeps every root the machine itself trusts,
/// including the private CA a corporate TLS-interception proxy installs;
/// replacing them would fix the reported failure and break every managed network
/// in exchange. It also means a stale bundle cannot cause a regression — the
/// worst case is that it contributes nothing and the OS decides, which is where
/// the app was before it existed.
Future<void> installTlsOverrides() async {
  SecurityContext? context;
  try {
    final pem = await rootBundle.load('assets/ca/cacert.pem');
    context = SecurityContext(withTrustedRoots: true)
      ..setTrustedCertificatesBytes(pem.buffer.asUint8List());
  } catch (e, s) {
    // Leaving `context` null is exactly the pre-existing behaviour — clients
    // fall back to SecurityContext.defaultContext. Worth reporting because it
    // silently removes the fix, not because it breaks anything.
    reportNonFatal(e, s, during: 'loading the bundled CA roots');
  }
  HttpOverrides.global = _PTHttpOverrides(context);
}

class _PTHttpOverrides extends HttpOverrides {
  _PTHttpOverrides(this._context);

  final SecurityContext? _context;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      // A caller that supplied its own context meant it; ours only fills in the
      // default. WebSocket.connect builds its client through here too, so
      // Realtime and LiveKit inherit this without knowing about it.
      super.createHttpClient(context ?? _context)..badCertificateCallback = _onBadCertificate;
}

/// One report per host+issuer per run. Supabase Realtime reconnects with
/// backoff, so a machine that cannot complete a handshake at all would
/// otherwise file the same event every few seconds until it gave up.
final _reported = <String>{};

/// Names the certificate a failed handshake was offered — the only way to tell
/// the two remaining causes apart now that the bundle is in place: a chain even
/// Mozilla's roots cannot complete, or an interception proxy whose issuer is
/// private by design and which no public bundle will ever satisfy.
///
/// What arrives here is the certificate verification actually stopped on — the
/// unchainable root or intermediate, not the leaf — which is the one worth
/// naming. Supabase serves leaf → GTS WE1 → GTS Root R4 cross-signed by
/// GlobalSign Root CA, so a report naming those is a chain we should have been
/// able to build, and anything else never reached Supabase at all.
bool _onBadCertificate(X509Certificate cert, String host, int port) {
  final detail =
      'host $host:$port, subject ${cert.subject}, issuer ${cert.issuer}, '
      'valid ${cert.startValidity.toIso8601String()} to ${cert.endValidity.toIso8601String()}';
  if (_reported.add('$host|${cert.issuer}')) {
    reportNonFatal(
      StateError('Rejected a TLS certificate — $detail'),
      StackTrace.current,
      during: 'verifying a TLS certificate',
    );
  } else {
    trace('tls certificate rejected again', category: 'tls', data: {'host': host});
  }
  // Reporting only. Returning true would accept every certificate the client
  // could not verify, which is precisely what an interception proxy needs from
  // us — and would trade a diagnosable failure for a silent one.
  return false;
}
