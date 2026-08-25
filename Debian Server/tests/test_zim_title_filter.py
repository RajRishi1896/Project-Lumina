"""Tests for the junk-title filter in GET /zim/articles (list_zim_articles).

The WHERE clause hides punctuation-led titles ('!', '!!', '! (CONFIG.SYS
directive...)') from the articles listing, but must NOT hide real
non-Latin-script articles. The filter is an inverted first-character
deny-list: ``SUBSTR(TRIM(za.title), 1, 1) NOT GLOB '<ASCII punctuation /
space class>*'`` hides only punctuation- and space-led titles, so digits,
letters, and any script above U+007F (Devanagari, Tamil, Kannada, Telugu,
CJK, accented Latin) count as valid.
An ASCII-only allow-list would return 0 rows for every non-Latin script.
Applied to both COUNT and SELECT so totals stay consistent. /zim/search is
intentionally untouched.
"""
import pytest

from app.async_db import db_exec, db_exec_many

ARCHIVE_ID = "ZIM-test-title-filter"

# Junk: ASCII punctuation, leading-space, underscore all start with a
# deny-list character and are hidden.
JUNK_TITLES = ["!", "!!", "! (CONFIG.SYS directive)", " (Weird Space)", "_underscore"]
# Non-Latin scripts and accented Latin are real articles, not junk:
# Devanagari (hi), Tamil (ta), and É-led French titles must be visible.
NON_ASCII_TITLES = ["भारत", "இந்தியா", "École"]
# Visible: letter-led and digit-led titles survive the GLOB filter
VISIBLE_TITLES = ["India", "Physics", "9th standard maths"] + NON_ASCII_TITLES
ALL_TITLES = VISIBLE_TITLES + JUNK_TITLES


@pytest.fixture(autouse=True)
async def seeded_zim_articles(setup_db):
    """Insert one archive plus fixture articles; reset the count cache."""
    await db_exec(
        "INSERT OR IGNORE INTO zim_archives "
        "(id, filename, title, article_count, language, uploaded_by, file_size, zim_path) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (ARCHIVE_ID, "wikipedia_en_test.zim", "Test Wiki",
         len(ALL_TITLES), "en", "admin", 0, ""),
    )
    await db_exec("DELETE FROM zim_articles WHERE archive_id = ?", (ARCHIVE_ID,))
    await db_exec_many(
        "INSERT INTO zim_articles "
        "(archive_id, article_id, title, path, namespace, has_thumbnail) "
        "VALUES (?, ?, ?, ?, 'A', 0)",
        [(ARCHIVE_ID, f"art-{i}", t, f"A/{i}.html") for i, t in enumerate(ALL_TITLES)],
    )
    # list_zim_articles caches COUNT per key for 60s: force fresh totals
    import zim_handler
    zim_handler._article_count_cache.clear()
    zim_handler._article_count_ts.clear()
    yield


@pytest.mark.asyncio
async def test_articles_list_filters_junk_titles(client):
    """Punctuation/space/underscore-led titles absent; alphanumeric-led present."""
    resp = await client.get("/zim/articles", params={"limit": 500})
    assert resp.status_code == 200
    body = resp.json()
    titles = [a["title"] for a in body["articles"]]
    for junk in JUNK_TITLES:
        assert junk not in titles, f"Junk title leaked into listing: {junk!r}"
    for good in VISIBLE_TITLES:
        assert good in titles, f"Visible title missing from listing: {good!r}"
    assert body["total"] == len(VISIBLE_TITLES)


@pytest.mark.asyncio
async def test_non_ascii_script_titles_are_included(client):
    """Devanagari/Tamil/accented-Latin titles are real articles, not junk.

    A Hindi or Tamil Wikipedia ZIM must show its articles: the ASCII GLOB
    alone would return 0 rows for every non-Latin script.
    """
    resp = await client.get("/zim/articles", params={"limit": 500})
    assert resp.status_code == 200
    titles = [a["title"] for a in resp.json()["articles"]]
    for title in NON_ASCII_TITLES:
        assert title in titles, f"Non-ASCII title wrongly filtered out: {title!r}"
    for junk in JUNK_TITLES:
        assert junk not in titles, f"ASCII junk title still visible: {junk!r}"


@pytest.mark.asyncio
async def test_articles_total_and_has_more_reflect_visible_rows(client):
    """Pagination totals count only visible rows, on every page."""
    page1 = (await client.get("/zim/articles", params={"limit": 2})).json()
    assert page1["total"] == len(VISIBLE_TITLES)
    assert len(page1["articles"]) == 2
    assert page1["has_more"] is True

    last_page = (await client.get(
        "/zim/articles", params={"offset": len(VISIBLE_TITLES) - 2, "limit": 2})).json()
    assert len(last_page["articles"]) == 2
    assert last_page["has_more"] is False

    everything = (await client.get("/zim/articles", params={"limit": 500})).json()
    assert sorted(a["title"] for a in everything["articles"]) == sorted(VISIBLE_TITLES)
