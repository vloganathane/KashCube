#!/usr/bin/env python3
import urllib.request

urls = [
    'https://raw.githubusercontent.com/geetaristo/pincode-india/main/pincode_data.json',
    'https://raw.githubusercontent.com/AshisMaharana/pincode-india/master/pincode.json',
    'https://raw.githubusercontent.com/ramnes/india-pincode/master/pincodes.json',
    'https://raw.githubusercontent.com/tanandia/pincodes-india/master/pincodes.json',
    'https://raw.githubusercontent.com/geoandcode/india-pincode-json/master/india-pincode.json',
    'https://raw.githubusercontent.com/India-pincode/india-pincode/master/pincode.json',
    'https://raw.githubusercontent.com/kalyankumar-m/pincodes-india/master/pincodes.json',
    'https://raw.githubusercontent.com/nshntarora/Indian-Cities-JSON/master/cities.json',
    'https://raw.githubusercontent.com/nichenametla/pincode-india/main/pincodes.json',
    'https://raw.githubusercontent.com/vinitshahdeo/India-PinCode-API/master/src/data/all_india_pin_code.json',
]
for url in urls:
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'KashCube'})
        with urllib.request.urlopen(req, timeout=8) as r:
            data = r.read(300)
            print(f"OK: {url}")
            print(f"  {data[:200]}")
    except Exception as e:
        print(f"FAIL: {url} -> {type(e).__name__}: {e}")
