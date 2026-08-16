#!/bin/bash
# Purpose: Prints the Lumina Hub connection banner + QR code to the laptop console.
# Usage:   Called by lumina-banner.service on boot.
# Args:    None
IP=$(ip -4 addr show scope global | grep inet | head -1 | cut -d/ -f1 | awk '{print $2}')
[ -z "$IP" ] && IP=10.42.0.1

echo ""
echo "============================================================"
echo "   LUMINA HUB"
echo "============================================================"
echo ""
echo "   Server:    http://$IP:8000"
echo "   Hotspot:   Lumina Hub"
echo "   Password:  lumina2026"
echo ""
echo "   Scan QR to connect to WiFi:"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/venv/bin/python" -c "
import qrcode
qr = qrcode.QRCode(box_size=1, border=1)
qr.add_data('WIFI:T:WPA;S:Lumina Hub;P:lumina2026;;')
qr.make(fit=True)
for row in qr.get_matrix():
    print('    ' + ''.join('\u2588\u2588' if c else '  ' for c in row))
"

echo ""
echo "   Then open in browser:"
echo "   http://$IP:8000"
echo ""
echo "============================================================"
echo ""
