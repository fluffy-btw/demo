#!/bin/bash
# Скрипт для автоматической настройки Samba DC на сервере BR-SRV
# Основан на инструкциях из samba.txt

set -e  # Прерывать выполнение при ошибке

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен выполняться от root (sudo)." 
   exit 1
fi

# Параметры домена
REALM="au-team.irpo"
DOMAIN="au-team"
ADMIN_PASS="P@ssw0rd"
DNS_FORWARDER="192.168.100.2"
DNS_SERVERS=("127.0.0.1" "192.168.100.2" "8.8.8.8")

echo "=== Настройка DNS (resolv.conf) ==="
# Резервная копия текущего resolv.conf
cp /etc/resolv.conf /etc/resolv.conf.bak
# Запись новых настроек
cat > /etc/resolv.conf <<EOF
nameserver ${DNS_SERVERS[0]}
nameserver ${DNS_SERVERS[1]}
nameserver ${DNS_SERVERS[2]}
EOF
echo "resolv.conf обновлён."

echo "=== Обновление пакетов и установка Samba DC ==="
apt-get update
apt-get install -y task-samba-dc bind-utils

echo "=== Очистка старых конфигураций Samba ==="
rm -rf /etc/samba/smb.conf
rm -rf /var/lib/samba
rm -rf /var/cache/samba
mkdir -p /var/lib/samba/sysvol

echo "=== Provision домена ==="
samba-tool domain provision \
    --realm="${REALM}" \
    --domain="${DOMAIN}" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --dns-forwarder="${DNS_FORWARDER}" \
    --adminpass="${ADMIN_PASS}" \
    --use-rfc2307 \
    --option="interfaces=lo enp0s3" \
    --option="bind interfaces only=yes"

echo "=== Копирование Kerberos конфигурации ==="
cp -f /var/lib/samba/private/krb5.conf /etc/krb5.conf

echo "=== Запуск и включение службы Samba ==="
# В Debian после установки task-samba-dc служба называется samba-ad-dc
systemctl enable --now samba-ad-dc || systemctl enable --now samba

echo "=== Проверка DNS (ping ya.ru) ==="
ping -c 3 ya.ru && echo "DNS работает." || echo "Внимание: ping не удался, проверьте сеть."

echo "=== Создание пользователей и группы ==="
for i in {1..5}; do
    samba-tool user add "user${i}.hq" "${ADMIN_PASS}"
done

samba-tool group add hq
for i in {1..5}; do
    samba-tool group addmembers hq "user${i}.hq"
done

echo "=== Настройка завершена ==="
echo "Контроллер домена ${DOMAIN}.${REALM} успешно развёрнут."
echo "Пользователи и группа созданы."