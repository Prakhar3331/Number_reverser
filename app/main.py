import time
from typing import Union
from fastapi import FastAPI, HTTPException, Query, Request, status
from fastapi.responses import Response
from pydantic import BaseModel, Field
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

INT64_MIN = -(2**63)
INT64_MAX = 2**63 - 1

app = FastAPI(
    title="Number Reverser API",
    description="A simple, secure microservice to reverse numbers with full edge-case handling.",
    version="1.0.0",
)

# Prometheus Metrics
REQUESTS_TOTAL = Counter("http_requests_total", "Total HTTP requests", ["endpoint", "status"])
REQUEST_DURATION = Histogram("http_request_duration_seconds", "HTTP request latency", ["endpoint"])


# Models
class ReverseRequest(BaseModel):
    number: Union[int, str] = Field(
        ...,
        description="The integer or numeric string to be reversed",
        examples=[12345, -987, "1200"],
    )


class ReverseResponse(BaseModel):
    original_input: Union[int, str]
    reversed_number: int
    reversed_string: str
    is_negative: bool
    dropped_leading_zeros: int
    execution_time_ms: float


class HealthResponse(BaseModel):
    status: str
    version: str = "1.0.0"


# Core Business Logic
def reverse_number(input_val: Union[int, str]) -> ReverseResponse:
    start_time = time.perf_counter()

    if input_val is None or isinstance(input_val, bool):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Invalid input: Input must be a valid integer or numeric string.",
        )

    raw_str = str(input_val).strip()
    if not raw_str:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Invalid input: Input string cannot be empty.",
        )

    if "." in raw_str:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Floating point / decimal numbers ('{raw_str}') are not supported.",
        )

    is_negative = False
    digits = raw_str

    if digits.startswith("-"):
        is_negative = True
        digits = digits[1:]
    elif digits.startswith("+"):
        digits = digits[1:]

    if not digits or not digits.isdigit():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Input '{input_val}' contains non-numeric characters.",
        )

    original_int = -int(digits) if is_negative else int(digits)

    # Check 64-bit integer overflow on input
    if original_int < INT64_MIN or original_int > INT64_MAX:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Input value {original_int} exceeds 64-bit signed integer bounds.",
        )

    # Perform reversal
    rev_digits = digits[::-1]
    rev_int = -int(rev_digits) if is_negative else int(rev_digits)
    rev_str = f"-{rev_digits}" if is_negative else rev_digits

    # Check 64-bit integer overflow on reversed result
    if rev_int < INT64_MIN or rev_int > INT64_MAX:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Reversed value {rev_int} exceeds 64-bit signed integer bounds.",
        )

    dropped_zeros = max(0, len(rev_digits) - len(str(abs(rev_int))))
    elapsed_ms = round((time.perf_counter() - start_time) * 1000.0, 4)

    return ReverseResponse(
        original_input=input_val,
        reversed_number=rev_int,
        reversed_string=rev_str,
        is_negative=is_negative,
        dropped_leading_zeros=dropped_zeros,
        execution_time_ms=elapsed_ms,
    )


# Security Headers Middleware
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response: Response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    return response


# Endpoints
@app.post("/api/v1/reverse", response_model=ReverseResponse)
def reverse_post(payload: ReverseRequest):
    with REQUEST_DURATION.labels(endpoint="/api/v1/reverse").time():
        result = reverse_number(payload.number)
        REQUESTS_TOTAL.labels(endpoint="/api/v1/reverse", status="200").inc()
        return result


@app.get("/api/v1/reverse", response_model=ReverseResponse)
def reverse_get(number: str = Query(..., description="Number to reverse")):
    with REQUEST_DURATION.labels(endpoint="/api/v1/reverse").time():
        result = reverse_number(number)
        REQUESTS_TOTAL.labels(endpoint="/api/v1/reverse", status="200").inc()
        return result


@app.get("/healthz", response_model=HealthResponse)
def liveness():
    return HealthResponse(status="healthy")


@app.get("/ready", response_model=HealthResponse)
def readiness():
    return HealthResponse(status="healthy")


@app.get("/metrics")
def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/")
def root():
    return {"service": "number-reverser-api", "status": "online", "docs": "/docs"}
