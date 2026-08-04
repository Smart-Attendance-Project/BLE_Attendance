# Load & Stress Tests

Pre-production tests that verify the system handles a full class of 50–70
students without crashing.  Three independent layers are tested:

| File | What it tests | Needs |
|---|---|---|
| `ble_hci_advertiser.py` | BLE radio layer — teacher phone scanner | Linux BT adapter + teacher Android phone |
| `ble_scan_stress_test.dart` | Flutter scan handler logic, no hardware | `flutter test` only |
| `db_stress.py` | DB insert throughput + summary query latency | Running Postgres |

---

## 1. BLE HCI Advertiser  (`ble_hci_advertiser.py`)

**The core test.** Cycles through N student IDs on a single Linux Bluetooth
adapter, advertising each one for ~400 ms before switching to the next.
The teacher's Android phone scans and should accumulate all students in its
detection list without freezing or crashing.

### Why one adapter is enough

The teacher app de-duplicates by **student ID string**, not by MAC address.
However, Android itself deduplicates received BLE advertisements **by MAC
address** within a single scan window — so if all students share the adapter's
public MAC, the phone only delivers ~1 callback per 7-second window.

The fix: the script now calls `HCI_LE_Set_Random_Address` before each student
slot, giving each student a unique spoofed random LE address.  Android sees
each student as a distinct device and delivers all of them.  One full cycle of
70 students at 400 ms/each = 28 s, spanning ~4 scan windows.  With unique MACs,
every student shows up.

### Burst mode (new)

Simulates the real-world scenario where all 70 students are already in range
when the teacher starts a session — the phone needs to detect all of them in
one sweep without dropping any.

```bash
# All 70 students cycled as fast as possible (50 ms/student = 3.5 s/round)
sudo python3 load_tests/ble_hci_advertiser.py --burst --students 70 --rounds 3

# Adjust burst dwell (default 0.4 applies — pass a low value for burst)
sudo python3 load_tests/ble_hci_advertiser.py --burst --dwell 0.05 --students 70
```

In burst mode:
- Each student gets 50 ms (or `--dwell` value) of airtime.
- 70 students × 50 ms = **3.5 s total**, well inside the 7-second Android scan
  window — so the phone should see all 70 in a single window.
- A 3-second pause between rounds lets you observe the count stabilise.
- **Expected result:** teacher phone shows all 70 after the first burst round.
- **Failure signal:** some students consistently missing across rounds = the
  phone is dropping events under load (setState storm, thread contention, etc.).

### Hardware needed

- A **USB Bluetooth dongle** plugged into this Linux machine (any cheap
  CSR8510/BCM20702 adapter works, ~₹300–500), **or**
- Run the script on your laptop if it has Bluetooth built in.

Confirm the adapter is visible:
```bash
hciconfig        # should show hci0
bluetoothctl show
```

### Run

```bash
# Start as root (HCI raw access requires it)
sudo python3 load_tests/ble_hci_advertiser.py

# Custom options
sudo python3 load_tests/ble_hci_advertiser.py \
    --hci hci0 \
    --students 70 \
    --div 1 \
    --batch 0 \
    --dwell 0.4 \
    --rounds 5
```

| Arg | Default | Meaning |
|---|---|---|
| `--hci` | `hci0` | Bluetooth adapter |
| `--students` | `70` | Student IDs to cycle |
| `--start` | `1` | First student index (→ `25CE001`) |
| `--div` | `1` | Division ID in payload |
| `--batch` | `0` | Batch ID (`0` = lecture / no batch) |
| `--dwell` | `0.4` | Seconds per student (sequential); per-student minimum in burst mode |
| `--rounds` | `5` | Full cycles to run |
| `--verified` | off | Mark all students biometric-verified |
| `--burst` | off | Burst mode — cycle all students as fast as possible to stress-test simultaneous detection |

### What to watch on the teacher phone

- Open the teacher app, start a session for division 1.
- The "Detected students" list should fill up with student IDs as the script
  runs.
- After one full cycle, you should see **all 70 students** with non-zero hit
  counts.
- No ANR dialog, no UI freeze, no app crash = **PASS**.

### Payload format (mirrors `_updateStudentAdvertising` in `main.dart`)

The script splits the advertisement across two packets:

**Primary advertisement** (passes the hardware scan filter):
```
AD type 0x01 (Flags):        0x06  (LE General Discoverable, BR/EDR not supported)
AD type 0x07 (128-bit UUID): FB 34 9B 5F 80 00 00 80 00 10 00 00 1C 18 00 00
                              ↑ little-endian form of 0000181C-0000-1000-8000-00805F9B34FB
```

**Scan response** (carries the actual payload — Android lowLatency = active scan, always requests this):
```
AD type 0xFF (Manufacturer): 0x4C 0x00  +  UTF-8 string
UTF-8 string: "{studentId}|{hits}|{total}|{divId}:{batchId}[|V]"
Example:      "25CE001|8|10|1:0"
```

Why 128-bit UUID in the primary AD (not 16-bit shorthand):
Android's `AdvertiseData.Builder.addServiceUuid()` (used by `flutter_ble_peripheral`)
always emits 128-bit UUID records (`AD type 0x07`). The `flutter_reactive_ble`
hardware scan filter on Android matches against 128-bit UUID records — packets
with only a 16-bit UUID (`AD type 0x03`) are silently dropped by the OS before
the Flutter app ever sees them.

Teacher parser (`_extractStudentPayload`):
- Reads `bytes.sublist(2)` from the scan response manufacturer data → strips the 2-byte company_id prefix
- Splits on `|` → `[studentId, hits, total, scope, ...]`

---

## 2. Flutter Scan Handler Stress Test  (`ble_scan_stress_test.dart`)

Pure Dart unit test.  No phone, no Bluetooth, no network needed.
Pumps synthetic `DiscoveredDevice` events directly into the same parsing and
tally logic the production app uses.

### Run

```bash
cd mobile/ble_attendance_mobile
flutter pub get
flutter test test/ble_scan_stress_test.dart --reporter expanded
```

### What it covers

| Test | What it catches |
|---|---|
| Parser correctness (8 cases) | Crashes on valid/invalid payloads |
| 70-student storm, all detected | Any student silently dropped |
| Completes in < 200 ms | setState storm / parse bottleneck |
| Duplicate events → max hits kept | Double-counting students |
| Division filter | Wrong-division students leaking in |
| Batch filter | Wrong-batch students leaking in |
| Range filter (start/end student ID) | Off-by-one in string comparison |
| Verified flag latches true | Biometric status flipping back to false |
| Teacher beacon in flood | Teacher packet parsed as a student |
| Presence ratio at 75% threshold | Wrong present/absent classification |
| 5 × 70 events < 500 ms total | Repeated scan-cycle restart cost |

Expected output:
```
00:00 +18: All tests passed!
```

---

## 3. Database Stress Test  (`db_stress.py`)

Tests the two DB-heavy paths that run during every live session:

- **Insert throughput** — one `Detection` row per student per BLE window.
  70 students × 10 windows = 700 inserts with 8 concurrent threads.
- **Summary query load** — the per-student `COUNT(detections)` + attendance
  lookup that the teacher panel polls every 10 s, run 20× concurrently.

All test data is created in isolated rows and deleted after the test.

### Run

```bash
# Make sure Postgres is running (docker compose up -d in backend/)
cd /path/to/repo
PYTHONPATH=backend .venv/bin/python load_tests/db_stress.py

# More aggressive
PYTHONPATH=backend .venv/bin/python load_tests/db_stress.py \
    --students 70 \
    --rounds 15 \
    --query-rounds 30 \
    --workers 10
```

| Arg | Default | Meaning |
|---|---|---|
| `--students` | `70` | Students per simulated session |
| `--rounds` | `10` | BLE windows (each inserts one row per student) |
| `--query-rounds` | `20` | Rounds of concurrent summary queries |
| `--workers` | `8` | Concurrent DB threads |
| `--skip-inserts` | off | Only run the summary query test |
| `--skip-summary` | off | Only run the insert test |

### Pass thresholds

| Metric | Threshold |
|---|---|
| Insert p95 latency | < 200 ms |
| Summary query p95 latency | < 500 ms |
| Errors | 0 |

---

## Known limitations

### BLE layer — one adapter = sequential, not simultaneous

Real phones broadcast simultaneously.  The Linux adapter broadcasts one at a
time, cycling through IDs.  This means:

- The teacher sees students **sequentially**, not all at once.
- If `--dwell` × `--students` > 7 s (the teacher scan-cycle restart), some
  student IDs may be seen in a later scan window.  This is fine for a 70-student
  test with `--dwell 0.4` (28 s/cycle), since the scan restarts at 7 s and
  will catch all 70 across ~4 windows.

To get closer to simultaneous broadcast, lower `--dwell` (minimum ~0.1 s is
stable with most adapters) or use multiple adapters with `--hci hci0` / `hci1`.

### Android BLE scan throttle

Android limits BLE scan starts to **5 per 30 seconds** per app.  The teacher
app already works around this with a 7-second restart timer.  If you see the
teacher app stop updating, wait 30 s for the throttle window to reset.
