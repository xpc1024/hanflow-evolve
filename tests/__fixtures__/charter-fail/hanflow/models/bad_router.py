def complete(prompt):  # 违规：IO 方法 complete 是 sync
    return ""


async def astream(prompt):  # 合规
    yield ""
