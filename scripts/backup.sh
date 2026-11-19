#!/bin/sh
set -eu
DIR=${1:-./backups}
KEEP_DAYS=${KEEP_DAYS:-7}
mkdir -p "$DIR"
STAMP=$(date +%Y%m%d-%H%M%S)
docker compose ${COMPOSE_ENV:+--env-file "$COMPOSE_ENV"} exec -T postgres pg_dump -U musiccloud musiccloud | gzip > "$DIR/db-$STAMP.sql.gz"
LIBRARY=${MC_LIBRARY_PATH:-./library}
tar -czf "$DIR/library-$STAMP.tar.gz" -C "$LIBRARY" .
find "$DIR" -type f -mtime +"$KEEP_DAYS" -delete
echo "backup written to $DIR"
