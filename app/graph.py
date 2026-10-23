import os
from datetime import datetime
from zoneinfo import ZoneInfo
from typing import Annotated, TypedDict
from langchain_core.messages import AnyMessage
from langchain_core.tools import tool
from langchain_openai import AzureChatOpenAI
from langgraph.graph import StateGraph, START
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition
from app.llm import get_llm

class State(TypedDict):
    messages: Annotated[list[AnyMessage], add_messages]

@tool
def get_time(tz:str = 'UTC') -> str:
    """Current time in an IANA Timezone, eg: Asia/Kolkata"""
    return datetime.now(ZoneInfo(tz)).isoformat()

tools = [get_time]
# llm = AzureChatOpenAI(
#     azure_deployment=os.getenv('AZURE_OPENAI_DEPLOYMENT')
# ).bind_tools(tools)
provider = os.environ["LLM_PROVIDER"]
llm = get_llm(provider).bind_tools(tools)

async def agent(state: State):
    return {"messages": [await llm.ainvoke(state["messages"])]}

def build(checkpointer):
    g = StateGraph(State)
    g.add_node("agent", agent)
    g.add_node("tools", ToolNode(tools))
    g.add_edge(START, "agent")
    g.add_conditional_edges("agent", tools_condition)
    g.add_edge("tools", "agent")
    return g.compile(checkpointer=checkpointer)