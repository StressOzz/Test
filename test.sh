#!/bin/sh

URL="https://raw.githubusercontent.com/routerich/RouterichAX3000_configs/refs/heads/main"
DIR="/etc/config"
DIR_BACKUP="/root/backup"
config_files="dhcp
youtubeUnblock
https-dns-proxy"

checkAndAddDomainPermanentName()
{
  nameRule="option name '$1'"
  str=$(grep -i "$nameRule" /etc/config/dhcp)
  if [ -z "$str" ] 
  then 
    uci add dhcp domain
    uci set dhcp.@domain[-1].name="$1"
    uci set dhcp.@domain[-1].ip="$2"
    uci commit dhcp
  fi
}

manage_package() {
    local name="$1"
    local autostart="$2"
    local process="$3"

    if opkg list-installed | grep -q "^$name"; then
        if /etc/init.d/$name enabled; then
            [ "$autostart" = "disable" ] && /etc/init.d/$name disable
        else
            [ "$autostart" = "enable" ] && /etc/init.d/$name enable
        fi

        if pidof $name > /dev/null; then
            [ "$process" = "stop" ] && /etc/init.d/$name stop
        else
            [ "$process" = "start" ] && /etc/init.d/$name start
        fi
    fi
}

install_youtubeunblock_packages() {
    PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
    VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
    BASE_URL="https://github.com/Waujito/youtubeUnblock/releases/download/v1.0.0/"
    PACK_NAME="youtubeUnblock"

    AWG_DIR="/tmp/$PACK_NAME"
    mkdir -p "$AWG_DIR"
    
    if opkg list-installed | grep -q $PACK_NAME; then
        echo "$PACK_NAME already installed"
    else
        PACKAGES="kmod-nfnetlink-queue kmod-nft-queue kmod-nf-conntrack"

        for pkg in $PACKAGES; do
            if opkg list-installed | grep -q "^$pkg "; then
                echo "$pkg already installed"
            else
                echo "$pkg not installed. Installing..."
                opkg install $pkg || {
                    echo "Error installing $pkg. Please, install $pkg manually and run the script again"
                    exit 1
                }
            fi
        done
        
        if [ ! "$VERSION" = "23.05.5" ]; then
            echo "Your OpenWRT version $VERSION not supported. Please install $PACK_NAME manually."
            exit 1
        fi

        YOUTUBEUNBLOCK_FILENAME="youtubeUnblock-1.0.0-10-f37c3dd-${PKGARCH}-openwrt-23.05.ipk"
        DOWNLOAD_URL="${BASE_URL}${YOUTUBEUNBLOCK_FILENAME}"
        wget -O "$AWG_DIR/$YOUTUBEUNBLOCK_FILENAME" "$DOWNLOAD_URL" || {
            echo "Error downloading $PACK_NAME."
            exit 1
        }
        opkg install "$AWG_DIR/$YOUTUBEUNBLOCK_FILENAME" || {
            echo "Error installing $PACK_NAME."
            exit 1
        }
    fi

    PACK_NAME="luci-app-youtubeUnblock"
    if opkg list-installed | grep -q $PACK_NAME; then
        echo "$PACK_NAME already installed"
    else
        YOUTUBEUNBLOCK_FILENAME="luci-app-youtubeUnblock-1.0.0-10-f37c3dd.ipk"
        DOWNLOAD_URL="${BASE_URL}${YOUTUBEUNBLOCK_FILENAME}"
        wget -O "$AWG_DIR/$YOUTUBEUNBLOCK_FILENAME" "$DOWNLOAD_URL" || {
            echo "Error downloading $PACK_NAME."
            exit 1
        }
        opkg install "$AWG_DIR/$YOUTUBEUNBLOCK_FILENAME" || {
            echo "Error installing $PACK_NAME."
            exit 1
        }
    fi

    rm -rf "$AWG_DIR"
}

checkPackageAndInstall() {
    local name="$1"
    local isRequried="$2"
    if opkg list-installed | grep -q $name; then
        echo "$name already installed..."
    else
        echo "$name not installed. Installing..."
        opkg install $name
        res=$?
        if [ "$isRequried" = "1" ]; then
            [ $res -ne 0 ] && {
                echo "Error installing $name. Please, install $name manually and run the script again"
                exit 1
            }
        fi
    fi
}

echo "Update list packages..."
opkg update

checkPackageAndInstall "coreutils-base64" "1"

# удалён блок проверки роутера

checkPackageAndInstall "https-dns-proxy" "1"
checkPackageAndInstall "luci-app-https-dns-proxy" "0"
checkPackageAndInstall "luci-i18n-https-dns-proxy-ru" "0"

install_youtubeunblock_packages

opkg upgrade youtubeUnblock
opkg upgrade luci-app-youtubeUnblock

if [ ! -d "$DIR_BACKUP" ]; then
  echo "Backup files..."
  mkdir -p $DIR_BACKUP
  for file in $config_files; do
    cp -f "$DIR/$file" "$DIR_BACKUP/$file"
  done

  echo "Replace configs..."
  for file in $config_files; do
    [ "$file" != "dhcp" ] && wget -O "$DIR/$file" "$URL/config_files/$file"
  done
fi

echo "Configure dhcp..."

uci set dhcp.cfg01411c.strictorder='1'
uci set dhcp.cfg01411c.filter_aaaa='1'
uci add_list dhcp.cfg01411c.server='127.0.0.1#5053'
uci add_list dhcp.cfg01411c.server='127.0.0.1#5054'
uci add_list dhcp.cfg01411c.server='127.0.0.1#5055'
uci add_list dhcp.cfg01411c.server='127.0.0.1#5056'
uci add_list dhcp.cfg01411c.server='/*.chatgpt.com/127.0.0.1#5056'
uci add_list dhcp.cfg01411c.server='/*.openai.com/127.0.0.1#5056'
uci add_list dhcp.cfg01411c.server='/*.github.com/127.0.0.1#5056'
uci add_list dhcp.cfg01411c.server='/*.gstatic.com/127.0.0.1#5056'
uci add_list dhcp.cfg01411c.server='/*.recaptcha.net/127.0.0.1#5056'
uci commit dhcp

echo "Add unblock ChatGPT..."
checkAndAddDomainPermanentName "chatgpt.com" "83.220.169.155"
checkAndAddDomainPermanentName "openai.com" "83.220.169.155"
checkAndAddDomainPermanentName "webrtc.chatgpt.com" "83.220.169.155"
checkAndAddDomainPermanentName "ios.chat.openai.com" "83.220.169.155"
checkAndAddDomainPermanentName "searchgpt.com" "83.220.169.155"

nameRule="option name 'Block_UDP_443'"
str=$(grep -i "$nameRule" /etc/config/firewall)
if [ -z "$str" ]; then
  echo "Add block QUIC..."
  uci add firewall rule
  uci set firewall.@rule[-1].name='Block_UDP_80'
  uci add_list firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].dest_port='80'
  uci set firewall.@rule[-1].target='REJECT'

  uci add firewall rule
  uci set firewall.@rule[-1].name='Block_UDP_443'
  uci add_list firewall.@rule[-1].proto='udp'
  uci set firewall.@rule[-1].src='lan'
  uci set firewall.@rule[-1].dest='wan'
  uci set firewall.@rule[-1].dest_port='443'
  uci set firewall.@rule[-1].target='REJECT'
  uci commit firewall
  service firewall restart
fi

cronTask="0 4 * * * wget -O - $URL/configure_zaprets.sh | sh"
str=$(grep -i "$cronTask" /etc/crontabs/root)
if [ -z "$str" ]; then
  echo "Add cron task auto run configure_zapret..."
  echo "$cronTask" >> /etc/crontabs/root
fi

manage_package "podkop" "disable" "stop"
manage_package "ruantiblock" "disable" "stop"
manage_package "https-dns-proxy" "enable" "start"
manage_package "youtubeUnblock" "enable" "start"

echo "Restart service..."
service youtubeUnblock restart
service https-dns-proxy restart
service dnsmasq restart
service odhcpd restart

printf "\033[32;1mConfigured completed...\033[0m\n"
