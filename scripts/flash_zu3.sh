#!/usr/bin/env bash
# One-click PYNQ image download and microSD flashing for the AUP-ZU3 on Ubuntu.
# Run: bash scripts/flash_zu3.sh --help
set -euo pipefail

readonly PYNQ_VERSION=3.1.1
readonly BASE_URL=https://download.amd.com/opendownload/pynq
# Refuse bigger disks unless --allow-large: a card this large is rare, an external drive is not.
readonly MAX_CARD_BYTES=$((256 * 1000 * 1000 * 1000))

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DOWNLOAD_DIR="$REPO_DIR/downloads"

UI_LANG=""
VARIANT=""
DEVICE=""
ZIP_FILE=""
VERIFY=1
ALLOW_LARGE=0
KEEPALIVE_PID=""

t() { if [[ "$UI_LANG" == zh ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
say() { printf '%s\n' "$(t "$1" "$2")"; }
step() { printf '\n==== %s ====\n' "$(t "$1" "$2")"; }
die() { printf '\n[%s] %s\n' "$(t ERROR 错误)" "$(t "$1" "$2")" >&2; exit 1; }

ask() { # ask VAR "english prompt" "chinese prompt"
    local __reply
    read -r -p "$(t "$2" "$3") " __reply || die "No input available. Run this in a terminal." "没有可用的输入，请在终端里运行。"
    printf -v "$1" '%s' "$__reply"
}

usage() {
    cat <<EOF
Download the AUP-ZU3 PYNQ v$PYNQ_VERSION image and write it to a microSD card.

Usage: bash scripts/flash_zu3.sh [options]

  --variant 4gb|8gb   Board memory, printed on the board as "4G" or "8G"
  --device /dev/sdX   Card to write (default: choose from a list)
  --zip FILE          Use an image zip you already downloaded
  --no-verify         Skip reading the card back after writing
  --allow-large       Allow disks larger than 256 GB
  --lang en|zh        Language of the messages
  -h, --help          Show this help
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --variant) VARIANT=${2:-}; shift 2 ;;
            --device) DEVICE=${2:-}; shift 2 ;;
            --zip) ZIP_FILE=${2:-}; shift 2 ;;
            --lang) UI_LANG=${2:-}; shift 2 ;;
            --no-verify) VERIFY=0; shift ;;
            --allow-large) ALLOW_LARGE=1; shift ;;
            -h | --help) usage; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
    done
    case "$UI_LANG" in "" | en | zh) ;; *) usage >&2; exit 2 ;; esac
    case "$VARIANT" in "" | 4gb | 8gb) ;; *) usage >&2; exit 2 ;; esac
}

choose_language() {
    [[ -n "$UI_LANG" ]] && return 0
    local reply=""
    read -r -p "Language / 语言: [1] English (default)  [2] 中文 : " reply || true
    if [[ "$reply" == 2 ]]; then UI_LANG=zh; else UI_LANG=en; fi
}

choose_variant() {
    while [[ -z "$VARIANT" ]]; do
        say 'Look at your board: next to the memory chips it is marked "4G" or "8G".' \
            '请看开发板：内存芯片旁边印有 “4G” 或 “8G”。'
        local reply
        ask reply "Which one is printed on your board? [4/8]:" "你的板子上印的是哪个？[4/8]："
        case "$reply" in
            4 | 4g | 4G | 4gb | 4GB) VARIANT=4gb ;;
            8 | 8g | 8G | 8gb | 8GB) VARIANT=8gb ;;
        esac
    done
}

# Size and checksum of AMD's published files, recorded on 2026-11-03. AMD publishes no
# checksums of its own, so a mismatch means a damaged download or a re-released file.
load_variant_info() {
    case "$VARIANT" in
        4gb) ZIP_SIZE=2204633663 IMG_SIZE=9755315200
             ZIP_SHA256=b21dd5daab6c835cfc43140180a5a267ac2b43697b51d3a02b9f6288e77ca3fb ;;
        8gb) ZIP_SIZE=2204637418 IMG_SIZE=9755336704
             ZIP_SHA256=c995d48a1184452be1b18faaf492e8b46100cd29afa100cb83cf670662648b9f ;;
    esac
    ZIP_NAME="AUP-ZU3-$PYNQ_VERSION-$VARIANT.zip"
    IMG_NAME="AUP-ZU3-$PYNQ_VERSION-$VARIANT.img"
}

ensure_tools() {
    local missing=() tool
    for tool in curl unzip; do
        command -v "$tool" >/dev/null || missing+=("$tool")
    done
    ((${#missing[@]})) || return 0
    say "Installing the missing tools: ${missing[*]}" "正在安装缺少的工具：${missing[*]}"
    sudo apt-get update
    sudo apt-get install -y "${missing[@]}"
}

is_block_device() { [[ -b "$1" ]]; }
blk_field() { lsblk -dnbo "$2" "$1" 2>/dev/null | sed -e 's/^ *//' -e 's/ *$//'; }
human_size() { numfmt --to=si --suffix=B "$1"; }

# True when the disk holds anything the running system depends on.
is_system_disk() {
    local mount
    while IFS= read -r mount; do
        case "$mount" in
            / | /boot | /boot/* | /home | /home/* | /usr | /usr/* | /var | /var/* | "[SWAP]") return 0 ;;
        esac
    done < <(lsblk -nro MOUNTPOINT "$1" 2>/dev/null)
    return 1
}

# Lists whole disks that look like an SD card: USB readers, removable disks, built-in SD slots.
list_cards() {
    local name type dev
    while read -r name type; do
        [[ "$type" == disk ]] || continue
        dev="/dev/$name"
        if [[ "$name" == mmcblk* ]]; then
            [[ "$(cat "/sys/block/$name/device/type" 2>/dev/null)" == SD ]] || continue
        elif [[ "$(blk_field "$dev" RM)" != 1 && "$(blk_field "$dev" TRAN)" != usb ]]; then
            continue
        fi
        [[ "$(blk_field "$dev" SIZE)" -gt 0 ]] 2>/dev/null || continue
        is_system_disk "$dev" && continue
        printf '%s\n' "$dev"
    done < <(lsblk -dnro NAME,TYPE)
}

check_target() {
    local dev=$1 size
    is_block_device "$dev" || die "$dev is not a disk." "$dev 不是磁盘。"
    [[ "$(blk_field "$dev" TYPE)" == disk ]] ||
        die "$dev is a partition. Choose the whole card, such as /dev/sdb rather than /dev/sdb1." \
            "$dev 是分区，请选择整张卡，例如 /dev/sdb 而不是 /dev/sdb1。"
    is_system_disk "$dev" && die "$dev holds your running system. Refusing to touch it." \
        "$dev 上装着正在运行的系统，已拒绝操作。"
    [[ "$(blk_field "$dev" RO)" == 0 ]] ||
        die "$dev is read-only. If your card adapter has a lock switch, slide it to unlocked." \
            "$dev 是只读的。如果读卡器或卡套上有锁定开关，请拨到解锁位置。"
    size=$(blk_field "$dev" SIZE)
    ((size >= IMG_SIZE)) ||
        die "$dev has $(human_size "$size"), the image needs $(human_size "$IMG_SIZE"). Use a 16 GB or larger card." \
            "$dev 容量为 $(human_size "$size")，镜像需要 $(human_size "$IMG_SIZE")。请使用 16 GB 或更大的卡。"
    ((size <= MAX_CARD_BYTES || ALLOW_LARGE)) ||
        die "$dev has $(human_size "$size"), which looks like a drive rather than a card. Use --allow-large if you are sure." \
            "$dev 容量为 $(human_size "$size")，看起来是硬盘而不是存储卡。如果确定无误，请加 --allow-large。"
}

describe_disk() {
    local dev=$1
    printf '%s  %s  %s %s' "$dev" "$(human_size "$(blk_field "$dev" SIZE)")" \
        "$(blk_field "$dev" VENDOR)" "$(blk_field "$dev" MODEL)"
}

choose_device() {
    if [[ -n "$DEVICE" ]]; then
        check_target "$DEVICE"
        return 0
    fi
    while true; do
        local cards=() i reply
        mapfile -t cards < <(list_cards)
        if ((${#cards[@]} == 0)); then
            ask reply "No SD card found. Insert the card, then press Enter to look again (q to quit):" \
                "没有找到 SD 卡。请插入存储卡，然后按回车重新查找（输入 q 退出）："
            [[ "$reply" == q ]] && exit 1
            sleep 2
            continue
        fi
        say "These disks look like SD cards:" "以下磁盘看起来是 SD 卡："
        for i in "${!cards[@]}"; do
            printf '  [%d] %s\n' "$((i + 1))" "$(describe_disk "${cards[$i]}")"
        done
        ask reply "Number of your card (Enter to look again):" "请输入存储卡的编号（按回车重新查找）："
        if [[ "$reply" =~ ^[0-9]+$ ]] && ((reply >= 1 && reply <= ${#cards[@]})); then
            DEVICE=${cards[$((reply - 1))]}
            check_target "$DEVICE"
            return 0
        fi
    done
}

confirm_erase() {
    local reply
    say "" ""
    say "EVERYTHING on this disk will be permanently erased:" "这块磁盘上的所有数据都将被永久清除："
    printf '  %s\n' "$(describe_disk "$DEVICE")"
    lsblk -no NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$DEVICE" | sed 's/^/    /'
    ask reply "Type ERASE to continue:" "确认无误请输入 ERASE 继续："
    [[ "$reply" == ERASE ]] || die "Cancelled. Nothing was changed." "已取消，未做任何更改。"
    DEVICE_ID="$(blk_field "$DEVICE" SIZE)|$(blk_field "$DEVICE" SERIAL)"
}

start_sudo_keepalive() {
    say "Writing to a disk needs administrator rights, so sudo may ask for your password." \
        "写入磁盘需要管理员权限，sudo 可能会要求输入你的登录密码（输入时不显示字符，属正常现象）。"
    sudo -v
    # The download can outlast sudo's password timeout.
    (while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done) &
    KEEPALIVE_PID=$!
}

sha_ok() { [[ "$(sha256sum "$1" | cut -d' ' -f1)" == "$ZIP_SHA256" ]]; }

prepare_zip() {
    if [[ -n "$ZIP_FILE" ]]; then
        [[ -f "$ZIP_FILE" ]] || die "File not found: $ZIP_FILE" "找不到文件：$ZIP_FILE"
        say "Checking $ZIP_FILE ..." "正在校验 $ZIP_FILE ..."
        sha_ok "$ZIP_FILE" || die "$ZIP_FILE is not the official $ZIP_NAME." "$ZIP_FILE 不是官方的 $ZIP_NAME。"
        return 0
    fi

    mkdir -p "$DOWNLOAD_DIR"
    ZIP_FILE="$DOWNLOAD_DIR/$ZIP_NAME"
    local have=0 avail
    [[ -f "$ZIP_FILE" ]] && have=$(stat -c %s "$ZIP_FILE")
    if ((have > ZIP_SIZE)); then
        rm -f "$ZIP_FILE"
        have=0
    fi
    if ((have < ZIP_SIZE)); then
        avail=$(df --output=avail -B1 "$DOWNLOAD_DIR" | tail -n1 | tr -d ' ')
        ((avail >= ZIP_SIZE - have)) ||
            die "Not enough free disk space: the download needs $(human_size "$((ZIP_SIZE - have))")." \
                "磁盘空间不足：下载还需要 $(human_size "$((ZIP_SIZE - have))")。"
        say "Downloading $ZIP_NAME ($(human_size "$ZIP_SIZE")). If this stops, run the script again and it will resume." \
            "正在下载 $ZIP_NAME（$(human_size "$ZIP_SIZE")）。如果中断，重新运行脚本即可继续下载。"
        curl -L --fail --retry 5 --retry-delay 5 -C - -o "$ZIP_FILE" "$BASE_URL/$ZIP_NAME" ||
            die "The download failed. Check your network and run the script again." \
                "下载失败。请检查网络后重新运行脚本。"
    fi
    say "Checking the download ..." "正在校验下载的文件 ..."
    if ! sha_ok "$ZIP_FILE"; then
        rm -f "$ZIP_FILE"
        die "The downloaded file is damaged and was deleted. Run the script again. If this keeps happening, AMD may have re-released the image: follow the manual steps in the guide and tell your TA." \
            "下载的文件已损坏并已删除，请重新运行脚本。如果反复出现，可能是 AMD 重新发布了镜像：请按指引中的手动步骤操作并告知助教。"
    fi
}

recheck_device() {
    [[ "$(blk_field "$DEVICE" SIZE)|$(blk_field "$DEVICE" SERIAL)" == "$DEVICE_ID" ]] ||
        die "$DEVICE changed while the image was downloading. Check the card and run the script again; the download is kept." \
            "下载期间 $DEVICE 发生了变化。请检查存储卡后重新运行脚本，已下载的文件会保留。"
}

unmount_partitions() {
    local part
    while read -r part; do
        [[ -n "$part" ]] && sudo umount "$part"
    done < <(lsblk -nro PATH,MOUNTPOINT "$DEVICE" | awk 'NF == 2 { print $1 }')
}

# Runs as root. The flock keeps udev from probing the new partitions until the read-back is
# done; an auto-mount in between would change the ext4 superblock and fail the comparison.
readonly WRITER_SCRIPT='
set -euo pipefail
zip=$1 entry=$2 dev=$3 size=$4 verify=$5 msg_write=$6 msg_verify=$7 msg_bad=$8
exec 9<"$dev"
flock -x 9
echo "$msg_write"
unzip -p "$zip" "$entry" | dd of="$dev" bs=4M iflag=fullblock oflag=direct conv=fsync status=progress
sync
blockdev --flushbufs "$dev"
if [ "$verify" = 1 ]; then
    echo "$msg_verify"
    cmp -n "$size" <(unzip -p "$zip" "$entry") <(dd if="$dev" bs=4M iflag=direct status=progress) || {
        echo "$msg_bad" >&2
        exit 3
    }
fi
'

write_card() {
    local rc=0
    sudo bash -c "$WRITER_SCRIPT" _ "$ZIP_FILE" "$IMG_NAME" "$DEVICE" "$IMG_SIZE" "$VERIFY" \
        "$(t "Writing the card, usually 5-15 minutes ..." "正在写入存储卡，通常需要 5-15 分钟 ...")" \
        "$(t "Reading the card back to check it, usually 5-10 minutes ..." "正在回读校验存储卡，通常需要 5-10 分钟 ...")" \
        "$(t "The card does not match the image: it is faulty or fake. Try a different card." "存储卡内容与镜像不一致：卡可能已损坏或是扩容假卡，请换一张卡。")" || rc=$?
    ((rc == 0)) || die "Writing failed (code $rc). Do not boot from this card. Re-insert it and try again, or try a different card." \
        "写入失败（代码 $rc）。请不要用这张卡启动。重新插入后再试，或换一张卡。"
}

finish_card() {
    # The desktop may auto-mount the new partitions as soon as the lock is released.
    sudo udevadm settle --timeout=10 || true
    sleep 2
    unmount_partitions || true
    sync
    sudo eject "$DEVICE" 2>/dev/null || true
}

cleanup() {
    [[ -z "$KEEPALIVE_PID" ]] || kill "$KEEPALIVE_PID" 2>/dev/null || true
}

main() {
    parse_args "$@"
    choose_language
    step "AUP-ZU3 PYNQ image v$PYNQ_VERSION" "AUP-ZU3 PYNQ 镜像 v$PYNQ_VERSION"
    trap cleanup EXIT

    step "Step 1 of 4: choose your board" "第 1/4 步：选择开发板"
    choose_variant
    load_variant_info
    say "Image: $IMG_NAME" "镜像：$IMG_NAME"

    step "Step 2 of 4: choose your card" "第 2/4 步：选择存储卡"
    ensure_tools
    choose_device
    confirm_erase
    start_sudo_keepalive

    step "Step 3 of 4: get the image" "第 3/4 步：获取镜像"
    say "You can leave this running from here on. Nothing else needs your input." \
        "从这里开始无需再操作，可以让它自动运行。"
    prepare_zip

    step "Step 4 of 4: write the card" "第 4/4 步：写入存储卡"
    recheck_device
    unmount_partitions
    write_card
    finish_card

    step "Done" "完成"
    say "The card is ready, and it is safe to remove it. Next: follow the \"Boot the board\" section of the guide." \
        "存储卡已写好，可以安全拔出。下一步：请按指引中的“启动开发板”一节操作。"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
