"""Explicit controls for the hosted screenshot observer experiment."""

def configuration(environment):
    flag = environment.get("POP_OBSERVER_PROBE")
    if flag is None:
        return None
    if flag != "1" or environment.get("GITHUB_ACTIONS") != "true" or environment.get("RUNNER_ENVIRONMENT") != "github-hosted":
        raise ValueError("观察实验只在明确启用的临时托管runner执行")
    values = [environment.get(key) for key in ("POP_OBSERVER_READBACK", "POP_OBSERVER_SAMPLING")]
    if any(value not in ("0", "1") for value in values):
        raise ValueError("观察实验必须明确指定读回和采样条件")
    return {"readback": values[0] == "1", "sampling": values[1] == "1"}


def prefix_plan(plan, observer):
    if observer is None:
        return plan
    end = next((i for i, (name, _) in enumerate(plan) if name == "emojiSymbols"), None)
    if end is None:
        raise ValueError("原截图计划缺少emoji目标")
    return plan[:end + 1]


def app_environment(observer):
    if observer is None:
        return []
    return ["--env", "POP_RENDER_PROBE=1", "--env", "POP_RENDER_PROBE_VARIANT=baseline",
            "--env", "POP_RENDER_PROBE_WORKLOAD=full-prefix"]
