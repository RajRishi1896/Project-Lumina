import urllib.request, json
try:
    r = urllib.request.urlopen('http://localhost:8000/zim/articles?limit=2&offset=0', timeout=10)
    d = json.loads(r.read())
    print('total:', d.get('total'))
    print('num_articles:', len(d.get('articles', [])))
    for a in d.get('articles', []):
        print('  -', a.get('title'), '|', a.get('article_id'))
except Exception as e:
    print('ERROR:', e)
