{{flutter_js}}
{{flutter_build_config}}

// Load the CanvasKit renderer from this site instead of Google's CDN so the
// app also boots on networks without internet access (offline-first).
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
  },
});
