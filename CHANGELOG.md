# Changelog

Alle wichtigen Änderungen an **Vektor_PDF** werden hier festgehalten.
Neueste Version steht oben.

## [Unveröffentlicht]

### Entfernt
- **Individuelle Bemaßung** wieder ausgebaut (Schalter, Layerfeld, Knopf „Layer anlegen“ und Anleitung im Dialog;
  Hilfslinien auf dem Layer „pdf_dim“ werden nicht mehr als Maße gedruckt, der Layer wird nicht mehr angelegt).
  Der Stand mit dieser Funktion ist im Branch **`individ_bem`** gesichert und kann später wieder übernommen werden.
  Vectric-Bemaßungen und Autobemaßung funktionieren unverändert.

### Geändert
- **Grundeinstellung bei Neuinstallation:** Der Bemaßungs-Regler steht jetzt auf **„nur Vectric“**, die Autobemaßung ist aus.
  Reihenbemaßung, Einzelmaße, Radien, Winkel und Polygone sind wie bisher aus. So ist die Zeichnung anfangs nicht überladen;
  Auto- und Reihenbemaßung lassen sich bei Bedarf zuschalten. Bereits gespeicherte Einstellungen bleiben unverändert.

### Neu (nach beta.4)
- **Bemaßungs-Regler** (Bereich „Bemaßung“): ein Schieber mit drei Stufen *Vectric · beide · Auto* ersetzt die Haken
  „Autobemaßung“ und „Vectric-Bemaßung aus“ (ziehen oder auf die Stufe klicken).
  - Links daneben Haken **„Bemaßung“** (an/aus, wie bei der Reihenbemaßung; früher „Bemaßung ausblenden“): aus = keine
    Vectric-/Autobemaßung im PDF, die Regler-Stellung bleibt gemerkt
    (der frühere Zustand „Auto aus + Vectric aus“ wird beim ersten Start zu diesem Haken).
  - Rechts der Knopf **„Auto-Einstellungen ►“** öffnet ein neu geordnetes Menü: eine Zeile je Maßart, „innen“ in einer
    eigenen Spalte, „Einzelmaße ab“ unten abgesetzt. Ausgegraut, wenn die Autobemaßung nicht aktiv ist.
- **Behoben: Vectric-Diagonalmaß von Ecke zu Ecke** (z. B. Diagonale eines Deckels) wurde falsch erkannt – das Gadget
  suchte ein parallel versetztes Maß mit Hilfslinien und nahm Punkte eines anderen Teils (296 statt 390,51). Jetzt wird
  zuerst geprüft, ob nahe zwei gegenüberliegenden Ecken des Bemaßungsrahmens echte Ecken eines Umrisses liegen
  (keine Punkte versetzter Werkzeugweg-Konturen). Welche Diagonale: Vectric versetzt die Maßlinie nur quer zur
  Messrichtung, also passt die Diagonale, gegen die der Rahmen nur seitlich verschoben ist.
- **Reihenbemaßung „je Teil“** (Haken neben „Bohrungen nur unten / links“): jedes Teil – ein geschlossener Umriss, der
  in keinem anderen liegt – bekommt seine eigene Reihe ab seiner linken unteren Ecke, direkt am Teil (mit Aufteilung
  oben/unten, links/rechts innerhalb des Teils). Die Einzelmaße des Teils rücken nach außen. Ohne Haken wie bisher.
- **Reihenbemaßung nach Seiten aufgeteilt:** Punkte in der oberen Hälfte werden oben bemaßt, in der unteren unten;
  Y-Werte links bzw. rechts nach Lage – z. B. obere und untere Lamello-Nuten je eine eigene Kette. Eine Reihe oben/rechts
  entfällt nur, wenn sie genau dieselben Werte hätte wie unten/links (z. B. Tür mit Topfbohrungen übereinander).
  Mit Reihenbemaßung werden auch die Einzelmaße („Jeder Vektor“) aufgeteilt: Teile in der oberen/rechten Hälfte
  bekommen ihr Maß oben/rechts (außer bei „außen“). Ohne Reihenbemaßung bleibt alles wie bisher.
  Schalter **„Bohrungen nur unten / links“**: runde Bohrungen (z. B. durchgehende Lochreihen) werden nicht aufgeteilt,
  sondern nur unten bzw. links bemaßt; Langlöcher und Linien bleiben auf ihrer Seite.
  Jeder Wert erscheint nur einmal: liegt er oben bei einem Langloch/einer Linie und unten nur bei Bohrungen (oder
  umgekehrt), bleibt er beim Langloch – z. B. Lochreihe unter dem oberen Lamello wird nicht zusätzlich unten bemaßt.
- **Reihenbemaßung innen, Autobemaßung außen:** Die Reihenbemaßung bekommt die erste Spur direkt an der Zeichnung;
  Autobemaßungen außerhalb der Zeichnung (z. B. Gesamtmaß) rücken um ihre Breite nach außen – Kette nah am Teil,
  Gesamtmaß ganz außen. Maße am Teil oder „innen“ bleiben, wo sie sind.
- **Reihenbemaßung: Langlöcher und Ende** – Langlöcher (Rechteck mit runden Enden, auch mit als Polygon angenäherten
  Enden wie die Lamello-Nuten aus „Korpusbearbeitung“) zählen wie Löcher und werden über ihre Mitte bemaßt; die Reihe läuft jetzt bis zur rechten bzw. oberen Kante der Zeichnung, damit die Kette
  geschlossen ist (z. B. 429 · 431 statt nur 429).
- **Einzelmaße außen** (Menü Auto-Einstellungen, „Jeder Vektor“ → *außen*): alle Einzelmaße außerhalb der ganzen
  Zeichnung – Breiten vorne (unten), Höhen links, mit Hilfslinien vom jeweiligen Teil; mehrere Maße stapeln sich
  in eigenen Spuren, das Gesamtmaß liegt ganz außen. Schließt sich mit *innen* aus. Gilt auch für Gruppen „als Ganzes“.
  Die Hilfslinien sind unterbrochen: kurzes Stück am Teil, dann erst wieder ab dem Umriss bis zur Maßlinie –
  so laufen keine Linien quer durch den Korpus.
- **Reihenbemaßung der Lochmitten** (Bereich „Bemaßung“, eigener Schalter „Reihenbemaßung: aus / steigend / Kette“,
  unabhängig von der Autobemaßung): bemaßt die Mitten aller Kreise ab der linken unteren Ecke der Zeichnung – X-Werte
  unter, Y-Werte links neben der Zeichnung, außerhalb der übrigen Maße. *steigend* = alle Werte ab 0 (0, 37, 69 …),
  zu dicht liegende Zahlen werden mit kleinem Knick versetzt; *Kette* = Abstände von Loch zu Loch auf einer
  Maßlinie. Kreise in Gruppen (Lochbilder) zählen mit. Unabhängig von „Bemaßung ausblenden“ – allein oder
  zusammen mit Vectric-/Autobemaßung nutzbar.
  Bezug wählbar „für: Löcher / Linien / beide“ – *Linien* = Lage gerader offener Linien (senkrechte → X-Wert,
  waagrechte → Y-Wert, z. B. Rasterlinien einer Opferplatte); *beide* = Löcher und Linien auf derselben Maßlinie.
  Bedienung wie die Bemaßung: links Haken „Reihenbemaßung“ (an/aus), Schieberegler *Löcher · beide · Linien*,
  rechts *steigend / Kette*. Regler oder Art anklicken schaltet den Haken mit ein; frühere Einstellung wird übernommen.
  Hilfslinien unterbrochen wie bei „außen“: kurzes Stück am Loch bzw. an der Linie, dann erst wieder ab dem Umriss.
- **Gruppen in der Autobemaßung** (Menü Auto-Einstellungen, „Gruppen: auslassen / als Ganzes / einzeln“):
  bisher wurden gruppierte Vektoren immer ausgelassen – z. B. bei einer Opferplatte mit gruppierten Lochbildern kam
  gar kein Maß. *auslassen* = wie bisher, *als Ganzes* = Breite und Höhe des Umrisses jeder Gruppe (auch „innen“),
  *einzeln* = jeder Vektor in der Gruppe wie ein ungruppierter. Verschachtelte Gruppen zählen zur obersten Gruppe.
  Die Abschlussmeldung weist auf die Einstellung hin, wenn Gruppen ohne Maß bleiben.
- **Leeres Feld „Speichern unter“ wird gemerkt:** Wer das Feld leert, bekommt beim Speichern den Windows-Dialog und
  beim nächsten Aufruf wieder ein leeres Feld (vorher stand dann der im Dialog gewählte Pfad drin). Sobald wieder ein
  Pfad eingetragen ist, gilt der Vorschlag wie bisher (letzter Ordner + Name der Zeichnung).
  Der Dialog meldet „Feld leer“ zusätzlich über ein verstecktes Feld, weil VCarve für ein geleertes Feld sonst
  noch den alten Wert liefern kann.
- **Behoben: Innenmaße bei gleichen Teilen nur einmal** (Hinweis von Gremlin): Gleich große Teile nebeneinander
  bekamen das Höhenmaß „innen“ nur beim ersten Teil, weil es als doppelt galt. Jetzt zählt ein Innenmaß nur dann als
  doppelt, wenn es auch an derselben Stelle liegt – jedes Teil bekommt seine Breite und Höhe.
- **Tooltips für „innen“** im Menü Auto-Einstellungen: erklären beim Drüberfahren, was „innen“ bei Gesamtmaßen,
  Einzelmaßen und Radien bedeutet (deutsch/englisch).
- **Papierformat US Letter** (Bereich „Seite“, „Papier: A4 / Letter“): 8,5 × 11 Zoll für „Einpassen“ und festen
  Maßstab. Bei Zoll-Zeichnungen ist Letter voreingestellt, die Wahl wird gemerkt. Beschriftungen und Meldungen
  nennen das gewählte Format („Auf Letter einpassen“, „passt nicht auf Letter“).
- **Behoben: Radius am Kreis fehlte**, wenn die Vectric-Radiuslinie senkrecht oder waagrecht vom Mittelpunkt
  läuft und die Zahl daneben steht (Pfeilspitze mitten auf der Rahmenkante statt in einer Ecke).
- **Hinweis bei großer Schrift auf A4:** Schriftgröße über 10 mm bei „Auf A4 einpassen“ oder festem Maßstab zeigt
  „groß für A4 – Zeichnung wird klein“ neben dem Feld (bei 1:1 kein Hinweis, dort sind große Schriften normal).
- **Bemaßung mit Maßstab skalieren** (Bereich „Bemaßung“): Schrifthöhe in der Zeichnung (Standard 10 mm) × Maßstab,
  begrenzt auf die eingestellte Schriftgröße (oben) und eine Mindestgröße (Standard 2 mm). Beispiel 1:5 → 2 mm,
  1:2 → 3,5 mm. Pfeile und Abstände der Maßlinien wachsen bzw. schrumpfen mit; Titel und Fußzeile bleiben gleich.
- **Maßstab frei wählbar** (Bereich „Seite“, dritte Option „Maßstab:“): z. B. 1:5, 1:7,5 oder 2:1 eintippen oder aus der
  Normliste (▾) wählen. Die Zeichnung kommt im eingestellten Maßstab mittig auf A4 (Ausrichtung wie gewählt; bei
  „Automatisch“ die, in die sie passt). Passt sie nicht, entsteht kein PDF, sondern ein Hinweis mit dem kleinsten
  passenden Normmaßstab.
- **Schmale Maße lesbar** (z. B. Maßketten auf stark verkleinerten Zeichnungen): Passen die Pfeile noch zwischen die
  Hilfslinien, nur die Zahl nicht, bleiben die Pfeile innen und die Zahl steht über (bzw. unter) dem Maß. Erst wenn
  auch die Pfeile nicht passen, kommen sie von außen; die Zahl steht dann daneben – oder, wenn dort schon etwas steht,
  über dem Maß. Zahlen benachbarter Maße weichen einander aus (bis zu zwei Reihen weiter außen).
- **Vectric-Maße besser erkannt**: Kurze Maße und Maßketten (z. B. 18,33 | 20 | 36,67 bei kleiner Maßschrift in VCarve)
  werden jetzt übernommen, auch wenn die Messpunkte etwas weiter vom Maß entfernt liegen. Schmale Maße mit Pfeilen
  von außen (z. B. Nutbreite 4) werden auch ohne ein zweites schmales Maß in der Zeichnung erkannt.
  Maßketten bleiben beim Auseinanderrücken in einer Reihe.
- **Diagnose**: Bei jedem Export schreibt das Gadget `vdim_diag.txt` (von Git ignoriert) mit Rahmen und Ergebnis
  jeder Vectric-Bemaßung – hilft beim Nachvollziehen, warum ein Maß fehlt.
- **Vectric-Maße überlappen nicht mehr**: Liegen Vectric-Bemaßungen so dicht, dass sie sich mit der PDF-Schrift
  überdecken würden (z. B. Gesamtmaß auf gleicher Höhe wie zwei Einzelmaße – bei sehr kleiner Maßschrift in VCarve),
  bleibt das kürzere Maß liegen und das längere rückt eine Spur nach außen. Hilfslinien laufen mit.
  Gerückt wird nur, wenn ein Maß das andere ganz umschließt und beide vom selben Bauteil auf dieselbe Seite
  zeigen – Maße verschiedener Teile (z. B. zwei Maßketten zwischen zwei Teilen) bleiben, wo VCarve sie hat.
- **Speichern unter** (neuer Bereich „Datei“ unten im Dialog): Pfad des PDFs direkt eintragen oder mit „…“ wählen.
  Das Feld hat eine eigene, breite Zeile; bei langen Pfaden ist das Ende (Dateiname) sichtbar.
  Vorgeschlagen werden der zuletzt benutzte Ordner (anfangs „Dokumente“) und der Name der VCarve-Datei (nur der Ordner wird gemerkt,
  damit eine neue Zeichnung nicht das alte PDF überschreibt). Eine vorhandene Datei wird überschrieben;
  leeres Feld = wie bisher beim Export nachfragen.
- **Farbiger Dialog**: Kopfzeile in Blau, jeder Bereich (Linien, Vektoren, Bemaßung, Beschriftung, Seite) mit eigener
  Farbe, weiße Karten auf hellem Grund, OK-Knopf hervorgehoben. Schriftgrößen und Abstände unverändert – der
  automatische Zoom passt wie bisher.
- **Schalter „Vectric-Bemaßung aus“** neben „Autobemaßung“: lässt die Vectric-Bemaßungen im PDF weg, auch wenn ihr
  Layer in VCarve eingeschaltet ist. Tooltip: „Empfohlen, wenn Autobemaßung verwendet wird“.
- Tooltip bei „Autobemaßung“: „Weitere Einstellungen: auf ► klicken“ (Hinweis auf das aufklappbare Menü).
- **Autobemaßung innen oder außen**: Bei „Gesamtmaße“ und „Maße jedes Vektors“ gibt es je ein Häkchen „innen“.
  Innen läuft die Maßlinie durchs Teil (ohne Maßhilfslinien), an der breitesten bzw. höchsten Stelle und mit dem
  dort gemessenen Wert. Bekommt ein Teil beide Innenmaße, liegt das waagrechte oben (Zahl rechts) und das senkrechte
  links (Zahl unten), damit sich nichts überdeckt. Gesamtmaße innen nur, wenn die Zeichnung aus einem Teil besteht –
  sonst bleiben sie außen.
- **Weniger Überlagerungen**: Schräge Maße (z. B. eine fast waagrechte Einzellinie) prüfen, ob ihr Platz frei ist, und
  rücken sonst eine Spur weiter nach außen. Übernommene Vectric-Bemaßungen gelten für die Autobemaßung als belegt.
- **Keine doppelten Maße mit Vectric**: Gibt es für eine Strecke schon eine Vectric-Bemaßung mit gleichem Wert,
  zeichnet die Autobemaßung dieses Maß nicht noch einmal.
- **Maßzahl in der Maßlinie (wie Vectric)**: Neue Einstellung im Bemaßungs-Bereich (Standard: an). Die Zahl sitzt
  mittig in der Maßlinie, die Linie ist um die Zahl unterbrochen – bei waagrechten, senkrechten und schrägen Maßen,
  übernommenen Vectric-Bemaßungen und Durchmessern. Ausgeschaltet steht die Zahl wie bisher über bzw. neben der Linie.
  Zu kurze Maße (Zahl passt nicht zwischen die Pfeile) und Winkel bleiben unverändert.
- **Vectric-Bemaßungen im PDF**: Waagrechte und senkrechte Bemaßungen aus VCarve werden automatisch ins PDF
  übernommen – mit Maßlinie, Pfeilen, Zahl und Hilfslinien. Gesteuert wird das über die Layer in VCarve:
  ist der Layer mit den Bemaßungen eingeschaltet, erscheinen sie im PDF, sonst nicht. An der Zeichnung
  wird nichts verändert. Schräge Bemaßungen kann VCarve nicht an Gadgets weitergeben – sie fehlen im PDF
  (Hinweis in der Abschlussmeldung).
- ~~**Individuelle Bemaßung**~~ *(wieder entfernt, siehe oben – Branch `individ_bem`)* (Schalter mit frei wählbarem Layer, Standard „pdf_dim“; fehlt der Layer, wird er – in Hellgrün, später änderbar – angelegt, auch per Knopf „Layer anlegen“; Anleitung im Rollmenü ►): Eine Linie von Pfeil zu Pfeil wird als Maß gedruckt, eine Linie
  mit 3 Punkten (V-Form) als Winkel – ebenfalls nur, wenn der Layer in VCarve eingeschaltet ist.
  Die Einstellungen „Maß-Layer“ und „ausblenden“ im Dialog entfallen dadurch.
- **Übersichtlicher Bemaßungs-Bereich**: Schalter „Autobemaßung“; die einzelnen Punkte der Autobemaßung (Gesamtmaße, jeder Vektor, Polylinien, Radien, Winkel,
  Einzelmaße ab) stehen in einem aufklappbaren Menü (▸).
- **Maßhilfslinien**: Maße von Vectric-Bemaßungen bekommen automatisch Hilfslinien
  senkrecht bis kurz vor das Bauteil – wie in einer technischen Zeichnung. Alle Maßhilfslinien halten
  2 mm Abstand zum Bauteil (vorher 1 mm).
- **Layer auswählen**: Unter „Welche Vektoren“ gibt es „Gewählte Layer“ mit einer Liste aller Layer zum Ankreuzen
  (z. B. nur Layer 1 und 3). Auch ausgeblendete Layer können gewählt werden; die Auswahl wird gemerkt.
  Interne Werkzeugweg-Layer von VCarve (z. B. „Werkzeugweg-Vorschauen“) erscheinen nicht in der Liste.
- **Layerfarbe**: Jede Linie wird automatisch in der Farbe ihres VCarve-Layers gedruckt; die Farbauswahl
  für die Linien entfällt (die Farbe der Bemaßung bleibt einstellbar). Sehr helle Farben/Weiß werden grau gedruckt.
- **Kleine Maße wie bei Vectric**: Passen Pfeile und Zahl nicht zwischen die Hilfslinien, zeigen die Pfeile von
  außen nach innen und die Zahl steht links (bzw. unten) daneben an der verlängerten Maßlinie.
  Auch solche schmalen Vectric-Bemaßungen (z. B. Nutbreite 8 mm zwischen zwei Linien) werden jetzt erkannt.
- **Kreise** als eigener Punkt im Menü der Autobemaßung: Radius „R …“ mit Pfeil von außen auf den Kreis;
  bei mehreren Kreisen weicht die Beschriftung entlang des Kreises aus.
- **Beschriftungen überlappen nicht mehr**: Radien an konzentrischen Bögen weichen entlang des Bogens
  seitlich aus (sonst gestaffelte Hinweislinien), gleiche Bögen werden nur einmal beschriftet; Zahlen schräger Maße weichen entlang der Maßlinie aus (z. B. bei sich kreuzenden Diagonalen).
- Hinweis, wenn das PDF nicht geschrieben werden kann, weil es noch geöffnet ist.

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
- „Winkel an Ecken“: Kommt in einem geschlossenen Vektor derselbe Winkel mehrmals vor, wird er nur einmal angezeigt.
- **Keine doppelten Maßketten**: Zwei Maßlinien mit gleichem Wert über praktisch derselben Strecke
  (z. B. Innen- und Außenkontur einer Doppellinie, oder ein Einzelmaß gleich dem Gesamtmaß) werden nur einmal gezeichnet.
- **Vectric-Bemaßung erweitert**: Maße *innerhalb* des Bauteils (Pfeile direkt auf den Kanten, Zahl mittig) werden
  jetzt erkannt und mittig gezeichnet; Maße mit kurzen Hilfslinien (Fangpunkt weit vom Maß entfernt) werden ebenfalls übernommen.
- **Kreis R auch für kleine Kreise**: Kreise bekommen ihr Radiusmaß unabhängig von „Einzelmaße ab“ (z. B. Bohrungen);
  Kreise aus Bezier-Kurven (z. B. importiert) werden jetzt ebenfalls als Kreis erkannt.
- **Radien auch an Bezier-Bögen**: Verrundungen, die als Bezier-Kurve vorliegen (z. B. nach Knotenbearbeitung oder Import),
  werden als Kreisbogen erkannt und bei „Radien an Bögen“ bemaßt. Freie Kurven bleiben unbemaßt.
- „Radien an Bögen“ bemaßt jetzt jeden Bogen; neuer Schalter darunter **„gleiche Radien nur einmal (je Vektor)“**
  (Standard: ein) zeigt einen gleichen Radius pro Vektor nur einmal.
- **Vectric-Bemaßung: schräge (parallele) Maße** werden jetzt übernommen (z. B. Diagonale eines Rechtecks).
- Vectric-Bemaßung: Hilfslinien führen jetzt immer zum gemessenen Punkt am richtigen Bauteil
  (vorher konnte z. B. am Kreis-Scheitel ein Nachbarteil getroffen werden).
- Vectric-Bemaßung: **Radiusmaße** werden übernommen (als „R …“ mit Pfeil von außen); Maße an Kreisen
  zeigen jetzt exakt den Vectric-Wert (Maßzahl aus den Vectric-Hilfslinien, vorher z. B. 11.999 statt 12.000).
- Radius-Beschriftungen bekommen rechts/oben eigenen Platz auf der Seite (wurden am Rand abgeschnitten).
- Hilfslinien, die tangential vom Bauteil weglaufen (z. B. am Kreis-Scheitel), beginnen erst, wo sie sich von der
  Kontur gelöst haben – keine „Kerbe“ mehr in der Kreislinie.
- Vectric-Radiusmaße, die in VCarve **innen** liegen (Linie vom Mittelpunkt zum Bogen), werden im PDF ebenso
  innen gezeichnet; außen liegende (Pfeil mit Fahne) bleiben außen.
- Neuer Schalter **„Radius innen (Linie vom Mittelpunkt, wie Vectric)“** in der Autobemaßung: Kreise und Bögen
  bekommen ihr R-Maß dann von innen statt mit Pfeil von außen.
- Vectric schräge Maße: Messpunkte werden zuerst an Ecken/Bogen-Enden gesucht (vorher konnte z. B. bei einem
  Sehnenmaß über einen Bogen ein Punkt mitten auf dem Bogen gewählt werden: 64.9 statt 70.7).
- **Vectric-Winkelmaße** werden übernommen: Scheitel und Schenkel werden gesucht, Maßbogen mit gleichem Radius und
  auf derselben Seite wie in VCarve (auch Winkel über 180°).
- **Längenmaße mit Abstand**: Einzel- und Gesamtmaße, die sich überschneiden würden, werden automatisch
  in eigene Reihen nach außen versetzt – keine Maßlinie und keine Zahl liegt mehr auf einer anderen.
  Der Platz am Blattrand wird dafür automatisch vergrößert.

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
