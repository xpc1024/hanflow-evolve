def compile(node):
    # 违规：if/elif node.type 硬编码分派
    if node.type == "llm":
        return run_llm(node)
    elif node.type == "tool":
        return run_tool(node)
    elif node.type == "research":
        return run_research(node)
