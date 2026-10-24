# Vektor_PDF

*[English version](README.md)*

Gadget für **Vectric VCarve Pro / Aspire** (ab V12), das Vektoren als gut lesbare **PDF-Zeichnung** exportiert – zum Ausdrucken für die Werkstatt, als maßstäbliche Vorlage oder als bemaßte Skizze für Kunden.

## Warum dieses Gadget?

Der Ausdruck direkt aus VCarve hat extrem dünne Linien und ist in der Werkstatt kaum zu lesen. Vektor_PDF druckt die Zeichnung mit einstellbarer Linienstärke, übernimmt die in VCarve gesetzten Maße gut lesbar und kann bei Bedarf selbst bemaßen.

## Funktionen

**Zeichnung**

- Export von **ausgewählten Vektoren**, **allen sichtbaren Layern** oder **gewählten Layern** (inkl. Gruppen)
- Jobs mit **mehreren Seiten (Sheets)**: aktuelle Seite oder alle Seiten als **mehrseitiges PDF**
- Linien, Bögen und Bézierkurven als echte Vektoren im PDF
- **Linienstärke** einstellbar, Farbe fest oder **wie in VCarve** (Farbe des Layers)
- Materialumriss optional grau mitdrucken

**Bemaßung** – alle Arten unabhängig voneinander ein- und ausschaltbar

- **Vectric-Bemaßung:** Maße, die du in VCarve gesetzt hast (waagrecht, senkrecht, schräg, Radien, Winkel), werden gut lesbar ins PDF übernommen – gesteuert über die Layer in VCarve
- **Auto-Bemaßung** (Schieber *Vectric · beide · Auto*, Menü „Auto-Einstellungen ►“):
  - Gesamtmaße, Maße jedes Vektors, Kreise (R), Radien an Bögen, Winkel an Ecken
  - jeweils wahlweise **innen** (durchs Teil) oder **außen** (vor der Zeichnung, mit unterbrochenen Hilfslinien)
  - Gruppen auslassen, als Ganzes oder einzeln bemaßen
  - Einzelmaße erst ab einer Mindestgröße (z. B. keine Maße an Buchstaben)
- **Reihenbemaßung** für Lochreihen, Langlöcher (z. B. Lamello) und Rasterlinien:
  - *steigend* (ab 0) oder als *Kette*
  - Bezug: Löcher, Linien oder beide
  - Aufteilung nach Seiten, Bohrungen nur unten/links, wahlweise **je Teil**
- Maßzahl in der Maßlinie (wie Vectric) oder darüber; Farbe, Linienstärke, Pfeil- und Schriftgröße einstellbar
- Schriftgröße optional mit dem Maßstab skalieren
- Maße weichen einander automatisch aus; doppelte Maße werden weggelassen

**Seite und Beschriftung**

- Papier **A4** oder **US Letter**, Hoch-/Querformat oder automatisch
- **Einpassen**, **1:1** oder **frei wählbarer Maßstab** (z. B. 1:5, 1:7,5, 2:1)
- **Titel** und **Notiz** oben, **Maßstab, Einheit (mm/Zoll) und Datum** in der Fußzeile
- **Speichern unter** direkt im Dialog (leeres Feld = beim Export nachfragen)
- Dialog, Meldungen und PDF auf **Deutsch oder Englisch**
- Alle Einstellungen werden gemerkt

## Installation

**Empfohlen:** `Vektor_PDF.vgadget` aus dem
[neuesten Release](https://github.com/hardiatgithub/Vektor_PDF/releases) herunterladen,
in VCarve / Aspire über **Gadgets → Install Gadget…** installieren und die Software neu starten.
Das Gadget erscheint dann unter **Gadgets → Vektor_PDF**.

**Manuell:** den Ordner `Vektor_PDF` mit `Vektor_PDF.lua` und `Vektor_PDF.htm` in den öffentlichen Gadget-Ordner kopieren, z. B.:

```
C:\Users\Public\Documents\Vectric Files\Gadgets\VCarve Pro V12.5\Vektor_PDF\
```

(Programmname und Version ggf. anpassen, z. B. `Aspire V12.5`) und neu starten.

> Ordnername und Name der `.lua`-Datei müssen gleich sein (`Vektor_PDF`).

## Verwendung

1. Job öffnen und – falls gewünscht – Vektoren auswählen.
2. **Gadgets → Vektor_PDF** starten.
3. Linien, Bemaßung, Beschriftung und Seite einstellen.
4. Mit **OK** bestätigen – das PDF wird unter „Speichern unter“ gespeichert (oder es wird nachgefragt).

## Tipp zu den Bemaßungen

Nach der Installation ist nur die **Vectric-Bemaßung** aktiv – das Gadget übernimmt also die Maße, die du **selbst in VCarve gesetzt hast**. Hast du keine Maße gezeichnet, erscheinen auch keine im PDF; dann einfach die Auto-Bemaßung zuschalten.

Weniger ist oft mehr: Wer alles gleichzeitig aktiviert, bekommt schnell eine überladene Zeichnung. Die Reihenbemaßung ist eher für spezielle Fälle gedacht, etwa Lochreihen oder Bohrbilder im Möbelbau.

## Hinweise

- Vectric-Texte haben keine Vektorform und werden übersprungen – für das PDF in Kurven umwandeln.
- Bei jedem Export schreibt das Gadget `vdim_diag.txt` in den Gadget-Ordner. Die Datei hilft beim Nachvollziehen, warum ein Vectric-Maß fehlt.
- Die PDF verwendet die Standardschrift Helvetica; Umlaute und Sonderzeichen (ä, ö, ü, ß, Ø) werden unterstützt.
- Entwickelt und getestet mit **VCarve Pro V12.5** unter Windows.

## Danke

Ein großes Dankeschön an **Gremlin** (gremlin529), der mit vielen hilfreichen Tipps, Tests und Ideen zur Seite steht.

## Feedback

Fehler gefunden oder eine Idee? Bitte ein [Issue](https://github.com/hardiatgithub/Vektor_PDF/issues) anlegen.

Alle Änderungen stehen im [CHANGELOG](CHANGELOG.md).

## Lizenz

MIT – siehe [LICENSE](LICENSE).
