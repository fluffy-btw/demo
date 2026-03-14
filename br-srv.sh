#!/bin/bash

# =============================================
# Скрипт настройки BR-SRV (ALT Linux)
# =============================================

# 1. Установка hostname
hostnamectl set-hostname br-srv.au-team.irpo

# 2. Создание пользователя sshuser (если не существует)
if ! id sshuser &>/dev/null; then
    useradd sshuser -u 1010 -m
else
    echo "Пользователь sshuser уже существует"
fi

# 3. Установка пароля
echo "sshuser:P@ssw0rd" | chpasswd

# 4. Добавление в группу wheel
usermod -aG wheel sshuser

# 5. Настройка sudo без пароля
if [ ! -f /etc/sudoers.d/sshuser ]; then
    echo "sshuser ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/sshuser
    chmod 440 /etc/sudoers.d/sshuser
else
    echo "Файл sudoers для sshuser уже существует"
fi

# 6. Настройка сети (интерфейс ens18)
mkdir -p /etc/net/ifaces/ens18

if [ ! -f /etc/net/ifaces/ens18/options ]; then
    cat > /etc/net/ifaces/ens18/options <<EOF
TYPE=eth
BOOTPROTO=static
DISABLED=no
EOF
else
    echo "Файл options уже существует, пропускаем"
fi

if [ ! -f /etc/net/ifaces/ens18/ipv4address ]; then
    echo "192.168.200.2/27" > /etc/net/ifaces/ens18/ipv4address
else
    echo "Файл ipv4address уже существует, пропускаем"
fi

if [ ! -f /etc/net/ifaces/ens18/ipv4route ]; then
    echo "default via 192.168.200.1" > /etc/net/ifaces/ens18/ipv4route
else
    echo "Файл ipv4route уже существует, пропускаем"
fi

# resolv.conf (можно перезаписать всегда)
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
EOF

# Перезапуск сети
systemctl restart network

# Проверка связи со шлюзом
echo "Проверка связи со шлюзом 192.168.200.1..."
ping -c 4 192.168.200.1

# 7. Настройка SSH
mkdir -p /etc/openssh

if [ ! -f /etc/openssh/banner ]; then
    echo "Authorized access only" > /etc/openssh/banner
fi

# Редактируем sshd_config
sed -i 's/^#\?Port .*/Port 2024/' /etc/openssh/sshd_config
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' /etc/openssh/sshd_config
sed -i 's/^#\?Banner .*/Banner \/etc\/openssh\/banner/' /etc/openssh/sshd_config

if ! grep -q "^AllowUsers" /etc/openssh/sshd_config; then
    echo "AllowUsers sshuser" >> /etc/openssh/sshd_config
else
    sed -i 's/^AllowUsers .*/AllowUsers sshuser/' /etc/openssh/sshd_config
fi

# Перезапуск SSH
systemctl restart sshd

# 8. Часовой пояс
timedatectl set-timezone Europe/Moscow

echo "Настройка BR-SRV завершена."