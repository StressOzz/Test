ZAPRET_VERSION=$(wget -qO- https://github.com/remittor/zapret-openwrt/releases | grep '/remittor/zapret-openwrt/releases/tag/' | sed 's|.*/tag/v||' | sort -V | tail -n1)
echo "$ZAPRET_VERSION"
