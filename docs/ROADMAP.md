# HelioBar — Roadmap

> Created 2026-06-08. Direction: **Path B — rich biometrics on Mac via the proprietary
> ZeppOS BLE protocol** (HRV, SpO2, stress, skin temp, respiratory rate, resting HR, sleep
> stages, ~7 days of history) — 100% local, no cloud, no account, no $99.
> Context & rationale: `docs/CONTEXT.md` §6–§7. Spike plan:
> `docs/superpowers/plans/2026-06-08-zeppos-ble-spike.md`.

## The three data tiers (why this roadmap is shaped the way it is)

| Tier | BLE path | Data | Status |
|---|---|---|---|
| 1 (shipped) | Standard HR `0x180D` | Averaged BPM | Rock solid |
| 2 (this roadmap) | Proprietary ZeppOS protocol | HRV*, SpO2, stress, skin temp, resp rate, resting HR, sleep stages, steps, ~7d history, battery | Proven in Gadgetbridge; not yet in HelioBar |
| 3 (fallback) | iOS + HealthKit | HRV, sleep, history | Not pursued (Path C fallback) |

\* **Daily-average HRV, not continuous RMSSD** — the strap never streams RR intervals over
either path. Design features around "morning HRV + trend + recovery," not live HRV.

---

## Phase 0 — Perfect the BPM app (no new BLE path needed)

Ships value immediately and makes the current app excellent regardless of Tier 2 progress.
Most of this is pure `HelioCore` (testable) or self-contained UI.

| # | Item | Where | Effort | Risk | Notes |
|---|---|---|---|---|---|
| 0.1 | **Resting-HR setting + Karvonen (HRR) zones** | HelioCore + Settings | M | low | More accurate than `220−age`; foundation for recovery score. Additive/opt-in. **← started this session** |
| 0.2 | **5-zone model** (Z1–Z5) | HelioCore | M | low | Standard training zones; pure + testable |
| 0.3 | **Persist session history** | App (file IO) | M | low | Today `resetSession()` discards everything; persist sparkline + daily min/avg/max |
| 0.4 | **Resonance / box breathing** | BreathingView + Settings | M | low | Configurable pace; 6 breaths/min coherence breathing (evidence-based) |
| 0.5 | **Low-HR (bradycardia) alert** | HelioCore + AppModel | S | low | Mirrors `ElevatedHRAlertEngine`; add quiet hours + notification actions |
| 0.6 | **Menu-bar customization** | MenuBarIcon + Settings | S | low | Optional battery glyph; HR / HR+zone / HR+trend |
| 0.7 | **Sparkline windows** | HRSparkline | S | low | 2 min / 10 min / 1 hr; zone-shaded background |
| 0.8 | **Accessibility pass** | Views | M | low | VoiceOver labels; honor Reduce Motion in PulsingHeart/Breathing |
| 0.9 | **Onboarding / first-run** | App | M | low | Guide "enable Heart Rate Push in Zepp" + permission priming |

## Phase 1 — De-risk Tier 2 (the BLE spike) — ✅ DONE (2026-06-08)

**The handshake works end-to-end against the real strap** (`./scripts/zepp-spike.sh` → AUTH OK).
Path B is proven: the full ZeppOS auth (B-163 ECDH + AES + chunked transport) is implemented in
HelioCore (verified) and authenticated locally. Phase 2 is unblocked. See the spike plan.

| # | Item | Effort | Notes |
|---|---|---|---|
| 1.1 | Run `./scripts/inspect-ble.sh` wearing the strap | S | Confirm proprietary ZeppOS service UUIDs exist on this device |
| 1.2 | Extract auth key via `huami-token` | S | One-time; email/password Zepp account. Don't unpair from Zepp after |
| 1.3 | Prototype the ECDH + AES handshake in a throwaway Swift CLI | L | Reference Gadgetbridge `Huami2021`/ZeppOS support; `kevdagoat/zepp-os-esphome` for the crypto |
| 1.4 | Decode one rich frame (HRV or resting HR) end-to-end | M | Proof the decode works → green-light Phase 2 |

## Phase 2 — Tier 2 features (the 3.0 headline)

Build only after Phase 1 is green. Decode logic goes in `HelioCore` (pure, testable);
the BLE transport + crypto in the app layer behind a `RichBiometricsMonitor` sibling to the
current `HeartRateMonitor`.

| # | Item | User value | Notes |
|---|---|---|---|
| 2.1 | **Auth-key setup flow** | — | Paste/import the key in Settings; secure storage (Keychain); clear "don't unpair from Zepp" warning |
| 2.2 | **Proprietary BLE transport + handshake** | — | `RichBiometricsMonitor`; graceful fallback to Tier-1 BPM if handshake fails |
| 2.3 | **Resting HR + HRV trend** | ★★★ | Morning reading + 7-day trend |
| 2.4 | **Recovery score** | ★★★ | HRV + resting HR → one number + menu-bar recovery ring. The flagship metric |
| 2.5 | **Sleep stages + smart alarm** | ★★★ | Light/deep/REM; wake-in-window near light sleep (most-requested community feature) |
| 2.6 | **Stress / SpO2 / skin temp / resp rate** | ★★ | The full Zepp dashboard, local |
| 2.7 | **~7 days on-device history backfill** | ★★ | Trends with no cloud, no account |
| 2.8 | **Steps / activity / workout auto-detect** | ★ | |

## Phase 3 — "Complete & perfect": distribution & reliability

| # | Item | Effort | Notes |
|---|---|---|---|
| 3.1 | **Notarization** ($99/yr) | M | Removes the Gatekeeper warning — #1 distribution friction. Gate on demand signal |
| 3.2 | **CI/CD** GitHub Action | M | tag → build → (notarize) → release. No `.github/workflows/` exists yet |
| 3.3 | **Sparkle auto-update** | M | Today UpdateChecker only checks + opens a browser |
| 3.4 | **Homebrew cask** | S | After notarization |
| 3.5 | **Localization** | M | All strings hardcoded English today |
| 3.6 | **Reliability**: reconnect backoff, multi-strap selection, overnight power assertion | M | `HeartRateMonitor` grabs the first `0x180D` device today |

---

## Architectural assets that de-risk all of the above
- `HelioCore` is platform-agnostic (zero AppKit) → ports to iOS unchanged (Path C fallback).
- `HeartRatePacket` already parses RR intervals → ready if any future firmware/device streams them.
- The `@Observable HealthStore` single-source-of-truth + the per-engine pattern
  (`*AlertEngine`, `BatteryEstimateEngine`, `UpdatePolicy`, `BreathingSession`) generalize
  cleanly to new metrics: add a field to the store, a pure engine in `HelioCore`, a view that reads it.
