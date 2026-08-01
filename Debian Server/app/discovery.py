"""mDNS (Zeroconf) service registration for the Lumina EduMesh Hub.

Registers ``EduMeshHub._http._tcp.local.`` on the local network so the
Flutter app can auto-discover the hub on any WiFi that carries one.
Discovery is optional: if the ``zeroconf`` package is not installed the
hub still starts and serves normally, just without the mDNS advertisement.
"""

import asyncio
import logging
import socket

logger = logging.getLogger("lumina.discovery")

# Ports 5353/udp (mDNS) must be open in UFW -- already allowed by setup_hub.sh.
_SERVICE_TYPE = "_http._tcp.local."
_INSTANCE_NAME = "EduMeshHub"
_SERVICE_PORT = 8000


class HubDiscovery:
    """Registers and unregisters the hub's mDNS service entry.

    Wraps the blocking ``zeroconf`` package in a thread so the event loop
    stays free. Holds the [Zeroconf] instance to allow clean shutdown.
    """

    def __init__(self) -> None:
        self._zc = None

    @staticmethod
    def _own_ipv4() -> str:
        """Return the first non-loopback IPv4 address of this host.

        Prefers the hotspot interface because it is the address students
        actually reach; any non-loopback address is acceptable for mDNS.
        """
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                return ip
        return "127.0.0.1"

    async def start(self) -> None:
        """Register the service; log a warning and continue if missing.

        Requires the optional ``zeroconf`` package. Never raises -- a
        failed advertisement must not take the hub down.
        """
        try:
            from zeroconf import ServiceInfo, Zeroconf
        except ImportError:
            logger.warning(
                "zeroconf not installed -- mDNS discovery disabled "
                "(pip install zeroconf to enable)"
            )
            return
        ip = self._own_ipv4()
        info = ServiceInfo(
            _SERVICE_TYPE,
            f"{_INSTANCE_NAME}.{_SERVICE_TYPE}",
            addresses=[socket.inet_aton(ip)],
            port=_SERVICE_PORT,
            properties={"version": "1"},
        )
        zc = Zeroconf()
        try:
            await asyncio.to_thread(zc.register_service, info)
        except Exception:
            logger.exception("mDNS registration failed")
            await asyncio.to_thread(zc.close)
            return
        self._zc = zc
        logger.info("mDNS registered: %s -> %s:%d", info.name, ip, _SERVICE_PORT)

    async def stop(self) -> None:
        """Unregister the service and close the Zeroconf instance."""
        zc = self._zc
        self._zc = None
        if zc is None:
            return
        try:
            await asyncio.to_thread(zc.close)
        except Exception:
            logger.exception("mDNS shutdown failed")
