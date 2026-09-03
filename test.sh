#!/bin/sh

echo "Останавливаем wrtg..."

# Остановить и отключить сервис
/etc/init.d/wrtg stop 2>/dev/null || true
/etc/init.d/wrtg disable 2>/dev/null || true

# Удалить cron-задачу wrtg
if [ -f /etc/crontabs/root ]; then
    sed -i '\|/etc/wrtg/update-cidr\.sh|d' /etc/crontabs/root
fi

# Удалить nftables
nft delete table inet tg_tproxy 2>/dev/null || true

# Удалить init-скрипт и бинарник
rm -f /etc/init.d/wrtg
rm -f /usr/sbin/wrtg

# Удалить всю конфигурацию и данные wrtg
rm -rf /etc/wrtg
rm -rf /var/lib/wrtg

# Удалить LuCI
rm -rf /usr/share/ucode/luci/template/wrtg
rm -f /usr/share/luci/menu.d/luci-app-wrtg.json
rm -f /usr/share/rpcd/acl.d/luci-app-wrtg.json

# Удалить старые версии LuCI
rm -f /usr/lib/lua/luci/controller/wrtg.lua
rm -f /usr/lib/lua/luci/model/cbi/wrtg.lua
rm -rf /usr/lib/lua/luci/view/wrtg

# Удалить оставшийся nft-файл
rm -f /etc/nftables.d/wrtg.nft

# Очистить временные файлы и кэш LuCI
rm -rf /tmp/luci-*
rm -f /tmp/luci-indexcache

# Перезапустить LuCI
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true

echo ""
echo "================================"
echo " wrtg полностью удалён"
echo "================================"
