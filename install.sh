#!/usr/bin/env bash
# Install Plasma AI Plasmoids: build bridges, substitute paths, deploy packages + helpers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME:-$HOME}"
PLASMOIDS_DIR="$HOME_DIR/.local/share/plasma/plasmoids"
STATE_DIR="$HOME_DIR/.local/state/dsh-widget"
OPT_DIR="$HOME_DIR/.local/opt/dsh-widget"
UNIT_DIR="$HOME_DIR/.config/systemd/user"
BUILD_DIR="$ROOT/.build"

echo "==> Plasma AI Plasmoids installer"
echo "    Home: $HOME_DIR"

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少命令: $1" >&2; exit 1; }; }
need cmake
need python3

# 1. Build the two QML bridge plugins if a C++ compiler + Qt6 are available.
build_bridge() {
    local prefix="$1" src="$2" name="$3"
    local b="$BUILD_DIR/$name"
    mkdir -p "$b/bridge"
    cp "$src" "$b/bridge/${name}.cpp"
    cp "$ROOT/bridge/${prefix}-${name}.h" "$b/bridge/${name}.h"
    cp "$ROOT/bridge/${prefix}-Dummy.qml" "$b/bridge/Dummy.qml"
    cp "$ROOT/bridge/${prefix}-CMakeLists.txt" "$b/bridge/CMakeLists.txt"
    cmake -S "$b/bridge" -B "$b/out" -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$b/out" -j"$(nproc)" >/dev/null
    local so="$b/out/${name}/lib${name}plugin.so"
    [ -f "$so" ] || so="$(find "$b/out" -name 'lib*plugin.so' | head -1)"
    echo "$so"
}

DSH_SO=""
WB_SO=""
if command -v g++ >/dev/null 2>&1; then
    DSH_SO="$(build_bridge dsh "$ROOT/bridge/dsh-dshbridge.cpp" dshbridge || true)"
    WB_SO="$(build_bridge wb "$ROOT/bridge/wb-wbbridge.cpp" wbbridge || true)"
else
    echo "    [skip] 未检测到 g++，跳过插件编译"
fi

# 2. Substitute @USER_HOME@ in a staged copy, then install each package.
echo "==> 部署四个 Plasmoid 包"
STAGE="$BUILD_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
for pkg in org.dean.dsh.usage.widget org.dean.dsh.chat.widget \
           org.dean.workbuddy.usage.widget org.dean.workbuddy.chat.widget; do
    mkdir -p "$STAGE/$pkg"
    (cd "$ROOT/plasmoids/$pkg" && tar cf - .) | (cd "$STAGE/$pkg" && tar xf -)
    # Replace placeholder everywhere in the staged text files.
    grep -rlZ '@USER_HOME@' "$STAGE/$pkg" 2>/dev/null | xargs -0 -r sed -i "s#@USER_HOME@#$HOME_DIR#g"

    # Drop the compiled plugin into this package's self-contained directory.
    short="dsh"; so="$DSH_SO"
    case "$pkg" in *workbuddy*) short="wb"; so="$WB_SO";; esac
    if [ -n "${so:-}" ] && [ -f "$so" ]; then
        target="$STAGE/$pkg/contents/ui/org/dean/$short"
        mkdir -p "$target"
        cp "$so" "$target/"
        base="$(basename "$so" plugin.so)"
        cp "$(dirname "$so")/${base}.so" "$target/" 2>/dev/null || true
    fi
done
mkdir -p "$PLASMOIDS_DIR"
for pkg in org.dean.dsh.usage.widget org.dean.dsh.chat.widget \
           org.dean.workbuddy.usage.widget org.dean.workbuddy.chat.widget; do
    rm -rf "$PLASMOIDS_DIR/$pkg"
    cp -a "$STAGE/$pkg" "$PLASMOIDS_DIR/$pkg"
done

# 3. Install helpers and systemd user unit.
echo "==> 部署 helper 脚本与 service"
mkdir -p "$OPT_DIR" "$UNIT_DIR" "$STATE_DIR"
for f in dsh-usage.py wb-usage.py wb-summary.py; do
    sed "s#@USER_HOME@#$HOME_DIR#g" "$ROOT/helpers/$f" > "$OPT_DIR/$f"
    chmod +x "$OPT_DIR/$f"
done
sed "s#@USER_HOME@#$HOME_DIR#g" "$ROOT/helpers/dsh-summary.service" > "$UNIT_DIR/dsh-summary.service"

# 4. Refresh caches and (best effort) reload the user service.
echo "==> 刷新缓存"
kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
systemctl --user daemon-reload >/dev/null 2>&1 || true
systemctl --user restart dsh-summary.service >/dev/null 2>&1 || true
echo "完成。请重启 Plasmashell (或重新登录) 后在桌面添加组件。"
