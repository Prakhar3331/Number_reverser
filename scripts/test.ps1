$ErrorActionPreference = "Stop"
Write-Host "=== Running Tests & Quality Checks ===" -ForegroundColor Cyan
flake8 app/ --max-line-length=100
bandit -r app/ -ll -ii
pytest -v --cov=app --cov-fail-under=90
Write-Host "All tests and quality checks passed!" -ForegroundColor Green
