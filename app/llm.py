def get_llm(provider: str = "openai"):
    if provider == "openai":
        import os
        from langchain_openai import ChatOpenAI
        return ChatOpenAI(model=os.environ["OPENAI_MODEL"], temperature=0)

