import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Fragt beim Schließen oder Neuladen nach, solange Änderungen noch nicht auf
/// dem Server sind. Im Browser liegen sie nur im Speicher.
void warnBeforeUnload(bool Function() pending) {
  web.window.addEventListener(
    'beforeunload',
    ((web.Event event) {
      if (pending()) event.preventDefault();
    }).toJS,
  );
}
