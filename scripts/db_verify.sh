#!/usr/bin/env bash
# db_verify.sh — thin wrapper so `scripts/db_verify.sh` works out of the box.
# It needs an embedded PostgreSQL (pip package `pgserver`) + psycopg2.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PY="${PYTHON_VENV:-/tmp/pgenv}/bin/python"
if [ ! -x "$PY" ] || ! "$PY" -c 'import pgserver, psycopg2' >/dev/null 2>&1; then
  echo "setting up the verification venv in ${PYTHON_VENV:-/tmp/pgenv} (one-off, ~15s) ..."
  python3 -m venv "${PYTHON_VENV:-/tmp/pgenv}" >/dev/null
  "${PY}" -m pip install --quiet --disable-pip-version-check pgserver psycopg2-binary
fi
export PATH="$("$PY" -c 'import pgserver,os;print(os.path.join(os.path.dirname(pgserver.__file__),"pginstall","bin"))'):$PATH"
exec "$PY" "$HERE/db_verify.py" "$@"
