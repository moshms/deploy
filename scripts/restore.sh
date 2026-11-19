#!/bin/sh
set -eu
DB_FILE=${1:?usage: restore.sh <db.sql.gz> [library.tar.gz]}
LIB_FILE=${2:-}
gunzip -c "$DB_FILE" | docker compose exec -T postgres psql -U musiccloud musiccloud
if [ -n "$LIB_FILE" ]; then
  LIBRARY=${MC_LIBRARY_PATH:-./library}
  mkdir -p "$LIBRARY"
  tar -xzf "$LIB_FILE" -C "$LIBRARY"
fi
echo "restore complete"
