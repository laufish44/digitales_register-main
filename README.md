# Digitales Register

Inoffizieller Client für das Digitale Register (`https://<schule>.digitalesregister.it`),
für Android und Windows.

> **Dies ist ein Fork.** Weiterentwickelt von Laurin Feichter, auf Basis von
> [miDeb/digitales_register](https://github.com/miDeb/digitales_register) von
> Michael Debertol und Simon Wachtler. Diese Version steht in keiner Verbindung
> zum ursprünglichen Projekt und wird von dessen Autoren weder unterstützt noch
> betreut. Fehler in dieser Version gehören hierher, nicht dorthin.
>
> Wie das Original steht auch dieser Fork unter der
> [GNU GPL v3](LICENSE.txt).

## Was in diesem Fork anders ist

* **Benachrichtigungen ohne fremden Server.** Android weckt die App über den
  AlarmManager etwa alle 15 Minuten; Windows startet dieselbe .exe mit
  `--background` als unsichtbaren Dienst. Es gibt keinen Push-Server und keine
  Firebase-Abhängigkeit mehr — nichts verlässt das Gerät außer der Anmeldung
  beim Register selbst.
* **Updates über GitHub-Releases**, eingebaut in die App.
* **Widgets** auf der Startseite: Demnächst, Morgen, Heute, Noten, Absenzen,
  Ferien, Mitteilungen — einzeln schaltbar, einstellbar und sortierbar.
* **Themes**, die auch die Form ändern, nicht nur die Farbe.
* **Statistikseite** (Noten, Absenzen nach Stunde/Wochentag/Fach/Monat),
  **Suche über alles**, **Absenz-Budget**, **Ferien-Countdown**,
  **Notenziel pro Fach**, **einstellbare Stundenzeiten**.
* **Absenzen eintragen und Mitteilungen schreiben** aus der App heraus.
* Reparaturen: Dateien öffnen unter Windows, gelesene Mitteilungen bleiben
  gelesen, „Zeugnis" lädt wieder, „Demnächst" findet auch ohne geöffneten
  Kalender etwas.

## Installation

Fertige Dateien liegen unter [Releases](../../releases):

* **Windows** — `...-setup.exe`, ein normaler Installations-Assistent
  (Startmenü-Eintrag, optionale Desktop-Verknüpfung, Deinstallierer).
  Installiert standardmäßig nur für den aktuellen Benutzer, deshalb ohne
  Administrator-Abfrage. SmartScreen warnt beim ersten Start, weil der
  Installer nicht signiert ist: „Weitere Informationen" → „Trotzdem ausführen".
* **Android** — die `.apk` direkt auf dem Gerät installieren
  („Installation aus unbekannten Quellen" muss erlaubt sein).

Die `.aab` ist für den Play Store und lässt sich nicht direkt installieren.

## Selbst bauen

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run                 # oder: flutter run --release
```

Für Release-Builds:

```sh
flutter build apk --release
flutter build appbundle --release
flutter build windows --release
"%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" windows\installer\digitales_register.iss
```

Gebaut mit Flutter 3.32.1. Der Windows-Installer braucht zusätzlich
[Inno Setup 6](https://jrsoftware.org/isinfo.php).

## Demo-Modus

Um die App ohne echten Zugang anzusehen: als Schule `Vinzentinum` wählen,
als Benutzer `demo-user-6540` und ein beliebiges Passwort. Es werden
Beispieldaten angezeigt; manche Funktionen verhalten sich dabei anders als
normal. Schreibende Aktionen sind im Demo-Modus gesperrt.

## Lizenz

GNU General Public License v3 — siehe [LICENSE.txt](LICENSE.txt).

Copyright © 2019–2022 Michael Debertol und Simon Wachtler
Änderungen dieser Version © 2026 Laurin Feichter
