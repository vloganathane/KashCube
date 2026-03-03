#!/usr/bin/env python3
"""
Generate assets/data/in_pincodes.json from the datameet India Post dataset.

Run once at development time:
    python3 scripts/generate_pincode_asset.py

Output format — compact JSON map:
    {"110001": ["New Delhi", "Delhi"], "400001": ["Mumbai", "Maharashtra"], ...}
    key   = 6-digit PIN
    value = [city, canonical_state]   (matching kIndianStates in Indian_states.dart)

No runtime network calls — purely a dev-time asset generator.
"""

import json
import sys
import urllib.request
from pathlib import Path

# ---------------------------------------------------------------------------
# State name normalisation → kIndianStates canonical values
# ---------------------------------------------------------------------------
STATE_MAP: dict[str, str] = {
    # Andaman & Nicobar
    "ANDAMAN AND NICOBAR": "Andaman & Nicobar",
    "ANDAMAN & NICOBAR": "Andaman & Nicobar",
    "ANDAMAN AND NICOBAR ISLANDS": "Andaman & Nicobar",
    # Andhra Pradesh
    "ANDHRA PRADESH": "Andhra Pradesh",
    # Arunachal Pradesh
    "ARUNACHAL PRADESH": "Arunachal Pradesh",
    # Assam
    "ASSAM": "Assam",
    # Bihar
    "BIHAR": "Bihar",
    # Chandigarh
    "CHANDIGARH": "Chandigarh",
    # Chhattisgarh
    "CHHATTISGARH": "Chhattisgarh",
    "CHATTISGARH": "Chhattisgarh",
    # Dadra & NH
    "DADRA AND NAGAR HAVELI": "Dadra & NH",
    "DADRA & NAGAR HAVELI": "Dadra & NH",
    "DADRA AND NAGAR HAVELI AND DAMAN AND DIU": "Dadra & NH",
    "DADRA & NH": "Dadra & NH",
    # Daman & Diu
    "DAMAN AND DIU": "Daman & Diu",
    "DAMAN & DIU": "Daman & Diu",
    # Delhi
    "DELHI": "Delhi",
    "NCT OF DELHI": "Delhi",
    # Goa
    "GOA": "Goa",
    # Gujarat
    "GUJARAT": "Gujarat",
    # Haryana
    "HARYANA": "Haryana",
    # Himachal Pradesh
    "HIMACHAL PRADESH": "Himachal Pradesh",
    # Jammu & Kashmir
    "JAMMU AND KASHMIR": "Jammu & Kashmir",
    "JAMMU & KASHMIR": "Jammu & Kashmir",
    "J&K": "Jammu & Kashmir",
    # Jharkhand
    "JHARKHAND": "Jharkhand",
    # Karnataka
    "KARNATAKA": "Karnataka",
    # Kerala
    "KERALA": "Kerala",
    # Ladakh
    "LADAKH": "Ladakh",
    # Lakshadweep
    "LAKSHADWEEP": "Lakshadweep",
    # Madhya Pradesh
    "MADHYA PRADESH": "Madhya Pradesh",
    # Maharashtra
    "MAHARASHTRA": "Maharashtra",
    # Manipur
    "MANIPUR": "Manipur",
    # Meghalaya
    "MEGHALAYA": "Meghalaya",
    # Mizoram
    "MIZORAM": "Mizoram",
    # Nagaland
    "NAGALAND": "Nagaland",
    # Odisha
    "ODISHA": "Odisha",
    "ORISSA": "Odisha",
    # Puducherry
    "PUDUCHERRY": "Puducherry",
    "PONDICHERRY": "Puducherry",
    # Punjab
    "PUNJAB": "Punjab",
    # Rajasthan
    "RAJASTHAN": "Rajasthan",
    # Sikkim
    "SIKKIM": "Sikkim",
    # Tamil Nadu
    "TAMIL NADU": "Tamil Nadu",
    "TAMILNADU": "Tamil Nadu",
    # Telangana
    "TELANGANA": "Telangana",
    # Tripura
    "TRIPURA": "Tripura",
    # Uttar Pradesh
    "UTTAR PRADESH": "Uttar Pradesh",
    # Uttarakhand
    "UTTARAKHAND": "Uttarakhand",
    "UTTARANCHAL": "Uttarakhand",
    # West Bengal
    "WEST BENGAL": "West Bengal",
}

# ---------------------------------------------------------------------------
# Data sources (tried in order)
# ---------------------------------------------------------------------------
SOURCES = [
    # datameet India Post GeoJSON — authoritative, public domain
    (
        "datameet/india-post GeoJSON",
        "https://raw.githubusercontent.com/datameet/india-post/master/data/pincodes.json",
        "json_array",
    ),
    # Fallback: another well-known repo CSV via raw GitHub
    (
        "India Post CSV (backup)",
        "https://raw.githubusercontent.com/sai-ravi-teja/Indian-Pincodes/main/pincodes.json",
        "json_array_alt",
    ),
]


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "KashCube-asset-generator/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read()


def normalise_state(raw: str) -> str | None:
    key = raw.upper().strip()
    return STATE_MAP.get(key)


def title_case(s: str) -> str:
    """Title-case a city name, handling common abbreviations."""
    return " ".join(
        w.capitalize() if w not in ("OF", "AND", "&") else w.lower()
        for w in s.strip().split()
    )


def process_datameet(raw: bytes) -> dict[str, list[str]]:
    """
    datameet pincodes.json format:
    [{"Pincode": "110001", "OfficeName": "Parliament Street H.O.", "DistrictName": "Central Delhi",
      "StateName": "DELHI", ...}, ...]
    """
    data = json.loads(raw)
    result: dict[str, list[str]] = {}
    skipped = 0
    for row in data:
        pin = str(row.get("Pincode") or row.get("pincode") or "").strip().zfill(6)
        if len(pin) != 6 or not pin.isdigit():
            continue
        raw_state = str(row.get("StateName") or row.get("state") or "").strip()
        state = normalise_state(raw_state)
        if not state:
            skipped += 1
            continue
        # Prefer DistrictName as city (more readable than OfficeName)
        city_raw = (
            row.get("DistrictName")
            or row.get("districtName")
            or row.get("district")
            or row.get("OfficeName")
            or row.get("officeName")
            or ""
        ).strip()
        city = title_case(city_raw) if city_raw else ""
        if not city:
            continue
        # Only insert if not already seen (first entry wins —  Head Office preference)
        if pin not in result:
            result[pin] = [city, state]
    print(f"  Processed {len(result)} pincodes, skipped {skipped} unknown states")
    return result


def main() -> None:
    out_dir = Path(__file__).parent.parent / "assets" / "data"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "in_pincodes.json"

    pincodes: dict[str, list[str]] = {}

    for name, url, fmt in SOURCES:
        print(f"Trying: {name}")
        print(f"  URL: {url}")
        try:
            raw = fetch(url)
            print(f"  Downloaded {len(raw):,} bytes")
        except Exception as e:
            print(f"  FAILED: {e}")
            continue

        try:
            if fmt in ("json_array", "json_array_alt"):
                pincodes = process_datameet(raw)
            else:
                print(f"  Unknown format: {fmt}")
                continue
        except Exception as e:
            print(f"  Parse error: {e}")
            continue

        if pincodes:
            break

    if not pincodes:
        print("\nAll sources failed. Generating minimal seed data for testing...")
        # Seed a representative sample so the app still compiles
        pincodes = {
            "110001": ["New Delhi", "Delhi"],
            "400001": ["Mumbai", "Maharashtra"],
            "600001": ["Chennai", "Tamil Nadu"],
            "500001": ["Hyderabad", "Telangana"],
            "560001": ["Bengaluru", "Karnataka"],
            "700001": ["Kolkata", "West Bengal"],
            "302001": ["Jaipur", "Rajasthan"],
            "226001": ["Lucknow", "Uttar Pradesh"],
            "380001": ["Ahmedabad", "Gujarat"],
            "160017": ["Chandigarh", "Chandigarh"],
        }

    # Sort by PIN for deterministic diffs
    sorted_data = dict(sorted(pincodes.items()))

    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(sorted_data, f, ensure_ascii=False, separators=(",", ":"))

    size_kb = out_file.stat().st_size / 1024
    print(f"\n✅ Written {len(sorted_data):,} entries to {out_file}")
    print(f"   File size: {size_kb:.1f} KB")

    # Quick coverage stats
    from collections import Counter
    state_counts = Counter(v[1] for v in sorted_data.values())
    print(f"\nTop 10 states by PIN count:")
    for state, count in state_counts.most_common(10):
        print(f"  {state:<30} {count:>6}")


if __name__ == "__main__":
    main()
