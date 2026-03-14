#!/bin/bash

# ============================================
# Скрипт начальной настройки HQ-SRV (ALT Linux)
# ============================================

# 1. Установка hostname
hostnamectl set-hostname hq-srv.au-team.irpo

# 2. Создание пользователя sshuser с домашним каталогом
useradd sshuser -u 1010 -m

# 3. Установка пароля (неинтерактивно)
echo "sshuser:P@ssw0rd" | chpasswd

# 4. Добавление пользователя в группу wheel (для sudo)
usermod -aG wheel sshuser

# 5. Настройка sudo без пароля для sshuser
echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/sshuser
chmod 440 /etc/sudoers.d/sshuser

# 6. Настройка сети (интерфейс ens18)
# Создаём каталог для интерфейса, если его нет
mkdir -p /etc/net/ifaces/ens18

# Файл options
cat > /etc/net/ifaces/ens18/options <<EOF
TYPE=eth
BOOTPROTO=static
DISABLED=no
EOF

# Файл ipv4address (адрес и маска)
echo "192.168.100.2/26" > /etc/net/ifaces/ens18/ipv4address

# Файл ipv4route (шлюз по умолчанию)
echo "default via 192.168.100.1" > /etc/net/ifaces/ens18/ipv4route

# 7. Настройка DNS (временный resolv.conf)
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
EOF

# 8. Перезапуск сети
systemctl restart network

# 9. Базовая настройка SSH (порт 2024, доступ только sshuser)
# Создаём баннер
mkdir -p /etc/openssh
echo "Authorized access only" > /etc/openssh/banner

# Редактируем sshd_config (заменяем/добавляем нужные строки)
sed -i 's/^#\?Port .*/Port 2024/' /etc/openssh/sshd_config
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' /etc/openssh/sshd_config
sed -i 's/^#\?Banner .*/Banner \/etc\/openssh\/banner/' /etc/openssh/sshd_config

# Добавляем AllowUsers, если строки нет
if ! grep -q "^AllowUsers" /etc/openssh/sshd_config; then
    echo "AllowUsers sshuser" >> /etc/openssh/sshd_config
else
    sed -i 's/^AllowUsers .*/AllowUsers sshuser/' /etc/openssh/sshd_config
fi

# Перезапуск SSH
systemctl restart sshd

# 10. Настройка BIND (DNS-сервер) – по желанию, можно добавить позже
# apt-get update && apt-get install -y bind bind-utils
# ... дальнейшая настройка зон

# 11. Установка часового пояса
timedatectl set-timezone Europe/Moscow

echo "Базовая настройка HQ-SRV завершена."