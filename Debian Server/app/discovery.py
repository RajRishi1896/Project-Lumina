"""mDNS / Zeroconf service beacon for the Lumina EduMesh Hub.

Broadcasts the hub as '_http._tcp' on the local network so that
EduMesh Android clients can discover the server automatically without
manual IP or DNS configuration.
"""

import socket
from zeroconf import IPVersion, ServiceInfo, Zeroconf
import logging


class MeshBeacon:
    """mDNS beacon that advertises the EduMesh Hub on the LAN.

    Registers an ``_http._tcp`` service record so that Zeroconf-capable
    clients (e.g. the EduMesh Android app) can locate the server by
    service type rather than by hardcoded IP.
    """

    def __init__(self, port: int = 8000):
        """Initialise the beacon with a given service port.

        Args:
            port: The TCP port the FastAPI server listens on.
        """
        self.port = port
        self.zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
        self.service_name = "EduMeshHub._http._tcp.local."
        self.host_ip = self._get_ip()

    def _get_ip(self) -> str:
        """Detect the primary non-loopback IPv4 address.

        Opens a dummy UDP socket to a non-routable address to trick the
        OS into revealing the interface address that would be used for
        outbound traffic.

        Returns:
            The detected IP string, or ``'127.0.0.1'`` on failure.
        """
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(('10.255.255.255', 1))
            IP = s.getsockname()[0]
        except Exception:
            IP = '127.0.0.1'
        finally:
            s.close()
        return IP

    def start(self):
        """Register the mDNS service so clients can discover the hub."""
        info = ServiceInfo(
            "_http._tcp.local.",
            self.service_name,
            addresses=[socket.inet_aton(self.host_ip)],
            port=self.port,
            properties={'version': '1.0'},
            server="lumina-hub.local.",
        )
        logging.info(f"Broadcasting Mesh Beacon at {self.host_ip}:{self.port}...")
        try:
            self.zeroconf.register_service(info)
        except Exception as e:
            logging.error(f"Beacon registration failed: {e}")

    def stop(self):
        """Unregister all mDNS services and shut down the Zeroconf instance."""
        self.zeroconf.unregister_all_services()
        self.zeroconf.close()
