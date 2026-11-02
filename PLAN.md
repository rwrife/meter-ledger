# Meter Ledger plan

## Scope and data contract

Flutter stable, Dart domain calculations and SQLite persistence, manual entries. Entities: property; meter with physical displayed unit and optional documented rollover modulus; timestamped reading with immutable correction reason; bill interval with billed quantity, amount and currency. Reconciliation compares readings only at documented interval boundaries in matching units; gaps and meter swaps yield unknown. Keep correction history and transactional imports. No automated provider integration or extrapolated billing assertions.

## Architecture and UX

One Flutter project with `windows/`, `android/`, `ios/`. Pure Dart interval calculations first, then local SQLite store, then UI. Strategy A platform-native adaptive: one small adaptive-widget seam (`MeterWorkspaceLayout`, `AdaptiveScaffold`, `AdaptiveDialog`): Cupertino iOS/iPadOS, Material 3 Android, Fluent Windows using `fluent_ui` when implementation justifies it. Phone bottom navigation, tablet split navigation, desktop navigation pane with resize and shortcuts; touch, keyboard/mouse, screen readers, high contrast, font scaling. TargetPlatform.iOS, TargetPlatform.android, TargetPlatform.windows golden/widget checks. Native date/file pickers and platform back behavior. No Material on iOS, Cupertino on Android, or phone UI on Windows.

Local-only data, explicit CSV and JSON export/backup, safe validated import, no account/telemetry/network. Files contain private addresses/utility costs; export requires explicit destination. No permissions needed for manual entry. Mobile tablets enabled. Android applicationId and iOS bundle identifier `com.infinityball.meterledger`. ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_TEAM_ID are configured by name for later opt-in store submission. Apple registration currently blocked by `FORBIDDEN_ERROR.PLA_NOT_ACCEPTED` pending owner action. `AppStore/description.txt` describes intended behavior; `AppStore/icon.png` holds real generated image, platform wiring pending.

## Milestones (dependency order)

1. Flutter stable skeleton and Windows test/build CI plus Android debug compile on Linux Docker; generate all three platform folders.
2. Pure Dart cumulative-reading deltas, rollover/replacement rules and exact-boundary comparison with deterministic tests.
3. SQLite migrations, correction audit, import transaction tests.
4. Properties/meters/readings/bills workflow and charts.
5. Platform-authentic adaptive UI and target-platform golden/widget plus accessibility tests.
6. CSV export and validated JSON backup/restore.
7. Wire generated icon to Windows `.ico`, Android/iOS launcher icon sets, audit listing copy, Windows release smoke. `.github/workflows/release.yml`: `v*` tag/manual dispatch, `windows-latest` release build, zip portable artifact and GitHub release. TestFlight via ASC secrets and Google Play later, not MVP.

## Verification and risks

Unit tests: same-unit interval math, missing boundary, decreasing readings, rollover with explicit modulus, meter replacement, equal timestamps, corrections, inconsistent billed units. Widget tests at phone/tablet/desktop sizes and three TargetPlatforms. CI runs `flutter test`, `flutter build windows --release` on `windows-latest`; Android `flutter build apk --debug` on Linux/Docker; iOS compilation requires macOS runner and belongs to later milestone. No claim of native build from Linux source checks. Actual bill totals may include fixed fees/taxes; never infer utility-provider fault from a discrepancy. Data can be lost without backup; require explicit export and atomic restore.

## Non-goals

No cloud sync, accounts, OCR, automated utility API, leak alarms, emergency monitoring, medical claims, rate prediction, or billing certification. No native Swift/Xcode-only app, React Native, Expo, Kotlin Multiplatform, .NET MAUI or Unity. Modern desktop UX is mandatory, not stretched phone UI.
