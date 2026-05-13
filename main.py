import os
import logging
from contextlib import asynccontextmanager
from dotenv import load_dotenv

load_dotenv()  # must be before all app imports

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from mangum import Mangum

from apps.prescriptions.router import router as prescriptions_router

# ── Logging ───────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
)
logger = logging.getLogger(__name__)

# ── Lifespan (startup / shutdown hooks) ──────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup
    logger.info("MEDMATE API starting up")
    yield
    # shutdown
    logger.info("MEDMATE API shutting down")
    # close persistent httpx client cleanly
    from apps.auth.dependencies import _get_http_client
    client = _get_http_client()
    if not client.is_closed:
        await client.aclose()
    logger.info("HTTP client closed")

# ── App ───────────────────────────────────────────────────────────────────────


_ENV = os.environ.get("ENV", "development")

app = FastAPI(
    title       = "MEDMATE API",
    version     = "2.0.0",
    description = "AI-powered prescription analysis for Indian handwritten prescriptions",
    lifespan    = lifespan,
    # disable docs in production Lambda
    docs_url    = "/docs"    if _ENV != "production" else None,
    redoc_url   = "/redoc"   if _ENV != "production" else None,
    openapi_url = "/openapi.json" if _ENV != "production" else None,
)

# ── CORS ──────────────────────────────────────────────────────────────────────

# allow_origins=["*"] + allow_credentials=True is a CORS spec violation
# use explicit origin list instead
_ALLOWED_ORIGINS = (
    os.environ.get("ALLOWED_ORIGINS", "").split(",")
    if os.environ.get("ALLOWED_ORIGINS")
    else ["*"]  # open during local development only
)

app.add_middleware(
    CORSMiddleware,
    allow_origins     = _ALLOWED_ORIGINS,
    allow_credentials = len(_ALLOWED_ORIGINS) > 1 or _ALLOWED_ORIGINS[0] != "*",
    allow_methods     = ["GET", "POST", "DELETE"],
    allow_headers     = ["Authorization", "Content-Type"],
)

# ── Global exception handler ──────────────────────────────────────────────────

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception on {request.method} {request.url.path}: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error — please try again"},
    )

# ── Routers ───────────────────────────────────────────────────────────────────

app.include_router(prescriptions_router)

# ── Health check ──────────────────────────────────────────────────────────────

@app.get("/health", tags=["system"])
async def health():
    return {
        "status"  : "ok",
        "version" : "2.0.0",
        "env"     : _ENV,
        "services": {
            "groq_vision": "meta-llama/llama-4-scout-17b-16e-instruct",
            "groq_llm"   : "llama-3.3-70b-versatile",
            "textract"   : "pending-aws-activation",
            "database"   : "supabase-postgresql",
            "storage"    : "aws-s3-ap-south-2",
        },
    }

# ── Lambda handler ────────────────────────────────────────────────────────────

handler = Mangum(app, lifespan="off")  # lifespan="off" recommended for Lambda

# ── Local dev ─────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)