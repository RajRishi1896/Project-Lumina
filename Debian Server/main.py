import uvicorn
import threading
import sys
from app.api import app
from app.discovery import MeshBeacon

def start_beacon():
    beacon = MeshBeacon(port=8000)
    try:
        beacon.start()
        # Keep the beacon thread alive
        import time
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        beacon.stop()

if __name__ == "__main__":
    print("🚀 Starting EduMesh Hub...")
    
    # Start the Discovery Beacon in a background thread
    beacon_thread = threading.Thread(target=start_beacon, daemon=True)
    beacon_thread.start()
    
    # Start the FastAPI Server
    uvicorn.run(app, host="0.0.0.0", port=8000)
