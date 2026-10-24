import os, time, uuid
import structlog
from contextlib import asynccontextmanager
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from langgraph.checkpoint.postgres.aio import AsyncPostgresSaver
from app.graph import build
from app.logging import configure_logging

configure_logging()
log = structlog.get_logger()

log.info("DATABASE_URL", DATABASE_URL=os.getenv("DATABASE_URL"))
log.info("OPENAI_API_KEY", OPENAI_API_KEY=os.getenv("OPENAI_API_KEY"))
log.info("LANGSMITH_API_KEY", LANGSMITH_API_KEY=os.getenv("LANGSMITH_API_KEY"))

@asynccontextmanager
async def lifespan(app:FastAPI):
    async with AsyncPostgresSaver.from_conn_string(os.getenv("DATABASE_URL")) as cp:
        await cp.setup() # Creates checkpoint tables
        app.state.graph = build(cp)
        yield

app = FastAPI(lifespan=lifespan)

@app.middleware("http")
async def request_context(request:Request, call_next):
    rid = request.headers.get("x-request-id", str(uuid.uuid4()))
    structlog.contextvars.bind_contextvars(request_id=rid)
    start_time = time.perf_counter()
    try:
        response = await call_next(request)
        log.info("request", status=response.status_code, ms=round((time.perf_counter() - start_time) * 1000))
        return response
    except Exception as e:
        log.exception("request_failed", ms=round((time.perf_counter() - start_time) * 1000))
        raise e
    finally:
        structlog.contextvars.clear_contextvars()

class Req(BaseModel):
    thread_id: str
    message: str

@app.get("/healthz")
def health():
    return {"ok": True}

@app.post("/chat")
async def chat(r: Req):
    out = await app.state.graph.ainvoke(
        {"messages": [("user",r.message)]},
        config={"configurable": {"thread_id": r.thread_id}, "recursion_limit": 10},
    )
    return {"reply": out["messages"][-1].content}

@app.post("/chat/stream")
async def chat_stream(r: Req):
    async def events():
        try:
            async for mode, chunk in app.state.graph.astream(
                {"messages": [("user", r.message)]},
                config={"configurable": {"thread_id": r.thread_id},
                        "recursion_limit": 10},
                stream_mode=["messages", "updates"],
            ):
                if mode == "messages":
                    msg, _meta = chunk
                    if msg.content:
                        import json
                        text = msg.content if isinstance(msg.content, str) else str(msg.content)
                        payload = text.replace("\n", "\\n")
                        yield f"event: token\ndata: {json.dumps({'t': text})}\n\n"
                elif mode == "updates":
                    for node in chunk:
                        log.info("node_complete", node=node)
                        yield f"event: node\ndata: {node}\n\n"
            yield "event: done\ndata: ok\n\n"
        except Exception as e:
            log.exception("stream_failed")
            yield f"event: error\ndata: {type(e).__name__}\n\n"

    return StreamingResponse(events(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache",
                                      "X-Accel-Buffering": "no"})