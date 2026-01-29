#!/bin/sh
[ "$(grep -oP '(?<=DISTRIB_RELEASE=).+' /etc/openwrt_release | tr -d "' " | cut -d. -f1)" -lt 25 ] && sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh) || sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Test/main/ow18.sh)
