import urllib.request, json

# Test page endpoint for India article (article_id = 7D31E0DA from search)
try:
    r = urllib.request.urlopen("http://localhost:8000/zim/page?article_id=7D31E0DA")
    data = json.loads(r.read().decode())
    html = data.get('html', '')
    print(f"Page endpoint: {r.status}, html length: {len(html)}")
    if html:
        print(f"First 200 chars: {html[:200]}")
    else:
        print("ERROR: empty html!")
except Exception as e:
    print(f"Page endpoint error: {e}")
    if hasattr(e, 'read'):
        print(e.read().decode()[:300])
