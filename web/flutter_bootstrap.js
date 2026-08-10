{{flutter_js}}
{{flutter_build_config}}

// Keep the Flutter renderer self-hosted. Flutter 3.44 no longer provides the
// legacy HTML renderer; CanvasKit is the supported renderer for default web
// builds. Serving it from /canvaskit avoids runtime dependency on gstatic.
_flutter.loader.load({
  config: {
    renderer: 'canvaskit',
    canvasKitBaseUrl: 'canvaskit/',
    canvasKitVariant: 'auto',
  },
});
