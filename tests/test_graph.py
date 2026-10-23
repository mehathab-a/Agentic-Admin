import pytest
from langgraph.checkpoint.memory import InMemorySaver
from app.graph import build

@pytest.mark.asyncio
async def test_graph_persists_state_per_thread():
    graph = build(InMemorySaver())
    cfg = {"configurable": {"thread_id": "a"}}
    await graph.ainvoke({"messages": [("user", "remember: blue")]}, config=cfg)
    state = await graph.aget_state(cfg)
    assert len(state.values["messages"]) >= 2

    other = await graph.aget_state({"configurable": {"thread_id": "b"}})
    assert not other.values.get("messages")