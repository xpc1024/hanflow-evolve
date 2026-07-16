class BadError(Exception):  # 违规：未继承 HanflowError
    pass


class GoodError(HanflowError):  # 合规
    pass
