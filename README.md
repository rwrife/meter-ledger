# Meter Ledger

Offline household utility meter journal: enter electricity, gas, and water readings, reconcile billed intervals, and spot unexplained usage on phone, tablet, and Windows without accounts.

## Why and for whom

For renters, homeowners, and small property caretakers who want a transparent record independent of utility portals. Record a meter's displayed cumulative reading and unit with date; compare interval usage against an entered bill's start/end dates, billed quantity, and total. See discrepancies as observations, not accusations or savings guarantees.

## Intended workflow

1. Add a property and one or more electricity (kWh), water (m³/gal), or gas (therm/m³) meters; record exact display unit, meter identifier nickname, and optional rollover modulus only when known.
2. Enter dated cumulative readings, including correction notes. Reject decreasing readings unless a documented rollover or meter replacement starts a new series. Never silently convert incompatible units.
3. Enter bill interval, billed quantity and optional amount/currency, then compare readings at exact boundaries. If no boundary reading exists, label the comparison **unknown**, not zero or an interpolated fact.
4. Review interval deltas and prior comparable periods; export CSV readings and JSON backup. Import validates before replacing local data.

## MVP and limits

- Multiple properties/meters, manual readings and correction audit trail; bill reconciliation with unknown-safe intervals; basic usage charts; export/import.
- No smart-meter API, automatic OCR, provider login, cloud sync, ads, tariff prediction, or billing disputes. Rate estimates are out of scope: actual bill totals include fees/taxes and varying tariffs.
- No medical, safety, leak-detection, or emergency claims. This is a personal log, not a calibrated billing instrument.

## Platforms and privacy

Flutter stable, one Dart codebase: Windows desktop primary CI/release, Android and iOS phones and tablets first-class. Adaptive layout supports touch, keyboard/mouse, resize and accessible screen-reader labels, contrast and scalable text. Strategy A: Cupertino on iOS/iPadOS, Material 3 on Android, Fluent-style desktop on Windows behind a small adaptive-widget seam; never impose another OS's appearance. SQLite local only, no network or account; explicit user-chosen backup/export paths. Optional camera capture is not MVP, so no camera/location/network permission requested. Backups may include private address and cost data; user controls sharing.

Android applicationId and iOS bundle ID: `com.infinityball.meterledger`; iPad enabled. ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_TEAM_ID names reserved for later opt-in iOS publishing; secret values never enter repository. `AppStore/description.txt` is planned-feature copy. `AppStore/icon.png` is generated art from OpenAI Images `gpt-image-2.5-flare`; platform icon wiring remains backlog work.

## Status and milestones

Documentation and generated art only; no Flutter project or builds yet. See [PLAN.md](PLAN.md) and seven issues: skeleton/CI, pure calculations, storage, workflows, adaptive UI, backup, release. Project skeleton must create `windows/`, `android/`, `ios/`. `.github/workflows/release.yml` must build zipped Windows release on `windows-latest` for `v*` tags/manual dispatch; TestFlight/Play submission deferred. No completed app or store listing claimed.

## Development quickstart (after skeleton issue)

Install pinned Flutter stable from `docs/toolchain.json`; run `flutter pub get`, `flutter test`, `flutter build windows --release` on Windows, and `flutter build apk --debug` on Linux/Docker. Source-only documentation cannot be built yet.

## Manual setup required

App Store Connect bundle identifier `com.infinityball.meterledger` was **not registered**: `FAILED bundleId lookup rejected: FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`. Apple account owner must accept current Program License Agreement, then rerun `/home/rwrife/workspaces/tool-lab/asc_create_bundle_id.py meter-ledger`. Do not claim registration until command returns `CREATED` or `EXISTS`.
