{{flutter_js}}
{{flutter_build_config}}

// Kein Service Worker: Nach einem Server-Update soll keine alte Fassung
// weiterlaufen. Fonts kommen vom eigenen Server.
_flutter.loader.load({
  onEntrypointLoaded: async (engineInitializer) => {
    const appRunner = await engineInitializer.initializeEngine({
      fontFallbackBaseUrl: 'fonts/',
    });
    await appRunner.runApp();
    // Das Startbild verschwindet, sobald die App läuft.
    document.getElementById('splash')?.remove();
  },
});
