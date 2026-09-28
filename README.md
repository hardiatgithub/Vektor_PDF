# Vektor_PDF

*[Deutsche Version](README.de.md)*

A gadget for **Vectric VCarve Pro / Aspire** (V12 and later) that exports your vectors as a clean **PDF drawing** – with adjustable line width and colour, automatic dimensions, a title and a scale note.

Handy for sending a customer a quick dimensioned sketch, printing a template 1:1, or keeping a paper record of a job.

## Features

- Export **selected vectors** or **all visible layers** (groups included)
- Lines, arcs and Bézier curves are written to the PDF as real vector graphics
- **Line width** and **colour** of the vectors adjustable
- **Automatic dimensions**
  - overall size (width × height)
  - optional size of every closed vector, circles as diameter (Ø)
  - minimum size for individual dimensions (e.g. no dimensions on lettering)
  - optional radii on arcs (R …)
  - optional angles at corners between straight edges (right angles are skipped)
  - colour, line width and arrow size of the dimensions adjustable
- **Manual dimensions and angles** via a dedicated layer (see below)
- **Title** and **note** at the top of the sheet
- **Scale, unit (mm/inch) and date** in the footer
- Page: **fit to A4** (portrait/landscape automatic) or **scale 1:1**
- Optional grey material outline
- Dialog, messages and PDF footer in **English or German** (switch at the top right of the dialog)
- All settings are remembered between runs

## Installation

**Recommended:** download `Vektor_PDF_x.y.z.vgadget` from the
[latest release](https://github.com/hardiatgithub/Vektor_PDF/releases/latest)
and install it in VCarve / Aspire via **Gadgets → Install Gadget**.

**Manual install:** copy the folder `Vektor_PDF` containing

- `Vektor_PDF.lua`
- `Vektor_PDF.htm`

to the public gadget folder, for example:

```
C:\Users\Public\Documents\Vectric Files\Gadgets\VCarve Pro V12.5\Vektor_PDF\
```

(adjust product name and version, e.g. `Aspire V12.5`) and restart the software.
The gadget then appears under **Gadgets → Vektor_PDF**.

> The folder name and the name of the `.lua` file must be identical (`Vektor_PDF`).

## Usage

1. Open a job and – if you like – select the vectors you want to export.
2. Run **Gadgets → Vektor_PDF**.
3. Choose line width, colours, dimensions, labels and page settings.
   Use **English / Deutsch** at the top right to switch the language.
4. Click **OK** and choose where to save the PDF.

## Manual dimensions

For dimensions the gadget cannot create automatically – e.g. the gap between two parts:

1. Create a layer called **`Bemassung`** in VCarve
   (the name can be changed in the dialog under *Dim. layer*).
2. On that layer, draw a **line** from point to point – snapping to the edges works best.
3. The gadget does not print this line as a vector but as a **dimension** with arrows and length –
   horizontal, vertical or aligned, depending on the direction of the line.

**Angles:** draw a line with **three points** in a V shape along the two edges – the middle point
is the corner (vertex). The gadget prints an arc with arrows and the angle, e.g. `45°`.

Tick **hide** next to *Dim. layer* to leave the manual dimensions out of the PDF
(or simply hide the layer in VCarve).

## Tips & limitations

- VCarve's own **dimension and text objects** cannot be read by gadgets and are skipped.
  The gadget creates its own dimensions instead. Convert text to curves if you want it in the PDF.
- **Lettering** converted to curves gets no individual dimensions if it is grouped
  or smaller than the *Min. size* setting.
- **Ellipses** and free-form curves consist of Bézier curves and therefore have no radius (R).
- The PDF uses the standard Helvetica font; Ø and accented characters are supported.
- Developed and tested with **VCarve Pro V12.5** on Windows.

## Feedback

Found a bug or have an idea? Please open an
[issue](https://github.com/hardiatgithub/Vektor_PDF/issues).

## Licence

MIT – see [LICENSE](LICENSE).
