ZAPRET_VERSION=$(wget -qO- https://github.com/remittor/zapret-openwrt/releases \
  | sed -n 's|.*href="/remittor/zapret-openwrt/releases/tag/v\([0-9.]*\)".*|\1|p' \
  | head -n1)

echo "$ZAPRET_VERSION"
