#!/usr/bin/env python3
"""
Linux BLE HCI Multi-Student Advertiser
=======================================
Simulates N student phones from a SINGLE Linux Bluetooth adapter by rapidly
cycling through student ID payloads in the BLE advertisement manufacturer data.

The teacher's phone scans for kStudentServiceUuid and parses the manufacturer
data. Since Android caches advertisements by MAC address, we rotate student IDs
faster than the teacher's 7-second scan-cycle restart — so the teacher sees
many distinct student IDs even though they all come from one MAC.

How it works
------------
  Each "round" (default: every 500 ms per student):
  1. Build a BLE ADV_NONCONN_IND packet with:
       - Flags AD type (0x01): LE General Discoverable + BR/EDR Not Supported
       - 16-bit UUID (0x03): 0x181C  (kStudentServiceUuid, little-endian)
       - Manufacturer Specific (0xFF): company_id=0x004C + UTF-8 payload
         payload format: "{studentId}|{hits}|{total}|{divId}:{batchId}"
  2. Write it directly to /dev/hci0 via hcitool cmd / btmgmt raw.

Requirements
------------
  - Linux with BlueZ (hciconfig, hcitool in PATH) — already confirmed present
  - A Bluetooth USB dongle plugged in (or built-in BT adapter)
  - Run as root, or add CAP_NET_ADMIN:
      sudo python3 ble_hci_advertiser.py
  - The teacher app running on a real Android phone in the same room

Usage
-----
  sudo python3 ble_hci_advertiser.py                         # 70 students, div 1
  sudo python3 ble_hci_advertiser.py --students 30 --div 2
  sudo python3 ble_hci_advertiser.py --students 60 --dwell 0.3 --rounds 8
  sudo python3 ble_hci_advertiser.py --hci hci1             # second adapter

Arguments
---------
  --hci        Adapter name (default: hci0)
  --students   Number of student IDs to cycle (default: 70)
  --start      First student index, e.g. 1 → 25CE001 (default: 1)
  --div        Division ID embedded in payload (default: 1)
  --batch      Batch ID (0 = no batch / lecture mode, default: 0)
  --dwell      Seconds to advertise each student ID (default: 0.4)
  --rounds     How many full cycles to run (default: 5)
  --total      Simulated global beacon counter sent to teacher (default: 10)
  --verified   Mark all students as biometric-verified in payload

Payload anatomy (mirrors _updateStudentAdvertising in main.dart)
----------------------------------------------------------------
  Text:   "25CE001|7|10|1:0"
           ^       ^ ^  ^ ^
           student hits total div:batch
  Bytes:  [0x4C,0x00] + utf8(text)   ← company_id little-endian prefix
  AD:     Type=0xFF (Manufacturer Specific), length=2+len(text)

Teacher-side parsing (_extractStudentPayload in main.dart)
----------------------------------------------------------
  bytes.sublist(2)  → strips the 2-byte company_id prefix
  payload.split('|') → ['25CE001','7','10','1:0']
"""

import argparse
import struct
import subprocess
import sys
import time

# ── Bluetooth constants ──────────────────────────────────────────────────────

# kStudentServiceUuid = '0000181C-0000-1000-8000-00805F9B34FB'
#
# CRITICAL: Android's AdvertiseData.Builder.addServiceUuid() always encodes
# the UUID as a 128-bit entry (AD type 0x07), even for Bluetooth SIG short-form
# UUIDs.  Android's hardware scan filter for flutter_reactive_ble's
# withServices: [...] matches against 128-bit UUID records.
# Using the 16-bit short form in AD type 0x03 will NOT pass the hardware filter
# on most Android devices — the packet gets silently dropped before the app
# even sees it.
#
# UUID bytes in little-endian order (how they appear in the BLE AD record):
#   0000181C-0000-1000-8000-00805F9B34FB
#   → FB 34 9B 5F 80 00 00 80 00 10 00 00 1C 18 00 00
STUDENT_SERVICE_UUID_128_LE = bytes([
    0xFB, 0x34, 0x9B, 0x5F, 0x80, 0x00,  # last 6 bytes of UUID
    0x00, 0x80,                            # next 2
    0x00, 0x10,                            # next 2
    0x00, 0x00,                            # next 2
    0x1C, 0x18, 0x00, 0x00,               # first 4 bytes (little-endian)
])
MANUFACTURER_ID = 0x004C           # kManufacturerId — little-endian: 0x4C 0x00


# ── HCI raw command helpers ──────────────────────────────────────────────────

def _le_bytes(n: int, length: int) -> bytes:
    """Little-endian integer → bytes."""
    return n.to_bytes(length, "little")


def build_adv_data(student_id: str, hits: int, total: int,
                   div_id: int, batch_id: int, verified: bool) -> bytes:
    """
    Build a BLE advertisement data blob (max 31 bytes) that the teacher app
    will parse as a valid student beacon.

    AD structure:
      [len][type=0x01][flags]                          Flags
      [len][type=0x07][16 uuid bytes LE]               Complete 128-bit UUIDs
      [len][type=0xFF][company_lo][company_hi][data]   Manufacturer Specific

    WHY 0x07 (128-bit) and NOT 0x03 (16-bit):
      Android's AdvertiseData.Builder.addServiceUuid() always emits the UUID as
      a 128-bit AD record (0x07), even for Bluetooth SIG assigned numbers.
      flutter_reactive_ble's withServices scan filter matches against 128-bit
      UUID records on Android — packets with only a 16-bit UUID (0x03) are
      dropped by the hardware scan filter before the app sees them.

    31-byte budget breakdown:
      Flags   : 3 bytes  (len=2, type=0x01, value=0x06)
      UUID128 : 18 bytes (len=17, type=0x07, 16 UUID bytes)
      Mfr hdr : 4 bytes  (len, type=0xFF, 2-byte company_id)
      Payload : 6 bytes  remaining for UTF-8 student data
      Total   : 31 bytes

    "25CE001|8|10|1:0" = 18 chars — too long for 6 bytes.
    We drop the scope suffix from the AD payload and rely on the app's
    _extractStudentPayload which already handles missing scope gracefully
    (divisionId stays null, and the teacher's division filter skips it).

    To pass the division filter we MUST include the scope.  So we trim the
    student ID prefix instead — but student IDs are fixed-length (7 chars for
    25CExxx), so we can't trim there either.

    Solution: put the full payload only in manufacturer data, and accept that
    the scope (divId:batchId) part may be truncated.  The teacher app's
    division filter will then drop the packet — UNLESS we set divisionId and
    batchId correctly in the payload within the 6-byte budget.

    Actually the simplest solution is to use a SCAN RESPONSE packet for the
    manufacturer data (up to 31 more bytes), keeping only the UUID in the
    primary advertisement.  hcitool supports this via the scan response data
    command (OCF 0x0009).  We do that below.

    Primary AD  (31 bytes): Flags + 128-bit UUID only
    Scan Response (31 bytes): Manufacturer data with full payload

    Android delivers both primary AD and scan response to the app as a single
    DiscoveredDevice event when in active scan mode (lowLatency = active).
    """
    v_flag = "|V" if verified else ""
    payload_str = f"{student_id}|{hits}|{total}|{div_id}:{batch_id}{v_flag}"
    payload_bytes = payload_str.encode("utf-8")

    # ── Primary advertisement: Flags + 128-bit UUID ───────────────────────
    flags_ad  = bytes([0x02, 0x01, 0x06])                              # 3 bytes
    uuid128_ad = bytes([0x11, 0x07]) + STUDENT_SERVICE_UUID_128_LE    # 18 bytes
    primary = flags_ad + uuid128_ad                                     # 21 bytes
    primary_padded = primary + bytes(31 - len(primary))                # pad to 31

    # ── Scan response: Manufacturer Specific with full payload ────────────
    mfr_data = struct.pack("<H", MANUFACTURER_ID) + payload_bytes
    # If payload still too long for 31-byte scan response, truncate payload
    # (max mfr payload = 31 - 2 [len+type] - 2 [company_id] = 27 bytes)
    max_payload = 27
    if len(payload_bytes) > max_payload:
        payload_bytes = payload_str.encode("utf-8")[:max_payload]
        mfr_data = struct.pack("<H", MANUFACTURER_ID) + payload_bytes
    mfr_ad = bytes([len(mfr_data) + 1, 0xFF]) + mfr_data
    scan_resp = mfr_ad + bytes(31 - len(mfr_ad))                      # pad to 31

    return primary_padded, scan_resp


def hcitool_cmd(hci: str, ogf: int, ocf: int, params: bytes) -> bool:
    """
    Send a raw HCI command via `hcitool cmd`.
    hcitool cmd <hci> <ogf> <ocf> [param bytes as hex...]
    """
    hex_params = " ".join(f"0x{b:02x}" for b in params)
    cmd = ["hcitool", "-i", hci, "cmd",
           f"0x{ogf:02x}", f"0x{ocf:02x}"] + hex_params.split()
    try:
        result = subprocess.run(cmd, capture_output=True, timeout=3)
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


# OGF / OCF for BLE advertising HCI commands
OGF_LE_CTL = 0x08
OCF_LE_SET_ADV_PARAMS   = 0x0006
OCF_LE_SET_ADV_DATA     = 0x0008
OCF_LE_SET_ADV_ENABLE   = 0x000A


def le_set_adv_params(hci: str):
    """
    HCI_LE_Set_Advertising_Parameters
    ADV_IND (0x00) — connectable, undirected, scannable.
    We need scannable (not ADV_NONCONN_IND) so the Android phone can send a
    scan request and receive the scan response containing the manufacturer data.
    Interval min/max: 100 ms (0x00A0)
    """
    params = struct.pack(
        "<HHBBB6sBB",
        0x00A0,   # adv_interval_min (100 ms)
        0x00A0,   # adv_interval_max (100 ms)
        0x00,     # adv_type: ADV_IND (connectable, undirected — scannable)
        0x00,     # own_address_type: public
        0x00,     # peer_address_type: public
        bytes(6), # peer_address: 00:00:00:00:00:00
        0x07,     # adv_channel_map: all three channels (37, 38, 39)
        0x00,     # adv_filter_policy: allow all
    )
    return hcitool_cmd(hci, OGF_LE_CTL, OCF_LE_SET_ADV_PARAMS, params)


def le_set_adv_data(hci: str, adv_data: bytes) -> bool:
    """
    HCI_LE_Set_Advertising_Data
    Param: 1 byte length + 31 bytes data
    """
    assert len(adv_data) == 31
    params = bytes([len(adv_data)]) + adv_data
    return hcitool_cmd(hci, OGF_LE_CTL, OCF_LE_SET_ADV_DATA, params)


def le_set_scan_response_data(hci: str, scan_resp: bytes) -> bool:
    """
    HCI_LE_Set_Scan_Response_Data  (OCF 0x0009)
    Param: 1 byte length + 31 bytes data
    Android lowLatency scan mode = active scan, so it WILL request scan
    responses. The manufacturer data travels in the scan response, which
    is what _extractStudentPayload reads.
    """
    assert len(scan_resp) == 31
    params = bytes([len(scan_resp)]) + scan_resp
    return hcitool_cmd(hci, OGF_LE_CTL, 0x0009, params)


def le_set_adv_enable(hci: str, enable: bool) -> bool:
    """HCI_LE_Set_Advertising_Enable"""
    return hcitool_cmd(hci, OGF_LE_CTL, OCF_LE_SET_ADV_ENABLE, bytes([1 if enable else 0]))


def bring_up(hci: str):
    subprocess.run(["hciconfig", hci, "up"], capture_output=True)
    time.sleep(0.2)


def reset_adv(hci: str):
    le_set_adv_enable(hci, False)
    time.sleep(0.05)


# ── Student ID generator ─────────────────────────────────────────────────────

def student_ids(n: int, start: int = 1) -> list[str]:
    return [f"25CE{i:03d}" for i in range(start, start + n)]


# ── Main advertising loop ────────────────────────────────────────────────────

def run(args):
    hci = args.hci
    ids = student_ids(args.students, args.start)
    div_id = args.div
    batch_id = args.batch
    dwell = args.dwell
    rounds = args.rounds
    base_total = args.total
    verified = args.verified

    print("=" * 58)
    print("BLE HCI Multi-Student Advertiser")
    print(f"  Adapter   : {hci}")
    print(f"  Students  : {len(ids)}  ({ids[0]} … {ids[-1]})")
    print(f"  Division  : {div_id}  Batch: {batch_id or 'none'}")
    print(f"  Dwell/ID  : {dwell}s")
    print(f"  Rounds    : {rounds}")
    print(f"  Verified  : {verified}")
    print("=" * 58)
    print()
    print("Make sure the teacher app is running and scanning on the phone.")
    print("Each student ID will be advertised for {:.0f} ms before cycling.".format(dwell * 1000))
    print()

    bring_up(hci)
    reset_adv(hci)

    if not le_set_adv_params(hci):
        print("[error] Could not set advertising parameters.")
        print("        Are you running as root?  Is the adapter plugged in?")
        sys.exit(1)

    total_advertised = 0
    t_start = time.monotonic()

    try:
        for round_num in range(1, rounds + 1):
            # Simulate increasing hit counter (teacher sent `round_num` beacons so far)
            total_beacons = base_total + round_num
            print(f"[round {round_num}/{rounds}]  total_beacons={total_beacons}")

            for idx, sid in enumerate(ids):
                # hits = how many of those beacons this student "saw"
                # Simulate ~85% in-range probability
                hits = max(1, int(total_beacons * 0.85))

                adv_data, scan_resp = build_adv_data(
                    student_id=sid,
                    hits=hits,
                    total=total_beacons,
                    div_id=div_id,
                    batch_id=batch_id,
                    verified=verified,
                )

                # Stop → update primary AD + scan response → start
                le_set_adv_enable(hci, False)
                le_set_adv_data(hci, adv_data)
                le_set_scan_response_data(hci, scan_resp)
                le_set_adv_enable(hci, True)

                total_advertised += 1
                if (idx + 1) % 10 == 0:
                    elapsed = time.monotonic() - t_start
                    rate = total_advertised / elapsed
                    print(f"  {idx + 1:3d}/{len(ids)} students cycled  "
                          f"({rate:.1f} IDs/s)  last={sid}")

                time.sleep(dwell)

            print(f"  Round {round_num} complete.\n")

    except KeyboardInterrupt:
        print("\n[interrupted]")
    finally:
        le_set_adv_enable(hci, False)
        elapsed = time.monotonic() - t_start
        print()
        print("=" * 58)
        print(f"Done.  {total_advertised} advertisement bursts in {elapsed:.1f}s")
        print(f"Rate: {total_advertised / elapsed:.1f} student IDs/s")
        print()
        print("Now check the teacher app:")
        print(f"  - Should show up to {len(ids)} students in the scan list")
        print("  - Each student should have a non-zero hit count")
        print("  - No crash / ANR / UI freeze on the teacher phone")
        print("=" * 58)


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(
        description="Advertise N student BLE beacons from one Linux adapter.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--hci",      default="hci0",  help="Bluetooth adapter")
    p.add_argument("--students", type=int, default=70,  help="Number of student IDs to cycle")
    p.add_argument("--start",    type=int, default=1,   help="First student index (25CE{N:03d})")
    p.add_argument("--div",      type=int, default=1,   help="Division ID in payload")
    p.add_argument("--batch",    type=int, default=0,   help="Batch ID (0 = lecture/no batch)")
    p.add_argument("--dwell",    type=float, default=0.4, help="Seconds per student ID")
    p.add_argument("--rounds",   type=int, default=5,   help="Full cycles to run")
    p.add_argument("--total",    type=int, default=10,  help="Simulated teacher beacon counter base")
    p.add_argument("--verified", action="store_true",   help="Mark all students biometric-verified")
    return p.parse_args()


if __name__ == "__main__":
    if sys.platform != "linux":
        print("This script requires Linux with BlueZ (hcitool/hciconfig).")
        sys.exit(1)
    run(parse_args())
