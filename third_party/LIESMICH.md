# Mitgeführter Fremdcode

## mobile_scanner 7.4.2

BSD-3-Clause, Copyright (c) 2022 Julian Steenbakker. Die Lizenz liegt
unverändert bei.

Unter Android liest das veröffentlichte Plugin Strichcodes mit einer
Google-Bibliothek, die dabei Geräte- und Nutzungsdaten an Google meldet und
sich nicht abschalten lässt. Diese Kopie liest unter Android stattdessen mit
zxing-cpp; alle Änderungen sind im Quelltext mit `PreppSuite patch`
gekennzeichnet (die Anpassung stammt aus dem Schwesterprojekt). iOS und die
Dart-Seite sind unverändert.
