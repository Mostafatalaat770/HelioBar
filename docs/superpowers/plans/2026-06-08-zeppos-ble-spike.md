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

## RESULTS — Step 1 DONE (2026-06-08) ✅ GREEN LIGHT

`inspect-ble.sh` on the actual strap (firmware `3.13.0.1`, serial `2445B531000856`,
MAC `C4:81:BC:2F:42:1F` from System ID) confirmed the proprietary stack. **It is the
Huami2021 / ZeppOS protocol** — same one Gadgetbridge decodes.

Service / characteristic map (Huami UUID base `XXXXXXXX-0000-3512-2118-0009AF100700`):

| UUID | Role | Props |
|---|---|---|
| `FEE0` / `FEE1` | Huami data + auth services | — |
| `0x0016` | **Chunked-2021 WRITE** (auth + commands) | writeWithoutResponse, notify |
| `0x0017` | **Chunked-2021 READ** | writeWithoutResponse, notify |
| `0x0004` / `0x0005` | Legacy activity fetch (history) CONTROL / DATA | — |
| `0x0001` / `0x0002` / `0x0006` / `0x0023..0x0025` | Legacy Huami chars | — |
| `00001530/1531/1532` | Firmware/DFU (ignore) | — |
| `2A37` (180D) | Live HR — already used by HelioBar | notify |
| `2A19` (180F) | Battery — already used | read, notify |

Decisions resolved:
- **No `0x0009` auth char** → Huami2021 ECDH handshake (not the legacy simple-AES one).
- **Rich data is fetch-based, not streamed.** Live HR stays on standard `2A37`; HRV/sleep/
  stress come from authenticated requests over `0x0016/0x0017`, history via `0x0004/0x0005`.
  → product shape = keep live HR + add a periodic "sync rich metrics" fetch.
- The strap accepted the Mac connection and exposed everything (Zepp closed). Whether the
  authenticated handshake also needs Zepp fully disconnected is TBD at Step 3.

**Next: Step 2 (get the auth key) + Step 3 (build the handshake).**

### Step 3 progress — crypto core built + verified offline (2026-06-08)
The hardware-independent half of the handshake is done, in `HelioCore/Sources/HelioCore/Zepp/`
(pure + unit-tested, rather than a throwaway CLI, so it can graduate straight into Phase 2):
- `AESECB` — AES-128-ECB, checked against the FIPS-197 vector.
- `GF163` — GF(2^163) field, checked against hand-computed reductions + the known x⁻¹.
- `B163` — curve point ops + ECDH. **Important correction:** Gadgetbridge's `ECDH_B163.java`
  showed the curve is **B-163 / sect163r2** (a=1, specific b + base point + order), NOT the
  Koblitz K-163/sect163k1 first assumed. The field is identical (same reduction poly), and b
  doesn't appear in add/double, so only the domain constants changed. Keys are 24-byte LE
  scalars; public keys / shared secrets are 48 bytes = x‖y (24-byte LE each), matching
  `ECDH_B163`. Fast structural tests run by default; the rigorous **n·G = ∞** proof of the
  B-163 params is opt-in:
  ```
  RUN_EC_SLOW_TESTS=1 swift test --filter B163Tests
  ```

- `Huami2021Chunked` — the chunked transfer framing over `0x0016/0x0017` (from the
  Gadgetbridge `Huami2021ChunkedEncoder`). Encoder + reassembling decoder, round-trip tested.
  Wire format (non-extended, 4-byte header): `[0]=0x03 [1]=flags [2]=writeHandle [3]=count`;
  first chunk then carries 4-byte LE length + 2-byte LE type; flags `0x01`=first, `0x06`=last,
  `0x08`=encrypted. `MAX_CHUNKLENGTH = mtu − 3 − headerSize`.

**Encrypted post-auth payload (captured for later, not yet coded):** `messageKey[i] =
sessionKey[i] ^ writeHandle`; payload wrapped as `seqNo(4) + data + crc32(4)`, padded to 16,
AES-encrypted. The ECDH auth exchange itself is sent *unencrypted* (sessionKey not yet known),
which is why the unencrypted framing above is what we need first.

**Still needs the auth key + hardware (next session):**
1. The auth command sequence (fetch Gadgetbridge `Huami2021` auth service): send our public
   key → receive device key + encrypted random → `sessionKey = sharedSecret[8..24] XOR authKey`
   → AES round-trip the challenge → confirm. Public-key byte layout/endianness from source.
2. A `Tools/ZeppSpike` BLE CLI: read `KEY` from `.env`, connect, run the handshake using the
   verified `Sect163k1`/`AESECB`/`Huami2021Chunked`, print "auth OK".
3. Iterate live against the strap (extended-flags? MTU? coexist-with-Zepp?).

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
