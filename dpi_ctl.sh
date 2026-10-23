#!/system/bin/sh

case "$0" in
    */*) MODDIR=$(cd "${0%/*}" 2>/dev/null && pwd) ;;
    *)   MODDIR="$PWD" ;;
esac

BIN="$MODDIR/bin/nfqws"
DOH_BIN="$MODDIR/bin/doh_forwarder"
PROP="$MODDIR/module.prop"
CHAIN="APP_DPI"
LEGACY_CHAIN="DISCORD_DPI"
QNUM=200
FWMARK="0x40000000/0x40000000"

# Kalıcı yapılandırma dizini
DATA_DIR="/data/adb/app-dpi-bypass"
CONF="$DATA_DIR/apps.list"
CONFIG_FILE="$DATA_DIR/config.conf"

[ -d "$DATA_DIR" ] || mkdir -p "$DATA_DIR" 2>/dev/null

if [ ! -f "$CONF" ]; then
    if [ -f "$MODDIR/apps.list" ]; then
        cp "$MODDIR/apps.list" "$CONF" 2>/dev/null || true
    else
        cat << 'EOF' > "$CONF" 2>/dev/null || true
com.discord
com.discord.canary
com.discord.ptb
EOF
    fi
fi

if [ ! -f "$CONFIG_FILE" ]; then
    if [ -f "$MODDIR/config.conf" ]; then
        cp "$MODDIR/config.conf" "$CONFIG_FILE" 2>/dev/null || true
    fi
fi

load_config() {
    DPI_MODE="preset"
    PRESET_NAME="discord_optimal"
    TCP_DESYNC="fake"
    TCP_SPLIT_POS="sni"
    TCP_FOOLING="md5sig"
    TCP_TTL_MODE="none"
    TCP_TTL_VALUE="8"
    TCP_PORTS="80,443,2053,2083,2087,2096,8443"
    UDP_DESYNC="fake"
    UDP_REPEATS="2"
    UDP_PORTS="50000-65535,19294-19344"
    UDP_FILTER_L7="discord"
    CUSTOM_EXTRA_ARGS=""
    CUSTOM_PROFILE_NAME=""
    CUSTOM_PROFILE_ARGS=""
    AUTO_TARGET_DOMAIN="discord.com"
    DNS_ENABLED="1"
    DNS_PRESET="cloudflare"
    DNS_UPSTREAM="https://1.1.1.1/dns-query"

    CFG=""
    if [ -f "$CONFIG_FILE" ]; then
        CFG="$CONFIG_FILE"
    elif [ -f "$MODDIR/config.conf" ]; then
        CFG="$MODDIR/config.conf"
    fi

    if [ -n "$CFG" ]; then
        while IFS='=' read -r key val || [ -n "$key" ]; do
            case "$key" in
                \#*|"") continue ;;
            esac
            key=$(echo "$key" | tr -d '[:space:]')
            val=$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
            case "$key" in
                DPI_MODE)           DPI_MODE="$val" ;;
                PRESET_NAME)        PRESET_NAME="$val" ;;
                TCP_DESYNC)         TCP_DESYNC="$val" ;;
                TCP_SPLIT_POS)      TCP_SPLIT_POS="$val" ;;
                TCP_FOOLING)        TCP_FOOLING="$val" ;;
                TCP_TTL_MODE)       TCP_TTL_MODE="$val" ;;
                TCP_TTL_VALUE)      TCP_TTL_VALUE="$val" ;;
                TCP_PORTS)          TCP_PORTS="$val" ;;
                UDP_DESYNC)         UDP_DESYNC="$val" ;;
                UDP_REPEATS)        UDP_REPEATS="$val" ;;
                UDP_PORTS)          UDP_PORTS="$val" ;;
                UDP_FILTER_L7)      UDP_FILTER_L7="$val" ;;
                CUSTOM_EXTRA_ARGS)  CUSTOM_EXTRA_ARGS="$val" ;;
                CUSTOM_PROFILE_NAME) CUSTOM_PROFILE_NAME="$val" ;;
                CUSTOM_PROFILE_ARGS) CUSTOM_PROFILE_ARGS="$val" ;;
                AUTO_TARGET_DOMAIN) AUTO_TARGET_DOMAIN="$val" ;;
                DNS_ENABLED)        DNS_ENABLED="$val" ;;
                DNS_PRESET)         DNS_PRESET="$val" ;;
                DNS_UPSTREAM)       DNS_UPSTREAM="$val" ;;
            esac
        done < "$CFG"
    fi
}

build_nfqws_args() {
    load_config

    if [ "$DPI_MODE" = "custom" ]; then
        echo "$CUSTOM_PROFILE_ARGS"
        return 0
    elif [ "$DPI_MODE" = "preset" ]; then
        case "$PRESET_NAME" in
            discord_optimal)
                ARGS="--filter-tcp=$TCP_PORTS --dpi-desync=fake --dpi-desync-fooling=md5sig"
                ;;
            split_sni_compatible)
                ARGS="--filter-tcp=$TCP_PORTS --dpi-desync=split --dpi-desync-split-pos=sni"
                ;;
            fake_badsum_autottl)
                ARGS="--filter-tcp=$TCP_PORTS --dpi-desync=fake --dpi-desync-fooling=badsum --dpi-desync-autottl=-1"
                ;;
            multisplit_midsni)
                ARGS="--filter-tcp=$TCP_PORTS --dpi-desync=multisplit --dpi-desync-split-pos=2,midsni"
                ;;
            disorder_sni)
                ARGS="--filter-tcp=$TCP_PORTS --dpi-desync=disorder --dpi-desync-split-pos=sni"
                ;;
            *)
                ARGS="--filter-tcp=$TCP_PORTS --dpi-desync=fake --dpi-desync-fooling=md5sig"
                ;;
        esac
        # UDP WebRTC kuralları
        ARGS="$ARGS --new --filter-udp=$UDP_PORTS"
        [ -n "$UDP_FILTER_L7" ] && ARGS="$ARGS --filter-l7=$UDP_FILTER_L7"
        ARGS="$ARGS --dpi-desync=fake --dpi-desync-repeats=2"
    else
        # Manuel mod
        ARGS="--filter-tcp=$TCP_PORTS --dpi-desync=$TCP_DESYNC"
        case "$TCP_DESYNC" in
            split|disorder|multisplit)
                [ -n "$TCP_SPLIT_POS" ] && ARGS="$ARGS --dpi-desync-split-pos=$TCP_SPLIT_POS"
                ;;
            fake)
                [ "$TCP_FOOLING" != "none" ] && [ -n "$TCP_FOOLING" ] && ARGS="$ARGS --dpi-desync-fooling=$TCP_FOOLING"
                ;;
        esac
        if [ "$TCP_TTL_MODE" = "auto" ]; then
            ARGS="$ARGS --dpi-desync-autottl=-1"
        elif [ "$TCP_TTL_MODE" = "custom" ] && [ -n "$TCP_TTL_VALUE" ]; then
            ARGS="$ARGS --dpi-desync-ttl=$TCP_TTL_VALUE"
        fi

        # UDP kuralları
        if [ "$UDP_DESYNC" != "none" ] && [ -n "$UDP_DESYNC" ]; then
            ARGS="$ARGS --new --filter-udp=$UDP_PORTS"
            [ -n "$UDP_FILTER_L7" ] && ARGS="$ARGS --filter-l7=$UDP_FILTER_L7"
            ARGS="$ARGS --dpi-desync=$UDP_DESYNC"
            [ -n "$UDP_REPEATS" ] && ARGS="$ARGS --dpi-desync-repeats=$UDP_REPEATS"
        fi

        # Uzman serbest parametreleri
        [ -n "$CUSTOM_EXTRA_ARGS" ] && ARGS="$ARGS $CUSTOM_EXTRA_ARGS"
    fi

    echo "$ARGS"
}

# Hedef paketlerin UID listesini deterministik olarak çözer
get_target_uids() {
    [ -f "$CONF" ] || return 0
    PKGS=$(grep -vE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null)
    [ -z "$PKGS" ] && return 0

    UIDS=""
    if [ -f "/data/system/packages.list" ]; then
        for pkg in $PKGS; do
            U=$(awk -v p="$pkg" '$1 == p {print $2}' /data/system/packages.list 2>/dev/null)
            [ -n "$U" ] && UIDS="$UIDS $U"
        done
    fi
    if [ -z "$UIDS" ]; then
        for pkg in $PKGS; do
            if [ -d "/data/data/$pkg" ]; then
                U=$(stat -c %u "/data/data/$pkg" 2>/dev/null)
                [ -n "$U" ] && UIDS="$UIDS $U"
            fi
        done
    fi
    if [ -z "$UIDS" ]; then
        for pkg in $PKGS; do
            U=$(dumpsys package "$pkg" 2>/dev/null | grep -m1 -E 'appId=|userId=' | cut -d= -f2 | tr -d ' \r\n')
            [ -n "$U" ] && UIDS="$UIDS $U"
        done
    fi
    echo "$UIDS" | tr ' ' '\n' | sort -u | tr '\n' ' '
}

is_running() {
    if pidof nfqws >/dev/null 2>&1 && \
       iptables -t mangle -C OUTPUT -j $CHAIN >/dev/null 2>&1 && \
       iptables -t mangle -S $CHAIN 2>/dev/null | grep -q NFQUEUE; then
        return 0
    fi
    return 1
}

update_desc() {
    NEW_DESC="$1"
    if [ -f "$PROP" ]; then
        sed -i "s|^description=.*|description=$NEW_DESC|" "$PROP" 2>/dev/null
    fi
    if [ -f "/data/adb/modules/app-dpi-bypass/module.prop" ]; then
        sed -i "s|^description=.*|description=$NEW_DESC|" "/data/adb/modules/app-dpi-bypass/module.prop" 2>/dev/null
    fi
}

apply_iptables_rules() {
    UIDS="$1"
    echo "[*] Applying iptables & ip6tables rules (UIDs: $UIDS)..."

    for ipt in iptables ip6tables; do
        while $ipt -t mangle -D OUTPUT -j $LEGACY_CHAIN 2>/dev/null; do :; done
        $ipt -t mangle -F $LEGACY_CHAIN 2>/dev/null
        $ipt -t mangle -X $LEGACY_CHAIN 2>/dev/null

        $ipt -t mangle -N $CHAIN 2>/dev/null
        $ipt -t mangle -F $CHAIN 2>/dev/null
        $ipt -t mangle -A $CHAIN -m mark --mark $FWMARK -j RETURN

        if [ -n "$UIDS" ]; then
            for uid in $UIDS; do
                $ipt -t mangle -A $CHAIN -m owner --uid-owner "$uid" -p tcp -m multiport --dports 80,443,2053,2083,2087,2096,8443 -j NFQUEUE --queue-num $QNUM --queue-bypass
                $ipt -t mangle -A $CHAIN -m owner --uid-owner "$uid" -p udp --dport 50000:65535 -j NFQUEUE --queue-num $QNUM --queue-bypass
                $ipt -t mangle -A $CHAIN -m owner --uid-owner "$uid" -p udp --dport 19294:19344 -j NFQUEUE --queue-num $QNUM --queue-bypass
            done
        fi

        $ipt -t mangle -C OUTPUT -j $CHAIN 2>/dev/null || $ipt -t mangle -I OUTPUT 1 -j $CHAIN
    done
}

clean_iptables_rules() {
    echo "[*] Clearing iptables & ip6tables rules..."
    for ipt in iptables ip6tables; do
        for ch in $CHAIN $LEGACY_CHAIN; do
            while $ipt -t mangle -D OUTPUT -j $ch 2>/dev/null; do :; done
            $ipt -t mangle -F $ch 2>/dev/null
            $ipt -t mangle -X $ch 2>/dev/null
        done
    done
}

start_nfqws() {
    if ! pidof nfqws >/dev/null 2>&1; then
        echo "[*] Starting nfqws daemon..."
        killall -9 nfqws 2>/dev/null
        NFQ_ARGS=$(build_nfqws_args)
        echo "[*] nfqws parameters: $NFQ_ARGS"
        eval "$BIN --daemon --uid=0:0,3003 --qnum=$QNUM $NFQ_ARGS"
        sleep 0.5
    fi
}

start_doh() {
    load_config
    if [ "$DNS_ENABLED" = "1" ] && [ -x "$DOH_BIN" ]; then
        if ! pidof doh_forwarder >/dev/null 2>&1; then
            echo "[*] Starting DoH forwarder daemon (upstream: $DNS_UPSTREAM)..."
            killall -9 doh_forwarder 2>/dev/null
            "$DOH_BIN" -listen 127.0.0.1:5354 -upstream "$DNS_UPSTREAM" -config "$CONFIG_FILE" >/dev/null 2>&1 &
            sleep 0.2
        fi
    fi
}

stop_doh() {
    killall -9 doh_forwarder 2>/dev/null
}

start() {
    UIDS=$(get_target_uids)
    if [ -z "$UIDS" ]; then
        echo "[-] Warning: Target packages or active UIDs not found in apps.list!"
        update_desc "[Inactive 🔴] apps.list is empty or target apps are not installed. Select apps in WebUI."
        return 1
    fi

    APP_COUNT=$(grep -cvE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null)
    apply_iptables_rules "$UIDS"
    start_nfqws
    start_doh

    if pidof nfqws >/dev/null 2>&1; then
        load_config
        echo "[+] App DPI Bypass started (PID: $(pidof nfqws), $APP_COUNT apps, Mode: $DPI_MODE)."
        update_desc "[Active 🟢] DPI bypass active for $APP_COUNT apps (Mode: $PRESET_NAME, UID: $UIDS)."
        return 0
    else
        echo "[-] Error: nfqws failed to start!"
        stop
        return 1
    fi
}

stop() {
    echo "[*] Stopping nfqws..."
    killall -9 nfqws 2>/dev/null
    stop_doh
    clean_iptables_rules
    update_desc "[Inactive 🔴] DPI bypass stopped. Start via WebUI or Action button."
    echo "[+] App DPI Bypass stopped."
}

reload() {
    UIDS=$(get_target_uids)
    APP_COUNT=$(grep -cvE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null)
    if [ -z "$UIDS" ]; then
        echo "[-] No target UIDs remaining, clearing rules..."
        clean_iptables_rules
        killall -9 nfqws 2>/dev/null
        stop_doh
        update_desc "[Inactive 🔴] No target apps selected. Select applications in WebUI."
        return 0
    fi

    apply_iptables_rules "$UIDS"
    killall -9 nfqws 2>/dev/null
    start_nfqws
    stop_doh
    start_doh
    load_config
    update_desc "[Active 🟢] DPI bypass active for $APP_COUNT apps (Mode: $PRESET_NAME, UID: $UIDS)."
    echo "[+] Configuration reloaded ($APP_COUNT apps, UID: $UIDS)."
}

status() {
    load_config
    if is_running; then
        UIDS=$(get_target_uids)
        APP_COUNT=$(grep -cvE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null)
        PKTS=$(iptables -t mangle -L $CHAIN -n -v -x 2>/dev/null | awk '$3=="NFQUEUE"{s+=$1} END{print s+0}')
        BYTES=$(iptables -t mangle -L $CHAIN -n -v -x 2>/dev/null | awk '$3=="NFQUEUE"{s+=$2} END{print s+0}')
        if [ "$DPI_MODE" = "preset" ]; then
            MODE_STR="Preset ($PRESET_NAME)"
        elif [ "$DPI_MODE" = "custom" ]; then
            MODE_STR="Custom Profile ($CUSTOM_PROFILE_NAME)"
        else
            MODE_STR="Manual ($TCP_DESYNC, fooling: $TCP_FOOLING)"
        fi
        echo "Status: Active 🟢 (PID: $(pidof nfqws))"
        echo "Mode: $MODE_STR"
        echo "Target Apps: $APP_COUNT packages (UID: $UIDS)"
        echo "Processed Traffic: $PKTS packets ($(awk -v b="$BYTES" 'BEGIN{if(b>1048576) printf "%.2f MB", b/1048576; else printf "%.2f KB", b/1024}') )"
        if [ "$DNS_ENABLED" = "1" ]; then
            DOH_PID=$(pidof doh_forwarder 2>/dev/null)
            if [ -n "$DOH_PID" ]; then
                echo "Zygisk DoH DNS: Active 🟢 (PID: $DOH_PID, Upstream: $DNS_UPSTREAM)"
            else
                echo "Zygisk DoH DNS: Standby 🟡 (Upstream: $DNS_UPSTREAM)"
            fi
        else
            echo "Zygisk DoH DNS: Disabled ⚪"
        fi
    else
        echo "Status: Inactive 🔴"
        echo "Rules disabled or nfqws is not running."
    fi
}

toggle() {
    if is_running; then
        stop
    else
        start
    fi
}

get_data() {
    echo "---STATUS---"
    PID=$(pidof nfqws 2>/dev/null)
    if [ -n "$PID" ] && iptables -t mangle -C OUTPUT -j $CHAIN >/dev/null 2>&1; then
        PKTS=$(iptables -t mangle -L $CHAIN -n -v -x 2>/dev/null | awk '$3=="NFQUEUE"{s+=$1} END{print s+0}')
        BYTES=$(iptables -t mangle -L $CHAIN -n -v -x 2>/dev/null | awk '$3=="NFQUEUE"{s+=$2} END{print s+0}')
        echo "active|$PID|$PKTS|$BYTES"
    else
        echo "inactive|0|0|0"
    fi

    echo "---SELECTED---"
    if [ -f "$CONF" ]; then
        grep -vE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null
    fi

    echo "---APPS---"
    T_USER="/data/local/tmp/user_pkgs_$$.txt"
    pm list packages -3 2>/dev/null | sed 's/^package://' | sort > "$T_USER"
    awk '
    FNR==NR { u[$1]=1; next }
    $2 >= 10000 && !/^\s*$/ {
        print $1 "\t" $2 "\t" (u[$1] ? 1 : 0)
    }' "$T_USER" /data/system/packages.list 2>/dev/null
    rm -f "$T_USER"

    echo "---CONFIG---"
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    elif [ -f "$MODDIR/config.conf" ]; then
        cat "$MODDIR/config.conf"
    fi

    echo "---CUSTOM-PROFILES---"
    if [ -f "$DATA_DIR/custom_profiles.json" ]; then
        cat "$DATA_DIR/custom_profiles.json"
    else
        echo "[]"
    fi

    echo "---DNS-STATUS---"
    DOH_PID=$(pidof doh_forwarder 2>/dev/null)
    ZYGISK_INSTALLED="0"
    [ -f "$MODDIR/zygisk/arm64-v8a.so" ] && ZYGISK_INSTALLED="1"
    load_config
    if [ -n "$DOH_PID" ]; then
        echo "active|$DOH_PID|$DNS_ENABLED|$DNS_PRESET|$DNS_UPSTREAM|$ZYGISK_INSTALLED"
    else
        echo "inactive|0|$DNS_ENABLED|$DNS_PRESET|$DNS_UPSTREAM|$ZYGISK_INSTALLED"
    fi
}

save_apps() {
    mkdir -p "$DATA_DIR"
    TMP="$DATA_DIR/apps.list.tmp"
    if [ $# -gt 0 ]; then
        printf "%s\n" "$@" > "$TMP"
    else
        : > "$TMP"
    fi
    mv -f "$TMP" "$CONF"
    cp -f "$CONF" "$MODDIR/apps.list" 2>/dev/null || true
    reload
}

save_config() {
    mkdir -p "$DATA_DIR"
    TMP="$DATA_DIR/config.conf.tmp"
    cat << EOF > "$TMP"
# App DPI Bypass Yapılandırma Dosyası
DPI_MODE="${1:-preset}"
PRESET_NAME="${2:-discord_optimal}"
TCP_DESYNC="${3:-fake}"
TCP_SPLIT_POS="${4:-sni}"
TCP_FOOLING="${5:-md5sig}"
TCP_TTL_MODE="${6:-none}"
TCP_TTL_VALUE="${7:-8}"
TCP_PORTS="${8:-80,443,2053,2083,2087,2096,8443}"
UDP_DESYNC="${9:-fake}"
UDP_REPEATS="${10:-2}"
UDP_PORTS="${11:-50000-65535,19294-19344}"
UDP_FILTER_L7="${12:-discord}"
CUSTOM_EXTRA_ARGS="${13:-}"
AUTO_TARGET_DOMAIN="${14:-discord.com}"
CUSTOM_PROFILE_NAME="${15:-}"
CUSTOM_PROFILE_ARGS="${16:-}"
DNS_ENABLED="${17:-1}"
DNS_PRESET="${18:-cloudflare}"
DNS_UPSTREAM="${19:-https://1.1.1.1/dns-query}"
EOF
    mv -f "$TMP" "$CONFIG_FILE"
    cp -f "$CONFIG_FILE" "$MODDIR/config.conf" 2>/dev/null || true
    echo "[+] Configuration saved ($CONFIG_FILE)."
    if is_running; then
        echo "[*] Restarting services with updated configuration..."
        killall -9 nfqws 2>/dev/null
        start_nfqws
        stop_doh
        start_doh
    fi
}

set_preset() {
    TARGET_PRESET="$1"
    [ -z "$TARGET_PRESET" ] && return 1
    load_config
    save_config "preset" "$TARGET_PRESET" "$TCP_DESYNC" "$TCP_SPLIT_POS" "$TCP_FOOLING" "$TCP_TTL_MODE" "$TCP_TTL_VALUE" "$TCP_PORTS" "$UDP_DESYNC" "$UDP_REPEATS" "$UDP_PORTS" "$UDP_FILTER_L7" "$CUSTOM_EXTRA_ARGS" "$AUTO_TARGET_DOMAIN" "$CUSTOM_PROFILE_NAME" "$CUSTOM_PROFILE_ARGS" "$DNS_ENABLED" "$DNS_PRESET" "$DNS_UPSTREAM"
}

set_custom_profile() {
    NAME="$1"
    shift
    ARGS="$*"
    [ -z "$NAME" ] && return 1
    load_config
    save_config "custom" "$PRESET_NAME" "$TCP_DESYNC" "$TCP_SPLIT_POS" "$TCP_FOOLING" "$TCP_TTL_MODE" "$TCP_TTL_VALUE" "$TCP_PORTS" "$UDP_DESYNC" "$UDP_REPEATS" "$UDP_PORTS" "$UDP_FILTER_L7" "$CUSTOM_EXTRA_ARGS" "$AUTO_TARGET_DOMAIN" "$NAME" "$ARGS" "$DNS_ENABLED" "$DNS_PRESET" "$DNS_UPSTREAM"
}

set_dns() {
    ENABLED="${1:-1}"
    UPSTREAM="${2:-https://1.1.1.1/dns-query}"
    PRESET="${3:-custom}"
    load_config
    save_config "$DPI_MODE" "$PRESET_NAME" "$TCP_DESYNC" "$TCP_SPLIT_POS" "$TCP_FOOLING" "$TCP_TTL_MODE" "$TCP_TTL_VALUE" "$TCP_PORTS" "$UDP_DESYNC" "$UDP_REPEATS" "$UDP_PORTS" "$UDP_FILTER_L7" "$CUSTOM_EXTRA_ARGS" "$AUTO_TARGET_DOMAIN" "$CUSTOM_PROFILE_NAME" "$CUSTOM_PROFILE_ARGS" "$ENABLED" "$PRESET" "$UPSTREAM"
    echo "[+] DNS settings updated: ENABLED=$ENABLED, PRESET=$PRESET, UPSTREAM=$UPSTREAM"
}

test_dns() {
    DOM="${1:-discord.com}"
    load_config
    if [ -x "$DOH_BIN" ]; then
        "$DOH_BIN" -test "$DOM" -upstream "$DNS_UPSTREAM"
    else
        echo "FAILED|$DOM|doh_forwarder binary not found|0ms"
    fi
}

save_custom_profiles() {
    JSON_DATA="$1"
    mkdir -p "$DATA_DIR"
    TMP="$DATA_DIR/custom_profiles.json.tmp"
    printf "%s\n" "$JSON_DATA" > "$TMP"
    mv -f "$TMP" "$DATA_DIR/custom_profiles.json"
    echo "[+] Custom profiles updated."
}

autotune_init() {
    TARGET_DOM="${1:-discord.com}"
    TARGET_IP=""
    if [ -x "/system/bin/toybox" ]; then
        TARGET_IP=$(toybox ping -c 1 -W 2 "$TARGET_DOM" 2>/dev/null | grep -m1 -oE '\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)' | tr -d '()')
    fi
    if [ -z "$TARGET_IP" ]; then
        TARGET_IP=$(ping -c 1 -W 2 "$TARGET_DOM" 2>/dev/null | grep -m1 -oE '\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)' | tr -d '()')
    fi

    if [ -z "$TARGET_IP" ]; then
        echo "ERROR|DNS resolution failed for $TARGET_DOM"
        return 1
    fi

    WAS_RUNNING=0
    pidof nfqws >/dev/null 2>&1 && WAS_RUNNING=1
    killall -9 nfqws 2>/dev/null

    mkdir -p "$DATA_DIR"
    echo "$TARGET_IP|$WAS_RUNNING" > "$DATA_DIR/.autotune_state"

    iptables -t mangle -I OUTPUT 1 -d "$TARGET_IP" -p tcp --dport 443 -j NFQUEUE --queue-num "$QNUM" --queue-bypass 2>/dev/null
    echo "OK|$TARGET_IP"
}

autotune_probe() {
    NAME="$1"
    TARGET_DOM="${2:-discord.com}"
    [ -z "$NAME" ] && return 1

    case "$NAME" in
        discord_optimal)
            PARAM="--filter-tcp=80,443 --dpi-desync=fake --dpi-desync-fooling=md5sig"
            ;;
        split_sni_compatible)
            PARAM="--filter-tcp=80,443 --dpi-desync=split --dpi-desync-split-pos=sni"
            ;;
        fake_badsum_autottl)
            PARAM="--filter-tcp=80,443 --dpi-desync=fake --dpi-desync-fooling=badsum --dpi-desync-autottl=-1"
            ;;
        multisplit_midsni)
            PARAM="--filter-tcp=80,443 --dpi-desync=multisplit --dpi-desync-split-pos=2,midsni"
            ;;
        disorder_sni)
            PARAM="--filter-tcp=80,443 --dpi-desync=disorder --dpi-desync-split-pos=sni"
            ;;
        *)
            PARAM="--filter-tcp=80,443 --dpi-desync=fake --dpi-desync-fooling=md5sig"
            ;;
    esac

    killall -9 nfqws 2>/dev/null
    eval "$BIN --daemon --uid=0:0,3003 --qnum=$QNUM $PARAM" 2>/dev/null
    sleep 0.25

    PROBE=$(curl -s -k -o /dev/null -w "%{http_code} %{time_total}" --connect-timeout 2 -m 3 "https://$TARGET_DOM" 2>/dev/null || echo "000 0")
    HTTP_CODE=$(echo "$PROBE" | awk '{print $1}')
    TIME_SEC=$(echo "$PROBE" | awk '{print $2}')

    killall -9 nfqws 2>/dev/null

    if [ "$HTTP_CODE" != "000" ] && [ -n "$HTTP_CODE" ]; then
        MS=$(awk -v t="$TIME_SEC" 'BEGIN{printf "%.0f", t*1000}')
        echo "RESULT|$NAME|SUCCESS|$HTTP_CODE|${MS}ms|$TIME_SEC"
    else
        echo "RESULT|$NAME|FAILED|TIMEOUT|0ms|9999"
    fi
}

autotune_finish() {
    STATE_FILE="$DATA_DIR/.autotune_state"
    if [ -f "$STATE_FILE" ]; then
        TARGET_IP=$(cut -d'|' -f1 "$STATE_FILE" 2>/dev/null)
        WAS_RUNNING=$(cut -d'|' -f2 "$STATE_FILE" 2>/dev/null)
        if [ -n "$TARGET_IP" ]; then
            iptables -t mangle -D OUTPUT -d "$TARGET_IP" -p tcp --dport 443 -j NFQUEUE --queue-num "$QNUM" --queue-bypass 2>/dev/null
        fi
        rm -f "$STATE_FILE"
        if [ "$WAS_RUNNING" = "1" ]; then
            start_nfqws
        fi
    fi
    echo "FINISHED"
}

autotune() {
    TARGET_DOM="${1:-discord.com}"
    echo "=== AUTOTUNE START ==="
    echo "Target: $TARGET_DOM"

    INIT_OUT=$(autotune_init "$TARGET_DOM")
    STATUS=$(echo "$INIT_OUT" | cut -d'|' -f1)
    if [ "$STATUS" != "OK" ]; then
        echo "$INIT_OUT"
        echo "=== AUTOTUNE END ==="
        return 1
    fi
    TARGET_IP=$(echo "$INIT_OUT" | cut -d'|' -f2)
    echo "Resolved IP: $TARGET_IP"

    WINNER=""
    BEST_TIME="9999"

    for strat in discord_optimal split_sni_compatible fake_badsum_autottl multisplit_midsni disorder_sni; do
        OUT=$(autotune_probe "$strat" "$TARGET_DOM")
        echo "$OUT" | cut -d'|' -f1-5
        S_STAT=$(echo "$OUT" | cut -d'|' -f3)
        T_SEC=$(echo "$OUT" | cut -d'|' -f6)
        if [ "$S_STAT" = "SUCCESS" ]; then
            IS_BETTER=$(awk -v t1="$T_SEC" -v t2="$BEST_TIME" 'BEGIN{print (t1 < t2) ? 1 : 0}')
            if [ "$IS_BETTER" -eq 1 ]; then
                BEST_TIME="$T_SEC"
                WINNER="$strat"
            fi
        fi
    done

    autotune_finish >/dev/null 2>&1

    if [ -n "$WINNER" ]; then
        WINNER_MS=$(awk -v t="$BEST_TIME" 'BEGIN{printf "%.0f", t*1000}')
        echo "WINNER|$WINNER|${WINNER_MS}ms"
    else
        echo "WINNER|NONE|0ms"
    fi

    echo "=== AUTOTUNE END ==="
}

add_app() {
    PKG="$1"
    [ -z "$PKG" ] && return 1
    mkdir -p "$DATA_DIR"
    if ! grep -qxF "$PKG" "$CONF" 2>/dev/null; then
        echo "$PKG" >> "$CONF"
        echo "[+] Added package: $PKG"
        reload
    else
        echo "[!] Package already added: $PKG"
    fi
}

del_app() {
    PKG="$1"
    [ -z "$PKG" ] && return 1
    if [ -f "$CONF" ]; then
        sed -i "/^$PKG$/d" "$CONF" 2>/dev/null
        echo "[+] Removed package: $PKG"
        reload
    fi
}

preview_cli() {
    load_config
    echo "$BIN --daemon --uid=0:0,3003 --qnum=$QNUM $(build_nfqws_args)"
}

case "$1" in
    start)       start ;;
    stop)        stop ;;
    restart)     stop; sleep 1; start ;;
    reload)      reload ;;
    toggle)      toggle ;;
    status)      status ;;
    get-data)    get_data ;;
    save-apps)   shift; save_apps "$@" ;;
    save-config) shift; save_config "$@" ;;
    set-preset)  shift; set_preset "$@" ;;
    set-custom-profile) shift; set_custom_profile "$@" ;;
    save-custom-profiles) shift; save_custom_profiles "$@" ;;
    set-dns)     shift; set_dns "$@" ;;
    test-dns)    shift; test_dns "$@" ;;
    autotune)    shift; autotune "$@" ;;
    autotune-init) shift; autotune_init "$@" ;;
    autotune-probe) shift; autotune_probe "$@" ;;
    autotune-finish) shift; autotune_finish "$@" ;;
    preview-cli) preview_cli ;;
    add-app)     shift; add_app "$@" ;;
    del-app)     shift; del_app "$@" ;;
    *)
        echo "Kullanım: $0 {start|stop|restart|reload|toggle|status|get-data|save-apps|save-config|set-preset|set-custom-profile|save-custom-profiles|set-dns|test-dns|autotune|preview-cli|add-app|del-app}"
        exit 1
        ;;
esac
