---
type: reference
title: Qt mis-parses compact SVG arc flags
description: A path packing large-arc and sweep as 00 comes out sheared in QtQuick.Shapes, so the shipped mark has its arcs converted to lines
tags: [qt, qml, svg]
status: stable
verified:
  - by: rendering the original path in QtQuick.Shapes and comparing against rsvg
    at: 2026-08-15
---

# The defect

SVG arc commands may pack the large-arc-flag and sweep-flag without separators,
which is valid and common in minified paths:

```
a19.79 19.79 0 00-4.88-1.51
```

Those two `0` characters are two flags. Qt's path parser reads `00` as a single
number, so every following value shifts by one and the geometry comes out
sheared. The shape renders, which is what makes it easy to miss: it just looks
subtly wrong.

# The fix used here

Discord's mark has 17 corner arcs, each with a radius under 0.08 in a 24 unit
box, which is invisible at bar sizes. Converting every one of them to a line
removes the parse hazard with no visible change.

The alternative, expanding the flags into a spaced form the parser reads
correctly, was not needed here but is the general answer for a path with arcs
that matter.

# Measuring the mark

The ink bounds, measured with rsvg rather than taken from the viewBox, are
x 0 to 24 and y 2.85 to 21.15, an aspect ratio of 1.3115. Fitting to the ink
bounds rather than to the viewBox is what makes an icon sit correctly against
neighbours drawn from a font.
