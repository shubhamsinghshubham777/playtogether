import 'dart:io';

import 'package:playtogether/diagnostics.dart';

/// Reports *what* certificate a failed TLS handshake was offered, without
/// changing whether it is accepted.
///
/// A `CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate` from a
/// Windows release build has two causes that need opposite fixes and are
/// indistinguishable from the message alone. Either the machine's root store is
/// missing an issuer it should have — Dart snapshots the Windows ROOT store
/// rather than building chains through CryptoAPI, so roots Windows would have
/// installed on demand never arrive (dart-lang/sdk#52266) — or something on the
/// network is intercepting TLS and presenting its own certificate, in which
/// case no amount of bundled public roots would help, because the issuer is
/// private by design.
///
/// What arrives here is the certificate verification actually stopped on — the
/// unchainable root or intermediate, not the leaf — which is exactly the one
/// worth naming. Supabase serves leaf → GTS WE1 → GTS Root R4 cross-signed by
/// GlobalSign Root CA, so a report naming any of those means a genuine chain the
/// machine could not complete, and a report naming anything else means the
/// connection never reached Supabase at all.
void installTlsDiagnostics() {
  HttpOverrides.global = _ReportingHttpOverrides();
}

class _ReportingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..badCertificateCallback = _onBadCertificate;
}

/// One report per host+issuer per run. Supabase Realtime reconnects with
/// backoff, so a machine that cannot complete a handshake at all would
/// otherwise file the same event every few seconds until it gave up.
final _reported = <String>{};

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
  // Reporting only. Returning true here would accept every certificate the
  // client could not verify, which is precisely what an interception proxy
  // needs from us — and would turn a diagnosable failure into a silent one.
  return false;
}
