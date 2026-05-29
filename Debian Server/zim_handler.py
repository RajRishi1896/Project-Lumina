import os
from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from typing import List, Dict

router = APIRouter()

# Directory where ZIM article HTML files are stored (server side)
ZIM_PAGES_DIR = os.path.join(os.path.dirname(__file__), "zim_pages")
os.makedirs(ZIM_PAGES_DIR, exist_ok=True)

@router.get("/zim/search")
def search_zim(query: str) -> List[Dict[str, str]]:
    """Search ZIM articles by title substring.
    Returns a list of objects with 'id' and 'title'.
    """
    results: List[Dict[str, str]] = []
    if not query:
        return results
    # Simple filename based search; assume files are named "<id>__<title>.html"
    for fname in os.listdir(ZIM_PAGES_DIR):
        if fname.endswith('.html'):
            parts = fname.rsplit('__', 1)
            if len(parts) == 2:
                article_id, title_part = parts
                title = title_part.rsplit('.html', 1)[0]
                if query.lower() in title.lower():
                    results.append({"id": article_id, "title": title})
    return results

@router.get("/zim/page")
def get_zim_page(article_id: str):
    """Return the HTML content of a ZIM article as JSON.
    The server looks for a file named "<id>__*.html" and returns its HTML string.
    """
    for fname in os.listdir(ZIM_PAGES_DIR):
        if fname.startswith(f"{article_id}__") and fname.endswith('.html'):
            file_path = os.path.join(ZIM_PAGES_DIR, fname)
            if os.path.exists(file_path):
                with open(file_path, 'r', encoding='utf-8') as f:
                    html_content = f.read()
                return JSONResponse(content={'id': article_id, 'html': html_content})
    raise HTTPException(status_code=404, detail='Article not found')
