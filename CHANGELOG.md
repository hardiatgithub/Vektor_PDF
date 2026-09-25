# Changelog

Alle wichtigen Änderungen an **Vektor_PDF** werden hier festgehalten.
Neueste Version steht oben.

## [Unveröffentlicht]

### Behoben
- Absturz bei Zeichnungen mit **Bézier-Kurven** („attempt to index local 'c1'“).
  Die Kontrollpunkte werden jetzt robust ausgelesen; falls das nicht möglich ist,
  wird die Kurve als Gerade gezeichnet und in der Abschlussmeldung darauf hingewiesen.

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
