# Music Cloud

Один музыкальный сервер на Rust вместо набора Navidrome + Copyparty + Tagr + beets: веб-плеер, Subsonic API, загрузка, автоимпорт, редактор тегов, S3 и опциональный транскодер.

## Что внутри

- `mc-api` — HTTP API, Subsonic `/rest`, загрузки `/tus`, стриминг, авторизация.
- `mc-worker` — автоскан, inotify, импорт загрузок по шаблону пути, запись тегов и обложек.
- `mc-transcoder` — gRPC-транскодер на ffmpeg с дисковым кэшем.
- `nginx` — TLS, статика веб-клиента и отдача файлов через `X-Accel-Redirect`.
- `PostgreSQL` — каталог, пользователи, задания и аудит.
- `Prometheus` + `Grafana` — опциональный мониторинг.

## Требования

- Linux-сервер с Docker и Compose plugin.
- Домен, A-запись которого указывает на сервер (для TLS).
- Открытые порты 80 и 443, SSH.
- Для S3 — S3-совместимое хранилище и `MC_MASTER_KEY`.

## Быстрый старт (ядро)

```bash
git clone https://github.com/moshms/deploy.git
cd deploy
cp .env.example .env
```

Заполните как минимум:

```dotenv
POSTGRES_PASSWORD=...
MC_ADMIN_USER=admin
MC_ADMIN_PASSWORD=...
MC_LIBRARY_PATH=/srv/music-cloud/library
MC_UID=65534
MC_GID=65534
```

Создайте библиотеку и выдайте права пользователю контейнера:

```bash
sudo mkdir -p /srv/music-cloud/library
sudo chown -R 65534:65534 /srv/music-cloud/library
```

Запуск:

```bash
docker compose -f compose.yml --env-file .env pull
docker compose -f compose.yml --env-file .env up -d
```

Откройте `http://SERVER_IP/`. Если администратор ещё не создан, веб-клиент покажет экран первого запуска. Логин и пароль из `.env` создаются автоматически при пустой базе.

## Профили

```bash
# только ядро: nginx, postgres, mc-api
docker compose -f compose.yml --env-file .env up -d

# + worker: автоскан, импорт, редактор тегов
docker compose -f compose.yml --env-file .env --profile worker up -d

# + транскодер
docker compose -f compose.yml --env-file .env --profile worker --profile transcode up -d

# + мониторинг
MC_METRICS=true docker compose -f compose.yml --env-file .env --profile monitoring up -d
```

Профиль можно задать в `.env`:

```dotenv
COMPOSE_PROFILES=worker,transcode,monitoring
MC_METRICS=true
```

## S3 и несколько библиотек

1. Сгенерируйте мастер-ключ и положите его в `.env`:

```bash
openssl rand -hex 32
```

```dotenv
MC_MASTER_KEY=<ключ>
```

2. Войдите как администратор и откройте «Админка → Хранилища».
3. Добавьте S3-хранилище: endpoint, region, bucket, access key, secret key, root prefix.
4. Создайте библиотеку, выбрав это хранилище.
5. Запустите скан.

Секреты S3 шифруются XChaCha20-Poly1305 и в API не возвращаются.

## Загрузка, импорт и теги

- Страница `/upload` доступна администратору и роли `uploader`.
- Файлы загружаются по tus с докачкой (`/tus`).
- Без worker файл остаётся в `uploads/<user>/...` и сразу индексируется.
- С worker задание импорта раскладывает файл по шаблону:

```dotenv
MC_IMPORT_PATH_TEMPLATE={albumartist}/{year} - {album}/{disc}-{track} {title}.{ext}
```

- Редактор тегов и обложек находится в «Админка → Редактор тегов» и работает только при запущенном worker. Правки пишутся в файлы фоновым заданием, затем библиотека пересканируется.
- Файлы библиотеки должны быть доступны на запись пользователю `MC_UID` (по умолчанию 65534).

## TLS через certbot

1. Укажите домен и email в `.env`:

```dotenv
MC_DOMAIN=music.example.com
MC_EMAIL=admin@example.com
MC_TLS=off
```

2. Поднимите nginx в HTTP-режиме и получите сертификат:

```bash
docker compose -f compose.yml --env-file .env up -d nginx

set -a
. .env
set +a

docker compose -f compose.yml --env-file .env --profile tls run --rm --entrypoint certbot certbot \
  certonly --webroot -w /var/www/certbot \
  -d "$MC_DOMAIN" --email "$MC_EMAIL" --agree-tos --no-eff-email
```

3. Включите TLS и запустите продление:

```dotenv
MC_TLS=on
```

```bash
docker compose -f compose.yml --env-file .env up -d nginx
docker compose -f compose.yml --env-file .env --profile tls up -d certbot
```

Nginx сам перечитывает конфиг каждые 6 часов, certbot продлевает сертификат каждые 12 часов.

## Домашний режим (Cloudflare Tunnel)

Белый IP не нужен: cloudflared подключается к Cloudflare и проксирует трафик на `nginx:80`.

1. В Cloudflare Zero Trust создайте туннель и public hostname, например `music.example.com` → `http://nginx:80`.
2. Скопируйте токен туннеля в `.env`:

```dotenv
CLOUDFLARE_TUNNEL_TOKEN=...
COMPOSE_PROFILES=home
MC_COOKIE_SECURE=true
MC_TLS=off
```

3. Запустите:

```bash
docker compose -f compose.yml --env-file .env --profile home up -d
```

Через CLI:

```bash
mc-cli --dir /opt/music-cloud install --profiles home --tunnel-token '...'
# или позже:
mc-cli --dir /opt/music-cloud profiles enable home
```

Порты 80/443 наружу можно не открывать. У Cloudflare есть ограничения на проксирование больших объёмов медиа — перед домашним режимом проверьте актуальные условия тарифа.

## Мониторинг

```dotenv
MC_METRICS=true
COMPOSE_PROFILES=worker,monitoring
GRAFANA_ADMIN_PASSWORD=...
```

Метрики отдают:

- `mc-api:8080/metrics`
- `mc-worker:8081/metrics`
- `mc-transcoder:8082/metrics`
- `postgres-exporter:9187/metrics`

Prometheus и Grafana слушают только `127.0.0.1` (порты 9090 и 3000). Для доступа используйте SSH-туннель:

```bash
ssh -L 9090:127.0.0.1:9090 -L 3000:127.0.0.1:3000 user@server
```

Дашборд «Music Cloud» и алерты подхватываются автоматически.

## Subsonic

- URL: `https://music.example.com/rest`
- Логин: имя пользователя Music Cloud.
- Пароль: основной пароль или отдельный Subsonic-секрет из `GET /api/v1/auth/subsonic`.
- Поддерживаются JSON и XML, `.view`-эндпоинты, стриминг, обложки, избранное, scrobble, плейлисты и очередь.

## Обновление

Образы собираются CI только по тегам в `main`. Для обновления:

```bash
# в .env поменять MC_TAG на новый тег
docker compose -f compose.yml --env-file .env pull
docker compose -f compose.yml --env-file .env up -d
```

## Бэкап

- База: `docker compose -f compose.yml --env-file .env exec -T postgres pg_dump -U musiccloud musiccloud > backup.sql`
- Библиотека: обычный бэкап каталога `MC_LIBRARY_PATH`.
- Секреты: `.env` (там `POSTGRES_PASSWORD` и `MC_MASTER_KEY`).

## CLI

`mc-cli` устанавливает стек, управляет профилями, администраторами, миграциями, бэкапом и диагностикой.

```bash
cargo install --path services/mc-cli --locked

mc-cli --dir /opt/music-cloud install \
  --library /srv/music-cloud/library \
  --domain music.example.com \
  --profiles worker,transcode

mc-cli --dir /opt/music-cloud profiles enable monitoring
mc-cli --dir /opt/music-cloud admin create --username admin --password '...'
mc-cli --dir /opt/music-cloud admin list
mc-cli --dir /opt/music-cloud admin reset-password --username admin --password '...'
mc-cli --dir /opt/music-cloud migrate
mc-cli --dir /opt/music-cloud export --output backup.sql
mc-cli --dir /opt/music-cloud import --file backup.sql
mc-cli --dir /opt/music-cloud doctor
```

`install --no-docker` пишет `music-cloud.env` и systemd-юниты для нативного запуска бинарников.

## Статус

Этапы 1–11 реализованы. Этап 12 — замер ресурсов и план разбиения (сам перенос репозитория не выполнялся). [docs/resource-usage.md](docs/resource-usage.md), [docs/repo-split.md](docs/repo-split.md).

## Разработка

```bash
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace --all-features

cd web
npm ci
npm run build
```

CI запускается на всех ветках и PR. Контейнеры публикуются в GHCR только по тегам `v*`.
