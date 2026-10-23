import sys
from langsmith import Client, evaluate
from langgraph.checkpoint.memory import InMemorySaver
from app.graph import build

graph = build(InMemorySaver())

def target(inputs: dict) -> dict:
    out = graph.invoke(
        {"messages": [{"user", inputs["question"]}]},
        config={"configurable": {"thread_id": inputs["thread_id"]},
                "recursion_limit": 10},
        )
    
    used_tool = any(
        getattr(m, "tool_calls", None) for m in out['messages']
    )
    return {"used_tool": used_tool, "reply": out["messages"][-1].content}

def correct_routing(outputs: dict, reference_outputs: dict) -> bool:
    expected = reference_outputs["expected"] == "tool_required"
    return outputs["used_tool"] == expected

THRESHOLD = 0.8

def main():
    results = evaluate(
        target,
        data="agent-platform-tool-routing",
        evaluators = [correct_routing],
        experiment_prefix="tool-routing",
    )
    scores = [r["evaluation_results"]["results"][0].score for r in results._results]
    rate = sum(bool(s) for s in scores) / len(scores)
    print(f"Pass rate: {rate:.2%}  (threshold: {THRESHOLD})")
    sys.exit(0 if rate >= THRESHOLD else 1)

if __name__ == "__main__":
    main()