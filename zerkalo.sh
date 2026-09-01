#!/bin/sh
# =========================================
# Zapret Manager by StressOzz
# =========================================
clear

ZAPRET_MANAGER_VERSION="9.85"; STR_VERSION_AUTOINSTALL="v7"
GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; BLUE="\033[0;34m"; NC="\033[0m"; DGRAY="\033[38;5;244m"

GH_RAW_HOST="https://raw.githubusercontent.com"; GH_MAIN_HOST="https://github.com"
GH_RAW="$GH_RAW_HOST"
GH_MAIN="$GH_MAIN_HOST"
BASE_URL="${GH_MAIN}/2Grey/awg-openwrt/releases/download/"
FLOWSEAL_STR_ZIP="${GH_MAIN}/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip"
GEO_HOSTS="${GH_RAW}/Internet-Helper/GeoHideDNS/refs/heads/main/hosts/hosts"
STR_URL="${GH_RAW}/StressOzz/Zapret-Manager/refs/heads/main/files/StrYoutube"
RAW="${GH_RAW}/hyperion-cs/dpi-checkers/refs/heads/main/ru/tcp-16-20/suite.v2.json"
RKN_URL="${GH_RAW}/IndeecFOX/zapret4rocket/refs/heads/master/extra_strats/TCP/RKN/List.txt"
URL_OLD="${GH_RAW}/StressOzz/Zapret-Manager/refs/heads/main/files/MagiTrickle/configOLD.yaml"
URL_DEFAULT="${GH_RAW}/StressOzz/Zapret-Manager/refs/heads/main/files/MagiTrickle/config.yaml"
URL_ITDOG="${GH_RAW}/StressOzz/Zapret-Manager/refs/heads/main/files/MagiTrickle/configAD.yaml"
EXCLUDE_URL="${GH_RAW}/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt"

PORTS_UDP="88,1024-2407,2409-4499,4502-19293,19345-49999,50101-65535"; PORTS_TCP="2802,2302,2502,3478-3480,3724,6000-8000,8085,8090,8100,8903,8904,25565,27015-27030,27036-27037,50001,60442"

DOMAINS="youtu.be youtube.com i.ytimg.com i9.ytimg.com yt3.ggpht.com yt4.ggpht.com googleapis.com jnn-pa.googleapis.com googleusercontent.com signaler-pa.youtube.com youtubei.googleapis.com manifest.googlevideo.com yt3.googleusercontent.com rr4---sn-4g5e6nze.googlevideo.com rr4---sn-5go7yner.googlevideo.com rr4---sn-q4flrnsl.googlevideo.com rr5---sn-n8v7knez.googlevideo.com rr2---sn-q4fl6ndl.googlevideo.com rr1---sn-q4fl6n6y.googlevideo.com rr1---sn-aj5go5-53.googlevideo.com rr1---sn-4axm-n8vs.googlevideo.com rr14---sn-n8v7kn7r.googlevideo.com rr16---sn-axq7sn76.googlevideo.com rr4---sn-jvhnu5g-c35d.googlevideo.com rr1---sn-8ph2xajvh-5xge.googlevideo.com rr1---sn-xguxaxjvh-gufl.googlevideo.com rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com rr1---sn-gvnuxaxjvh-jx3l.googlevideo.com rr1---sn-gvnuxaxjvh-o8ge.googlevideo.com rr5---sn-gvnuxaxjvh-n8vk.googlevideo.com rr10---sn-gvnuxaxjvh-304z.googlevideo.com rr12---sn-gvnuxaxjvh-bvwz.googlevideo.com rr3---sn-ug5onuxaxjvh-n8v6.googlevideo.com rr1---sn-ug5onuxaxjvh-p5ge.googlevideo.com rr1---sn-ug5onuxaxjvh-p3ul.googlevideo.com rr1---sn-ug5onuxaxjvh-n8v6.googlevideo.com rr1---sn-u5uuxaxjvhg0-ocje.googlevideo.com"

OWRTAWG=$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release | cut -d"'" -f2); ARCHAWG="$(grep DISTRIB_ARCH /etc/openwrt_release | cut -d"'" -f2)_$(grep DISTRIB_TARGET /etc/openwrt_release | cut -d"'" -f2 | tr '/' '_')" 
CRON_CMD="/etc/init.d/mihomo restart"; CONFIGPATH="/etc/magitrickle/state/config.yaml"; PACKAGES_UPDATED=0; TS_WARN_FLAG="/opt/zapret/tmp/ts_warning_shown"
CRON_FILE="/etc/crontabs/root"; CONFIGMIX="/etc/mihomo/config.yaml"; LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)
CONF="/etc/config/zapret"; CUSTOM_DIR="/opt/zapret/init.d/openwrt/custom.d/"; HOSTLIST_FILE="/opt/zapret/ipset/zapret-hosts-user.txt"; fileGP="/opt/zapret/ipset/zapret-hosts-google.txt"
TMP_SF="/tmp/zapret_temp"; HOSTS_FILE="/etc/hosts"; TMP_LIST="$TMP_SF/zapret_yt_list.txt"; tmpDIR="/tmp/PodkopAWG"
GV_XTREME_FILE="/opt/zapret/tmp/GvXtreme"; GV_XTREME_PORTS="80,88,444-65535"; GV_XTREME_NFQWS_PORTS="80,88,443-65535"
IF_NAME="AWG"; PROTO="amneziawg"; DEV_NAME="amneziawg0"; DISCORD_DEF_HOSTLIST="/opt/zapret/ipset_def/zapret-hosts-user.txt"
SAVED_STR="$TMP_SF/StrYou.txt"; HOSTS_USER="$TMP_SF/hosts-user.txt"; OUT_DPI="$TMP_SF/dpi_urls.txt"; OUT="$TMP_SF/str_flow.txt"; ZIP="$TMP_SF/repo.zip"
BACKUP_FILE="/opt/zapret/tmp/hosts_temp.txt"; STR_FILE="$TMP_SF/str_test.txt"; TEMP_FILE="$TMP_SF/str_temp.txt"
RESULTS="/opt/zapret/tmp/zapret_bench.txt"; BACK="$TMP_SF/zapret_back.txt"; TMP_RES="$TMP_SF/zapret_results_all.$$"
FINAL_STR="$TMP_SF/StrFINAL.txt"; NEW_STR="$TMP_SF/StrNEW.txt"; OLD_STR="$TMP_SF/StrOLD.txt"; SECRET_FILE="/etc/tg-ws-proxy/secret.conf"
ARCH_FULL="$(cat /etc/openwrt_release | grep DISTRIB_ARCH | cut -d"'" -f2)"; MODEL="$(cat /tmp/sysinfo/model 2>/dev/null)"
RES1="/opt/zapret/tmp/results_flowseal.txt"; RES2="/opt/zapret/tmp/results_versions.txt"; RES3="/opt/zapret/tmp/results_all.txt"
RES_CUSTOM="/opt/zapret/tmp/results_custom.txt"; CUSTOM_STR_FILE="/root/custom_test.txt"; CUSTOM_RESULTS="$RES_CUSTOM"; CUSTOM_BACK="$TMP_SF/zapret_custom_backup.conf"
RES_DOMAIN="/opt/zapret/tmp/results_domain.txt"; RES_YOUTUBE="/opt/zapret/tmp/results_youtube.txt"; Fin_IP_Dis="104\.25\.158\.178 finland[0-9]\{5\}\.discord\.media"; PARALLEL=8
EXCLUDE_FILE="/opt/zapret/ipset/zapret-hosts-user-exclude.txt"; fileDoH="/etc/config/https-dns-proxy"; EXPERT_MODE_FILE="/etc/zapret_manager_expert_mode"
ALL_BLOCKS="$AI\n$INSTAGRAM\n$NTC\n$LIBRUSEC\n$TGWeb\n$TWCH\n$SCell\n$SPFY"; TMP_ARCHIVE_RS="/tmp/tg-ws-proxy-rs.tar.gz"; TMP_DIR_RS="/tmp/tg-ws-proxy-rs"
hosts_enabled() { if grep -q "### dns.malw.link" /etc/hosts; then hosts_echo="Malw.link"; return 0; elif grep -q "#mafioznik" /etc/hosts; then hosts_echo="Mafioznik"; return 0; elif grep -q "### dns.geohide.ru" /etc/hosts; then hosts_echo="GeoHide"; return 0
elif grep -q "45.155.204.190\|instagram.com\|rutor.info\|lib.rus.ec\|ntc.party\|twitch.tv\|web.telegram.org\|www.spotify.com\|store.supercell.com\|raw.githubusercontent.com\|lkfl2.nalog.ru" /etc/hosts; then hosts_echo="добавлены"; return 0; fi; return 1; }
hosts_add() { printf "%b\n" "$1" | while IFS= read -r L; do grep -qxF "$L" /etc/hosts || echo "$L" >> /etc/hosts; done; /etc/init.d/dnsmasq restart >/dev/null 2>&1; }; D() { printf '%b' "$(printf '%s' "$1" | sed 's/../\\x&/g')"; }
ZAPRET_RESTART () { chmod +x /opt/zapret/sync_config.sh; /opt/zapret/sync_config.sh; /etc/init.d/zapret restart >/dev/null 2>&1; sleep 1; }
PAUSE() { echo -ne "Нажмите Enter..."; read dummy; }; BACKUP_DIR="/opt/zapret_backup"; DATE_FILE="$BACKUP_DIR/date_backup.txt"
BIN_PATH_GO="/usr/bin/tg-ws-proxy-go"; INIT_PATH_GO="/etc/init.d/tg-ws-proxy-go"; BIN_PATH_RS="/usr/bin/tg-ws-proxy-rs"; INIT_PATH_RS="/etc/init.d/tg-ws-proxy-rs"
X1="68747470733a2f2f7767636c692e76657263656c2e617070"; X2="68747470733a2f2f73616e74612d61746d6f2e72752f776172702f776172702e706870"
REPO="xyzmean/splify"; WARP_EP="engage.cloudflareclient.com:4500"; WARP_IFACE="warp0"; TMP_SPL="/tmp/splify"; S101="$(D "$X1")"; S102="$(D "$X2")"; W1="$S101"; II="$S102"
AWG_JC=4; AWG_JMIN=40; AWG_JMAX=70; AWG_H1=1; AWG_H2=2; AWG_H3=3; AWG_H4=4; AWG_S1=0; AWG_S2=0; AWG_JMAX=70; AWG_H1=1; AWG_H2=2; AWG_H3=3; AWG_H4=4; AWG_S1=0; AWG_S2=0
AWG_I1="<b 0xce000000010897a297ecc34cd6dd000044d0ec2e2e1ea2991f467ace4222129b5a098823784694b4897b9986ae0b7280135fa85e196d9ad980b150122129ce2a9379531b0fd3e871ca5fdb883c369832f730e272d7b8b74f393f9f0fa43f11e510ecb2219a52984410c204cf875585340c62238e14ad04dff382f2c200e0ee22fe743b9c6b8b043121c5710ec289f471c91ee414fca8b8be8419ae8ce7ffc53837f6ade262891895f3f4cecd31bc93ac5599e18e4f01b472362b8056c3172b513051f8322d1062997ef4a383b01706598d08d48c221d30e74c7ce000cdad36b706b1bf9b0607c32ec4b3203a4ee21ab64df336212b9758280803fcab14933b0e7ee1e04a7becce3e2633f4852585c567894a5f9efe9706a151b615856647e8b7dba69ab357b3982f554549bef9256111b2d67afde0b496f16962d4957ff654232aa9e845b61463908309cfd9de0a6abf5f425f577d7e5f6440652aa8da5f73588e82e9470f3b21b27b28c649506ae1a7f5f15b876f56abc4615f49911549b9bb39dd804fde182bd2dcec0c33bad9b138ca07d4a4a1650a2c2686acea05727e2a78962a840ae428f55627516e73c83dd8893b02358e81b524b4d99fda6df52b3a8d7a5291326e7ac9d773c5b43b8444554ef5aea104a738ed650aa979674bbed38da58ac29d87c29d387d80b526065baeb073ce65f075ccb56e47533aef357dceaa8293a523c5f6f790be90e4731123d3c6152a70576e90b4ab5bc5ead01576c68ab633ff7d36dcde2a0b2c68897e1acfc4d6483aaaeb635dd63c96b2b6a7a2bfe042f6aed82e5363aa850aace12ee3b1a93f30d8ab9537df483152a5527faca21efc9981b304f11fc95336f5b9637b174c5a0659e2b22e159a9fed4b8e93047371175b1d6d9cc8ab745f3b2281537d1c75fb9451871864efa5d184c38c185fd203de206751b92620f7c369e031d2041e152040920ac2c5ab5340bfc9d0561176abf10a147287ea90758575ac6a9f5ac9f390d0d5b23ee12af583383d994e22c0cf42383834bcd3ada1b3825a0664d8f3fb678261d57601ddf94a8a68a7c273a18c08aa99c7ad8c6c42eab67718843597ec9930457359dfdfbce024afc2dcf9348579a57d8d3490b2fa99f278f1c37d87dad9b221acd575192ffae1784f8e60ec7cee4068b6b988f0433d96d6a1b1865f4e155e9fe020279f434f3bf1bd117b717b92f6cd1cc9bea7d45978bcc3f24bda631a36910110a6ec06da35f8966c9279d130347594f13e9e07514fa370754d1424c0a1545c5070ef9fb2acd14233e8a50bfc5978b5bdf8bc1714731f798d21e2004117c61f2989dd44f0cf027b27d4019e81ed4b5c31db347c4a3a4d85048d7093cf16753d7b0d15e078f5c7a5205dc2f87e330a1f716738dce1c6180e9d02869b5546f1c4d2748f8c90d9693cba4e0079297d22fd61402dea32ff0eb69ebd65a5d0b687d87e3a8b2c42b648aa723c7c7daf37abcc4bb85caea2ee8f55bec20e913b3324ab8f5c3304f820d42ad1b9f2ffc1a3af9927136b4419e1e579ab4c2ae3c776d293d397d575df181e6cae0a4ada5d67ecea171cca3288d57c7bbdaee3befe745fb7d634f70386d873b90c4d6c6596bb65af68f9e5121e67ebf0d89d3c909ceedfb32ce9575a7758ff080724e1ab5d5f43074ecb53a479af21ed03d7b6899c36631c0166f9d47e5e1d4528a5d3d3f744029c4b1c190cbfbad06f5f83f7ad0429fa9a2719c56ffe3783460e166de2d8>"
AUTO_RESULTS="/opt/zapret/tmp/results_auto.txt"; AUTO_BACK="$TMP_SF/zapret_auto_back.txt"; AUTO_LOG="/opt/zapret/tmp/auto_best.log"; AUTO_CRON_CMD="/usr/bin/zmsA --auto-best"
AUTO_LOCK="/tmp/zapret_auto_best.lock"; AUTO_STOP_FLAG="$TMP_SF/zapret_auto_best.stop"; LOCAL_ARCH="$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)"
BIN_VER_GO="/usr/bin/tg-ws-proxy-go_ver"; BIN_VER_RS="/usr/bin/tg-ws-proxy-rs_ver"; BYEDPI_DNS_BACKUP="/etc/byedpi_dns_localuse"

if command -v opkg >/dev/null 2>&1; then PKG="opkg"; GO_SUF="1"; CONFZ="/etc/opkg/distfeeds.conf"; PKG_IS_APK=0; UPDATE="opkg update"; INSTALL="opkg install"
DELETE="opkg remove"; ARCH="$(opkg print-architecture | awk '{print $2}' | tail -n1)"; VER_SUF="r1-all"; SUF_MT=""; SPL_SUF="all"; RELEASE_TAG="v${BYEDPI_LATEST_VER}-24.10"
RAZ="ipk"; TMP_FILE_GO="/tmp/tg-ws-proxy.ipk"; else PKG="apk"; GO_SUF="r1"; CONFZ="/etc/apk/repositories.d/distfeeds.list"; PKG_IS_APK=1; SPL_SUF="noarch"; RELEASE_TAG="v${BYEDPI_LATEST_VER}-25.12"
UPDATE="apk update"; INSTALL="apk add --allow-untrusted"; DELETE="apk del"; ARCH="$(apk --print-arch 2>/dev/null)"; RAZ="apk"; VER_SUF="r1"; SUF_MT="r"; TMP_FILE_GO="/tmp/tg-ws-proxy.apk"; fi

MIRROR=""; CURRENT_MIRROR=$(head -n1 "$CONFZ" | awk '{print $NF}' | sed 's|https://||;s|/releases/.*||')
if grep -qE 'mirror-03\.infra\.openwrt\.org|ftp\.snt\.utwente\.nl/pub/software/openwrt|mirror\.berlin\.freifunk\.net/downloads\.openwrt|mirror\.sjtu\.edu\.cn/openwrt|ftp\.halifax\.rwth-aachen\.de/openwrt|mirror\.accum\.se/mirror/openwrt|downloads\.openwrt\.org' "$CONFZ"; then
    echo -e "${CYAN}Проверяем доступность ${NC}$CURRENT_MIRROR"
    if ! wget -q --spider --timeout=2 "https://$CURRENT_MIRROR/releases/" >/dev/null 2>&1; then
        echo -e "$CURRENT_MIRROR ${RED}недоступен!${NC}"
        echo -e "${CYAN}Подбираем зеркало ${NC}OpenWRT"
        if wget -q --spider --timeout=3 "https://mirror-03.infra.openwrt.org" >/dev/null 2>&1; then
            MIRROR="mirror-03.infra.openwrt.org"          
        elif wget -q --spider --timeout=3 "https://ftp.halifax.rwth-aachen.de/openwrt/releases/" >/dev/null 2>&1; then
            MIRROR="ftp.halifax.rwth-aachen.de/openwrt"
        elif wget -q --spider --timeout=3 "https://mirror.accum.se/mirror/openwrt.org/releases/" >/dev/null 2>&1; then
            MIRROR="mirror.accum.se/mirror/openwrt.org"
        elif wget -q --spider --timeout=3 "https://ftp.snt.utwente.nl/pub/software/openwrt/releases/" >/dev/null 2>&1; then
            MIRROR="ftp.snt.utwente.nl/pub/software/openwrt"
        elif wget -q --spider --timeout=3 "https://mirror.berlin.freifunk.net/downloads.openwrt/releases/" >/dev/null 2>&1; then
            MIRROR="mirror.berlin.freifunk.net/downloads.openwrt"
        elif wget -q --spider --timeout=3 "https://mirror.sjtu.edu.cn/openwrt/releases/" >/dev/null 2>&1; then
            MIRROR="mirror.sjtu.edu.cn/openwrt"
        elif wget -q --spider --timeout=3 "https://downloads.openwrt.org/releases/" >/dev/null 2>&1; then
            MIRROR="downloads.openwrt.org"
        fi
        if [ -n "$MIRROR" ]; then
            echo -e "${CYAN}Переключаемся на ${NC}$MIRROR"
            sed -i "s|https://.*/releases/|https://$MIRROR/releases/|g" "$CONFZ"
        else
            echo -e "${RED}Резервные зеркала недоступны!${NC}"
        fi
    else
        echo -e "$CURRENT_MIRROR ${GREEN}доступен!${NC}"
    fi
fi

update_packages(){ [ "$PACKAGES_UPDATED" = "1" ] && return 0; echo -e "${CYAN}Обновляем список пакетов${NC}"; $UPDATE >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка обновления списка пакетов!${NC}\n"; PAUSE; return 1; }; PACKAGES_UPDATED=1; }

if ! curl --version >/dev/null 2>&1; then echo -e "\ncurl ${RED}отсутствует ${NC}или${RED} работает некорректно${NC}\n"; echo -e "${MAGENTA}Устанавливаем ${NC}curl"
$DELETE curl libcurl >/dev/null 2>&1; if ! update_packages; then echo -e "\n${RED}Ошибка обновления списка пакетов!${NC}\n"; else PACKAGES_UPDATED=1; fi
echo -e "${CYAN}Устанавливаем ${NC}curl"; if ! $INSTALL libcurl curl >/dev/null 2>&1; then echo -e "\n${RED}Не удалось установить curl!${NC}\n"; PAUSE; fi; fi
