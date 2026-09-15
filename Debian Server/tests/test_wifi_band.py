"""WiFi band endpoint tests: parsing, support validation, no-op switching."""
import app.routers.system_stats as ws


def test_parse_nm_band():
    """nmcli terse output parses to a band code or empty when unknown."""
    assert ws._parse_nm_band("802-11-wireless.band:a") == "a"
    assert ws._parse_nm_band("802-11-wireless.band:bg") == "bg"
    assert ws._parse_nm_band("a") == "a"
    assert ws._parse_nm_band("") == ""
    assert ws._parse_nm_band("whatever") == ""


async def test_rejects_unsupported_band(admin_client, monkeypatch):
    """Requesting a band the adapter lacks is a 400 naming support."""
    monkeypatch.setattr(ws, "_wifi_caps", ["bg"])
    r = await admin_client.post("/system/wifi-band", json={"band": "a"})
    assert r.status_code == 400
    assert "support" in r.json()["detail"].lower()


async def test_same_band_no_reboot(admin_client, monkeypatch):
    """Re-requesting the live band succeeds without scheduling a reboot."""
    monkeypatch.setattr(ws, "_wifi_caps", ["a", "bg"])

    async def fake_band():
        return "a"

    monkeypatch.setattr(ws, "_read_nm_band", fake_band)
    r = await admin_client.post("/system/wifi-band", json={"band": "a"})
    assert r.status_code == 200
    assert r.json()["reboot"] is False


async def test_invalid_band(admin_client):
    """Anything outside a/bg is a 400."""
    r = await admin_client.post("/system/wifi-band", json={"band": "5ghz"})
    assert r.status_code == 400


async def test_get_shape(admin_client, monkeypatch):
    """GET reports band, label, and capabilities."""
    monkeypatch.setattr(ws, "_wifi_caps", ["a", "bg"])

    async def fake_band():
        return "bg"

    monkeypatch.setattr(ws, "_read_nm_band", fake_band)
    r = await admin_client.get("/system/wifi-band")
    assert r.json() == {"band": "bg", "label": "2.4 GHz", "supported": ["a", "bg"]}
