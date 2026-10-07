#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="OU-SB"
APP_VERSION="2.0.0"
AUTHOR="nodeseek @cshaizhihao"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/cshaizhihao/OU-SB/main/OU-SB.sh"

OU_SB_ROOT="${OU_SB_ROOT:-}"
APP_DIR="${OU_SB_APP_DIR:-${OU_SB_ROOT}/etc/ou-sb}"
SB_DIR="${OU_SB_SB_DIR:-${OU_SB_ROOT}/etc/sing-box}"
CONFIG_PATH="${OU_SB_CONFIG_PATH:-$SB_DIR/config.json}"
STATE_PATH="${OU_SB_STATE_PATH:-$APP_DIR/state.json}"
BACKUP_DIR="${OU_SB_BACKUP_DIR:-$APP_DIR/backups}"
LOCK_PATH="${OU_SB_LOCK_PATH:-$APP_DIR/ou-sb.lock}"
CERT_DIR="${OU_SB_CERT_DIR:-$APP_DIR/certs}"
INSTALL_DIR="${OU_SB_INSTALL_DIR:-${OU_SB_ROOT}/usr/local/lib/ou-sb}"
INSTALL_PATH="$INSTALL_DIR/OU-SB.sh"
COMMAND_PATH="${OU_SB_COMMAND_PATH:-${OU_SB_ROOT}/usr/local/bin/sb}"
SYSTEMD_DIR="${OU_SB_SYSTEMD_DIR:-${OU_SB_ROOT}/etc/systemd/system}"
OPENRC_DIR="${OU_SB_OPENRC_DIR:-${OU_SB_ROOT}/etc/init.d}"
SERVICE_NAME="sing-box"

TAG_SS="ou-sb-ss"
TAG_HY2="ou-sb-hy2"
TAG_TUIC="ou-sb-tuic"
TAG_VLESS="ou-sb-vless-reality"
TAG_ANYTLS="ou-sb-anytls-reality"
TAG_SNELL="ou-sb-snell"

OS_FAMILY="unknown"
INIT_SYSTEM="unknown"
init_colors() {
    if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_CYAN=$'\033[38;5;44m'
        C_BLUE=$'\033[38;5;39m'
        C_GREEN=$'\033[38;5;42m'
        C_YELLOW=$'\033[38;5;214m'
        C_RED=$'\033[38;5;196m'
        C_MUTED=$'\033[38;5;245m'
    else
        C_RESET="" C_BOLD="" C_CYAN="" C_BLUE="" C_GREEN=""
        C_YELLOW="" C_RED="" C_MUTED=""
    fi
}

info() { printf '%s[INFO]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok() { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf '%s[ERR ]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

banner() {
    if [[ -t 1 ]]; then
        clear || true
    fi
    printf '%s%s' "$C_CYAN" "$C_BOLD"
    cat <<'EOF'
   ____  __  __      _____ ____
  / __ \/ / / /     / ___// __ )
 / / / / / / /______\__ \/ __  |
/ /_/ / /_/ /_____/___/ / /_/ /
\____/\____/     /_____/_____/
EOF
    printf '%s' "$C_RESET"
    printf '  %sSing-box 多协议管理工具%s  v%s\n' "$C_BOLD" "$C_RESET" "$APP_VERSION"
    printf '  作者：%s\n\n' "$AUTHOR"
}

detect_platform() {
    local id="" like=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id="${ID:-}"
        like="${ID_LIKE:-}"
    fi
    case " $id $like " in
        *alpine*) OS_FAMILY="alpine" ;;
        *debian*|*ubuntu*) OS_FAMILY="debian" ;;
        *rhel*|*fedora*|*centos*|*rocky*|*almalinux*) OS_FAMILY="redhat" ;;
        *) OS_FAMILY="unknown" ;;
    esac
    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        INIT_SYSTEM="openrc"
    fi
}

require_root() {
    [[ "${OU_SB_TESTING:-0}" == "1" ]] && return 0
    [[ $(id -u) -eq 0 ]] || die "请使用 root 用户运行"
}

install_dependencies() {
    local missing=0 command
    for command in curl jq openssl flock ss; do
        command -v "$command" >/dev/null 2>&1 || missing=1
    done
    [[ $missing -eq 0 ]] && return 0
    info "安装基础依赖"
    case "$OS_FAMILY" in
        alpine) apk add --no-cache bash curl jq openssl ca-certificates util-linux iproute2 ;;
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y bash curl jq openssl ca-certificates util-linux iproute2
            ;;
        redhat) dnf install -y bash curl jq openssl ca-certificates util-linux iproute || yum install -y bash curl jq openssl ca-certificates util-linux iproute ;;
        *) die "无法自动安装依赖，请先安装 bash、curl、jq、openssl、flock、ss" ;;
    esac
}

prepare_directories() {
    mkdir -p "$APP_DIR" "$SB_DIR" "$BACKUP_DIR" "$CERT_DIR" "$INSTALL_DIR"
    chmod 700 "$APP_DIR" "$BACKUP_DIR" "$CERT_DIR"
}

acquire_lock() {
    command -v flock >/dev/null 2>&1 || die "未找到 flock"
    exec 9>"$LOCK_PATH"
    flock -n 9 || die "另一个 OU-SB 操作正在运行"
}

init_state() {
    [[ -s "$STATE_PATH" ]] && jq -e . "$STATE_PATH" >/dev/null 2>&1 && return 0
    jq -n --arg author "$AUTHOR" '{
        schema: 1,
        owner: "OU-SB",
        author: $author,
        public_host: "",
        node_name: "OU-SB",
        config_adopted: false,
        hy2: {hop_ports: "", listen_port: 0, firewall_backend: ""},
        reality: {vless: {}, anytls: {}},
        snell: {client_version: 0, obfs: "none"}
    }' > "$STATE_PATH"
    chmod 600 "$STATE_PATH"
}

state_get() {
    jq -r "$1 // empty" "$STATE_PATH"
}

state_set_string() {
    local path=$1 value=$2 tmp
    tmp=$(mktemp "$APP_DIR/.state.XXXXXX")
    jq --arg path "$path" --arg value "$value" 'setpath($path | split("."); $value)' "$STATE_PATH" > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$STATE_PATH"
}

state_set_number() {
    local path=$1 value=$2 tmp
    tmp=$(mktemp "$APP_DIR/.state.XXXXXX")
    jq --arg path "$path" --argjson value "$value" 'setpath($path | split("."); $value)' "$STATE_PATH" > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$STATE_PATH"
}

state_set_boolean() {
    local path=$1 value=$2 tmp
    tmp=$(mktemp "$APP_DIR/.state.XXXXXX")
    jq --arg path "$path" --argjson value "$value" 'setpath($path | split("."); $value)' "$STATE_PATH" > "$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$STATE_PATH"
}

ensure_base_config() {
    if [[ -s "$CONFIG_PATH" ]]; then
        jq -e '.inbounds and .outbounds' "$CONFIG_PATH" >/dev/null 2>&1 || die "现有 sing-box 配置不是有效的 OU-SB 可管理结构"
        if [[ $(state_get '.config_adopted') != true ]]; then
            local answer foreign_count backup
            foreign_count=$(jq '[.inbounds[]? | select(((.tag // "") | startswith("ou-sb-")) | not)] | length' "$CONFIG_PATH")
            if ((foreign_count > 0)); then
                [[ -t 0 ]] || die "检测到非 OU-SB 配置，需要交互确认后才能管理"
                warn "检测到 $foreign_count 个非 OU-SB 入站；OU-SB 只会增删 ou-sb-* 标签"
                read -r -p "备份并保留现有配置，继续？[y/N]: " answer
                [[ $answer =~ ^[Yy]$ ]] || die "已取消"
                backup=$(backup_config)
                ok "现有配置已备份：$backup"
            fi
            state_set_boolean 'config_adopted' true
        fi
        return 0
    fi
    jq -n '{
        log: {level: "info", timestamp: true},
        inbounds: [],
        outbounds: [{type: "direct", tag: "direct-out"}]
    }' > "$CONFIG_PATH"
    chmod 600 "$CONFIG_PATH"
    state_set_boolean 'config_adopted' true
}

config_has_tag() {
    jq -e --arg tag "$1" '.inbounds[]? | select(.tag == $tag)' "$CONFIG_PATH" >/dev/null 2>&1
}

protocol_exists() {
    config_has_tag "$1"
}

backup_config() {
    local stamp target
    stamp="$(date '+%Y%m%d-%H%M%S')-$(rand_hex 3)"
    target="$BACKUP_DIR/config-$stamp.json"
    cp -p "$CONFIG_PATH" "$target"
    printf '%s\n' "$target"
}

validate_candidate() {
    local candidate=$1
    [[ "${OU_SB_FORCE_CHECK_FAIL:-0}" == "1" ]] && return 1
    jq -e . "$candidate" >/dev/null 2>&1 || return 1
    if [[ "${OU_SB_TESTING:-0}" == "1" ]]; then
        return 0
    fi
    command -v sing-box >/dev/null 2>&1 || return 1
    sing-box check -c "$candidate" >/dev/null 2>&1
}

service_restart() {
    [[ "${OU_SB_TESTING:-0}" == "1" ]] && return 0
    case "$INIT_SYSTEM" in
        systemd) systemctl restart "$SERVICE_NAME" ;;
        openrc) rc-service "$SERVICE_NAME" restart ;;
        *) return 1 ;;
    esac
}

service_start() {
    case "$INIT_SYSTEM" in
        systemd) systemctl start "$SERVICE_NAME" ;;
        openrc) rc-service "$SERVICE_NAME" start ;;
        *) return 1 ;;
    esac
}

service_stop() {
    case "$INIT_SYSTEM" in
        systemd) systemctl stop "$SERVICE_NAME" ;;
        openrc) rc-service "$SERVICE_NAME" stop ;;
        *) return 1 ;;
    esac
}

service_status() {
    case "$INIT_SYSTEM" in
        systemd) systemctl status "$SERVICE_NAME" --no-pager ;;
        openrc) rc-service "$SERVICE_NAME" status ;;
        *) warn "未知的服务管理器" ;;
    esac
}

service_ready() {
    [[ "${OU_SB_TESTING:-0}" == "1" ]] && return 1
    case "$INIT_SYSTEM" in
        systemd) [[ -f "$SYSTEMD_DIR/sing-box.service" ]] ;;
        openrc) [[ -f "$OPENRC_DIR/sing-box" ]] ;;
        *) return 1 ;;
    esac
}

commit_candidate() {
    local candidate=$1 description=$2 backup
    validate_candidate "$candidate" || { rm -f "$candidate"; warn "配置校验失败，未应用：$description"; return 1; }
    backup=$(backup_config)
    chmod 600 "$candidate"
    mv -f "$candidate" "$CONFIG_PATH"
    if service_ready && ! service_restart; then
        warn "服务重启失败，正在恢复配置"
        cp -p "$backup" "$CONFIG_PATH"
        service_restart || true
        return 1
    fi
    ok "$description"
}

apply_inbound_json() {
    local tag=$1 inbound_json=$2 candidate
    if config_has_tag "$tag"; then
        warn "协议已存在：$tag"
        return 2
    fi
    candidate=$(mktemp "$SB_DIR/.config.XXXXXX")
    jq --argjson inbound "$inbound_json" '.inbounds += [$inbound]' "$CONFIG_PATH" > "$candidate"
    commit_candidate "$candidate" "协议配置已添加"
}

replace_inbound_json() {
    local tag=$1 inbound_json=$2 candidate
    candidate=$(mktemp "$SB_DIR/.config.XXXXXX")
    jq --arg tag "$tag" --argjson inbound "$inbound_json" '
        .inbounds = ([.inbounds[] | select(.tag != $tag)] + [$inbound])
    ' "$CONFIG_PATH" > "$candidate"
    commit_candidate "$candidate" "协议配置已更新"
}

remove_inbound_tags() {
    local description=$1
    shift
    local candidate tags_json
    tags_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)
    candidate=$(mktemp "$SB_DIR/.config.XXXXXX")
    jq --argjson tags "$tags_json" '.inbounds = [.inbounds[] | select(.tag as $tag | $tags | index($tag) | not)]' "$CONFIG_PATH" > "$candidate"
    commit_candidate "$candidate" "$description"
}

random_port() {
    local port attempt
    for ((attempt = 0; attempt < 50; attempt++)); do
        port=$((RANDOM % 50001 + 10000))
        if ! port_in_use "$port" && ! port_in_config "$port" && ! port_in_hy2_hop_spec "$port"; then
            printf '%s\n' "$port"
            return 0
        fi
    done
    return 1
}

port_in_use() {
    local port=$1
    command -v ss >/dev/null 2>&1 || return 1
    ss -H -lntu 2>/dev/null | awk '{print $5}' | grep -Eq "(^|:)$port$"
}

port_in_config() {
    local port=$1
    [[ -s $CONFIG_PATH ]] || return 1
    jq -e --argjson port "$port" '.inbounds[]? | select(.listen_port == $port)' "$CONFIG_PATH" >/dev/null 2>&1
}

hop_spec_contains_port() {
    local spec=$1 port=$2 item start end
    local -a items
    [[ -n $spec ]] || return 1
    IFS=',' read -r -a items <<< "$spec"
    for item in "${items[@]}"; do
        if [[ $item =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start=${BASH_REMATCH[1]}
            end=${BASH_REMATCH[2]}
            ((10#$port >= 10#$start && 10#$port <= 10#$end)) && return 0
        elif ((10#$port == 10#$item)); then
            return 0
        fi
    done
    return 1
}

port_in_hy2_hop_spec() {
    local spec
    [[ -s $STATE_PATH ]] || return 1
    spec=$(state_get '.hy2.hop_ports')
    hop_spec_contains_port "$spec" "$1"
}

valid_port() {
    [[ $1 =~ ^[0-9]+$ && ${#1} -le 5 ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

prompt_port() {
    local label=$1 input default_port
    default_port=$(random_port) || die "无法找到可用端口"
    while true; do
        read -r -p "$label [默认 $default_port]: " input
        input=${input:-$default_port}
        if ! valid_port "$input"; then
            warn "端口必须在 1-65535 之间"
        elif port_in_config "$input"; then
            warn "端口 $input 已被其他协议配置使用"
        elif port_in_hy2_hop_spec "$input"; then
            warn "端口 $input 位于 HY2 跳跃范围内"
        elif port_in_use "$input"; then
            warn "端口 $input 已被占用"
        else
            printf '%s\n' "$input"
            return 0
        fi
    done
}

valid_hop_spec() {
    local spec=$1 item start end
    local -a items
    [[ -n $spec && $spec != *[[:space:]]* ]] || return 1
    IFS=',' read -r -a items <<< "$spec"
    ((${#items[@]} > 0 && ${#items[@]} <= 32)) || return 1
    for item in "${items[@]}"; do
        if [[ $item =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start=${BASH_REMATCH[1]}
            end=${BASH_REMATCH[2]}
            valid_port "$start" && valid_port "$end" && ((10#$start <= 10#$end)) || return 1
        elif ! valid_port "$item"; then
            return 1
        fi
    done
}

prompt_hop_spec() {
    local input
    while true; do
        read -r -p "跳跃端口（如 20000-30000 或 20000,21000-22000，留空关闭）: " input
        [[ -z $input ]] && { printf '\n'; return 0; }
        if ! valid_hop_spec "$input"; then
            warn "端口范围格式无效"
        elif hop_spec_conflicts_with_config "$input"; then
            warn "跳跃范围与其他协议端口冲突"
        else
            printf '%s\n' "$input"
            return 0
        fi
    done
}

hop_spec_conflicts_with_config() {
    local spec=$1 port
    while IFS= read -r port; do
        [[ -n $port ]] || continue
        hop_spec_contains_port "$spec" "$port" && return 0
    done < <(jq -r --arg hy2 "$TAG_HY2" '.inbounds[]? | select(.tag != $hy2) | .listen_port // empty' "$CONFIG_PATH")
    return 1
}

valid_endpoint_host() {
    [[ -n $1 && ${#1} -le 253 && $1 != *[[:space:],/?#]* ]]
}

valid_sni() {
    [[ -n $1 && ${#1} -le 253 && $1 =~ ^[A-Za-z0-9.-]+$ ]]
}

prompt_sni() {
    local input
    while true; do
        read -r -p "Reality SNI [addons.mozilla.org]: " input
        input=${input:-addons.mozilla.org}
        if valid_sni "$input"; then
            printf '%s\n' "$input"
            return 0
        fi
        warn "SNI 必须是有效域名"
    done
}

rand_base64() { openssl rand -base64 "$1" | tr -d '\n\r'; }
rand_hex() { openssl rand -hex "$1"; }
rand_uuid() {
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        tr -d '\n\r' < /proc/sys/kernel/random/uuid
    else
        local hex
        hex=$(openssl rand -hex 16)
        printf '%s-%s-%s-%s-%s\n' "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" "${hex:16:4}" "${hex:20:12}"
    fi
}

ensure_certificates() {
    [[ -s "$CERT_DIR/fullchain.pem" && -s "$CERT_DIR/privkey.pem" ]] && return 0
    info "生成 HY2/TUIC 自签证书"
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$CERT_DIR/privkey.pem" -out "$CERT_DIR/fullchain.pem" \
        -subj "/CN=www.bing.com" >/dev/null 2>&1
    chmod 600 "$CERT_DIR/privkey.pem"
}

get_public_host() {
    local host
    host=$(state_get '.public_host')
    if [[ -n $host ]]; then
        printf '%s\n' "$host"
        return 0
    fi
    host=$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)
    [[ -n $host ]] || host="YOUR_SERVER_IP"
    printf '%s\n' "$host"
}

host_for_uri() {
    local host=$1
    if [[ $host == *:* && $host != \[*\] ]]; then
        printf '[%s]' "$host"
    else
        printf '%s' "$host"
    fi
}

url_encode() { jq -rn --arg value "$1" '$value | @uri'; }
base64_nowrap() { base64 | tr -d '\n\r'; }

generate_reality_material() {
    local output private public sid
    output=$(sing-box generate reality-keypair 2>/dev/null) || return 1
    private=$(awk -F': *' '/PrivateKey|Private key/ {print $2; exit}' <<< "$output")
    public=$(awk -F': *' '/PublicKey|Public key/ {print $2; exit}' <<< "$output")
    [[ -n $private && -n $public ]] || return 1
    sid=$(rand_hex 8)
    printf '%s\t%s\t%s\n' "$private" "$public" "$sid"
}

add_ss() {
    protocol_exists "$TAG_SS" && { warn "SS2022 已安装"; return 0; }
    local port password inbound
    port=$(prompt_port "SS2022 端口")
    password=$(rand_base64 16)
    inbound=$(jq -nc --arg tag "$TAG_SS" --argjson port "$port" --arg password "$password" '{
        type:"shadowsocks", tag:$tag, listen:"::", listen_port:$port,
        method:"2022-blake3-aes-128-gcm", password:$password
    }')
    apply_inbound_json "$TAG_SS" "$inbound"
}

add_hy2() {
    protocol_exists "$TAG_HY2" && { warn "Hysteria2 已安装"; return 0; }
    local port password hop inbound
    port=$(prompt_port "HY2 实际监听端口")
    hop=$(prompt_hop_spec)
    password=$(rand_base64 18)
    ensure_certificates
    inbound=$(jq -nc --arg tag "$TAG_HY2" --argjson port "$port" --arg password "$password" \
        --arg cert "$CERT_DIR/fullchain.pem" --arg key "$CERT_DIR/privkey.pem" '{
        type:"hysteria2", tag:$tag, listen:"::", listen_port:$port,
        users:[{name:"ou-sb", password:$password}],
        tls:{enabled:true, alpn:["h3"], certificate_path:$cert, key_path:$key}
    }')
    apply_inbound_json "$TAG_HY2" "$inbound" || return
    state_set_number 'hy2.listen_port' "$port"
    state_set_string 'hy2.hop_ports' "$hop"
    if [[ -n $hop ]]; then
        apply_hy2_firewall || warn "HY2 已添加，但端口跳跃防火墙规则未能应用"
    fi
}

add_tuic() {
    protocol_exists "$TAG_TUIC" && { warn "TUIC 已安装"; return 0; }
    local port uuid password inbound
    port=$(prompt_port "TUIC 端口")
    uuid=$(rand_uuid)
    password=$(rand_base64 18)
    ensure_certificates
    inbound=$(jq -nc --arg tag "$TAG_TUIC" --argjson port "$port" --arg uuid "$uuid" --arg password "$password" \
        --arg cert "$CERT_DIR/fullchain.pem" --arg key "$CERT_DIR/privkey.pem" '{
        type:"tuic", tag:$tag, listen:"::", listen_port:$port,
        users:[{name:"ou-sb", uuid:$uuid, password:$password}], congestion_control:"bbr",
        tls:{enabled:true, alpn:["h3"], certificate_path:$cert, key_path:$key}
    }')
    apply_inbound_json "$TAG_TUIC" "$inbound"
}

add_vless() {
    protocol_exists "$TAG_VLESS" && { warn "VLESS Reality 已安装"; return 0; }
    local port uuid sni material private public sid inbound
    port=$(prompt_port "VLESS Reality 端口")
    sni=$(prompt_sni)
    uuid=$(rand_uuid)
    material=$(generate_reality_material) || { warn "Reality 密钥生成失败"; return 1; }
    IFS=$'\t' read -r private public sid <<< "$material"
    inbound=$(jq -nc --arg tag "$TAG_VLESS" --argjson port "$port" --arg uuid "$uuid" \
        --arg sni "$sni" --arg private "$private" --arg sid "$sid" '{
        type:"vless", tag:$tag, listen:"::", listen_port:$port,
        users:[{name:"ou-sb", uuid:$uuid, flow:"xtls-rprx-vision"}],
        tls:{enabled:true, server_name:$sni, reality:{enabled:true,
            handshake:{server:$sni, server_port:443}, private_key:$private, short_id:[$sid]}}
    }')
    apply_inbound_json "$TAG_VLESS" "$inbound" || return
    state_set_string 'reality.vless.public_key' "$public"
    state_set_string 'reality.vless.short_id' "$sid"
    state_set_string 'reality.vless.sni' "$sni"
}

add_anytls() {
    protocol_exists "$TAG_ANYTLS" && { warn "AnyTLS Reality 已安装"; return 0; }
    local port password sni material private public sid inbound
    port=$(prompt_port "AnyTLS Reality 端口")
    sni=$(prompt_sni)
    password=$(rand_base64 18)
    material=$(generate_reality_material) || { warn "Reality 密钥生成失败"; return 1; }
    IFS=$'\t' read -r private public sid <<< "$material"
    inbound=$(jq -nc --arg tag "$TAG_ANYTLS" --argjson port "$port" --arg password "$password" \
        --arg sni "$sni" --arg private "$private" --arg sid "$sid" '{
        type:"anytls", tag:$tag, listen:"::", listen_port:$port,
        users:[{name:"ou-sb", password:$password}],
        tls:{enabled:true, server_name:$sni, reality:{enabled:true,
            handshake:{server:$sni, server_port:443}, private_key:$private, short_id:[$sid]}}
    }')
    apply_inbound_json "$TAG_ANYTLS" "$inbound" || return
    state_set_string 'reality.anytls.public_key' "$public"
    state_set_string 'reality.anytls.short_id' "$sid"
    state_set_string 'reality.anytls.sni' "$sni"
}

sing_box_version() {
    sing-box version 2>/dev/null | awk 'NR==1 {print $3}'
}

snell_supported() {
    local candidate
    command -v sing-box >/dev/null 2>&1 || return 1
    candidate=$(mktemp)
    jq -n '{
        inbounds: [{type:"snell", tag:"probe", listen:"127.0.0.1", listen_port:61601,
            version:5, psk:"123456789012", obfs_mode:"none"}],
        outbounds: [{type:"direct", tag:"direct"}]
    }' > "$candidate"
    if sing-box check -c "$candidate" >/dev/null 2>&1; then
        rm -f "$candidate"
        return 0
    fi
    rm -f "$candidate"
    return 1
}

ensure_snell_capable() {
    local version answer
    version=$(sing_box_version || true)
    if snell_supported; then
        return 0
    fi
    warn "Snell 需要 sing-box 1.14.0-alpha.38 或更高版本，当前版本：${version:-未安装}"
    read -r -p "是否安装官方 beta/testing 版本？[y/N]: " answer
    [[ $answer =~ ^[Yy]$ ]] || return 1
    install_sing_box beta
    version=$(sing_box_version || true)
    snell_supported
}

add_snell() {
    protocol_exists "$TAG_SNELL" && { warn "Snell 已安装"; return 0; }
    ensure_snell_capable || { warn "已取消 Snell 安装"; return 0; }
    local port choice client_version server_version password obfs mode inbound
    port=$(prompt_port "Snell 端口")
    cat <<'EOF'
1) Snell v4 客户端（v5 兼容服务端）
2) Snell v5 客户端（不含 QUIC Proxy）
3) Snell v6
EOF
    read -r -p "版本 [1]: " choice
    case "${choice:-1}" in
        1) client_version=4; server_version=5 ;;
        2) client_version=5; server_version=5 ;;
        3) client_version=6; server_version=6 ;;
        *) warn "无效版本"; return 1 ;;
    esac
    password=$(rand_base64 24)
    if [[ $server_version -eq 5 ]]; then
        read -r -p "HTTP 混淆？[y/N]: " choice
        [[ $choice =~ ^[Yy]$ ]] && obfs="http" || obfs="none"
        inbound=$(jq -nc --arg tag "$TAG_SNELL" --argjson port "$port" --arg password "$password" --arg obfs "$obfs" '{
            type:"snell", tag:$tag, listen:"::", listen_port:$port,
            version:5, psk:$password, obfs_mode:$obfs
        }')
    else
        mode="default"
        inbound=$(jq -nc --arg tag "$TAG_SNELL" --argjson port "$port" --arg password "$password" --arg mode "$mode" '{
            type:"snell", tag:$tag, listen:"::", listen_port:$port,
            version:6, psk:$password, mode:$mode
        }')
        obfs="none"
    fi
    apply_inbound_json "$TAG_SNELL" "$inbound" || return
    state_set_number 'snell.client_version' "$client_version"
    state_set_string 'snell.obfs' "$obfs"
}

add_protocol_menu() {
    while true; do
        banner
        cat <<'EOF'
  添加协议
  ─────────────────────────
  1) Shadowsocks 2022
  2) Hysteria2
  3) TUIC
  4) VLESS TCP + XTLS Vision + Reality
  5) AnyTLS Reality
  6) Snell v4/v5/v6（实验）
  0) 返回
EOF
        read -r -p "选择: " choice
        case "$choice" in
            1) add_ss; break ;;
            2) add_hy2; break ;;
            3) add_tuic; break ;;
            4) add_vless; break ;;
            5) add_anytls; break ;;
            6) add_snell; break ;;
            0) return 0 ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}

remove_protocol_menu() {
    cat <<'EOF'
1) Shadowsocks 2022
2) Hysteria2
3) TUIC
4) VLESS Reality
5) AnyTLS Reality
6) Snell
0) 返回
EOF
    local choice tag name
    read -r -p "删除协议: " choice
    case "$choice" in
        1) tag=$TAG_SS; name=SS2022 ;;
        2) tag=$TAG_HY2; name=HY2 ;;
        3) tag=$TAG_TUIC; name=TUIC ;;
        4) tag=$TAG_VLESS; name=VLESS ;;
        5) tag=$TAG_ANYTLS; name=AnyTLS ;;
        6) tag=$TAG_SNELL; name=Snell ;;
        0) return 0 ;;
        *) warn "无效选项"; return 1 ;;
    esac
    protocol_exists "$tag" || { warn "$name 未安装"; return 0; }
    read -r -p "确认删除 $name？[y/N]: " choice
    [[ $choice =~ ^[Yy]$ ]] || return 0
    [[ $tag == "$TAG_HY2" ]] && { clear_hy2_firewall || true; state_set_string 'hy2.hop_ports' ''; }
    remove_inbound_tags "$name 已删除" "$tag"
}

change_protocol_port() {
    local tag name choice new_port candidate current
    cat <<'EOF'
1) Shadowsocks 2022
2) Hysteria2
3) TUIC
4) VLESS Reality
5) AnyTLS Reality
6) Snell
0) 返回
EOF
    read -r -p "选择协议: " choice
    case "$choice" in
        1) tag=$TAG_SS; name=SS2022 ;;
        2) tag=$TAG_HY2; name=HY2 ;;
        3) tag=$TAG_TUIC; name=TUIC ;;
        4) tag=$TAG_VLESS; name=VLESS ;;
        5) tag=$TAG_ANYTLS; name=AnyTLS ;;
        6) tag=$TAG_SNELL; name=Snell ;;
        0) return 0 ;;
        *) warn "无效选项"; return 1 ;;
    esac
    protocol_exists "$tag" || { warn "协议不存在"; return 1; }
    current=$(jq -r --arg tag "$tag" '.inbounds[] | select(.tag==$tag) | .listen_port' "$CONFIG_PATH")
    new_port=$(prompt_port "$name 新端口（当前 $current）")
    candidate=$(mktemp "$SB_DIR/.config.XXXXXX")
    jq --arg tag "$tag" --argjson port "$new_port" '(.inbounds[] | select(.tag==$tag) | .listen_port) = $port' "$CONFIG_PATH" > "$candidate"
    commit_candidate "$candidate" "端口已修改为 $new_port" || return
    if [[ $tag == "$TAG_HY2" ]]; then
        state_set_number 'hy2.listen_port' "$new_port"
        [[ -n $(state_get '.hy2.hop_ports') ]] && apply_hy2_firewall
    fi
}

configure_hy2_hopping() {
    protocol_exists "$TAG_HY2" || { warn "请先安装 Hysteria2"; return 0; }
    local spec port
    spec=$(prompt_hop_spec)
    port=$(jq -r --arg tag "$TAG_HY2" '.inbounds[] | select(.tag==$tag) | .listen_port' "$CONFIG_PATH")
    state_set_string 'hy2.hop_ports' "$spec"
    state_set_number 'hy2.listen_port' "$port"
    if [[ -n $spec ]]; then
        apply_hy2_firewall
    else
        clear_hy2_firewall
        ok "HY2 端口跳跃已关闭"
    fi
}

detect_firewall_backend() {
    if command -v nft >/dev/null 2>&1; then
        printf 'nftables\n'
    elif command -v iptables >/dev/null 2>&1; then
        printf 'iptables\n'
    else
        return 1
    fi
}

ensure_firewall_tool() {
    detect_firewall_backend >/dev/null 2>&1 && return 0
    [[ "${OU_SB_TESTING:-0}" == "1" ]] && return 1
    info "安装 nftables"
    case "$OS_FAMILY" in
        alpine) apk add --no-cache nftables ;;
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y nftables
            ;;
        redhat) dnf install -y nftables || yum install -y nftables ;;
        *) return 1 ;;
    esac
}

clear_hy2_firewall() {
    [[ "${OU_SB_TESTING:-0}" == "1" ]] && return 0
    if command -v nft >/dev/null 2>&1; then
        nft delete table inet ou_sb_hy2 >/dev/null 2>&1 || true
    fi
    if command -v iptables >/dev/null 2>&1; then
        while iptables -t nat -C PREROUTING -p udp -j OU_SB_HY2 >/dev/null 2>&1; do
            iptables -t nat -D PREROUTING -p udp -j OU_SB_HY2
        done
        iptables -t nat -F OU_SB_HY2 >/dev/null 2>&1 || true
        iptables -t nat -X OU_SB_HY2 >/dev/null 2>&1 || true
    fi
    if command -v ip6tables >/dev/null 2>&1; then
        while ip6tables -t nat -C PREROUTING -p udp -j OU_SB_HY2 >/dev/null 2>&1; do
            ip6tables -t nat -D PREROUTING -p udp -j OU_SB_HY2
        done
        ip6tables -t nat -F OU_SB_HY2 >/dev/null 2>&1 || true
        ip6tables -t nat -X OU_SB_HY2 >/dev/null 2>&1 || true
    fi
}

apply_hy2_firewall() {
    local spec port backend item rule_port
    local -a items
    spec=$(state_get '.hy2.hop_ports')
    port=$(state_get '.hy2.listen_port')
    [[ -n $spec ]] || return 0
    valid_hop_spec "$spec" || { warn "保存的 HY2 跳跃范围无效"; return 1; }
    valid_port "$port" || { warn "保存的 HY2 监听端口无效"; return 1; }
    ensure_firewall_tool || { warn "无法安装 nftables，端口跳跃不可用"; return 1; }
    backend=$(detect_firewall_backend) || { warn "未找到 nftables 或 iptables"; return 1; }
    clear_hy2_firewall
    if [[ $backend == nftables ]]; then
        nft add table inet ou_sb_hy2
        nft 'add chain inet ou_sb_hy2 prerouting { type nat hook prerouting priority dstnat; policy accept; }'
        IFS=',' read -r -a items <<< "$spec"
        for item in "${items[@]}"; do
            nft add rule inet ou_sb_hy2 prerouting udp dport "$item" redirect to ":$port"
        done
    else
        iptables -t nat -N OU_SB_HY2
        iptables -t nat -A PREROUTING -p udp -j OU_SB_HY2
        command -v ip6tables >/dev/null 2>&1 && { ip6tables -t nat -N OU_SB_HY2; ip6tables -t nat -A PREROUTING -p udp -j OU_SB_HY2; }
        IFS=',' read -r -a items <<< "$spec"
        for item in "${items[@]}"; do
            rule_port=${item/-/:}
            iptables -t nat -A OU_SB_HY2 -p udp --dport "$rule_port" -j REDIRECT --to-ports "$port"
            command -v ip6tables >/dev/null 2>&1 && ip6tables -t nat -A OU_SB_HY2 -p udp --dport "$rule_port" -j REDIRECT --to-ports "$port"
        done
    fi
    state_set_string 'hy2.firewall_backend' "$backend"
    ok "HY2 UDP 跳跃规则已应用：$spec -> $port ($backend)"
}

hop_spec_to_server_ports() {
    local spec=$1 item
    IFS=',' read -r -a items <<< "$spec"
    for item in "${items[@]}"; do
        printf '%s\n' "${item/-/:}"
    done | jq -R . | jq -s .
}

show_links() {
    local host uri_host label tag port password method uuid sni public sid encoded hop version obfs
    host=$(get_public_host)
    uri_host=$(host_for_uri "$host")
    label=$(url_encode "$(state_get '.node_name')")
    printf '\n%s节点配置%s\n' "$C_BOLD" "$C_RESET"
    printf '%s\n' '────────────────────────────────────────'
    if protocol_exists "$TAG_SS"; then
        method=$(jq -r --arg tag "$TAG_SS" '.inbounds[]|select(.tag==$tag)|.method' "$CONFIG_PATH")
        password=$(jq -r --arg tag "$TAG_SS" '.inbounds[]|select(.tag==$tag)|.password' "$CONFIG_PATH")
        port=$(jq -r --arg tag "$TAG_SS" '.inbounds[]|select(.tag==$tag)|.listen_port' "$CONFIG_PATH")
        encoded=$(printf '%s:%s' "$method" "$password" | base64_nowrap)
        printf 'SS2022\nss://%s@%s:%s#%s-SS2022\n\n' "$encoded" "$uri_host" "$port" "$label"
    fi
    if protocol_exists "$TAG_HY2"; then
        password=$(jq -r --arg tag "$TAG_HY2" '.inbounds[]|select(.tag==$tag)|.users[0].password' "$CONFIG_PATH")
        port=$(jq -r --arg tag "$TAG_HY2" '.inbounds[]|select(.tag==$tag)|.listen_port' "$CONFIG_PATH")
        hop=$(state_get '.hy2.hop_ports')
        [[ -n $hop ]] && port=$hop
        printf 'Hysteria2\nhy2://%s@%s:%s/?sni=www.bing.com&alpn=h3&insecure=1#%s-HY2\n' "$(url_encode "$password")" "$uri_host" "$port" "$label"
        if [[ -n $hop ]]; then
            printf 'sing-box server_ports: '
            hop_spec_to_server_ports "$hop" | jq -c .
            printf 'sing-box hop_interval: 30s\n'
        fi
        printf '\n'
    fi
    if protocol_exists "$TAG_TUIC"; then
        uuid=$(jq -r --arg tag "$TAG_TUIC" '.inbounds[]|select(.tag==$tag)|.users[0].uuid' "$CONFIG_PATH")
        password=$(jq -r --arg tag "$TAG_TUIC" '.inbounds[]|select(.tag==$tag)|.users[0].password' "$CONFIG_PATH")
        port=$(jq -r --arg tag "$TAG_TUIC" '.inbounds[]|select(.tag==$tag)|.listen_port' "$CONFIG_PATH")
        printf 'TUIC\ntuic://%s:%s@%s:%s/?congestion_control=bbr&alpn=h3&sni=www.bing.com&insecure=1#%s-TUIC\n\n' "$uuid" "$(url_encode "$password")" "$uri_host" "$port" "$label"
    fi
    for tag in "$TAG_VLESS" "$TAG_ANYTLS"; do
        protocol_exists "$tag" || continue
        port=$(jq -r --arg tag "$tag" '.inbounds[]|select(.tag==$tag)|.listen_port' "$CONFIG_PATH")
        sni=$(jq -r --arg tag "$tag" '.inbounds[]|select(.tag==$tag)|.tls.server_name' "$CONFIG_PATH")
        sid=$(jq -r --arg tag "$tag" '.inbounds[]|select(.tag==$tag)|.tls.reality.short_id[0]' "$CONFIG_PATH")
        if [[ $tag == "$TAG_VLESS" ]]; then
            public=$(state_get '.reality.vless.public_key')
            uuid=$(jq -r --arg tag "$tag" '.inbounds[]|select(.tag==$tag)|.users[0].uuid' "$CONFIG_PATH")
            printf 'VLESS TCP + XTLS Vision + Reality\nvless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&type=tcp&sni=%s&fp=chrome&pbk=%s&sid=%s#%s-VLESS\n\n' "$uuid" "$uri_host" "$port" "$sni" "$public" "$sid" "$label"
        else
            public=$(state_get '.reality.anytls.public_key')
            password=$(jq -r --arg tag "$tag" '.inbounds[]|select(.tag==$tag)|.users[0].password' "$CONFIG_PATH")
            printf 'AnyTLS Reality\nanytls://%s@%s:%s/?security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s#%s-AnyTLS\n\n' "$(url_encode "$password")" "$uri_host" "$port" "$sni" "$public" "$sid" "$label"
        fi
    done
    if protocol_exists "$TAG_SNELL"; then
        port=$(jq -r --arg tag "$TAG_SNELL" '.inbounds[]|select(.tag==$tag)|.listen_port' "$CONFIG_PATH")
        password=$(jq -r --arg tag "$TAG_SNELL" '.inbounds[]|select(.tag==$tag)|.psk' "$CONFIG_PATH")
        version=$(state_get '.snell.client_version')
        obfs=$(state_get '.snell.obfs')
        printf 'Snell v%s (Surge)\nOU-SB-Snell = snell, %s, %s, psk=%s, version=%s' "$version" "$host" "$port" "$password" "$version"
        [[ $obfs == http ]] && printf ', obfs=http'
        printf '\n\n'
    fi
}

show_protocol_status() {
    local tag name status
    printf '  %-34s %s\n' "协议" "状态"
    printf '  %-34s %s\n' "────────────────────────────────" "────"
    while IFS='|' read -r tag name; do
        if protocol_exists "$tag"; then status="${C_GREEN}已安装${C_RESET}"; else status="${C_MUTED}未安装${C_RESET}"; fi
        printf '  %-34s %b\n' "$name" "$status"
    done <<EOF
$TAG_SS|Shadowsocks 2022
$TAG_HY2|Hysteria2
$TAG_TUIC|TUIC
$TAG_VLESS|VLESS TCP+Vision+Reality
$TAG_ANYTLS|AnyTLS Reality
$TAG_SNELL|Snell v4/v5/v6
EOF
}

configure_identity() {
    local host name current
    current=$(state_get '.public_host')
    read -r -p "连接 IP 或 DDNS [${current:-自动检测}]: " host
    host=${host#[}
    host=${host%]}
    if [[ -n $host ]]; then
        valid_endpoint_host "$host" || { warn "连接地址格式无效"; return 1; }
        state_set_string 'public_host' "$host"
    fi
    current=$(state_get '.node_name')
    read -r -p "节点名称 [$current]: " name
    [[ -n $name ]] && state_set_string 'node_name' "$name"
    ok "节点信息已更新"
}

show_logs() {
    case "$INIT_SYSTEM" in
        systemd) journalctl -u "$SERVICE_NAME" -n 100 --no-pager ;;
        openrc) tail -n 100 /var/log/sing-box.log 2>/dev/null || warn "暂无日志" ;;
    esac
}

restore_backup() {
    local latest candidate
    latest=$(for file in "$BACKUP_DIR"/config-*.json; do
        [[ -e $file ]] && printf '%s\n' "$file"
    done | sort -r | head -n1)
    [[ -n $latest ]] || { warn "没有可恢复的备份"; return 0; }
    candidate=$(mktemp "$SB_DIR/.config.XXXXXX")
    cp -p "$latest" "$candidate"
    commit_candidate "$candidate" "已恢复 $(basename "$latest")"
}

create_manual_backup() {
    local backup
    backup=$(backup_config)
    ok "配置已备份：$backup"
}

normalize_sing_box_arch() {
    local machine=$1
    case "$machine" in
        x86_64|amd64) printf 'amd64\n' ;;
        aarch64|arm64) printf 'arm64\n' ;;
        armv7l|armv7) printf 'armv7\n' ;;
        armv6l|armv6) printf 'armv6\n' ;;
        armv5l|armv5) printf 'armv5\n' ;;
        i386|i486|i586|i686|386) printf '386\n' ;;
        loongarch64|loong64) printf 'loong64\n' ;;
        mips64el|mips64le) printf 'mips64le\n' ;;
        mipsel|mipsle) printf 'mipsle\n' ;;
        ppc64le|riscv64|s390x) printf '%s\n' "$machine" ;;
        *) return 1 ;;
    esac
}

github_api_get() {
    local url=$1
    if [[ -n ${GITHUB_TOKEN:-} ]]; then
        curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" -H 'Accept: application/vnd.github+json' "$url"
    else
        curl -fsSL -H 'Accept: application/vnd.github+json' "$url"
    fi
}

check_free_space_kb() {
    local path=$1 required_kb=$2 available_kb
    available_kb=$(df -Pk "$path" | awk 'NR == 2 {print $4}')
    [[ $available_kb =~ ^[0-9]+$ ]] || return 1
    ((available_kb >= required_kb))
}

install_sing_box_alpine() {
    local channel=$1 release_json tag version arch asset_name asset_json
    local asset_url asset_digest asset_size digest actual required_kb
    local temp_dir archive binary target

    if [[ $channel == beta ]]; then
        release_json=$(github_api_get 'https://api.github.com/repos/SagerNet/sing-box/releases?per_page=30' \
            | jq -c '[.[] | select(.prerelease == true and .draft == false)] | first')
    else
        release_json=$(github_api_get 'https://api.github.com/repos/SagerNet/sing-box/releases/latest')
    fi
    [[ -n $release_json && $release_json != null ]] || die "无法获取 sing-box $channel 版本信息"

    tag=$(jq -r '.tag_name // empty' <<< "$release_json")
    version=${tag#v}
    [[ -n $version ]] || die "sing-box 版本信息无效"
    arch=$(normalize_sing_box_arch "$(uname -m)") || die "不支持的 CPU 架构：$(uname -m)"
    asset_name="sing-box-${version}-linux-${arch}-musl.tar.gz"
    asset_json=$(jq -c --arg name "$asset_name" '.assets[] | select(.name == $name)' <<< "$release_json")
    [[ -n $asset_json ]] || die "未找到适用于 $arch 的官方 sing-box 压缩包"

    asset_url=$(jq -r '.browser_download_url // empty' <<< "$asset_json")
    asset_digest=$(jq -r '.digest // empty' <<< "$asset_json")
    asset_size=$(jq -r '.size // 0' <<< "$asset_json")
    [[ -n $asset_url && $asset_digest == sha256:* && $asset_size =~ ^[0-9]+$ ]] \
        || die "sing-box 下载信息缺少 URL 或 SHA-256"

    required_kb=$((asset_size * 4 / 1024 + 32768))
    check_free_space_kb "$APP_DIR" "$required_kb" \
        || die "磁盘空间不足，安装至少需要约 $((required_kb / 1024)) MiB 可用空间"

    temp_dir=$(mktemp -d "$APP_DIR/install.XXXXXX")
    archive="$temp_dir/$asset_name"
    info "下载 sing-box $version ($arch)"
    if ! curl -fL --retry 3 --connect-timeout 10 "$asset_url" -o "$archive"; then
        rm -rf -- "$temp_dir"
        die "sing-box 下载失败"
    fi

    digest=${asset_digest#sha256:}
    actual=$(sha256sum "$archive" | awk '{print $1}')
    if [[ $actual != "$digest" ]]; then
        rm -rf -- "$temp_dir"
        die "sing-box SHA-256 校验失败"
    fi

    if ! tar -xzf "$archive" -C "$temp_dir"; then
        rm -rf -- "$temp_dir"
        die "sing-box 压缩包解压失败"
    fi
    binary=$(find "$temp_dir" -type f -name sing-box | head -n1)
    [[ -n $binary && -x $binary ]] || { rm -rf -- "$temp_dir"; die "压缩包中未找到 sing-box 可执行文件"; }

    target="${OU_SB_SING_BOX_BIN:-/usr/local/bin/sing-box}"
    mkdir -p "$(dirname "$target")"
    install -m 755 "$binary" "$target"
    rm -rf -- "$temp_dir"
    hash -r
}

install_sing_box() {
    local channel=${1:-stable}
    info "安装 sing-box ($channel)"
    if [[ $OS_FAMILY == alpine ]]; then
        install_sing_box_alpine "$channel"
    elif [[ $channel == beta ]]; then
        curl -fsSL https://sing-box.app/install.sh | sh -s -- --beta
    else
        curl -fsSL https://sing-box.app/install.sh | sh
    fi
    command -v sing-box >/dev/null 2>&1 || die "sing-box 安装失败"
    ok "$(sing-box version 2>/dev/null | head -n1)"
}

setup_services() {
    local sb_bin
    sb_bin=$(command -v sing-box)
    if [[ $INIT_SYSTEM == systemd ]]; then
        mkdir -p "$SYSTEMD_DIR"
        cat > "$SYSTEMD_DIR/sing-box.service" <<EOF
[Unit]
Description=sing-box service managed by OU-SB
After=network-online.target ou-sb-firewall.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$sb_bin run -c $CONFIG_PATH
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
        cat > "$SYSTEMD_DIR/ou-sb-firewall.service" <<EOF
[Unit]
Description=OU-SB Hysteria2 port hopping
Before=sing-box.service

[Service]
Type=oneshot
ExecStart=$COMMAND_PATH --apply-firewall
ExecStop=$COMMAND_PATH --clear-firewall
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable sing-box ou-sb-firewall >/dev/null
    elif [[ $INIT_SYSTEM == openrc ]]; then
        cat > "$OPENRC_DIR/sing-box" <<EOF
#!/sbin/openrc-run
name="sing-box"
command="$sb_bin"
command_args="run -c $CONFIG_PATH"
command_background="yes"
pidfile="/run/sing-box.pid"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.log"
depend() { need net; after ou-sb-firewall; }
EOF
        cat > "$OPENRC_DIR/ou-sb-firewall" <<EOF
#!/sbin/openrc-run
description="OU-SB Hysteria2 port hopping"
start() { $COMMAND_PATH --apply-firewall; }
stop() { $COMMAND_PATH --clear-firewall; }
EOF
        chmod +x "$OPENRC_DIR/sing-box" "$OPENRC_DIR/ou-sb-firewall"
        rc-update add ou-sb-firewall default >/dev/null 2>&1 || true
        rc-update add sing-box default >/dev/null 2>&1 || true
    else
        die "仅支持 systemd 或 OpenRC"
    fi
}

install_self() {
    local source_path=${BASH_SOURCE[0]}
    mkdir -p "$INSTALL_DIR" "$(dirname "$COMMAND_PATH")"
    if [[ -f $source_path && $source_path != /dev/fd/* && $source_path != /proc/self/fd/* ]]; then
        install -m 755 "$source_path" "$INSTALL_PATH"
    else
        curl -fsSL "$RAW_SCRIPT_URL" -o "$INSTALL_PATH"
        chmod 755 "$INSTALL_PATH"
    fi
    ln -sfn "$INSTALL_PATH" "$COMMAND_PATH"
}

update_ou_sb() {
    local tmp
    tmp=$(mktemp)
    curl -fsSL "$RAW_SCRIPT_URL" -o "$tmp"
    bash -n "$tmp" || { rm -f "$tmp"; warn "下载的新脚本语法校验失败"; return 1; }
    install -m 755 "$tmp" "$INSTALL_PATH"
    rm -f "$tmp"
    ok "OU-SB 已更新"
}

update_sing_box() {
    local channel=stable
    protocol_exists "$TAG_SNELL" && channel=beta
    install_sing_box "$channel"
    if validate_candidate "$CONFIG_PATH"; then
        if service_restart; then
            ok "sing-box 已更新并重启"
        else
            warn "sing-box 更新成功，但服务重启失败"
        fi
    else
        warn "更新后的 sing-box 无法通过当前配置校验"
        return 1
    fi
}

uninstall_ou_sb() {
    local answer candidate count
    read -r -p "确认卸载 OU-SB 并删除其协议？[y/N]: " answer
    [[ $answer =~ ^[Yy]$ ]] || return 0
    clear_hy2_firewall || true
    candidate=$(mktemp "$SB_DIR/.config.XXXXXX")
    jq '.inbounds = [.inbounds[] | select((.tag // "") | startswith("ou-sb-") | not)]' "$CONFIG_PATH" > "$candidate"
    commit_candidate "$candidate" "OU-SB 协议已移除" || return
    count=$(jq '.inbounds | length' "$CONFIG_PATH")
    if ((count == 0)); then
        service_stop || true
        if [[ $INIT_SYSTEM == systemd ]]; then
            systemctl disable sing-box ou-sb-firewall >/dev/null 2>&1 || true
            rm -f "$SYSTEMD_DIR/sing-box.service" "$SYSTEMD_DIR/ou-sb-firewall.service"
            systemctl daemon-reload
        else
            rc-update del sing-box default >/dev/null 2>&1 || true
            rc-update del ou-sb-firewall default >/dev/null 2>&1 || true
            rm -f "$OPENRC_DIR/sing-box" "$OPENRC_DIR/ou-sb-firewall"
        fi
    fi
    rm -f "$COMMAND_PATH"
    rm -rf "$APP_DIR" "$INSTALL_DIR"
    ok "OU-SB 已卸载；sing-box 程序本体未删除"
    exit 0
}

pause_screen() {
    if [[ -t 0 ]]; then
        read -r -p "按 Enter 返回..." _ || true
    fi
}

main_menu() {
    local choice
    while true; do
        banner
        show_protocol_status
        cat <<'EOF'

  1) 查看节点配置      10) 服务状态
  2) 添加协议          11) 查看日志
  3) 删除协议          11) 查看日志
  4) 修改协议端口      12) 校验配置
  5) HY2 端口跳跃      13) 手动备份
  6) 节点信息          14) 恢复最近备份
  7) 启动服务          15) 更新 sing-box
  8) 停止服务          16) 更新 OU-SB
  9) 重启服务          17) 卸载 OU-SB
  0) 退出
EOF
        printf '\n'
        read -r -p "请选择: " choice
        case "$choice" in
            1) show_links; pause_screen ;;
            2) add_protocol_menu; pause_screen ;;
            3) remove_protocol_menu; pause_screen ;;
            4) change_protocol_port; pause_screen ;;
            5) configure_hy2_hopping; pause_screen ;;
            6) configure_identity; pause_screen ;;
            7)
                if service_start; then ok "服务已启动"; else warn "服务启动失败"; fi
                pause_screen
                ;;
            8)
                if service_stop; then ok "服务已停止"; else warn "服务停止失败"; fi
                pause_screen
                ;;
            9)
                if service_restart; then ok "服务已重启"; else warn "服务重启失败"; fi
                pause_screen
                ;;
            10) service_status || true; pause_screen ;;
            11) show_logs; pause_screen ;;
            12)
                if validate_candidate "$CONFIG_PATH"; then ok "配置校验通过"; else warn "配置校验失败"; fi
                pause_screen
                ;;
            13) create_manual_backup; pause_screen ;;
            14) restore_backup; pause_screen ;;
            15) update_sing_box; pause_screen ;;
            16) update_ou_sb; pause_screen ;;
            17) uninstall_ou_sb ;;
            0) exit 0 ;;
            *) warn "无效选项"; sleep 1 ;;
        esac
    done
}

first_run() {
    local answer
    if command -v sing-box >/dev/null 2>&1; then
        info "检测到 $(sing-box version 2>/dev/null | head -n1)"
    else
        install_sing_box stable
    fi
    install_self
    setup_services
    configure_identity
    read -r -p "现在添加第一个协议？[Y/n]: " answer
    [[ ! $answer =~ ^[Nn]$ ]] && add_protocol_menu
    apply_hy2_firewall || true
    service_restart || service_start || warn "服务启动失败，请使用 sb 查看状态"
}

cli_status() {
    printf '%s %s\n' "$APP_NAME" "$APP_VERSION"
    printf 'OS: %s | init: %s\n' "$OS_FAMILY" "$INIT_SYSTEM"
    if command -v sing-box >/dev/null 2>&1; then
        printf 'sing-box: %s\n' "$(sing-box version 2>/dev/null | head -n1)"
    else
        printf 'sing-box: 未安装\n'
    fi
    printf '配置: %s\n' "$CONFIG_PATH"
    if [[ -s "$CONFIG_PATH" ]]; then
        jq -r '.inbounds[]?.tag // empty' "$CONFIG_PATH" | sed 's/^/协议: /'
    fi
}

cli_validate() {
    validate_candidate "$CONFIG_PATH" || die "配置校验失败"
    jq -e . "$STATE_PATH" >/dev/null || die "状态文件校验失败"
    ok "配置和状态校验通过"
}

cli_backup() {
    [[ -s "$CONFIG_PATH" ]] || die "配置文件不存在"
    backup_config
}

cli_export() {
    show_links
}

doctor() {
    local missing=() command
    for command in bash curl jq openssl flock ss awk grep sed base64 tar sha256sum install find; do
        command -v "$command" >/dev/null 2>&1 || missing+=("$command")
    done
    if ((${#missing[@]})); then
        warn "缺少依赖：${missing[*]}"
        return 1
    fi
    ok "基础依赖完整"
    cli_validate
}

usage() {
    cat <<EOF
$APP_NAME $APP_VERSION
用法：
  sb                     打开管理面板
  sb --apply-firewall    恢复 OU-SB 的 HY2 跳跃规则
  sb --clear-firewall    清理 OU-SB 的 HY2 跳跃规则
  sb --status            查看系统、服务和协议状态
  sb --validate          校验配置和状态文件
  sb --backup            创建配置备份
  sb --export             输出客户端连接信息
  sb --doctor             检查依赖和配置
  sb --version           显示版本
EOF
}

main() {
    init_colors
    detect_platform
    require_root
    install_dependencies
    prepare_directories
    acquire_lock
    init_state
    ensure_base_config
    case "${1:-}" in
        --apply-firewall) apply_hy2_firewall; exit $? ;;
        --clear-firewall) clear_hy2_firewall; exit $? ;;
        --status) cli_status; exit $? ;;
        --validate) cli_validate; exit $? ;;
        --backup) cli_backup; exit $? ;;
        --export) cli_export; exit $? ;;
        --doctor) doctor; exit $? ;;
        --version) printf '%s %s\n' "$APP_NAME" "$APP_VERSION"; exit 0 ;;
        --help|-h) usage; exit 0 ;;
        "") ;;
        *) usage; exit 1 ;;
    esac
    if [[ ! -x $COMMAND_PATH || ! -x $INSTALL_PATH ]] || ! command -v sing-box >/dev/null 2>&1; then
        banner
        first_run
    fi
    main_menu
}

init_colors
if [[ "${OU_SB_LIB_ONLY:-0}" != "1" ]]; then
    main "$@"
fi
