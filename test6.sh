ZAPRET_VERSION=$(wget -qO- https://github.com/remittor/zapret-openwrt/releases \
  | grep -m1 '/remittor/zapret-openwrt/releases/tag/' \
  | sed 's|.*/tag/v\([0-9.]*\).*|\1|')

echo "$ZAPRET_VERSION"
