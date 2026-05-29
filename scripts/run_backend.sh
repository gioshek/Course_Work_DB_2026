#!/bin/bash

cd "$(dirname "$0")/../backend" || exit 1

source venv/bin/activate

uvicorn app.main:app --reload --host 127.0.0.1 --port 8000

# ./scripts/run_backend.sh