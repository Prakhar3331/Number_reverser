# Stage 1: Build virtual environment
FROM python:3.11-slim AS builder

WORKDIR /build
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt

# Stage 2: Minimal non-root runtime
FROM python:3.11-slim AS runtime

RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Create dedicated non-root user
RUN groupadd -g 10001 appuser && \
    useradd -u 10001 -g 10001 -s /sbin/nologin -M -d /app appuser

WORKDIR /app
COPY --from=builder --chown=10001:10001 /opt/venv /opt/venv
COPY --chown=10001:10001 app/ /app/app

USER 10001:10001
EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
