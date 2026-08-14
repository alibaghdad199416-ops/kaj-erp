import 'dart:async';

/// Executes one browser download click and guarantees DOM/object-URL cleanup.
///
/// Keeping the lifecycle independent of `dart:html` makes duplicate-click and
/// cleanup behavior directly testable on the Dart VM.
void triggerBrowserDownload({
  required void Function() attach,
  required void Function() click,
  required void Function() detach,
  required void Function() revoke,
  Duration revokeDelay = const Duration(seconds: 10),
}) {
  attach();
  try {
    click();
  } finally {
    detach();
    // Edge/Chrome may start consuming the Blob after click() returns.
    unawaited(Future<void>.delayed(revokeDelay, revoke));
  }
}
