ZAPRET_VERSION=$(wget -qO- https://github.com/remittor/zapret-openwrt/releases \
  | grep '/remittor/zapret-openwrt/releases/tag/' \
  | sed -n 's|.*/tag/v\([0-9.]*\).*|\1|p' \
  | sort -V \
  | tail -n1)

echo "$ZAPRET_VERSION"
