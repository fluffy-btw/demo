#!/bin/bash
# ====================================================
# Скрипт настройки BR-SRV как контроллера домена Samba
# для демоэкзамена (ALT Linux)
# ====================================================

set -e  # Прерывание при ошибке

echo "=== 1. Обновление пакетов ==="
apt-get update
apt-get install -y task-samba-dc

echo "=== 2. Очистка старых конфигураций Samba ==="
rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba/
rm -rf /var/cache/samba/
mkdir -p /var/lib/samba/sysvol/

echo "=== 3. Настройка DNS-резолвера ==="
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
nameserver 8.8.8.8
EOF

echo "=== 4. Инициализация домена (provision) ==="
samba-tool domain provision \
    --realm=au-team.irpo \
    --domain=au-team \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --dns-forwarder=192.168.100.2 \
    --adminpass='P@ssw0rd'

echo "=== 5. Копирование Kerberos конфигурации ==="
cp -f /var/lib/samba/private/krb5.conf /etc/krb5.conf

echo "=== 6. Запуск Samba ==="
systemctl enable --now samba

echo "=== 7. Проверка статуса домена ==="
samba-tool domain info 127.0.0.1

echo "=== 8. Установка утилит для проверки ==="
apt-get install -y bind-utils

echo "=== 9. Проверка доступа в интернет ==="
ping -c 4 ya.ru

echo "=== 10. Проверка Kerberos ==="
echo "P@ssw0rd" | kinit administrator@AU-TEAM.IRPO
klist

echo "=== 11. Создание пользователей ==="
samba-tool user add user1.hq P@ssw0rd
samba-tool user add user2.hq P@ssw0rd
samba-tool user add user3.hq P@ssw0rd
samba-tool user add user4.hq P@ssw0rd
samba-tool user add user5.hq P@ssw0rd

echo "=== 12. Создание группы и добавление пользователей ==="
samba-tool group add hq
samba-tool group addmembers hq user1.hq
samba-tool group addmembers hq user2.hq
samba-tool group addmembers hq user3.hq
samba-tool group addmembers hq user4.hq
samba-tool group addmembers hq user5.hq

echo "=== Настройка BR-SRV успешно завершена ==="