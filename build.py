import subprocess
import sys
import argparse
import os

def build_flutter(flavor, platform, release=True):
    target_file = "lib/main.dart"
    build_mode = "--release" if release else "--debug"
    dart_define = f"--dart-define=ENV={flavor}"

    cmd = []

    if platform == "android":
        cmd = [
            "flutter", "build", "apk",
            "--flavor", flavor,
            "-t", target_file,
            dart_define
        ]
        if release:
            cmd.append("--release")
        else:
            cmd.append("--debug")

    elif platform == "ios":
        cmd = [
            "flutter", "build", "ios",
            "--flavor", flavor,
            "-t", target_file,
            dart_define
        ]
        if release:
            cmd.append("--release")
        else:
            cmd.append("--debug")
    else:
        print(f"❌ 不支持的平台: {platform}")
        sys.exit(1)

    print("🚀 打包命令：", " ".join(cmd))
    subprocess.run(cmd, check=True)
    print("✅ 打包完成：平台 =", platform, ", 环境 =", flavor)

def main():
    parser = argparse.ArgumentParser(description="Flutter 多环境打包工具")
    parser.add_argument("--flavor", required=True, help="环境名称，例如 dev、prod、test")
    parser.add_argument("--platform", required=True, help="平台名称 android 或 ios")
    parser.add_argument("--debug", action="store_true", help="使用 debug 模式打包（默认 release）")

    args = parser.parse_args()

    build_flutter(
        flavor=args.flavor,
        platform=args.platform,
        release=not args.debug
    )

if __name__ == "__main__":
    main()
