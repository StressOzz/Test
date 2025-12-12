wget -qO- https://github.com/remittor/zapret-openwrt/releases | grep '/remittor/zapret-openwrt/releases/tag/' | sed 's|.*/tag/||' | sort -V | tail -n1
