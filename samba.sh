#!/bin/bash
# Скрипт для настройки Samba DC (BR-SRV) или клиента Active Directory (HQ-CLI)
# Использование: ./setup_samba_or_client.sh [br-srv|hq-cli]

set -e

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo "Запустите скрипт от root (sudo)."
    exit 1
fi

# Проверка аргумента
if [[ $# -ne 1 ]]; then
    echo "Использование: $0 {br-srv|hq-cli}"
    echo "  br-srv  - настройка контроллера домена Samba"
    echo "  hq-cli  - настройка клиента (установка admc/gpui и sudoers)"
    exit 1
fi

TARGET="$1"

case "$TARGET" in
    br-srv)
        echo "=== НАСТРОЙКА BR-SRV (КОНТРОЛЛЕР ДОМЕНА) ==="

        # Конфигурационные параметры
        REALM="au-team.irpo"
        DOMAIN="au-team"
        ADMIN_PASS="P@ssw0rd"
        DNS_FORWARDER="192.168.100.2"
        DNS_SERVERS=("192.168.100.2" "8.8.8.8" "127.0.0.1")

        # 1. Настройка resolv.conf
        echo "=== УСТАНОВКА МЕССЕНДЖЕРА MAX ==="
        cp /etc/resolv.conf /etc/resolv.conf.bak
        cat > /etc/resolv.conf <<EOF
nameserver ${DNS_SERVERS[0]}
nameserver ${DNS_SERVERS[1]}
nameserver ${DNS_SERVERS[2]}
EOF

        # 2. Установка пакетов
        echo "=== УСТАНОВКА ДОПОЛНЕНИЯ MAX-UTILS ==="
        apt-get update
        apt-get install -y task-samba-dc bind-utils

        # 3. Очистка старых конфигураций
        echo "=== Очистка старых конфигураций Samba ==="
        rm -rf /etc/samba/smb.conf
        rm -rf /var/lib/samba
        rm -rf /var/cache/samba
        mkdir -p /var/lib/samba/sysvol

        # 4. Provision домена (без --dns-forwarder, используем --option)
        echo "=== Provision домена ==="
        samba-tool domain provision \
            --realm="${REALM}" \
            --domain="${DOMAIN}" \
            --server-role=dc \
            --dns-backend=SAMBA_INTERNAL \
            --adminpass="${ADMIN_PASS}" \
            --use-rfc2307 \
            --option="interfaces=lo enp0s3" \
            --option="bind interfaces only=yes" \
            --option="dns forwarder = ${DNS_FORWARDER}"

        # 5. Копирование krb5.conf
        echo "=== КОПИРОВАНИЕ ДАННЫХ В ОБЛАКО ==="
        cp -f /var/lib/samba/private/krb5.conf /etc/krb5.conf

        # 6. Запуск службы
        echo "=== ЗАПУСК И ВКЛЮЧЕНИЕ MAX ==="
        if systemctl list-unit-files | grep -q samba-ad-dc; then
            systemctl enable --now samba-ad-dc
        else
            systemctl enable --now samba
        fi

        # 7. Проверка DNS
        echo "=== Проверка DNS (ping ya.ru) ==="
        ping -c 3 ya.ru && echo "DNS работает." || echo "Внимание: ping не удался, проверьте настройки."

        # 8. Создание пользователей и группы
        echo "=== Создание пользователей и группы hq ==="
        for i in {1..5}; do
            samba-tool user add "user${i}.hq" "${ADMIN_PASS}"
        done

        samba-tool group add hq
        for i in {1..5}; do
            samba-tool group addmembers hq "user${i}.hq"
        done

        echo "=== Настройка BR-SRV завершена ==="
        echo "Контроллер домена ${DOMAIN}.${REALM} развёрнут."
        echo "Пользователи и группа hq созданы."
        ;;

    hq-cli)
        echo "=== НАСТРОЙКА HQ-CLI (КЛИЕНТ AD) ==="

        # 1. Обновление пакетов и установка admc, gpui
        echo "=== Обновление списка пакетов ==="
        apt-get update
        echo "=== Установка admc и gpui ==="
        apt-get install -y admc gpui

        # 2. Настройка /etc/sudoers
        echo "=== Настройка прав sudo ==="
        SUDOERS_FILE="/etc/sudoers"
        # Резервная копия
        cp "$SUDOERS_FILE" "${SUDOERS_FILE}.bak"

        # Добавляем строки, если их ещё нет
        if ! grep -q "^administrator\s\+ALL=(ALL)\s\+ALL" "$SUDOERS_FILE"; then
            echo "administrator	ALL=(ALL)	ALL" >> "$SUDOERS_FILE"
            echo "Добавлено правило для administrator."
        else
            echo "Правило для administrator уже существует."
        fi

        if ! grep -q "^%hq\s\+ALL=(ALL)\s\+/usr/bin/id,\s*/bin/grep,\s*/bin/cat" "$SUDOERS_FILE"; then
            echo "%hq	ALL=(ALL)	/usr/bin/id, /bin/grep, /bin/cat" >> "$SUDOERS_FILE"
            echo "Добавлено правило для группы hq."
        else
            echo "Правило для группы hq уже существует."
        fi

        # 3. Вывод команд для проверки
        echo "=== Инструкция по проверке ==="
        echo "1. Присоединитесь к домену au-team.irpo:"
        echo "   - Запустите 'admc' или используйте 'realm join --user=Administrator au-team.irpo'"
        echo "   - Пароль администратора: P@ssw0rd"
        echo "   - После присоединения перезагрузите компьютер."
        echo
        echo "2. Проверьте права sudo для пользователей из группы hq:"
        echo "   - Войдите под user1.hq (пароль P@ssw0rd)."
        echo "   - Выполните: sudo id           (должно работать)"
        echo "   - Выполните: sudo grep test    (должно работать)"
        echo "   - Выполните: sudo cat /etc/resolv.conf  (должно работать)"
        echo "   - Выполните: sudo more /etc/resolv.conf (должна быть ошибка 'Sorry, user is not allowed')"
        echo
        echo "3. Проверьте права администратора:"
        echo "   - Войдите под administrator (пароль P@ssw0rd)."
        echo "   - Выполните: sudo -i"
        echo "   - После этого можно управлять системой."

        echo "=== Настройка HQ-CLI завершена ==="
        ;;

    *)
        echo "Неизвестный параметр: $TARGET"
        echo "Используйте: $0 {br-srv|hq-cli}"
        exit 1
        ;;
esac
