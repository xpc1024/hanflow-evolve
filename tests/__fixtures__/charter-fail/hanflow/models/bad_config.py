from dataclasses import dataclass

@dataclass
class RouterConfig:  # 违规：Config 类用了 dataclass
    model: str
