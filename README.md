# agent-platform

A small LangGraph agent served over FastAPI. Conversations are checkpointed in Postgres, tool calls route through a single timezone tool, and requests are logged as JSON.

Python 3.11. Package version `0.1.0`.

## What is in place

### Agent graph (`app/graph.py`)

- State is a message list merged with LangGraph `add_messages`.
- One tool, `get_time`, returns the current time as an ISO timestamp for an IANA timezone (default `UTC`).
- The graph is `START → agent → (tools when the model requests them) → agent`, compiled with a checkpointer and a recursion limit of 10 at the API boundary.
- The model comes from `get_llm`, selected by the `LLM_PROVIDER` environment variable. Only `openai` is implemented (`OPENAI_MODEL`, temperature 0). `langchain-anthropic` and `langchain-aws` are dependencies; those providers are not wired up yet. A commented Azure OpenAI path is still in the file.

### HTTP API (`app/api.py`)

On startup the app opens an `AsyncPostgresSaver` from `DATABASE_URL`, creates the checkpoint tables, and compiles the graph onto `app.state`.

| Method | Path | Behavior |
| --- | --- | --- |
| `GET` | `/healthz` | Returns `{"ok": true}`. |
| `POST` | `/chat` | Body: `thread_id`, `message`. Invokes the graph and returns `{"reply": ...}` from the last message. |
| `POST` | `/chat/stream` | Same body. Server-sent events: `token` (message text), `node` (completed node name), then `done`. Failures emit `error` with the exception type. |

Every request binds a `request_id` (incoming `x-request-id`, or a new UUID) and logs status and duration. Streamed runs also log each completed node.

### Logging (`app/logging.py`)

structlog writes JSON lines with merged context vars, log level, and an ISO timestamp. The `httpx` logger is set to warning.

### Persistence

Thread state is stored in LangGraph’s Postgres checkpointer, keyed by `thread_id`.

### Docker

`docker-compose.yml` runs two services:

- **db** — Postgres 16, database `agent`, user `postgres`, password `postgres`, published on port 5432. A `pg_isready` healthcheck runs every 3 seconds, up to 10 times.
- **api** — built from the local `Dockerfile`, published on port 8000. It loads `.env` and sets `DATABASE_URL` to `postgresql://postgres:postgres@db:5432/agent`. It starts only after `db` is healthy.

The image is multi-stage, based on `python:3.11-slim`:

1. Install `uv`, then `uv export --no-dev --no-emit-project --no-hashes` from `pyproject.toml` and `uv.lock`, and `pip install` those packages into `/install`. `--no-emit-project` drops the local editable package (pip cannot hash it), and `--no-hashes` avoids the hash check that blocked that install.
2. Copy `/install` into a runtime image, add a non-root user `app` (uid 1000), copy `app/`, and run `uvicorn app.api:app` on `0.0.0.0:8000`.

`.dockerignore` keeps `.venv`, `.env`, `.git`, caches, `tests/`, `evals/`, and `terraform/` out of the build context. The image does not use the `requirements.txt` in the repo root; dependencies come from the lockfile at build time.

### Tests

- `tests/test_tools.py` — `get_time` returns a timezone-aware ISO time, differs between timezones, and raises on an unknown zone.
- `tests/test_graph.py` — with `InMemorySaver`, a thread keeps its messages and a different `thread_id` stays empty.

### Evals (`evals/`)

LangSmith dataset `agent-platform-tool-routing` (created by `evals/datasets.py`) labels questions as `tool_required` or `no_tool`. `evals/run.py` is meant to run the graph against that dataset, score whether a tool was called, and exit non-zero if the pass rate is under 80%. The invoke call currently passes a set (`{"user", question}`) where the graph expects a user message, so that runner does not execute yet.

### CI (`.github/workflows/ci.yml`)

The `ci` workflow runs on pushes and pull requests to `main`. Jobs run in order: tests, then the eval gate, then an image push. The build job runs only when the ref is `refs/heads/main`.

| Job | What it does |
| --- | --- |
| `test` | Postgres 16 service container, `uv sync --all-extras --dev`, then `uv run pytest -q`. |
| `evals` | Same install, then `uv run python evals/run.py`. |
| `build` | Assumes an AWS role with OIDC, logs in to ECR in `us-east-1`, and pushes `agentic-admin` tagged with the commit SHA and `latest`. |

Permissions are `contents: read` and `id-token: write` (for the role assumption).

Secrets: `POSTGRES_PASSWORD`, `POSTGRES_DB`, `OPENAI_API_KEY`, `LANGSMITH_API_KEY`, `AWS_ROLE_ARN`.

Repository variables: `LANGSMITH_TRACING`, `LANGSMITH_PROJECT`, `LLM_PROVIDER`, `OPENAI_MODEL`, `OPENAI_API_VERSION`.

The workflow file does not parse yet. On the ECR login step, `id: ecr` is indented under `uses`, and on the push step `env` is indented under `name`. GitHub will reject the file until those keys sit beside `uses` and `name`. The Postgres service option is `--health_retries`; Actions expects `--health-retries`. The test job’s `DATABASE_URL` host is `db`, while the service container is named `postgres`.

### Package stub

`src/agent_platform/__init__.py` exposes the `agent-platform` console script, which prints a hello line. The running service lives in `app/`, not in that package.

## Layout

```
app/                  graph, LLM factory, FastAPI app, logging
evals/                LangSmith dataset setup and tool-routing eval
tests/                tool and checkpointer tests
src/agent_platform/   console-script stub
Dockerfile            multi-stage API image
docker-compose.yml    Postgres 16 and the API
.dockerignore         build-context exclusions
pyproject.toml        dependencies (uv)
uv.lock               locked dependency set used by the image
.github/workflows/ci.yml   test, eval gate, ECR push
```

## Run

Put model settings in `.env` (`LLM_PROVIDER`, `OPENAI_MODEL`, `OPENAI_API_KEY`). Compose overrides `DATABASE_URL` so the API talks to the `db` service.

```bash
docker compose up --build
```

The API is on port 8000 once Postgres is healthy.

To run the API on the host instead, start only the database and point `DATABASE_URL` at localhost:

```bash
uv sync
docker compose up -d db
export DATABASE_URL=postgresql://postgres:postgres@localhost:5432/agent
export LLM_PROVIDER=openai
export OPENAI_MODEL=gpt-4o-mini
export OPENAI_API_KEY=...
uv run uvicorn app.api:app --reload
```

```bash
curl -s localhost:8000/healthz
curl -s localhost:8000/chat \
  -H 'content-type: application/json' \
  -d '{"thread_id":"t1","message":"What time is it in Asia/Kolkata?"}'
```

```bash
uv run pytest
uv run python -m evals.datasets   # once, needs LANGSMITH_API_KEY
uv run python -m evals.run
```
