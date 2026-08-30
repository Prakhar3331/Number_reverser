#!/usr/bin/env bash
set -e
echo "=== Running Tests & Quality Checks ==="
flake8 app/ --max-line-length=100
bandit -r app/ -ll -ii
pytest -v --cov=app --cov-fail-under=90
echo "All tests and quality checks passed!"
