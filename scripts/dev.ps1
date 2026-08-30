$ErrorActionPreference = "Stop"
Write-Host "Starting Number Reverser locally on http://localhost:8000..." -ForegroundColor Cyan
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
