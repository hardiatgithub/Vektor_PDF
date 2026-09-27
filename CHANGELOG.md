# Changelog

Alle wichtigen Änderungen an **Vektor_PDF** werden hier festgehalten.
Neueste Version steht oben.

## [Unveröffentlicht]

### Neu
- **Radius-Bemaßung**: Option „Radien an Bögen (R …)“ beschriftet Bögen mit Hinweislinie
  und Pfeil. Gleiche Radien werden je Vektor nur einmal angegeben; Kreise behalten ihr Ø-Maß.

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
