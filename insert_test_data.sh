#!/bin/bash
set -euo pipefail

if [ -z "${1-}" ]; then
    echo "Usage: $0 <sql_file>" >&2
    echo "Error: Please provide the path to the .sql file to import." >&2
    exit 1
fi

. .env
podman exec -i reportdb psql reportdb -U "$REPORT_DB_USER" -h localhost -f "/test/$1"
