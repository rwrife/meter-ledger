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

Flutter stable, one Dart codebase: Windows desktop primary CI/release, Android and iOS phones and tablets first-class. Current shell shows only a coming-soon message using Cupertino on iOS, Material 3 on Android, and plain Flutter desktop widgets on Windows. Adaptive navigation, Fluent-style desktop workspace, accessibility and scalable layout remain planned; never impose another OS's appearance. Planned data layer uses local SQLite without network or accounts; backup/export with user-chosen destination remains future work. No camera/location permission needed for manual entry. Future backups may include private address and cost data; user controls sharing.

Android applicationId and iOS bundle ID: `com.infinityball.meterledger`; iPad enabled. ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_TEAM_ID names reserved for later opt-in iOS publishing; secret values never enter repository. `AppStore/description.txt` is planned-feature copy. `AppStore/icon.png` is generated art from OpenAI Images `gpt-image-2.5-flare`; platform icon wiring remains backlog work.

## Status and milestones

Flutter project skeleton and platform folders exist. CI tests and builds Windows release plus Android debug; app currently displays a coming-soon screen, with no meter storage or calculations. See [PLAN.md](PLAN.md) and remaining issues. Windows release workflow and store submission remain backlog work. No completed app or store listing claimed.

## Development quickstart

Install Flutter 3.47.7 stable from `docs/toolchain.json`; run `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test`, `flutter build windows --release` on Windows, and `flutter build apk --debug` on Linux/Android Docker. iOS compile requires macOS and remains unverified.

## Manual setup required

App Store Connect bundle identifier `com.infinityball.meterledger` was **not registered**: `FAILED bundleId lookup rejected: FORBIDDEN_ERROR.PLA_NOT_ACCEPTED`. Apple account owner must accept current Program License Agreement, then rerun `/home/rwrife/workspaces/tool-lab/asc_create_bundle_id.py meter-ledger`. Do not claim registration until command returns `CREATED` or `EXISTS`.
