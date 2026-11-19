#!/bin/sh
set -eu

TAG="${MC_TAG:-v0.5.0}"
PREFIX="${MC_IMAGE_PREFIX:-ghcr.io/moshms}"
OUT="${1:-music-cloud-bundle}"

images="$PREFIX/api:$TAG $PREFIX/worker:$TAG $PREFIX/transcoder:$TAG $PREFIX/web:$TAG postgres:17-alpine"

if [ "${INCLUDE_MONITORING:-0}" = "1" ]; then
    images="$images prom/prometheus:latest grafana/grafana:latest prometheuscommunity/postgres-exporter:latest"
fi
if [ "${INCLUDE_TLS:-0}" = "1" ]; then
    images="$images certbot/certbot:latest"
fi
if [ "${INCLUDE_HOME:-0}" = "1" ]; then
    images="$images cloudflare/cloudflared:latest"
fi

mkdir -p "$OUT"
cp compose.yml .env.example README.md "$OUT"/
cp -a monitoring "$OUT"/

if [ "${SKIP_PULL:-0}" != "1" ]; then
    for image in $images; do
        docker pull "$image"
    done
fi

docker save -o "$OUT/music-cloud-images.tar" $images

echo "Bundle ready: $OUT"
echo "Copy it to the server, then run:"
echo "  cd $OUT"
echo "  docker load -i music-cloud-images.tar"
echo "  cp .env.example .env"
echo "  docker compose -f compose.yml --env-file .env up -d"
