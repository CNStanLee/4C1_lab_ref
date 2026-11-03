#!/usr/bin/env bash
# Finds the AUP-ZU3 serial port, fixes its permissions, and opens it in COMTool on Ubuntu.
# Run: bash scripts/serial_zu3.sh --help
set -euo pipefail

readonly COMTOOL_VERSION=3.4.1
readonly COMTOOL_ARCHIVE="comtool_ubuntu_20.04_v$COMTOOL_VERSION.tar.xz"
readonly COMTOOL_URL="https://github.com/Neutree/COMTool/releases/download/v$COMTOOL_VERSION/$COMTOOL_ARCHIVE"
readonly COMTOOL_SHA256=2feb04d015d081d425f50863e46d386b7e5889cc7bec6a7a567728b711d55e46
# The board's FT2232 has two channels: interface 00 is JTAG, interface 01 is the UART.
readonly ZU3_USB_ID=0403:6010
readonly ZU3_UART_INTERFACE=01
readonly UDEV_RULE_FILE=/etc/udev/rules.d/70-aup-zu3-serial.rules # uaccess needs a name below 73
readonly WAIT_SECONDS=120

USER=${USER:-$(id -un)}
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS_DIR="$REPO_DIR/.tools"
LOG_DIR="$REPO_DIR/logs"
COMTOOL_BIN="$TOOLS_DIR/comtool/comtool"

UI_LANG=""
PORT=""
BAUD=115200
LIST_ONLY=0
CLI_MODE=0

t() { if [[ "$UI_LANG" == zh ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
say() { printf '%s\n' "$(t "$1" "$2")"; }
die() { printf '\n[%s] %s\n' "$(t ERROR 错误)" "$(t "$1" "$2")" >&2; exit 1; }

usage() {
    cat <<EOF
Find the AUP-ZU3 serial port, fix its permissions, and open it in COMTool.

Usage: bash scripts/serial_zu3.sh [options]

  --list          Only show the serial ports and whether you can open them
  --port DEVICE   Use this port instead of detecting it, such as /dev/ttyUSB1
  --baud RATE     Baud rate (default: 115200)
  --cli           Use the picocom terminal instead of the COMTool window
  --lang en|zh    Language of the messages
  -h, --help      Show this help
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --port) PORT=${2:-}; shift 2 ;;
            --baud) BAUD=${2:-}; shift 2 ;;
            --lang) UI_LANG=${2:-}; shift 2 ;;
            --list) LIST_ONLY=1; shift ;;
            --cli) CLI_MODE=1; shift ;;
            -h | --help) usage; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
    done
    case "$UI_LANG" in "" | en | zh) ;; *) usage >&2; exit 2 ;; esac
    [[ "$BAUD" =~ ^[0-9]+$ ]] || { usage >&2; exit 2; }
}

choose_language() {
    [[ -n "$UI_LANG" ]] && return 0
    local reply=""
    read -r -p "Language / 语言: [1] English (default)  [2] 中文 : " reply || true
    if [[ "$reply" == 2 ]]; then UI_LANG=zh; else UI_LANG=en; fi
}

list_ports() {
    compgen -G '/dev/ttyUSB*' || true
    compgen -G '/dev/ttyACM*' || true
}

port_prop() { # port_prop DEVICE KEY...: the first of these udev properties that is set
    local dev=$1 key value props
    shift
    props=$(udevadm info -q property -n "$dev" 2>/dev/null || true)
    for key in "$@"; do
        value=$(sed -n "s/^$key=//p" <<<"$props" | head -n1)
        if [[ -n "$value" ]]; then
            printf '%s' "$value"
            return 0
        fi
    done
}

port_usb_id() {
    printf '%s:%s' "$(port_prop "$1" ID_USB_VENDOR_ID ID_VENDOR_ID)" "$(port_prop "$1" ID_USB_MODEL_ID ID_MODEL_ID)"
}
port_interface() { port_prop "$1" ID_USB_INTERFACE_NUM; }
port_is_zu3_uart() { [[ "$(port_usb_id "$1")" == "$ZU3_USB_ID" && "$(port_interface "$1")" == "$ZU3_UART_INTERFACE" ]]; }
port_access_ok() { [[ -r "$1" && -w "$1" ]]; }

port_role() {
    if [[ "$(port_usb_id "$1")" != "$ZU3_USB_ID" ]]; then
        t "other device" "其他设备"
    elif [[ "$(port_interface "$1")" == "$ZU3_UART_INTERFACE" ]]; then
        t "AUP-ZU3 UART (boot log)" "AUP-ZU3 串口（启动日志）"
    else
        t "AUP-ZU3 JTAG (not for logs)" "AUP-ZU3 JTAG（不是日志口）"
    fi
}

print_ports() {
    local port access
    say "Serial ports found:" "检测到的串口："
    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        if port_access_ok "$port"; then access=$(t "can open" "可打开"); else access=$(t "no permission" "无权限"); fi
        printf '  %-14s %-10s %s  [%s]\n' "$port" "$(port_usb_id "$port")" "$(port_role "$port")" "$access"
    done < <(list_ports)
}

# Called while waiting: explains why a board that is plugged in has no serial port.
explain_missing_port() {
    command -v lsusb >/dev/null && lsusb -d "$ZU3_USB_ID" >/dev/null 2>&1 || return 0
    say "The board's USB chip is connected, but Linux made no serial port for it. Loading the driver ..." \
        "已检测到开发板的 USB 芯片，但系统没有为它创建串口，正在加载驱动 ..."
    sudo modprobe ftdi_sio || true
    if systemctl is-active --quiet brltty 2>/dev/null; then
        say "The brltty braille service is running and can take over USB serial ports. If no port appears, run: sudo apt remove brltty" \
            "brltty 盲文服务正在运行，它可能占用 USB 串口。如果仍没有串口，请运行：sudo apt remove brltty"
    fi
}

wait_for_ports() {
    local waited=0 explained=0
    [[ -z "$(list_ports)" ]] || return 0
    say "No serial port yet. Connect a USB-C cable from your computer to the port marked PROG UART, and power the board on. Waiting ..." \
        "还没有串口。请用 USB-C 线连接电脑和板上标有 PROG UART 的接口，并打开开发板电源。正在等待 ..."
    while [[ -z "$(list_ports)" ]]; do
        ((waited < WAIT_SECONDS)) || die "No serial port appeared. See \"Troubleshooting\" in the guide." \
            "没有出现串口。请查看指引中的“常见问题”。"
        if ((waited == 10 && !explained)); then
            explain_missing_port
            explained=1
        fi
        sleep 2
        waited=$((waited + 2))
    done
    sleep 1 # let udev finish creating the second channel and applying permissions
}

choose_port() {
    if [[ -n "$PORT" ]]; then
        [[ -e "$PORT" ]] || die "$PORT does not exist." "$PORT 不存在。"
        return 0
    fi
    wait_for_ports

    local all=() uarts=() port candidates i reply
    mapfile -t all < <(list_ports)
    for port in "${all[@]}"; do
        port_is_zu3_uart "$port" && uarts+=("$port")
    done
    if ((${#uarts[@]} == 1)); then
        PORT=${uarts[0]}
        say "Found the AUP-ZU3 serial port: $PORT" "已找到 AUP-ZU3 串口：$PORT"
        return 0
    fi
    if ((${#uarts[@]} > 1)); then
        say "More than one AUP-ZU3 is connected." "连接了多块 AUP-ZU3。"
        candidates=("${uarts[@]}")
    else
        say "No AUP-ZU3 was recognised. Is the cable in the port marked PROG UART? You can still pick a port:" \
            "没有识别到 AUP-ZU3。线是否插在 PROG UART 接口上？也可以手动选择一个串口："
        candidates=("${all[@]}")
    fi
    for i in "${!candidates[@]}"; do
        printf '  [%d] %s  %s\n' "$((i + 1))" "${candidates[$i]}" "$(port_role "${candidates[$i]}")"
    done
    read -r -p "$(t "Number of the port to open:" "请输入要打开的串口编号：") " reply ||
        die "No input available. Use --port to name the port." "没有可用的输入，请用 --port 指定串口。"
    [[ "$reply" =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= ${#candidates[@]})) ||
        die "Not a valid number." "编号无效。"
    PORT=${candidates[$((reply - 1))]}
}

install_udev_rule() {
    sudo tee "$UDEV_RULE_FILE" >/dev/null <<EOF
# AUP-ZU3 PROG UART: let the logged-in user open it, and keep ModemManager away from it.
SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", TAG+="uaccess", ENV{ID_MM_DEVICE_IGNORE}="1"
EOF
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=tty --action=change
    sudo udevadm settle --timeout=5 || true
}

fix_permissions() {
    port_access_ok "$PORT" && return 0
    say "You do not have permission to open $PORT yet. Fixing that now; sudo may ask for your password." \
        "你还没有打开 $PORT 的权限，现在开始修复；sudo 可能会要求输入你的登录密码（输入时不显示字符）。"
    id -nG "$USER" | tr ' ' '\n' | grep -qx dialout || sudo usermod -aG dialout "$USER"
    [[ "$(port_usb_id "$PORT")" != "$ZU3_USB_ID" ]] || install_udev_rule
    # Group membership only counts after the next login, so grant this session access as well.
    port_access_ok "$PORT" || sudo setfacl -m "u:$USER:rw" "$PORT" || true
    port_access_ok "$PORT" || die "Still no permission on $PORT. Log out, log back in, and try again." \
        "仍然没有 $PORT 的权限。请注销并重新登录后再试。"
    say "Permission granted, and it stays in place for next time." "权限已获取，以后无需再次设置。"
}

warn_if_busy() {
    local pids
    pids=$(fuser "$PORT" 2>/dev/null | xargs) || true
    [[ -n "$pids" ]] || return 0
    say "Warning: another program is using $PORT, and the two would split the log between them. Close it first:" \
        "警告：另一个程序正在使用 $PORT，两者会互相抢占日志数据。请先关闭它："
    # shellcheck disable=SC2086
    ps -o pid=,comm= -p $pids | sed 's/^/  /' || true
}

install_comtool() {
    [[ -x "$COMTOOL_BIN" ]] && return 0
    command -v curl >/dev/null || { sudo apt-get update; sudo apt-get install -y curl; }
    local archive="$TOOLS_DIR/$COMTOOL_ARCHIVE"
    mkdir -p "$TOOLS_DIR"
    say "Downloading COMTool $COMTOOL_VERSION (first run only) ..." "正在下载 COMTool $COMTOOL_VERSION（仅首次运行需要）..."
    curl -L --fail --retry 3 -o "$archive" "$COMTOOL_URL" ||
        die "The COMTool download failed. Check your network, or use --cli." "COMTool 下载失败。请检查网络，或使用 --cli。"
    if [[ "$(sha256sum "$archive" | cut -d' ' -f1)" != "$COMTOOL_SHA256" ]]; then
        rm -f "$archive"
        die "The COMTool download is damaged. Run the script again." "COMTool 下载文件已损坏，请重新运行脚本。"
    fi
    tar xf "$archive" -C "$TOOLS_DIR"
    rm -f "$archive"
    # Everything else COMTool needs is in the archive; only libGL may be absent from a minimal install.
    ldconfig -p | grep -q 'libGL\.so\.1' || sudo apt-get install -y libgl1
}

# Fills in COMTool's config so that it opens on this port and saves the log to a file. Its
# serial settings only accept known keys: anything unexpected there stops it from starting.
write_comtool_config() {
    mkdir -p "$LOG_DIR"
    command -v python3 >/dev/null || return 0
    python3 -I - "$HOME/.config/comtool/config.json" "$PORT" "$BAUD" "$LOG_DIR/zu3.log" "$UI_LANG" <<'EOF'
import json, os, sys

path, port, baud, log_path, ui_lang = sys.argv[1:]
config = None
try:
    with open(path, encoding="utf-8") as f:
        config = json.load(f)
except (OSError, ValueError):
    pass
if not isinstance(config, dict) or config.get("version") != 3:
    config = {
        "version": 3, "skin": "light", "locale": "en", "encoding": "UTF-8", "skipVersion": None,
        "connId": "serial", "pluginsInfo": {"external": {}}, "activeItem": "dbg-1",
        "currItem": None, "items": [],
    }
config["locale"] = "zh_CN" if ui_lang == "zh" else "en"
item = next((i for i in config["items"] if i.get("pluginId") == "dbg"), None)
if item is None:
    item = {"name": "Send Receive", "pluginId": "dbg", "config": {"conns": {}, "plugin": {}}}
    config["items"].insert(0, item)
conns = item["config"]["conns"]
conns["currConn"] = "serial"
conns.setdefault("serial", {}).update(port=port, baudrate=int(baud))
item["config"]["plugin"].update(saveLog=True, saveLogAutoNew=True, saveLogPath=log_path)
config["currItem"] = item["name"]
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
EOF
}

print_next_steps() {
    say "" ""
    say "Port $PORT at $BAUD baud. In COMTool:" "串口 $PORT，波特率 $BAUD。在 COMTool 中："
    say "  1. Check that the Port box shows $PORT, then click OPEN." "  1. 确认 Port（端口）一栏显示 $PORT，然后点击 OPEN（打开）。"
    say "  2. Press the board's reset button to see the log from the very start." "  2. 按开发板上的复位键，即可从头查看启动日志。"
    say "  Logs are saved in $LOG_DIR" "  日志保存在 $LOG_DIR"
}

run_cli() {
    command -v picocom >/dev/null || { sudo apt-get update; sudo apt-get install -y picocom; }
    mkdir -p "$LOG_DIR"
    local log="$LOG_DIR/zu3_$(date +%Y%m%d_%H%M%S).log"
    say "Log file: $log. To quit, press Ctrl+A and then Ctrl+X. Press the board's reset button to see the log from the start." \
        "日志文件：$log。退出请按 Ctrl+A 再按 Ctrl+X。按开发板上的复位键可从头查看启动日志。"
    exec picocom -b "$BAUD" --logfile "$log" "$PORT"
}

run_comtool() {
    if [[ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        say "There is no graphical desktop here, so using the terminal instead of COMTool." \
            "当前没有图形桌面，改用终端方式。"
        run_cli
    fi
    install_comtool
    write_comtool_config
    print_next_steps
    local rc=0
    (cd "$TOOLS_DIR/comtool" && exec "$COMTOOL_BIN") || rc=$?
    ((rc == 0)) || die "COMTool stopped with an error (code $rc). Run this script again with --cli to use the terminal instead." \
        "COMTool 异常退出（代码 $rc）。请加上 --cli 重新运行，改用终端方式。"
}

main() {
    parse_args "$@"
    choose_language
    if ((LIST_ONLY)); then
        print_ports
        return 0
    fi
    choose_port
    fix_permissions
    warn_if_busy
    if ((CLI_MODE)); then run_cli; else run_comtool; fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
