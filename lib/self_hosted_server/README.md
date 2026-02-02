# Self-Hosted Sync Server

Minimal FastAPI server for local network sync.

## Run with Docker

```bash
docker build -t tier-monitor-sync .
docker run --rm -p 8000:8000 tier-monitor-sync
```

## Run with Docker Compose (alternative)

```bash
docker compose up --build
```

## Optional API token

Set `API_TOKEN` so the server requires the `X-API-Token` header.

```bash
docker run --rm -p 8000:8000 -e API_TOKEN=secret tier-monitor-sync
```

## Endpoints

- `GET /health` simple health check
- `GET /sync/summary` returns last upload time + max dates per table
- `POST /sync/upload` replace server data with client tables
- `GET /sync/download` fetch server tables + summary

## Tombstones

Deletions are tracked via a `deleted_at` timestamp. Clients keep tombstones so deletions can sync across devices.
