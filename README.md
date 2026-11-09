# Bociva

Ernährungstagebuch mit Kalorien- und Wasserzählung, Strichcode-Scanner,
KI-Analyse von Mahlzeiten und Anbindung an Apple Health und Health Connect.
Die App funktioniert eigenständig auf dem Gerät. Wer mehrere Geräte oder die
Weboberfläche nutzen möchte, betreibt einen eigenen Server.

## Funktionen

- Tagebuch nach Mahlzeiten mit Kalorien, Eiweiß, Kohlenhydraten und Fett
- Tagesziele nach Mifflin-St Jeor, mit Untergrenze und begrenztem Tempo
- Wasser, Gewicht, Verlauf über 7 und 30 Tage
- Strichcodes und Produktsuche über Open Food Facts, Grundnahrungsmittel offline
- KI-Analyse von Fotos und Texten, Auswertung des Verlaufs
- Aktivität aus Apple Health und Health Connect, FIT-Import aus Garmin Connect
- Abgleich zwischen Geräten, Weboberfläche, Datenexport, Konto löschen

## Aufbau

| Ordner | Inhalt |
|---|---|
| `packages/bociva_shared` | Modelle, Berechnungen, Abgleich, KI, FIT (reines Dart) |
| `app` | Flutter-App für iOS, Android und Web |
| `server` | Dart-Server mit verschlüsseltem SQLite, liefert die Weboberfläche aus |

Auf dem Gerät liegen die Daten in einer verschlüsselten SQLite-Datenbank, der
Schlüssel im Schlüsselbund bzw. Keystore. Im Browser bleiben sie nur im Speicher.
Beim Abgleich gewinnt je Datensatz die jüngere Änderung.

## Server einrichten

```bash
app/tool/build_web.sh
```

```bash
docker compose up -d --build
```

```bash
docker compose logs bociva
```

Im Protokoll steht der Einrichtungscode für das erste Konto; es wird
Administrator. Weitere Konten entstehen über Einladungen unter „Mehr“. Der
Server lauscht nur auf `127.0.0.1:8770`; davor gehört ein Reverse Proxy mit
HTTPS. `./keys` gesondert sichern: Ohne den Schlüssel ist `./data` unlesbar.

| Variable | Bedeutung |
|---|---|
| `BOCIVA_DATA_DIR`, `BOCIVA_KEY_FILE` | Datenordner, Schlüsseldatei |
| `BOCIVA_HOST`, `BOCIVA_PORT` | Adresse und Port (Standard 8770) |
| `BOCIVA_WEB_DIR` | Ordner der Weboberfläche |
| `BOCIVA_TRUST_PROXY` | `true` hinter einem Reverse Proxy |
| `BOCIVA_AI_BASE_URL`, `BOCIVA_AI_MODEL`, `BOCIVA_AI_API_KEY` | KI-Dienst |
| `BOCIVA_FOOD_CONTACT` | Kontakt in der Kennung gegenüber Open Food Facts |

## KI-Analyse

Bociva spricht jeden Dienst mit Chat-Completions-Schnittstelle an, selbst
gehostet oder als API. Ohne Einrichtung ist die KI aus, alles andere
funktioniert weiter. In der App lässt sich unter „Mehr → KI-Analyse“ ein eigener
Dienst eintragen oder der des Servers nutzen; die Weboberfläche nutzt den des
Servers. Für Fotos braucht das Modell Bildverständnis.

## Garmin und Apple Fitness

Bociva liest Schritte, aktive Kalorien und Gewicht aus Apple Health bzw. Health
Connect. Dort landen auch die Daten von Apple Watch und Fitness. Garmin-Daten
kommen dorthin, wenn sie in Garmin Connect für Apple Health freigegeben sind.
Einzelne Aktivitäten lassen sich außerdem als `.fit` oder `.zip` importieren.

## Entwicklung

```bash
cd packages/bociva_shared && dart pub get && dart analyze && dart test
```

```bash
cd server && dart pub get && dart analyze && dart test
```

```bash
cd app && flutter pub get && flutter analyze && flutter test
```

Der Integrationstest setzt eine frische Installation voraus und läuft deshalb
nur im Simulator oder Emulator:

```bash
cd app && flutter test integration_test/standalone_test.dart -d <simulator-id>
```
