import os
import sys
import subprocess
import zipfile

def package():
    root = os.path.dirname(os.path.abspath(__file__))
    project_dir = root
    # Target lua source in Source folder
    src_lua = os.path.join(project_dir, "Source", "mods", "chinese_input_fix", "fix_ime.lua")
    if not os.path.exists(src_lua):
        src_lua = os.path.join(os.path.dirname(project_dir), "ChineseInputFix_impl.lua")

    # Call pack_addon tool from skill
    parent = os.path.dirname(project_dir)
    pack_tool = os.path.join(parent, "hd2-lua-mod-skill", "tools", "pack_addon.py")

    cmd = [
        sys.executable,
        os.path.join(parent, "package_mod.py")
    ]

    print("Running packaging command...")
    res = subprocess.run([sys.executable, os.path.join(parent, "package_mod.py")], cwd=parent, capture_output=True, text=True)
    print("STDOUT:", res.stdout)
    if res.stderr:
        print("STDERR:", res.stderr)

    zip_path = os.path.join(project_dir, "ChineseInputFix-v1.0.0.zip")
    if os.path.exists(zip_path):
        with zipfile.ZipFile(zip_path, 'r') as z:
            z.extractall(project_dir)
        print("Successfully packaged and extracted mod files into Addon/")

if __name__ == "__main__":
    package()
