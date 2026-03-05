#!/bin/bash
# Скрипт настройки ISP для демо-экзамена
# Должен выполняться от root

set -e  # прерывать при ошибке

# Определение интерфейсов (кроме loopback)
interfaces=($(ls /sys/class/net | grep -v lo | sort))
if [ ${#interfaces[@]} -lt 3 ]; then
    echo "Ошибка: обнаружено менее 3 сетевых интерфейсов (${#interfaces[@]})"
    exit 1
fi

wan_iface=${interfaces[0]}
lan1_iface=${interfaces[1]}
lan2_iface=${interfaces[2]}

echo "Обнаруженные интерфейсы: ${interfaces[@]}"
echo "Будут использованы:"
echo "  WAN (интернет, DHCP): $wan_iface"
echo "  LAN1 (HQ, 172.16.4.1/28): $lan1_iface"
echo "  LAN2 (BR, 172.16.5.1/28): $lan2_iface"
echo "Проверьте правильность. Прервите скрипт (Ctrl+C), если неверно."
sleep 5

# 1. Установка имени хоста
hostnamectl set-hostname isp
echo "Имя хоста установлено: isp"

# 2. Настройка /etc/network/interfaces
echo "Настройка /etc/network/interfaces..."
cat > /etc/network/interfaces <<EOF
# Loopback
auto lo
iface lo inet loopback

# WAN - интернет (DHCP)
auto $wan_iface
iface $wan_iface inet dhcp

# LAN для HQ
auto $lan1_iface
iface $lan1_iface inet static
    address 172.16.4.1/28

# LAN для BR
auto $lan2_iface
iface $lan2_iface inet static
    address 172.16.5.1/28
EOF

# 3. Включение форвардинга пакетов
echo "Включение IP forwarding..."
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p

# 4. Настройка NAT (masquerade) через iptables
echo "Настройка iptables (NAT)..."
iptables -t nat -A POSTROUTING -s 172.16.4.0/28 -o $wan_iface -j MASQUERADE
iptables -t nat -A POSTROUTING -s 172.16.5.0/28 -o $wan_iface -j MASQUERADE

# Сохранение правил
iptables-save > /root/rules
echo "Правила iptables сохранены в /root/rules"

# Добавление в crontab для восстановления после перезагрузки
(crontab -l 2>/dev/null | grep -v "/sbin/iptables-restore"; echo "@reboot /sbin/iptables-restore < /root/rules") | crontab -
echo "Cron задача добавлена"

# 5. Настройка часового пояса
timedatectl set-timezone Europe/Moscow
echo "Часовой пояс установлен: Europe/Moscow"

# 6. Перезапуск сети для применения настроек
echo "Перезапуск сетевых сервисов..."
systemctl restart networking || {
    echo "Не удалось перезапустить networking, пробуем поднять интерфейсы вручную"
    ifdown $lan1_iface; ifup $lan1_iface
    ifdown $lan2_iface; ifup $lan2_iface
    dhclient -v $wan_iface
}

# Проверка
echo "Проверка назначенных IP-адресов:"
ip -4 addr show $lan1_iface | grep -o "172.16.4.1/28" && echo "LAN1 OK" || echo "Ошибка на LAN1"
ip -4 addr show $lan2_iface | grep -o "172.16.5.1/28" && echo "LAN2 OK" || echo "Ошибка на LAN2"
ip -4 addr show $wan_iface | grep -o "inet [0-9.]*" && echo "WAN получил IP" || echo "WAN не получил IP (возможно, нет DHCP-сервера)"

echo "Настройка ISP завершена."