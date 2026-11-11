#!/bin/sh
set -eu

COMPOSE_FILE="${COMPOSE_FILE:-compose.yml}"
ENV_FILE="${ENV_FILE:-.env}"
SAMPLES="${SAMPLES:-3}"
INTERVAL="${INTERVAL:-5}"

if [ ! -f "$ENV_FILE" ]; then
    echo "missing $ENV_FILE" >&2
    exit 1
fi

ids=$(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps -q)
if [ -z "$ids" ]; then
    echo "no running containers for $COMPOSE_FILE" >&2
    exit 1
fi

echo "| Контейнер | CPU | Память | Mem % | Сеть | Диск |"
echo "| --- | ---: | ---: | ---: | ---: | ---: |"

i=1
while [ "$i" -le "$SAMPLES" ]; do
    docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}|{{.BlockIO}}' $ids \
        | sort \
        | awk -F'|' '{ printf "| %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6 }'
    i=$((i + 1))
    if [ "$i" -le "$SAMPLES" ]; then
        sleep "$INTERVAL"
    fi
done
