#!/usr/bin/env bash
set -e
echo "Starting Number Reverser locally on http://localhost:8000..."
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
