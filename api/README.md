# vault-vital-trace-api

A small NestJS service with a single authenticated endpoint: it accepts a
session's 4 artifact files (a `.mov` video, two `.json` files, and a `.csv`
file) plus a `sessionId`, and uploads all 4 into a Google Cloud Storage
bucket under `sessions/{sessionId}/`. There is no database — GCS is the
only persistence.

## Requirements

- Node.js 20+, Yarn
- A GCS bucket
- A GCP service account with `roles/storage.objectCreator` **and**
  `roles/storage.objectAdmin` on that bucket — the latter is required
  because a partially-failed upload triggers a compensating delete of the
  objects that did succeed, and object versioning/overwrite checks also
  rely on delete/metadata permissions.

## Setup

```bash
yarn install
cp .env.example .env
```

Edit `.env` and set, at minimum, `API_KEY`, `GCS_PROJECT_ID`, and
`GCS_BUCKET_NAME`. For GCS credentials, pick exactly one:

- **(a)** `GCS_CREDENTIALS_JSON` — the full service-account JSON as a
  single-line string
- **(b)** `GOOGLE_APPLICATION_CREDENTIALS` — path to a keyfile
- **(c)** leave both unset — Application Default Credentials are used
  (this is the right choice when deployed on Cloud Run/GCE)

## Run

```bash
yarn start:dev
```

Swagger UI is served at `http://localhost:8080/docs` when
`SWAGGER_ENABLED=true` (the default; set it to `false` in production,
since this is an internal, shared-secret-protected API).

## Endpoint reference

`POST /sessions/uploads`, `multipart/form-data`, requires header
`x-api-key: <API_KEY>` (header name configurable via `API_KEY_HEADER`).

| field | required | extension | max size (env) |
|---|---|---|---|
| `sessionId` (text field) | yes | — | 1–128 chars, `[A-Za-z0-9_-]`, must start alphanumeric |
| `videoFile` | yes | `.mov` | `MAX_VIDEO_SIZE_MB` (default 1024) |
| `jsonFile1` | yes | `.json` | `MAX_JSON_SIZE_MB` (default 16) |
| `jsonFile2` | yes | `.json` | `MAX_JSON_SIZE_MB` (default 16) |
| `csvFile` | yes | `.csv` | `MAX_CSV_SIZE_MB` (default 32) |

Objects land at:

```
sessions/{sessionId}/video.mov
sessions/{sessionId}/data-1.json
sessions/{sessionId}/data-2.json
sessions/{sessionId}/data.csv
```

(`sessions` prefix configurable via `GCS_OBJECT_PREFIX`.) Re-uploading the
same `sessionId` returns `409 Conflict` — each object is written with a
GCS `ifGenerationMatch: 0` precondition, so an existing session's files
are never silently overwritten. If any of the 4 uploads fails, the ones
that already succeeded are deleted so a retry with the same `sessionId`
isn't permanently blocked.

### Error codes

All errors share this envelope:

```jsonc
{
  "error": {
    "code": "VALIDATION_FAILED",
    "message": "One or more uploaded files failed validation.",
    "details": [{ "field": "videoFile", "code": "INVALID_FILE_EXTENSION", "expected": ".mov", "received": ".mp4" }],
    "request_id": "...",
    "timestamp": "..."
  }
}
```

| HTTP | code | when |
|---|---|---|
| 400 | `VALIDATION_FAILED` | missing/invalid `sessionId`, or file field violations wrapped under `details` (`FILE_REQUIRED`, `INVALID_FILE_EXTENSION`, `INVALID_FILE_MIMETYPE`) |
| 401 | `API_KEY_MISSING` / `API_KEY_INVALID` | missing or wrong `x-api-key` |
| 409 | `SESSION_ALREADY_EXISTS` | an object already exists at that `sessionId` prefix |
| 413 | `FILE_TOO_LARGE` | a file exceeds its per-field size cap |
| 500 | `GCS_PERMISSION_DENIED` / `GCS_BUCKET_NOT_FOUND` / `GCS_UPLOAD_FAILED` | storage backend errors |

### Example

```bash
curl -X POST http://localhost:8080/sessions/uploads \
  -H "x-api-key: $API_KEY" \
  -F "sessionId=a1b2c3d4-5e6f-7081-9abc-def012345678" \
  -F "videoFile=@./samples/recording.mov;type=video/quicktime" \
  -F "jsonFile1=@./samples/metrics.json;type=application/json" \
  -F "jsonFile2=@./samples/events.json;type=application/json" \
  -F "csvFile=@./samples/trace.csv;type=text/csv"
```

## Testing

```bash
yarn test        # unit tests + coverage-relevant logic
yarn test:cov     # unit tests with coverage report (80% statement threshold)
yarn test:e2e     # end-to-end tests (GCS client mocked)
```

## Docker / Cloud Run

```bash
docker compose -f docker-compose.dev.yml up
```

**Large-video caveat:** uploaded files are streamed to disk in
`os.tmpdir()` before being pushed to GCS. On Cloud Run, `tmpdir()` is an
in-memory tmpfs counted against the instance's memory limit, so a
`MAX_VIDEO_SIZE_MB=1024` default requires provisioning **at least 2GiB**
of instance memory. Cloud Run's own request size limits and timeouts
should also be reviewed for large uploads (`--timeout`, streaming
support). If typical recordings are much smaller in practice, lowering
`MAX_VIDEO_SIZE_MB` simplifies this considerably.
