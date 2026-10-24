# Vektor_PDF

*[Deutsche Version](README.de.md)*

A gadget for **Vectric VCarve Pro / Aspire** (V12 and later) that exports your vectors as a clearly readable **PDF drawing** – to print for the workshop, as a true-to-scale template, or as a dimensioned sketch for a customer.

## Why this gadget?

Printing directly from VCarve gives extremely thin lines that are hard to read in the workshop. Vektor_PDF prints the drawing with adjustable line width, takes over the dimensions you set in VCarve in a readable form and can add dimensions by itself if you want.

## Features

**Drawing**

- Export **selected vectors**, **all visible layers** or **chosen layers** (groups included)
- Jobs with **several sheets**: current sheet or all sheets as a **multi-page PDF**
- Lines, arcs and Bézier curves as real vector graphics in the PDF
- Adjustable **line width**; fixed colour or **as in VCarve** (colour of the layer)
- Optional grey material outline

**Dimensions** – every type can be switched on and off independently

- **Vectric dimensions:** dimensions you added in VCarve (horizontal, vertical, aligned, radii, angles) are carried over into the PDF in a readable form – controlled by the layers in VCarve
- **Auto dimensions** (slider *Vectric · both · Auto*, menu "Auto settings ►"):
  - overall size, each vector, circles (R), radii on arcs, angles at corners
  - each one **inside** (through the part) or **outside** (in front of the drawing, with broken extension lines)
  - groups skipped, measured as a whole or each vector on its own
  - single dimensions only above a minimum size (e.g. none on lettering)
- **Row dimensions** for hole rows, slots (e.g. Lamello) and grid lines:
  - *running* (from 0) or as a *chain*
  - reference: holes, lines or both
  - split by side, holes only bottom/left, optionally **per part**
- Value inside the dimension line (like Vectric) or above it; colour, line width, arrow and font size adjustable
- Font size can scale with the drawing scale
- Dimensions move out of each other's way; duplicates are left out

**Page and labels**

- Paper **A4** or **US Letter**, portrait/landscape or automatic
- **Fit to page**, **1:1** or **any scale** (e.g. 1:5, 1:7.5, 2:1)
- **Title** and **note** at the top, **scale, unit (mm/inch) and date** in the footer
- **Save as** right in the dialog (empty field = ask when exporting)
- Dialog, messages and PDF in **English or German**
- All settings are remembered

## Installation

**Recommended:** download `Vektor_PDF.vgadget` from the
[latest release](https://github.com/hardiatgithub/Vektor_PDF/releases),
install it in VCarve / Aspire via **Gadgets → Install Gadget…** and restart the software.
The gadget then appears under **Gadgets → Vektor_PDF**.

**Manual install:** copy the folder `Vektor_PDF` containing `Vektor_PDF.lua` and `Vektor_PDF.htm` to the public gadget folder, for example:

```
C:\Users\Public\Documents\Vectric Files\Gadgets\VCarve Pro V12.5\Vektor_PDF\
```

(adjust product name and version, e.g. `Aspire V12.5`) and restart.

> The folder name and the name of the `.lua` file must be identical (`Vektor_PDF`).

## Usage

1. Open a job and – if you like – select the vectors you want to export.
2. Run **Gadgets → Vektor_PDF**.
3. Choose lines, dimensions, labels and page settings.
   Use **English / Deutsch** at the top right to switch the language.
4. Click **OK** – the PDF is saved to the "Save as" path (or you are asked where to save it).

## A note on dimensions

After installation, only **Vectric dimensions** are active – the gadget takes the dimensions **you've added yourself in VCarve**. If you haven't drawn any dimensions, none will appear in the PDF; in that case just switch on auto dimensions.

Less is often more: turning everything on at once quickly clutters the drawing. Row dimensions are meant for special cases, such as hole rows or drilling patterns in furniture making.

## Tips & limitations

- VCarve text objects have no vector shape and are skipped – convert text to curves if you want it in the PDF.
- On every export the gadget writes `vdim_diag.txt` to the gadget folder. It helps to find out why a Vectric dimension is missing.
- The PDF uses the standard Helvetica font; Ø and accented characters are supported.
- Developed and tested with **VCarve Pro V12.5** on Windows.

## Thanks

A big thank you to **Gremlin** (gremlin529), who supports the project with lots of helpful tips, testing and ideas.

## Feedback

Found a bug or have an idea? Please open an
[issue](https://github.com/hardiatgithub/Vektor_PDF/issues).

All changes are listed in the [CHANGELOG](CHANGELOG.md) (German).

## Licence

MIT – see [LICENSE](LICENSE).
