#!/usr/bin/env python3
"""
Convert /tmp/package/pincodes.json (from india-pincode-lookup npm package)
into assets/data/in_pincodes.json used by PincodeLookupService.

Output format:
  {"110001": ["New Delhi", "Delhi"], "400001": ["Mumbai", "Maharashtra"], ...}
  key   = 6-digit PIN string
  value = [district/city name, canonical state matching kIndianStates]
"""

import json
from pathlib import Path
from collections import defaultdict, Counter

STATE_MAP = {
    "ANDAMAN AND NICOBAR": "Andaman & Nicobar",
    "ANDAMAN & NICOBAR": "Andaman & Nicobar",
    "ANDAMAN AND NICOBAR ISLANDS": "Andaman & Nicobar",
    "ANDAMAN & NICOBAR ISLANDS": "Andaman & Nicobar",
    "ANDHRA PRADESH": "Andhra Pradesh",
    "ARUNACHAL PRADESH": "Arunachal Pradesh",
    "ASSAM": "Assam",
    "BIHAR": "Bihar",
    "CHANDIGARH": "Chandigarh",
    "CHHATTISGARH": "Chhattisgarh",
    "CHATTISGARH": "Chhattisgarh",
    "DADRA AND NAGAR HAVELI": "Dadra & NH",
    "DADRA & NAGAR HAVELI": "Dadra & NH",
    "DADRA AND NAGAR HAVELI AND DAMAN AND DIU": "Dadra & NH",
    "DADRA & NH": "Dadra & NH",
    "DAMAN AND DIU": "Daman & Diu",
    "DAMAN & DIU": "Daman & Diu",
    "DELHI": "Delhi",
    "NCT OF DELHI": "Delhi",
    "GOA": "Goa",
    "GUJARAT": "Gujarat",
    "HARYANA": "Haryana",
    "HIMACHAL PRADESH": "Himachal Pradesh",
    "JAMMU AND KASHMIR": "Jammu & Kashmir",
    "JAMMU & KASHMIR": "Jammu & Kashmir",
    "J&K": "Jammu & Kashmir",
    "JHARKHAND": "Jharkhand",
    "KARNATAKA": "Karnataka",
    "KERALA": "Kerala",
    "LADAKH": "Ladakh",
    "LAKSHADWEEP": "Lakshadweep",
    "MADHYA PRADESH": "Madhya Pradesh",
    "MAHARASHTRA": "Maharashtra",
    "MANIPUR": "Manipur",
    "MEGHALAYA": "Meghalaya",
    "MIZORAM": "Mizoram",
    "NAGALAND": "Nagaland",
    "ODISHA": "Odisha",
    "ORISSA": "Odisha",
    "PUDUCHERRY": "Puducherry",
    "PONDICHERRY": "Puducherry",
    "PUNJAB": "Punjab",
    "RAJASTHAN": "Rajasthan",
    "SIKKIM": "Sikkim",
    "TAMIL NADU": "Tamil Nadu",
    "TAMILNADU": "Tamil Nadu",
    "TELANGANA": "Telangana",
    "TRIPURA": "Tripura",
    "UTTAR PRADESH": "Uttar Pradesh",
    "UTTARAKHAND": "Uttarakhand",
    "UTTARANCHAL": "Uttarakhand",
    "WEST BENGAL": "West Bengal",
}

# Manual overrides: districts that belong to Telangana (post-2014 split)
# but appear as "ANDHRA PRADESH" in the legacy dataset
TELANGANA_DISTRICTS = {
    "Adilabad", "Bhadradri Kothagudem", "Hyderabad", "Jagtial", "Jangaon",
    "Jayashankar Bhupalpally", "Jogulamba Gadwal", "Kamareddy", "Karimnagar",
    "Khammam", "Komaram Bheem Asifabad", "Mahabubabad", "Mahabubnagar",
    "Mancherial", "Medak", "Medchal Malkajgiri", "Mulugu", "Nagarkurnool",
    "Nalgonda", "Narayanpet", "Nirmal", "Nizamabad", "Peddapalli", "Rajanna Sircilla",
    "Rangareddy", "Sangareddy", "Siddipet", "Suryapet", "Vikarabad",
    "Wanaparthy", "Warangal Rural", "Warangal Urban", "Yadadri Bhuvanagiri",
    # Common spellings
    "Rangareddi", "Ranga Reddy",
}

def title_case(s: str) -> str:
    stop = {"of", "and", "&", "the"}
    words = s.strip().split()
    return " ".join(
        w.capitalize() if (i == 0 or w.lower() not in stop) else w.lower()
        for i, w in enumerate(words)
    )

def canonical_state(raw_state: str, district: str) -> str | None:
    key = raw_state.upper().strip()
    state = STATE_MAP.get(key)
    # Fix post-2014 Telangana districts still labelled as Andhra Pradesh
    if state == "Andhra Pradesh" and district in TELANGANA_DISTRICTS:
        state = "Telangana"
    return state

def main() -> None:
    src = Path("/tmp/package/pincodes.json")
    if not src.exists():
        print(f"Source not found: {src}")
        return

    raw = json.loads(src.read_text())
    print(f"Input records: {len(raw):,}")

    # Group by pincode — pick head office (H.O.) first, else first entry
    by_pin: dict[str, list] = defaultdict(list)
    for row in raw:
        pin = str(row.get("pincode", "")).strip().zfill(6)
        if len(pin) != 6 or not pin.isdigit():
            continue
        by_pin[pin].append(row)

    result: dict[str, list[str]] = {}
    skipped_state = Counter()

    for pin, rows in by_pin.items():
        # Prefer Head Office record for the city name
        ho = next((r for r in rows if "H.O" in r.get("officeName", "")), rows[0])
        raw_state = str(ho.get("stateName", "")).strip()
        district = str(ho.get("districtName", "")).strip()
        state = canonical_state(raw_state, district)
        if not state:
            skipped_state[raw_state] += 1
            continue
        city = title_case(district) if district else title_case(
            ho.get("officeName", "").split(" ")[0]
        )
        result[pin] = [city, state]

    print(f"Output entries: {len(result):,}")
    if skipped_state:
        print(f"Skipped (unknown state): {dict(skipped_state.most_common(10))}")

    out = Path(__file__).parent.parent / "assets" / "data" / "in_pincodes.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(dict(sorted(result.items())), f, ensure_ascii=False, separators=(",", ":"))

    print(f"\n✅ Written to {out}  ({out.stat().st_size / 1024:.0f} KB)")
    state_counts = Counter(v[1] for v in result.values())
    print("\nPIN counts by state:")
    for s, c in state_counts.most_common():
        print(f"  {s:<35} {c:>5}")

if __name__ == "__main__":
    main()
