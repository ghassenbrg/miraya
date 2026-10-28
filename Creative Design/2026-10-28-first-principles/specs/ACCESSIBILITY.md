# Accessibility and contrast — proposal only

Calculated WCAG contrast ratios from the proposal tokens:

- Ink `#10131B` / Paper `#F6F5F2`: **17.03:1**
- Slate `#646B7A` / Paper: **4.91:1**
- Iris Dark `#4A3DCC` / Paper: **6.80:1**
- White / Iris `#6D5DF5`: **4.63:1**
- White / TV Ink `#08090D`: **19.90:1**
- Focus Lime `#D6F65E` / TV Ink: **16.30:1**
- Ink / Focus Lime: **15.21:1**
- Mint `#B8F2E6` / Ink: **14.93:1**
- Ember `#FF7A6B` / Ink: **7.29:1**

Iris on Paper is **4.25:1**, so it is not used for normal-sized body text.

D-pad focus uses stroke + halo + scale; status is never color-only. Pairing digits are oversized/tabular. The safer `Decline` action receives first focus on an unsolicited pairing request. Back/Stop behavior is written on-screen. The identity does not require animation; any future seam animation should honor reduced-motion settings.