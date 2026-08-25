# Mixomo OpenWrt Installer

Установщик Mihomo + hev-socks5-tunnel + MagiTrickle + LuCI-панели для OpenWrt,
переработанный в модульную структуру (по образцу Zapret Manager).

## Что изменилось по сравнению с монолитным скриптом

- **Один большой `.sh` со встроенным JS на 900+ строк → набор файлов.**
  Логика (`lib/*.sh`) отделена от статических ассетов LuCI
  (`assets/**`), которые раньше жили внутри heredoc-ов.
- **Убрано дублирование** скачивания файлов: вся логика повторных
  попыток и перебора зеркал вынесена в одну функцию `download_file()`
  (`lib/common.sh`), вместо трёх разных `curl`/`wget`-конструкций.
- **Единая функция `get_latest_tag()`** для получения последнего релиза
  GitHub — раньше было продублировано для Mihomo и MagiTrickle.
- **install.sh стал тонким оркестратором** (~80 строк): читает шаги,
  вызывает функции из `lib/`, выводит прогресс через `run_step()`.
- **Точечная установка**: `./install.sh mihomo` / `hev-tunnel` /
  `magitrickle` — можно переустановить/обновить один компонент, не
  трогая остальные (в оригинале это было возможно только целиком).
- **Bootstrap для запуска в одну строку**: если рядом со скриптом нет
  `lib/`/`assets/` (например, скачали только `install.sh` через
  `curl | sh`), он сам скачивает архив репозитория во временную папку.
- Существующий рабочий `config.yaml` пользователя больше не трогается
  и не переписывается — поведение сохранено как в оригинале.

## Структура

```
install.sh                          — точка входа
lib/common.sh                       — логи, pkg-менеджер, скачивание, arch-detect
lib/mihomo.sh                       — ядро Mihomo, конфиг, служба, LuCI-страница, Zashboard
lib/hev_tunnel.sh                   — hev-socks5-tunnel + сеть/firewall UCI
lib/magitrickle.sh                  — MagiTrickle + LuCI-страница
assets/mihomo/config.js             — редактор конфига (ACE) для LuCI
assets/mihomo/configs/config.yaml   — дефолтный конфиг Mihomo
assets/mihomo/mihomo.init           — init.d служба
assets/mihomo/luci-app-mihomo*.json — меню и ACL LuCI
assets/magitrickle/*                — страница и меню LuCI для MagiTrickle
```

## Запуск

```sh
git clone https://github.com/<ваш-форк>/Zapret-Manager.git
cd Zapret-Manager/files/Mixomo
sh install.sh
```

Либо одной командой (bootstrap сам подтянет остальные файлы):

```sh
curl -fsSL https://raw.githubusercontent.com/<ваш-форк>/Zapret-Manager/main/files/Mixomo/install.sh | sh
```

> Перед публикацией не забудьте поправить переменные `REPO`/`BRANCH`
> в начале `install.sh` на адрес вашего репозитория.

## Точечные команды

```sh
sh install.sh mihomo        # ядро + LuCI-страница + Zashboard
sh install.sh hev-tunnel    # только TUN-туннель
sh install.sh magitrickle   # только MagiTrickle
sh install.sh -v            # версия скрипта
```
