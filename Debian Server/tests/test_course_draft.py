"""Regression: Save Draft must unpublish a published course via PUT."""
import pytest


@pytest.mark.asyncio
async def test_put_status_draft_unpublishes(admin_client):
    """PUT with status='draft' flips published 1 -> 0; 'published' flips back."""
    r = await admin_client.post("/api/teacher/courses", json={
        "title": "Draft Test", "subject": "General", "grade": 5, "language": "en"})
    assert r.status_code == 200, r.text
    cid = r.json()["id"]

    # Publish via toggle, then Save Draft must revert it
    r = await admin_client.post(f"/api/teacher/courses/{cid}/publish")
    assert r.is_success and r.json()["published"] == 1

    r = await admin_client.put(f"/api/teacher/courses/{cid}", json={
        "title": "Draft Test", "subject": "General", "grade": 5,
        "language": "en", "status": "draft"})
    assert r.is_success and r.json()["published"] == 0

    # Re-publish explicitly through the same metadata save path
    r = await admin_client.put(f"/api/teacher/courses/{cid}", json={
        "title": "Draft Test", "subject": "General", "grade": 5,
        "language": "en", "status": "published"})
    assert r.is_success and r.json()["published"] == 1

    # No status field -> publish state untouched
    r = await admin_client.put(f"/api/teacher/courses/{cid}", json={
        "title": "Renamed", "subject": "General", "grade": 5, "language": "en"})
    assert r.is_success and r.json()["published"] == 1 and r.json()["title"] == "Renamed"
