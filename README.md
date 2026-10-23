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

`docker-compose.yml` runs Postgres 16 with database `agent`, user `postgres`, password `postgres`, published on port 5432. Thread state is stored in LangGraph’s Postgres checkpointer, keyed by `thread_id`.

### Tests

- `tests/test_tools.py` — `get_time` returns a timezone-aware ISO time, differs between timezones, and raises on an unknown zone.
- `tests/test_graph.py` — with `InMemorySaver`, a thread keeps its messages and a different `thread_id` stays empty.

### Evals (`evals/`)

LangSmith dataset `agent-platform-tool-routing` (created by `evals/datasets.py`) labels questions as `tool_required` or `no_tool`. `evals/run.py` is meant to run the graph against that dataset, score whether a tool was called, and exit non-zero if the pass rate is under 80%. The invoke call currently passes a set (`{"user", question}`) where the graph expects a user message, so that runner does not execute yet.

### Package stub

`src/agent_platform/__init__.py` exposes the `agent-platform` console script, which prints a hello line. The running service lives in `app/`, not in that package.

## Layout

```
app/           graph, LLM factory, FastAPI app, logging
evals/         LangSmith dataset setup and tool-routing eval
tests/         tool and checkpointer tests
src/agent_platform/   console-script stub
docker-compose.yml    Postgres 16
pyproject.toml        dependencies (uv)
```

## Run

```bash
uv sync
docker compose up -d
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
