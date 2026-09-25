# pdf_vectric

Gadget für **Vectric VCarve Pro / Aspire** (ab V12), das Vektoren als **PDF-Zeichnung** exportiert – mit einstellbarer Linienstärke, automatischer Bemaßung, Titel und Maßstabsangabe.

## Funktionen

- Export von **ausgewählten Vektoren** oder **allen sichtbaren Ebenen** (inkl. Gruppen)
- Linien, Bögen und Bézierkurven werden als echte Vektoren ins PDF geschrieben
- **Linienstärke** frei einstellbar (z. B. 0,3 fein · 0,5 normal · 1,0 kräftig)
- **Automatische Bemaßung**
  - Gesamtmaße (Breite × Höhe)
  - optional Maße jedes geschlossenen Vektors, Kreise als Durchmesser (Ø)
- **Titel** und **Notiz** oben auf dem Blatt
- **Maßstab, Einheit (mm/Zoll) und Datum** in der Fußzeile
- Seitenformat: **auf A4 einpassen** (Hoch-/Querformat automatisch) oder **Maßstab 1:1**
- Materialumriss optional grau mitdrucken
- Einstellungen werden zwischen den Aufrufen gespeichert

## Installation

1. Den Ordner `pdf_vectric` mit den Dateien
   - `pdf_vectric.lua`
   - `pdf_vectric.htm`

   in den Gadget-Ordner von Vectric kopieren, z. B.:

   ```
   C:\ProgramData\Vectric\VCarve Pro\V12.0\Gadgets\pdf_vectric\
   ```

   (Programmname und Version ggf. anpassen, z. B. `Aspire\V12.0`.)

2. Vectric neu starten. Das Gadget erscheint im Menü **Gadgets → pdf_vectric**.

> Wichtig: Ordnername und Name der `.lua`-Datei müssen gleich sein (`pdf_vectric`).

## Verwendung

1. Job öffnen und – falls gewünscht – Vektoren auswählen.
2. **Gadgets → pdf_vectric** starten.
3. Linienstärke, Bemaßung, Beschriftung und Seitenformat einstellen.
4. Mit **OK** bestätigen und Speicherort für die PDF-Datei wählen.

## Hinweise

- Vectric-eigene Texte und Bemaßungen haben keine Vektorform und werden übersprungen – die Maße erzeugt das Gadget selbst.
- Die PDF verwendet die Standardschrift Helvetica; Umlaute und Sonderzeichen (ä, ö, ü, ß, Ø) werden unterstützt.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
