#!/usr/bin/env python3
"""把 Noto Sans SC Bold 裁剪成只含游戏实际用到的字。

为什么需要：网页导出没有系统字体可回退，中文必须随包携带；整份字体约 8 MB，
裁剪后只有一两百 KB，首次加载才够小。

用法（在项目根目录）：
    tools\\.venv\\Scripts\\python.exe tools\\build_font.py

只要改了游戏里的任何文字，就要重跑一次。tests/test_runner.gd 会检查
脚本里出现的字是否都在裁剪后的字体里，漏跑会被测试拦住。

字体：Noto Sans SC（SIL Open Font License 1.1）。正式字体字号尚未拍板，这是临时选用。
"""

from __future__ import annotations

import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE_URL = "https://github.com/notofonts/noto-cjk/raw/main/Sans/SubsetOTF/SC/NotoSansSC-Bold.otf"
LICENSE_URL = "https://github.com/notofonts/noto-cjk/raw/main/Sans/LICENSE"
CACHE_DIR = ROOT / "tools" / ".cache"
SOURCE_FONT = CACHE_DIR / "NotoSansSC-Bold.otf"
OUT_DIR = ROOT / "assets" / "fonts"
OUT_FONT = OUT_DIR / "NotoSansSC-Bold-subset.otf"
OUT_LICENSE = OUT_DIR / "NotoSansSC-LICENSE.txt"

# 这些位置里出现的字都会进字体。
SCAN_DIRS = ["scripts", "scenes"]
SCAN_FILES = ["project.godot"]
SCAN_SUFFIXES = {".gd", ".tscn", ".tres"}

# 不管源码里有没有，都保留：可打印 ASCII 和常用中文标点。
ALWAYS_KEEP = "".join(chr(c) for c in range(0x20, 0x7F)) + "，。！？：；、（）《》「」“”‘’·—…％＋－×÷～"


def download(url: str, target: pathlib.Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    print(f"下载 {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "build_font.py"})
    with urllib.request.urlopen(request, timeout=120) as response:
        target.write_bytes(response.read())


def collect_characters() -> set[str]:
    chars: set[str] = set(ALWAYS_KEEP)
    paths = [ROOT / name for name in SCAN_FILES]
    for directory in SCAN_DIRS:
        paths.extend(p for p in (ROOT / directory).rglob("*") if p.suffix in SCAN_SUFFIXES)
    for path in paths:
        if path.is_file():
            chars.update(path.read_text(encoding="utf-8"))
    return {c for c in chars if c.isprintable()}


def main() -> int:
    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
    except ImportError:
        print("缺少 fonttools：先运行 tools\\.venv\\Scripts\\python.exe -m pip install fonttools")
        return 1

    if not SOURCE_FONT.exists():
        download(SOURCE_URL, SOURCE_FONT)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    if not OUT_LICENSE.exists():
        download(LICENSE_URL, OUT_LICENSE)

    chars = collect_characters()
    available = set(TTFont(str(SOURCE_FONT)).getBestCmap().keys())
    missing = sorted(c for c in chars if ord(c) not in available)
    if missing:
        print("源字体里没有这些字（会显示成方框）：" + " ".join(f"{c}(U+{ord(c):04X})" for c in missing))

    options = subset.Options()
    options.name_IDs = ["*"]  # 保留版权与许可信息
    options.notdef_outline = True
    font = subset.load_font(str(SOURCE_FONT), options)
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=[ord(c) for c in chars])
    subsetter.subset(font)
    subset.save_font(font, str(OUT_FONT), options)

    size_kb = OUT_FONT.stat().st_size / 1024
    print(f"写出 {OUT_FONT.relative_to(ROOT)}：{len(chars)} 个字，{size_kb:.0f} KB")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
