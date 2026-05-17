import socket
from zeroconf import IPVersion, ServiceInfo, Zeroconf
import logging

class MeshBeacon:
    def __init__(self, port=8000):
        self.port = port
        self.zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
        self.service_name = "EduMeshHub._http._tcp.local."
        self.host_ip = self._get_ip()
        
    def _get_ip(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            # doesn't even have to be reachable
            s.connect(('10.255.255.255', 1))
            IP = s.getsockname()[0]
        except Exception:
            IP = '127.0.0.1'
        finally:
            s.close()
        return IP

    def start(self):
        info = ServiceInfo(
            "_http._tcp.local.",
            self.service_name,
            addresses=[socket.inet_aton(self.host_ip)],
            port=self.port,
            properties={'version': '1.0', 'hub_id': 'LUMINA_HUB_01'},
            server="lumina-hub.local.",
        )
        print(f"📡 Broadcasting Mesh Beacon at {self.host_ip}:{self.port}...")
        self.zeroconf.register_service(info)

    def stop(self):
        self.zeroconf.unregister_all_services()
        self.zeroconf.close()
