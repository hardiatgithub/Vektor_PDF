# Vektor_PDF

Gadget für **Vectric VCarve Pro / Aspire** (ab V12), das Vektoren als **PDF-Zeichnung** exportiert – mit einstellbarer Linienstärke, automatischer Bemaßung, Titel und Maßstabsangabe.

## Funktionen

- Export von **ausgewählten Vektoren** oder **allen sichtbaren Ebenen** (inkl. Gruppen)
- Linien, Bögen und Bézierkurven werden als echte Vektoren ins PDF geschrieben
- **Linienstärke** frei einstellbar (z. B. 0,3 fein · 0,5 normal · 1,0 kräftig)
- **Automatische Bemaßung**
  - Gesamtmaße (Breite × Höhe)
  - optional Maße jedes geschlossenen Vektors, Kreise als Durchmesser (Ø)
  - Einzelmaße erst ab einer Mindestgröße (z. B. keine Maße an Buchstaben)
  - Farbe der Bemaßung wählbar (Schwarz, Blau, Rot, Grün, Grau)
- **Titel** und **Notiz** oben auf dem Blatt
- **Maßstab, Einheit (mm/Zoll) und Datum** in der Fußzeile
- Seitenformat: **auf A4 einpassen** (Hoch-/Querformat automatisch) oder **Maßstab 1:1**
- Materialumriss optional grau mitdrucken
- Einstellungen werden zwischen den Aufrufen gespeichert

## Installation

1. Den Ordner `Vektor_PDF` mit den Dateien
   - `Vektor_PDF.lua`
   - `Vektor_PDF.htm`

   in den öffentlichen Gadget-Ordner von Vectric kopieren, z. B.:

   ```
   C:\Users\Public\Documents\Vectric Files\Gadgets\VCarve Pro V12.5\Vektor_PDF\
   ```

   (Programmname und Version ggf. anpassen, z. B. `Aspire V12.5`.)
   Der Ordner `C:\ProgramData\Vectric\...\Gadgets` ist für die mitgelieferten
   Vectric-Gadgets gedacht.

2. Vectric neu starten. Das Gadget erscheint im Menü **Gadgets → Vektor_PDF**.

> Wichtig: Ordnername und Name der `.lua`-Datei müssen gleich sein (`Vektor_PDF`).

## Verwendung

1. Job öffnen und – falls gewünscht – Vektoren auswählen.
2. **Gadgets → Vektor_PDF** starten.
3. Linienstärke, Bemaßung, Beschriftung und Seitenformat einstellen.
4. Mit **OK** bestätigen und Speicherort für die PDF-Datei wählen.

## Hinweise

- Vectric-eigene Texte und Bemaßungen haben keine Vektorform und werden übersprungen – die Maße erzeugt das Gadget selbst.
- Die PDF verwendet die Standardschrift Helvetica; Umlaute und Sonderzeichen (ä, ö, ü, ß, Ø) werden unterstützt.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
