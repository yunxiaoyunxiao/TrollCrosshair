# FloatImage 1.1 — TrollStore iPadOS

This branch contains the FloatImage 1.1 source snapshot prepared for iPadOS 17.0 and TrollStore.

## Status
- Source project snapshot; not a compiled IPA.
- PHPicker image selection and GIF decoding via ImageIO.
- X/Y position, width, height, opacity controls and one-tap reset.
- Settings preview uses the same decoded image as the floating view.
- URL scheme: `floatimage://toggle`, `floatimage://show`, `floatimage://hide`.

## Important limitation
The current floating window is a same-process UIKit UIWindow prototype. `UIWindowLevelAlert + 1` does not establish cross-app display. A separate HUD process/scene and the required system permissions still need implementation and real-device verification. URL Scheme activation may foreground the app; it is not silent background execution.

## Build
Open `TrollCrosshair_1_0/TrollCrosshair.xcodeproj` on macOS with Xcode and build for iPadOS 17.0. No IPA is included in this branch yet.
