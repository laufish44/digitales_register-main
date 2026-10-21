# Fernkonfiguration

`config.json` wird von jeder App (ab 8.8.0) beim Start von GitHub geladen
(`raw.githubusercontent.com/.../master/remote/config.json`). Was hier steht,
kommt ohne neue Version bei allen an. Eine kaputte oder fehlende Datei ändert
nichts – die App macht dann einfach weiter wie bisher.

## Schulkalender

`schoolCalendars` nach dem Jahr, in dem das Schuljahr beginnt. Ein Kalender
hier gilt statt des eingebauten.

Damit geänderte Ferien bei allen in den Einstellungen landen, **muss
`calendarRevision` erhöht werden** (z. B. von 2 auf 3). Dann ersetzt die App
die gespeicherten Ferien einmal durch diese – beim übernächsten Start, weil
die Datei beim Start geladen und erst beim nächsten Start angewendet wird.

## Hinweise

Kurze Mitteilungen an alle, oben in der App als Banner, jeder nur einmal:

```json
"notices": [
  {
    "id": "2026-11-wartung",
    "title": "Wartung",
    "text": "Das Register ist am Samstag ab 8 Uhr nicht erreichbar.",
    "until": "2026-11-15",
    "platforms": ["android", "windows"],
    "belowVersion": "8.9.0",
    "url": "https://github.com/laufish44/digitales_register-main/releases"
  }
]
```

Nur `id` und `text` sind Pflicht. Eine neue `id` zeigt den Hinweis erneut.
`belowVersion` zeigt ihn nur Versionen darunter (z. B. „bitte aktualisieren“).