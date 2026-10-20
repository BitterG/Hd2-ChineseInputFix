"""一键打包 ChineseInputFix。

用法:
    python build_mod.py              # 从 Source/ 打包成 ChineseInputFix-v<源码版本>.zip, 并展开到 Addon/
    python build_mod.py --no-extract

版本号只有一处真理: 源码里的 `local MOD_VERSION = "x.y.z"`。
zip 名、控制台输出、STATUS 文件全部由它推导, 不会再出现"包名还是旧版本"。

依赖: hd2-lua-mod-skill 的 tools/build_addon.py(生成 .patch_0 归档)。
默认去 ../hd2-lua-mod-skill/tools 找, 也可用 --tools 或环境变量 HD2_TOOLS 指定。
"""

import argparse
import json
import os
import re
import subprocess
import sys
import uuid
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "mods/chinese_input_fix/fix_ime"          # 归档内路径(= addon 入口名)
GUID = str(uuid.uuid5(uuid.NAMESPACE_DNS, "mods.kugua.chinese_input_fix"))  # 必须稳定
DISPLAY_NAME = "ChineseInputFix"
MOD_TITLE = "ChineseInputFix"
SOURCE_REL = os.path.join("Source", "mods", "chinese_input_fix", "fix_ime.lua")
VERSION_RE = re.compile(r'local\s+MOD_VERSION\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"')

DESCRIPTION = (
    "游戏内中文输入框(黑色毛玻璃, 支持微软/搜狗/微信/百度/QQ 等输入法), "
    "可给聊天文字上色与调字号(<c=AARRGGBB> / <s=xx>, 字号 10-99)。"
    "需要 Bingus Shared Loader v15+ (addon 支持已开启)。"
    "可选: CowboyBingus Mod Options Menu v1 (api 1) 提供游戏内设置页; "
    "未安装时读取 %LOCALAPPDATA%\\CowboyBingus\\Helldivers2\\Logs\\ChineseInputFix.ini。"
)

EXTRA_FILES = ("README.md", "README-zh-CN.md")


def find_tool(explicit):
    candidates = []
    if explicit:
        candidates.append(explicit)
    env = os.environ.get("HD2_TOOLS")
    if env:
        candidates.append(env)
    candidates.append(os.path.join(os.path.dirname(HERE), "hd2-lua-mod-skill", "tools"))
    candidates.append(os.path.join(HERE, "tools"))
    for folder in candidates:
        script = os.path.join(folder, "build_addon.py")
        if os.path.isfile(script):
            return script
    raise SystemExit("找不到 build_addon.py, 请用 --tools 指向 hd2-lua-mod-skill/tools 目录")


def rewrite_zip(zip_path, version):
    """把 build_addon 生成的 manifest 换成中文描述(带版本号), 并附上 README。"""
    with zipfile.ZipFile(zip_path) as archive:
        entries = {info.filename: archive.read(info.filename) for info in archive.infolist()}

    description = "v%s  " % version + DESCRIPTION
    manifest = {
        "Version": 1,
        "Guid": GUID,
        "Name": DISPLAY_NAME,
        "Description": description,
        "Options": [{
            "Name": MOD_TITLE,
            "Description": description,
            "Include": ["Addon"],
        }],
    }
    entries["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    for name in EXTRA_FILES:
        path = os.path.join(HERE, name)
        if os.path.isfile(path):
            with open(path, "rb") as handle:
                entries[name] = handle.read()

    temp = zip_path + ".tmp"
    with zipfile.ZipFile(temp, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(entries):
            info = zipfile.ZipInfo(path, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, entries[path])
    os.replace(temp, zip_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools", help="hd2-lua-mod-skill/tools 目录")
    parser.add_argument("--no-extract", action="store_true", help="只生成 zip, 不展开到 Addon/")
    args = parser.parse_args()

    source = os.path.join(HERE, SOURCE_REL)
    if not os.path.isfile(source):
        raise SystemExit("源码不存在: " + source)
    with open(source, "rb") as handle:
        raw = handle.read()
    if raw[:3] == b"\xef\xbb\xbf":
        raise SystemExit("源码带 UTF-8 BOM, 游戏会静默不加载: " + source)

    matched = VERSION_RE.search(raw.decode("utf-8"))
    if not matched:
        raise SystemExit("源码里找不到 MOD_VERSION, 无法推导版本号: " + source)
    version = matched.group(1)
    zip_name = "ChineseInputFix-v%s.zip" % version

    tool = find_tool(args.tools)
    zip_path = os.path.join(HERE, zip_name)
    command = [
        sys.executable, tool,
        "--name", NAME,
        "--entry", source,
        "--guid", GUID,
        "--display-name", DISPLAY_NAME,
        "--output", zip_path,
    ]
    print("版本:", version, "(取自源码 MOD_VERSION)")
    print("打包:", " ".join(command))
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.stdout.strip():
        print(result.stdout.strip())
    if result.returncode != 0:
        print(result.stderr.strip(), file=sys.stderr)
        raise SystemExit("打包失败")

    rewrite_zip(zip_path, version)

    if not args.no_extract:
        with zipfile.ZipFile(zip_path) as archive:
            archive.extractall(HERE)
        print("已展开到:", os.path.join(HERE, "Addon"))

    # 旧版本的 zip 一并清掉, 免得管理器里混进两个版本
    for name in os.listdir(HERE):
        if name.startswith("ChineseInputFix-v") and name.endswith(".zip") and name != zip_name:
            os.remove(os.path.join(HERE, name))
            print("已删除旧包:", name)

    print("完成:", zip_path)


if __name__ == "__main__":
    main()
