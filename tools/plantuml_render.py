#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""用 PlantUML 官方服务渲染 .puml 为 PNG，不需要本地 Java。

用法：
    python tools/plantuml_render.py docs/uml/08-state-product-trade.puml
    python tools/plantuml_render.py docs/uml/*.puml --force

为什么要有这个脚本：团队里装 Java + Graphviz 的成本比想象中高，
而仓库里的图必须能从 .puml 源码重新产出，否则改了源码图还是旧的。
"""
import argparse
import os
import sys
import zlib
import urllib.request
import urllib.error

DEFAULT_PROXY = "http://127.0.0.1:7897"
SERVER = "https://www.plantuml.com/plantuml/png"


def _encode6bit(b):
    if b < 10:
        return chr(48 + b)
    b -= 10
    if b < 26:
        return chr(65 + b)
    b -= 26
    if b < 26:
        return chr(97 + b)
    b -= 26
    if b == 0:
        return "-"
    if b == 1:
        return "_"
    return "?"


def _append3bytes(b1, b2, b3):
    c1 = b1 >> 2
    c2 = ((b1 & 0x3) << 4) | (b2 >> 4)
    c3 = ((b2 & 0xF) << 2) | (b3 >> 6)
    c4 = b3 & 0x3F
    return (_encode6bit(c1) + _encode6bit(c2) +
            _encode6bit(c3) + _encode6bit(c4))


def plantuml_encode(text):
    """PlantUML 的 URL 编码：deflate 压缩后按 6bit 自定义字母表编码。"""
    data = zlib.compress(text.encode("utf-8"))[2:-4]
    out = []
    for i in range(0, len(data), 3):
        chunk = data[i:i + 3]
        b1 = chunk[0]
        b2 = chunk[1] if len(chunk) > 1 else 0
        b3 = chunk[2] if len(chunk) > 2 else 0
        out.append(_append3bytes(b1, b2, b3))
    return "".join(out)


def render(puml_path, proxy=None):
    with open(puml_path, "rb") as f:
        raw = f.read()
    text = raw.decode("utf-8-sig")
    url = SERVER + "/" + plantuml_encode(text)

    handlers = []
    if proxy:
        handlers.append(urllib.request.ProxyHandler(
            {"http": proxy, "https": proxy}))
    opener = urllib.request.build_opener(*handlers)
    req = urllib.request.Request(url, headers={
        "User-Agent": "campusswap-doc-tool/1.0"})
    with opener.open(req, timeout=90) as resp:
        payload = resp.read()
    if not payload.startswith(b"\x89PNG"):
        raise RuntimeError("返回的不是 PNG，首 200 字节：%r" % payload[:200])

    png_path = os.path.splitext(puml_path)[0] + ".png"
    with open(png_path, "wb") as f:
        f.write(payload)
    return png_path, len(payload)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--proxy", default=os.environ.get("PUML_PROXY", DEFAULT_PROXY),
                    help="HTTP 代理，默认 7897；传空字符串表示直连")
    args = ap.parse_args()

    failed = 0
    for path in args.files:
        if not path.endswith(".puml"):
            continue
        try:
            out, size = render(path, args.proxy or None)
            print("OK   %-52s %6.1f KB" % (os.path.basename(out), size / 1024.0))
        except Exception as exc:  # noqa: BLE001
            failed += 1
            print("FAIL %-52s %s" % (os.path.basename(path), exc))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
