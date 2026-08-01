import urllib.request, json
r = urllib.request.urlopen('http://localhost:8000/zim/search?query=India&limit=5')
data = json.loads(r.read())
for i, a in enumerate(data['articles']):
    print(f"{i+1}. {a['title']}")
