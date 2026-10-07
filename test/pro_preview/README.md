# Pro UI visual preview (golden screenshots)

Regenerate every screenshot (no backend or login needed): `flutter test test/pro_preview --update-goldens` — PNGs land in `test/pro_preview/goldens/` (390×844 @2x, plus `<name>_tall.png` at 390×1500).
One screen group per `*_test.dart` (run a single file to iterate); `harness.dart` holds fonts, plugin mocks, the signed-in fake user/branding and the router; `fixtures.dart` is the fake API (dates are relative to today); unmatched requests are logged as `[pro_preview] UNMATCHED`.
Text styles without a `fontFamily` render in Roboto (as on Android); preview the intended all-Geist look with `--dart-define=PREVIEW_FALLBACK_FONT=Geist`.
A plain `flutter test` skips these previews (live clocks make them differ run to run); add `--dart-define=PRO_PREVIEW=true` without `--update-goldens` to use them as a visual-regression check.
