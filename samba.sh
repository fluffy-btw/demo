#!/bin/bash
# Скрипт для настройки Samba DC на BR-SRV (исправленная версия)
set -e

if [[ $EUID -ne 0 ]]; then
    echo "Запустите скрипт от root (sudo)."
    exit 1
fi

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
# В зависимости от дистрибутива служба может называться samba-ad-dc или samba
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

echo "=== Настройка завершена ==="
echo "Контроллер домена ${DOMAIN}.${REALM} развёрнут."
echo "Пользователи и группа hq созданы."
