#!/usr/bin/env bash
# Runs the SQL test-suite against a throwaway local Postgres (not a real Supabase project).
# Usage: PGHOST=/tmp PGPORT=54329 PGUSER=postgres supabase/tests/run.sh
set -euo pipefail
cd "$(dirname "$0")"
DB=folio_test_$$
psql -qd postgres -c "create database $DB" >/dev/null
trap 'psql -qd postgres -c "drop database $DB" >/dev/null' EXIT
export PGDATABASE=$DB
psql -q -v ON_ERROR_STOP=1 -f 00_stub_auth.sql
for m in ../migrations/*.sql; do psql -q -v ON_ERROR_STOP=1 -f "$m"; done
psql -q -v ON_ERROR_STOP=1 -f 10_sync_core.sql
psql -q -v ON_ERROR_STOP=1 -f 20_cloud_books.sql
psql -q -v ON_ERROR_STOP=1 -f 30_sync_more_tables.sql
