import uvicorn

if __name__ == "__main__":
    print("[INFO] Starting EduMesh Hub...")
    uvicorn.run("app.api:app", host="0.0.0.0", port=8000, reload=False)
