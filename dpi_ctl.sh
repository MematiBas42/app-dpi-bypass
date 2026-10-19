#!/system/bin/sh

case "$0" in
    */*) MODDIR=$(cd "${0%/*}" 2>/dev/null && pwd) ;;
    *)   MODDIR="$PWD" ;;
esac

BIN="$MODDIR/bin/nfqws"
PROP="$MODDIR/module.prop"
CHAIN="APP_DPI"
LEGACY_CHAIN="DISCORD_DPI"
QNUM=200
FWMARK="0x40000000/0x40000000"

# Kalıcı yapılandırma dizini
DATA_DIR="/data/adb/app-dpi-bypass"
CONF="$DATA_DIR/apps.list"

[ -d "$DATA_DIR" ] || mkdir -p "$DATA_DIR"
if [ ! -f "$CONF" ]; then
    if [ -f "$MODDIR/apps.list" ]; then
        cp "$MODDIR/apps.list" "$CONF"
    else
        cat << 'EOF' > "$CONF"
com.discord
com.discord.canary
com.discord.ptb
EOF
    fi
fi

# Hedef paketlerin UID listesini deterministik olarak çözer
get_target_uids() {
    [ -f "$CONF" ] || return 0
    PKGS=$(grep -vE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null)
    [ -z "$PKGS" ] && return 0

    UIDS=""
    # 1. En hızlı ve güvenilir kaynak: Android packages.list
    if [ -f "/data/system/packages.list" ]; then
        for pkg in $PKGS; do
            U=$(awk -v p="$pkg" '$1 == p {print $2}' /data/system/packages.list 2>/dev/null)
            [ -n "$U" ] && UIDS="$UIDS $U"
        done
    fi
    # 2. Yedek: stat /data/data
    if [ -z "$UIDS" ]; then
        for pkg in $PKGS; do
            if [ -d "/data/data/$pkg" ]; then
                U=$(stat -c %u "/data/data/$pkg" 2>/dev/null)
                [ -n "$U" ] && UIDS="$UIDS $U"
            fi
        done
    fi
    # 3. Yedek: dumpsys appId
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
}

apply_iptables_rules() {
    UIDS="$1"
    echo "[*] iptables & ip6tables kuralları uygulanıyor (UID listesi: $UIDS)..."

    for ipt in iptables ip6tables; do
        # Eski ve legacy zincirleri temizle
        while $ipt -t mangle -D OUTPUT -j $LEGACY_CHAIN 2>/dev/null; do :; done
        $ipt -t mangle -F $LEGACY_CHAIN 2>/dev/null
        $ipt -t mangle -X $LEGACY_CHAIN 2>/dev/null

        # Yeni zincir oluştur ve temizle
        $ipt -t mangle -N $CHAIN 2>/dev/null
        $ipt -t mangle -F $CHAIN 2>/dev/null
        $ipt -t mangle -A $CHAIN -m mark --mark $FWMARK -j RETURN

        if [ -n "$UIDS" ]; then
            for uid in $UIDS; do
                # Standart ve alternatif TLS / HTTPS portları
                $ipt -t mangle -A $CHAIN -m owner --uid-owner "$uid" -p tcp -m multiport --dports 80,443,2053,2083,2087,2096,8443 -j NFQUEUE --queue-num $QNUM --queue-bypass
                # WebRTC, Ses / Video UDP portları
                $ipt -t mangle -A $CHAIN -m owner --uid-owner "$uid" -p udp --dport 50000:65535 -j NFQUEUE --queue-num $QNUM --queue-bypass
                $ipt -t mangle -A $CHAIN -m owner --uid-owner "$uid" -p udp --dport 19294:19344 -j NFQUEUE --queue-num $QNUM --queue-bypass
            done
        fi

        $ipt -t mangle -C OUTPUT -j $CHAIN 2>/dev/null || $ipt -t mangle -I OUTPUT 1 -j $CHAIN
    done
}

clean_iptables_rules() {
    echo "[*] iptables & ip6tables kuralları temizleniyor..."
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
        echo "[*] nfqws daemon başlatılıyor..."
        killall -9 nfqws 2>/dev/null
        $BIN --daemon \
             --uid=0:0,3003 \
             --qnum=$QNUM \
             --filter-tcp=80,443,2053,2083,2087,2096,8443 \
             --dpi-desync=fake \
             --dpi-desync-fooling=md5sig \
             --new \
             --filter-udp=50000-65535,19294-19344 \
             --filter-l7=discord \
             --dpi-desync=fake \
             --dpi-desync-repeats=2
        sleep 0.5
    fi
}

start() {
    UIDS=$(get_target_uids)
    if [ -z "$UIDS" ]; then
        echo "[-] Uyarı: apps.list içinde hedef paket veya aktif UID bulunamadı!"
        update_desc "[Pasif 🔴] apps.list boş veya seçili uygulamalar yüklü değil. WebUI üzerinden uygulama seçin."
        return 1
    fi

    APP_COUNT=$(grep -cvE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null)
    apply_iptables_rules "$UIDS"
    start_nfqws

    if pidof nfqws >/dev/null 2>&1; then
        echo "[+] App DPI Bypass başlatıldı (PID: $(pidof nfqws), $APP_COUNT uygulama)."
        update_desc "[Aktif 🟢] $APP_COUNT uygulama için DPI bypass aktif (UID: $UIDS)."
        return 0
    else
        echo "[-] Hata: nfqws başlatılamadı!"
        stop
        return 1
    fi
}

stop() {
    echo "[*] nfqws durduruluyor..."
    killall -9 nfqws 2>/dev/null
    clean_iptables_rules
    update_desc "[Pasif 🔴] DPI bypass durduruldu. WebUI veya Action butonu ile başlatabilirsiniz."
    echo "[+] App DPI Bypass durduruldu."
}

reload() {
    UIDS=$(get_target_uids)
    APP_COUNT=$(grep -cvE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null)
    if [ -z "$UIDS" ]; then
        echo "[-] Hedef UID kalmadı, kurallar temizleniyor..."
        clean_iptables_rules
        killall -9 nfqws 2>/dev/null
        update_desc "[Pasif 🔴] Hiçbir uygulama seçili değil. WebUI üzerinden uygulama seçin."
        return 0
    fi

    apply_iptables_rules "$UIDS"
    start_nfqws
    update_desc "[Aktif 🟢] $APP_COUNT uygulama için DPI bypass aktif (UID: $UIDS)."
    echo "[+] Yapılandırma yenilendi ($APP_COUNT uygulama, UID: $UIDS)."
}

status() {
    if is_running; then
        UIDS=$(get_target_uids)
        APP_COUNT=$(grep -cvE '^[[:space:]]*(#|$)' "$CONF" 2>/dev/null)
        PKTS=$(iptables -t mangle -L $CHAIN -n -v -x 2>/dev/null | awk '$3=="NFQUEUE"{s+=$1} END{print s+0}')
        BYTES=$(iptables -t mangle -L $CHAIN -n -v -x 2>/dev/null | awk '$3=="NFQUEUE"{s+=$2} END{print s+0}')
        echo "Durum: Aktif 🟢 (PID: $(pidof nfqws))"
        echo "Hedef Uygulamalar: $APP_COUNT adet (UID: $UIDS)"
        echo "İşlenen Trafik: $PKTS paket ($(awk -v b="$BYTES" 'BEGIN{if(b>1048576) printf "%.2f MB", b/1048576; else printf "%.2f KB", b/1024}') )"
    else
        echo "Durum: Pasif 🔴"
        echo "Kurallar devre dışı veya nfqws çalışmıyor."
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
    reload
}

add_app() {
    PKG="$1"
    [ -z "$PKG" ] && return 1
    mkdir -p "$DATA_DIR"
    if ! grep -qxF "$PKG" "$CONF" 2>/dev/null; then
        echo "$PKG" >> "$CONF"
        echo "[+] Paket eklendi: $PKG"
        reload
    else
        echo "[!] Paket zaten ekli: $PKG"
    fi
}

del_app() {
    PKG="$1"
    [ -z "$PKG" ] && return 1
    if [ -f "$CONF" ]; then
        sed -i "/^$PKG$/d" "$CONF" 2>/dev/null
        echo "[+] Paket çıkarıldı: $PKG"
        reload
    fi
}

case "$1" in
    start)    start ;;
    stop)     stop ;;
    restart)  stop; sleep 1; start ;;
    reload)   reload ;;
    toggle)   toggle ;;
    status)   status ;;
    get-data) get_data ;;
    save-apps) shift; save_apps "$@" ;;
    add-app)  shift; add_app "$@" ;;
    del-app)  shift; del_app "$@" ;;
    *)
        echo "Kullanım: $0 {start|stop|restart|reload|toggle|status|get-data|save-apps|add-app|del-app}"
        exit 1
        ;;
esac
