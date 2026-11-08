from fastapi import FastAPI

app = FastAPI(title="Private Backend API")


@app.get("/")
def read_root():
    return {
        "message": "Hello from the private backend API.",
        "service": "backend-api",
    }


@app.get("/health")
def health_check():
    return {"status": "ok"}
