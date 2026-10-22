#!/usr/bin/env python3
"""将 CI 的两份 base64 描述文件写入临时目录，只导出文件路径。"""
import base64
import binascii
import os
from pathlib import Path
import sys


def main():
    bindings = (
        ("APPSTORE_PROVISIONING_PROFILE", "APPSTORE_PROFILE", "Pop.provisionprofile"),
        ("APPSTORE_WIDGET_PROVISIONING_PROFILE", "WIDGET_PROVISIONING_PROFILE", "PopWidgets.provisionprofile"),
    )
    decoded = []
    for secret, variable, filename in bindings:
        encoded = os.environ.get(secret, "")
        if not encoded.strip():
            raise ValueError(f"缺少 {secret}")
        try:
            data = base64.b64decode("".join(encoded.split()), validate=True)
        except (ValueError, binascii.Error):
            raise ValueError(f"{secret} 不是有效的 base64 描述文件") from None
        if not data:
            raise ValueError(f"{secret} 解码后为空")
        decoded.append((variable, filename, data))

    directory = Path(os.environ["RUNNER_TEMP"])
    environment_file = Path(os.environ["GITHUB_ENV"])
    written = []
    try:
        for _, filename, data in decoded:
            path = directory / filename
            # 不覆盖既有文件；权限不依赖 runner 的 umask。
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            written.append(path)
            with os.fdopen(descriptor, "wb") as output:
                output.write(data)
        with environment_file.open("a") as output:
            for variable, filename, _ in decoded:
                output.write(f"{variable}={directory / filename}\n")
    except Exception:
        for path in written:
            path.unlink()
        raise


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, ValueError):
        # 不回显输入或文件内容；实际 CMS、团队和 App ID 仍由签名脚本核验。
        print("error: 描述文件准备失败；请检查两份描述文件 Secret、base64 格式和临时目录。", file=sys.stderr)
        sys.exit(1)
