#!/usr/bin/env python3
"""Probe additional pincode data sources."""
import urllib.request

urls = [
    # datameet repo (try various paths)
    'https://api.github.com/repos/datameet/india-post/contents/',
    'https://api.github.com/repos/datameet/india-post/contents/data',
    # Aniket repo
    'https://api.github.com/repos/Aniket965/india-pincodes/contents/',
    # vinitshahdeo
    'https://api.github.com/repos/vinitshahdeo/India-PinCode-API/contents/src/data',
    # deepanshu
    'https://api.github.com/repos/deepanshu-rawat6/PinCode-API/contents/',
    # codelink
    'https://api.github.com/repos/mauliksavalia/pincode-india/contents/',
]
for url in urls:
    try:
        req = urllib.request.Request(url, headers={
            'User-Agent': 'KashCube',
            'Accept': 'application/vnd.github.v3+json',
        })
        with urllib.request.urlopen(req, timeout=8) as r:
            import json
            items = json.loads(r.read())
            if isinstance(items, list):
                names = [i['name'] for i in items[:10]]
                print(f"OK: {url}")
                print(f"  Files: {names}")
            else:
                print(f"OK: {url}")
                print(f"  {str(items)[:200]}")
    except Exception as e:
        print(f"FAIL: {url} -> {e}")
