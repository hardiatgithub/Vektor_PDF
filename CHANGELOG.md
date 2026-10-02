# Changelog

Alle wichtigen Änderungen an **Vektor_PDF** werden hier festgehalten.
Neueste Version steht oben.

## [Unveröffentlicht]

### Geändert
- **Release-Ablauf** (Beitrag von Gremlin): Entwicklungsdateien heißen jetzt `Vektor_PDF_dev.lua` /
  `Vektor_PDF_dev.htm`; `MakeRelease.ps1` setzt Version und Unterversion und erzeugt die `.vgadget`-Datei
  im Ordner `release`. Die Version wird im Dialog, im Fenstertitel und in der Abschlussmeldung angezeigt.

### Verbessert
- **Einzellinien werden bemaßt**: Eine einzelne gerade Linie bekommt bei „Maße jedes Vektors“ ihre Länge –
  waagrecht und senkrecht wie die übrigen Einzelmaße, schräge Linien mit einem parallelen Maß daneben.
- Neue Option **„Offene Polylinien: jedes gerade Stück“**: bemaßt bei offenen Polylinien jedes gerade Teilstück
  (Bögen und Kurven werden ausgelassen; „Einzelmaße ab“ gilt für die Größe der ganzen Polylinie).
- **Gerade Kurven** (Bézier-Stücke, deren Kontrollpunkte auf der Verbindungslinie liegen) werden wie Linien
  behandelt: Sie werden bemaßt und bekommen Winkel an den Ecken.
- **Winkelmaße übersichtlicher**: kleinere Maßbögen (4–10 mm, passend zur Schenkellänge); Zahlen weichen
  anderen Zahlen aus; gleiche Winkel dicht nebeneinander (z. B. Innen- und Außenkontur einer Doppellinie)
  werden bei „Winkel an Ecken“ nur einmal bemaßt.
- **Längenmaße mit Abstand**: Einzel- und Gesamtmaße, die sich überschneiden würden, werden automatisch
  in eigene Reihen nach außen versetzt – keine Maßlinie und keine Zahl liegt mehr auf einer anderen.
  Der Platz am Blattrand wird dafür automatisch vergrößert.
- **Hinweis auf Vectric-Bemaßungen**: Die Abschlussmeldung zählt übersprungene Vectric-Bemaßungen getrennt
  und erklärt, dass VCarve deren Punkte nicht an Gadgets weitergibt – Maße bitte als Linien auf dem Maß-Layer zeichnen.

### Behoben
- Bei Jobs mit **mehreren Seiten (Sheets)** lagen alle Teile im PDF übereinander. Die Seiten werden jetzt
  über ihren Namen erkannt (die Seiten-Kennungen von VCarve V12.5 sind interne Objekte).
- Bei **hoher Bildschirm-Skalierung** (z. B. 150 %) war die Schrift in den Eingabefeldern zu groß.
  Die Felder haben jetzt eine feste Schrift und wachsen mit; passt der Dialog nicht ins Fenster,
  wird er automatisch verkleinert, sodass OK/Abbrechen sichtbar bleiben.

### Neu
- Auswahl **„Seiten: Aktuelle Seite / Alle Seiten“** im Dialog. „Alle Seiten“ erzeugt ein **mehrseitiges PDF**
  mit je einer PDF-Seite pro VCarve-Seite; der Seitenname steht im Titel. Bei „Nur ausgewählte“ wird
  wie bisher die Auswahl exportiert.
- **A4-Ausrichtung** wählbar: Automatisch (je Seite passend), Hochformat oder Querformat –
  damit alle Seiten eines mehrseitigen PDFs gleich ausgerichtet werden können.
- **Dialoggröße und Zoom** werden gemerkt: Das Fenster öffnet sich wieder so groß wie beim letzten Mal
  (auch nach „Abbrechen“), und die neue Auswahl **Zoom** unten links skaliert den Dialoginhalt.
  „Auto“ richtet sich nach der Bildschirm-DPI, sonst ist ein fester Wert von 100 % bis 250 % wählbar. (Beitrag von Gremlin)
  Das Fenster wird nie größer als der Bildschirm.

## [1.3.2] – 2026-09-28

### Neu
- **Versionsnummer** wird im Fenstertitel, oben im Dialog und in der Abschlussmeldung angezeigt.
- **Winkelmaß**: Eine Linie mit **3 Punkten** (V-Form) auf dem Maß-Layer wird als Winkel bemaßt –
  der mittlere Punkt ist der Scheitel. Bogen mit Pfeilen und Gradzahl (z. B. 45°).
- **Automatische Winkel**: Option „Winkel an Ecken (ohne 90°)“ bemaßt jede Ecke zwischen zwei Geraden –
  ohne Maß-Layer. Rechte Winkel werden ausgelassen; es gelten „Einzelmaße ab“ und die Gruppen-Regel.
- **Zahlenfelder akzeptieren Komma und Punkt** (z. B. `0,5` oder `0.5`). Anzeige passend zur Sprache;
  bei ungültiger Eingabe nennt eine Meldung das betroffene Feld.
- Abschlussmeldung zeigt Anzahl der Längen- und Winkelmaße; findet das Gadget keine manuellen Maße,
  nennt sie den Grund (Layer nicht gefunden – mit Liste der vorhandenen Layer –, ausgeblendet oder leer).
- Englische Anleitung für Vectric-Nutzer: **README.md** ist jetzt Englisch (GitHub-Startseite),
  die deutsche Anleitung liegt in **README.de.md**; beide verweisen aufeinander.

## [1.3.1] – 2026-09-27

### Neu
- **Sprache Deutsch / English** oben rechts im Dialog umschaltbar. Die Beschriftung des Dialogs
  wechselt sofort; Meldungen, Fußzeile (Maßstab/Scale, Datum) und Dezimaltrennzeichen im PDF
  folgen der Auswahl. Die Einstellung wird gespeichert.

## [1.3.0] – 2026-09-27

### Neu
- **Radius-Bemaßung**: Option „Radien an Bögen (R …)“ beschriftet Bögen mit Hinweislinie
  und Pfeil. Gleiche Radien werden je Vektor nur einmal angegeben; Kreise behalten ihr Ø-Maß.
- **Manuelle Maße**: Linien auf dem Layer „Bemassung“ (Name im Dialog einstellbar) werden nicht
  gezeichnet, sondern als Maß mit Pfeilen und Länge gedruckt – waagrecht, senkrecht oder schräg.
- **Linienstärke der Bemaßung** einstellbar (Standard 0,25 mm), unabhängig von den Vektoren.
- **Pfeilgröße** der Bemaßung einstellbar (Standard 2,5 mm).
- **Farbe der Vektoren** wählbar: Schwarz, Blau, Rot, Grün oder Grau.
- Option **„ausblenden“** beim Maß-Layer: manuelle Maße werden nicht gedruckt,
  ohne den Layer in VCarve ausblenden zu müssen.
  Solange angekreuzt, ist das Feld für den Layer-Namen ausgegraut.

### Geändert
- README: Installation in den öffentlichen Gadget-Ordner
  (`C:\Users\Public\Documents\Vectric Files\Gadgets\...`), neue Optionen beschrieben.

## [1.2.0] – 2026-09-26

### Neu
- **Farbe der Bemaßung** wählbar: Schwarz, Blau, Rot, Grün oder Grau
  (Maßlinien, Pfeile und Zahlen; Titel und Fußzeile bleiben schwarz).

## [1.1.0] – 2026-09-25

### Geändert
- „Maße jedes geschlossenen Vektors“ bemaßt keine Vektoren mehr, die in einer **Gruppe** liegen
  (z. B. in Kurven umgewandelter Text). Die Buchstaben werden gezeichnet, aber nicht einzeln bemaßt.

### Neu
- Einstellung **„Einzelmaße ab … mm“** (Standard 25 mm): kleinere Vektoren, z. B. Buchstaben,
  bekommen keine Einzelmaße. 0 = alle Vektoren bemaßen.
- Abschlussmeldung zeigt, wie viele Vektoren in Gruppen liegen.

## [1.0.1] – 2026-09-25

### Behoben
- Absturz bei Zeichnungen mit **Bézier-Kurven** („attempt to index local 'c1'“).
- Ellipsen und andere Bézier-Kurven wurden als Geraden gezeichnet (Ellipse → Raute).
  Die Kurven werden jetzt korrekt in feinen Schritten nachgezeichnet.

### Neu
- Diagnose-Hinweis in der Abschlussmeldung, falls eine Kurve trotzdem nicht gelesen werden kann.

## [1.0.0] – 2026-09-25

Erste Veröffentlichung auf GitHub.

### Neu
- Export von Vektoren als PDF mit einstellbarer Linienstärke
- Automatische Bemaßung (Gesamtmaße und optional jeder geschlossene Vektor, Kreise als Ø)
- Titel, Notiz sowie Maßstab, Einheit und Datum in der Fußzeile
- Seitenformat „auf A4 einpassen“ oder „Maßstab 1:1“
- Optional grauer Materialumriss
- README, Lizenz (MIT) und .gitignore

### Geändert
- Gadget von `pdf_vectric` in **Vektor_PDF** umbenannt (Ordner, Dateien und Repository)

### Behoben
- Dialog öffnete sich nicht, weil die falsche HTML-Datei geladen wurde
- Absturz bei „Materialumriss grau mitdrucken“ („attempt to index field 'MaterialBlock'“)
