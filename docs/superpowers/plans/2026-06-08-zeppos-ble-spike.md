# Spike: ZeppOS proprietary BLE protocol on the Helio Strap

> Created 2026-06-08. Goal: **prove (or disprove) that HelioBar can read rich biometrics
> (starting with HRV / resting HR) directly from the strap over the proprietary ZeppOS BLE
> protocol — locally, no cloud.** This is a throwaway spike to de-risk Phase 2 of
> `docs/ROADMAP.md` before committing to the full build. Time-box: ~1 day.

## Why this is now low-risk
Gadgetbridge **already decodes** the Helio Strap (HRV, sleep, stress, SpO2, HR, battery)
over this protocol — merged and confirmed working. We are porting a proven reference, not
inventing one. The only genuine unknowns are (a) the exact service UUIDs on *this* strap,
and (b) re-implementing the crypto handshake in Swift/CoreBluetooth.

## Success criterion (the one thing that green-lights Phase 2)
Decode **one** rich value end-to-end from the strap — ideally **resting HR or daily-average
HRV** — in a standalone Swift CLI, using a locally-extracted auth key. If that works, the
transport + crypto are real and the rest is decoding more frame types.

---

## Step 1 — Confirm the proprietary service exists on this device (~15 min)
Run the inspector we already have; it discovers **all** services (`discoverServices(nil)`):

```bash
./scripts/inspect-ble.sh   # wear the strap, keep it near the Mac
```

Look in the output for **non-standard service UUIDs** beyond the known standard ones
(`180D` HR, `180F` battery, `180A` device info, `1800/1801` GAP/GATT). Expect a vendor
service — historically Huami used `FEE0`/`FEE1` (and char handles `0x0016/0x0017` for auth on
newer ZeppOS). **Record the actual UUIDs and characteristic properties** (read/write/notify)
into this file. If no proprietary service appears, STOP — fall back to Path C (iOS+HealthKit).

> Note: the strap may only expose / accept the proprietary service when it is **not currently
> connected to the Zepp app**. Close Zepp on the phone (or put the phone out of range) during
> the scan.

## Step 2 — Extract the auth key (one-time, ~15 min)
Use [`huami-token`](https://codeberg.org/argrento/huami-token):

1. Ensure the strap is paired + synced in the **Zepp app** with an **email/password** account
   (social-login accounts won't work — create an email/password Amazfit account if needed).
2. Run `huami-token` with `--method amazfit --email ... --password ...` to fetch the
   per-device Bluetooth token (16-byte auth key).
3. **Do NOT unpair the strap from Zepp afterward** — that invalidates the key (server-based
   pairing). The key is otherwise stable.
4. Store it only in a local, untracked file for the spike (see Security below).

## Step 3 — Prototype the handshake in a throwaway Swift CLI (~half day)
New scratch target (e.g. `Tools/ZeppSpike/`, do **not** wire into the app yet). Reference, in
priority order:
- **Gadgetbridge** — canonical Java decode. Find the Huami2021 / ZeppOS support classes
  (`*Huami2021*Support`, `*Coordinator`) and the auth/`Huami2021ChunkedEncoder/Decoder`.
- **`kevdagoat/zepp-os-esphome`** — the crypto in C++/Python: **ECDH on `sect163k1` + AES-ECB**,
  `session_key = shared_secret[8..24] XOR auth_key`; auth chars `0x0016` (write) / `0x0017`
  (notify). Cross-checked against Gadgetbridge.
- **`a9eelsh/HelioCore`** — same Swift/CoreBluetooth stack; borrow CoreBluetooth wiring patterns.

Handshake shape to implement:
1. Subscribe (notify) to the auth characteristic.
2. Send "request random" → receive challenge.
3. ECDH key exchange (sect163k1) → derive `session_key` via the XOR-with-auth-key step.
4. AES-encrypt the challenge, write it back → receive "auth success".
5. On success, subscribe to the data characteristic(s) and request a metric.

## Step 4 — Decode one rich frame (~1–2 h)
Once authenticated, request/parse the simplest high-value frame. Candidates by ascending
difficulty: **battery (proprietary) → resting HR → daily HRV**. Match the byte layout against
Gadgetbridge's parser. Print the decoded value. **That printout is the green light.**

---

## If green → Phase 2 shape (not part of the spike)
- Decoders move into `HelioCore` as pure, unit-tested functions (feed them captured frames as
  `Data` fixtures — same style as `HeartRatePacketTests`).
- Transport + crypto live in the app as `RichBiometricsMonitor`, a sibling of
  `HeartRateMonitor`, pushing into `HealthStore`. **Tier-1 BPM stays the fallback** if the
  handshake fails (so we never regress reliability).
- Auth key stored in the **Keychain**; Settings flow to import it (Phase 2.1).

## Security (must hold)
- The auth key and any account credentials go in **untracked** files only (already covered by
  `.gitignore` patterns for `.build/`; add an explicit ignore for any `*.authkey`/secrets file).
- Never commit the key, a captured token, or account credentials. (Repo history was previously
  scanned clean — keep it that way; see `docs/CONTEXT.md` §8.)

## Open questions to resolve during the spike
- [ ] Exact proprietary service + characteristic UUIDs on this strap (fill from Step 1).
- [ ] Does the strap allow the proprietary connection while Zepp is also connected, or must
      Zepp be disconnected? (Affects daily-use UX — does the user have to choose HelioBar *or* Zepp?)
- [ ] Is rich data **streamed live** or only **fetched on demand** (history sync)? Determines
      whether "live HRV-ish" is even meaningful vs. a periodic morning fetch.
- [ ] Auth-key longevity in practice — does a Zepp app update or re-sync rotate it?
