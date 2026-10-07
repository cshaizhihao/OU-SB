#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d /tmp/ou-sb-test.XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT

export OU_SB_LIB_ONLY=1
export OU_SB_TESTING=1
export OU_SB_ROOT="$TEST_ROOT"

# shellcheck disable=SC1091
. "$PROJECT_DIR/OU-SB.sh"

passes=0
failures=0

pass() {
    printf 'ok - %s\n' "$1"
    passes=$((passes + 1))
}

fail() {
    printf 'not ok - %s\n' "$1" >&2
    failures=$((failures + 1))
}

assert_true() {
    local name=$1
    shift
    if "$@"; then pass "$name"; else fail "$name"; fi
}

assert_false() {
    local name=$1
    shift
    if "$@"; then fail "$name"; else pass "$name"; fi
}

assert_eq() {
    local name=$1 expected=$2 actual=$3
    if [[ $expected == "$actual" ]]; then
        pass "$name"
    else
        fail "$name (expected=$expected actual=$actual)"
    fi
}

prepare_directories
init_state
ensure_base_config

assert_true "base config is valid JSON" jq -e '.inbounds == [] and .outbounds[0].tag == "direct-out"' "$CONFIG_PATH"

vless_uuid="11111111-2222-3333-4444-555555555555"
vless=$(jq -nc --arg tag "$TAG_VLESS" --arg uuid "$vless_uuid" '{
    type:"vless", tag:$tag, listen:"::", listen_port:443,
    users:[{uuid:$uuid, flow:"xtls-rprx-vision"}],
    tls:{enabled:true, reality:{enabled:true, private_key:"private", short_id:["aabbccdd"]}}
}')
assert_true "add VLESS" apply_inbound_json "$TAG_VLESS" "$vless"

ss=$(jq -nc --arg tag "$TAG_SS" '{
    type:"shadowsocks", tag:$tag, listen:"::", listen_port:1443,
    method:"2022-blake3-aes-128-gcm", password:"cGFzc3dvcmQxMjM0NTY="
}')
assert_true "add SS after VLESS" apply_inbound_json "$TAG_SS" "$ss"
assert_eq "VLESS credentials survive SS addition" "$vless_uuid" "$(jq -r --arg tag "$TAG_VLESS" '.inbounds[]|select(.tag==$tag)|.users[0].uuid' "$CONFIG_PATH")"
assert_eq "two protocols coexist" "2" "$(jq '.inbounds|length' "$CONFIG_PATH")"

if apply_inbound_json "$TAG_SS" "$ss" >/dev/null 2>&1; then
    fail "duplicate tag is rejected"
else
    pass "duplicate tag is rejected"
fi
assert_eq "duplicate attempt keeps inbound count" "2" "$(jq '.inbounds|length' "$CONFIG_PATH")"

assert_true "remove SS only" remove_inbound_tags "test remove" "$TAG_SS"
assert_true "VLESS remains after SS removal" protocol_exists "$TAG_VLESS"
assert_false "SS is gone" protocol_exists "$TAG_SS"

assert_true "valid continuous hop range" valid_hop_spec "20000-30000"
assert_true "valid mixed hop range" valid_hop_spec "20000,21000-22000,23000"
assert_false "reject descending range" valid_hop_spec "30000-20000"
assert_false "reject out-of-range port" valid_hop_spec "0,65536"
assert_false "reject whitespace" valid_hop_spec "20000, 21000"
assert_eq "convert hop range for sing-box" '["20000","21000:22000"]' "$(hop_spec_to_server_ports '20000,21000-22000' | jq -c .)"
assert_true "detect port inside hop range" hop_spec_contains_port "20000,21000-22000" "21500"
assert_false "detect port outside hop range" hop_spec_contains_port "20000,21000-22000" "23000"
assert_true "valid DDNS endpoint" valid_endpoint_host "node.example.com"
assert_true "valid IPv6 endpoint" valid_endpoint_host "2001:db8::1"
assert_false "reject endpoint injection characters" valid_endpoint_host "host,evil"
assert_eq "map x86_64 release architecture" "amd64" "$(normalize_sing_box_arch x86_64)"
assert_eq "map Alpine aarch64 release architecture" "arm64" "$(normalize_sing_box_arch aarch64)"
assert_eq "map 32-bit ARM release architecture" "armv7" "$(normalize_sing_box_arch armv7l)"
assert_false "reject unsupported release architecture" normalize_sing_box_arch "sparc64"

before=$(sha256sum "$CONFIG_PATH" | awk '{print $1}')
bad_candidate=$(mktemp "$SB_DIR/.config.XXXXXX")
jq '.log.level="debug"' "$CONFIG_PATH" > "$bad_candidate"
export OU_SB_FORCE_CHECK_FAIL=1
if commit_candidate "$bad_candidate" "forced failure" >/dev/null 2>&1; then
    fail "failed validation is rejected"
else
    pass "failed validation is rejected"
fi
unset OU_SB_FORCE_CHECK_FAIL
after=$(sha256sum "$CONFIG_PATH" | awk '{print $1}')
assert_eq "failed validation leaves config untouched" "$before" "$after"

snell=$(jq -nc --arg tag "$TAG_SNELL" '{
    type:"snell", tag:$tag, listen:"::", listen_port:6160,
    version:5, psk:"123456789012", obfs_mode:"http"
}')
assert_true "add Snell v5-compatible inbound" apply_inbound_json "$TAG_SNELL" "$snell"
# shellcheck disable=SC2016
assert_true "Snell uses supported HTTP obfs" jq -e --arg tag "$TAG_SNELL" '.inbounds[]|select(.tag==$tag)|.version==5 and .obfs_mode=="http"' "$CONFIG_PATH"

anytls=$(jq -nc --arg tag "$TAG_ANYTLS" '{
    type:"anytls", tag:$tag, listen:"::", listen_port:2443,
    users:[{name:"ou-sb", password:"anytls-password"}],
    tls:{enabled:true, server_name:"example.com", reality:{enabled:true,
        private_key:"private", short_id:["1122334455667788"]}}
}')
assert_true "add AnyTLS alongside VLESS" apply_inbound_json "$TAG_ANYTLS" "$anytls"
state_set_string 'public_host' 'node.example.com'
state_set_string 'reality.vless.public_key' 'vless-public-key'
state_set_string 'reality.anytls.public_key' 'anytls-public-key'
links=$(show_links)
assert_true "VLESS link is explicitly TCP Vision Reality" grep -q 'flow=xtls-rprx-vision&security=reality&type=tcp' <<< "$links"
assert_true "VLESS keeps its own Reality public key" grep -q 'pbk=vless-public-key' <<< "$links"
assert_true "AnyTLS keeps a separate Reality public key" grep -q 'pbk=anytls-public-key' <<< "$links"

trojan=$(jq -nc --arg tag "$TAG_TROJAN" '{type:"trojan", tag:$tag, listen:"::", listen_port:3443, users:[{name:"ou-sb", password:"trojan-password"}], tls:{enabled:true, certificate_path:"/tmp/fullchain.pem", key_path:"/tmp/privkey.pem"}}')
assert_true "add Trojan TLS inbound" apply_inbound_json "$TAG_TROJAN" "$trojan"
trojan_links=$(show_links)
assert_true "Trojan link is exported" grep -q '^trojan://' <<< "$trojan_links"
assert_true "Trojan tag is managed" protocol_exists "$TAG_TROJAN"

printf '\n%d passed, %d failed\n' "$passes" "$failures"
((failures == 0))
