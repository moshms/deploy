# Разбиение репозитория

Сейчас это монорепо: `crates/`, `services/`, `web/`, `deploy/`, `proto/`. Разбиение нужно, когда сервисы начнут релизиться независимо. До этого монорепо дешевле.

## Целевые репозитории

| Репозиторий | Содержимое | Артефакты |
| --- | --- | --- |
| `music-cloud-core` | `crates/mc-core`, `mc-auth`, `mc-crypto`, `mc-db`, `mc-jobs`, `mc-media`, `mc-proto`, `mc-runtime`, `mc-scanner`, `mc-storage`, `mc-telemetry`, `mc-api-types` | версионированные crates, `mc-proto` |
| `music-cloud-api` | `services/mc-api` | образ `mc-api` |
| `music-cloud-worker` | `services/mc-worker` | образ `mc-worker` |
| `music-cloud-transcoder` | `services/mc-transcoder` | образ `mc-transcoder` |
| `music-cloud-web` | `web/` | статика, встраивается в образ `nginx` |
| `music-cloud-deploy` | `deploy/`, `docker/`, `README.md`, e2e | compose, конфиги, тесты развёртывания |
| `music-cloud-cli` | `services/mc-cli` | статический бинарь |

## Версионирование

- `music-cloud-core` публикуется в приватный registry или подключается git-тегом.
- Сервисы фиксируют точные версии `mc-*` в `Cargo.toml`; обновление — отдельный PR.
- Релизный тег `vX.Y.Z` ставится одновременно на сервисы и deploy; deploy пиннит теги образов.
- `mc-proto` и `mc-api-types` версионируются строже остальных: ломающее изменение — major.

## CI/CD

- В каждом репозитории свой CI: fmt, clippy, test, сборка образа.
- Образы публикуются в GHCR с именами `ghcr.io/imtrim/music-cloud-<service>`.
- `music-cloud-deploy` прогоняет e2e на зафиксированных тегах: core, core+worker+transcode, всё+monitoring.
- В монорепо остаётся зелёный CI до дня переноса.

## Порядок переноса

1. Зафиксировать текущий `main` тегом `v1.0.0`.
2. Создать пустые репозитории и права в GHCR.
3. Вынести `crates/` через `git filter-repo --path crates/`, добавить `Cargo.toml` воркспейса, опубликовать первую версию.
4. Вынести сервисы по одному, заменив path-зависимости на версии; CI должен собрать образ до удаления из монорепо.
5. Вынести `web/` и `deploy/`; в deploy перейти на `MC_TAG` без `build:`.
6. Вынести `mc-cli`; собирать musl-бинарь на тегах.
7. Перевести монорепо в read-only и оставить ссылки на новые репозитории.

## Что не делаем автоматически

Создание новых GitHub-репозиториев и перенос истории требуют доступа к организации и решения по именам пакетов. Этот файл — план, а не выполненный перенос.
