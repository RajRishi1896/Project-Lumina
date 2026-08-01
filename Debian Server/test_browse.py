import urllib.request, json
r = urllib.request.urlopen("http://localhost:8000/zim/articles?limit=3", timeout=10)
d = json.loads(r.read())
print("total:", d["total"])
print("articles:", len(d["articles"]))
print("first:", d["articles"][0]["title"] if d["articles"] else "none")
