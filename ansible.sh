#!/bin/bash
# Автоматическая настройка Ansible Controller на BR-SRV
# Включает копирование ключей на удалённые узлы (без интерактива)

set -e

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo "Скрипт должен выполняться от root (sudo)."
    exit 1
fi

# Параметры подключения
PASSWORD="P@ssw0rd"
SSH_USER="sshuser"
NET_USER="net_admin"
SSH_PORT=2024

# Список узлов с форматом "user@host[:port]"
NODES=(
    "$SSH_USER@hq-srv:$SSH_PORT"
    "$SSH_USER@br-srv:$SSH_PORT"
    "$SSH_USER@hq-cli"
    "$NET_USER@hq-rtr"
    "$NET_USER@br-rtr"
)

echo "=== 1. Установка пакетов ==="
apt-get update
apt-get install -y ansible python3 sshpass

echo "=== 2. Настройка ansible.cfg ==="
mkdir -p /etc/ansible
cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
interpreter_python=/usr/bin/python3
EOF

echo "=== 3. Генерация SSH-ключа (если отсутствует) ==="
if [[ ! -f ~/.ssh/id_rsa ]]; then
    mkdir -p ~/.ssh
    ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa
    echo "SSH-ключ создан."
else
    echo "SSH-ключ уже существует."
fi

echo "=== 4. Создание inventory-файла ==="
cat > /etc/ansible/hosts <<EOF
[servers]
hq-srv ansible_ssh_user=$SSH_USER ansible_ssh_port=$SSH_PORT
br-srv ansible_ssh_user=$SSH_USER ansible_ssh_port=$SSH_PORT

[cli]
hq-cli ansible_ssh_user=$SSH_USER

[eco]
hq-rtr ansible_user=$NET_USER ansible_password=$PASSWORD ansible_connection=network_cli ansible_network_os=ios
br-rtr ansible_user=$NET_USER ansible_password=$PASSWORD ansible_connection=network_cli ansible_network_os=ios
EOF

echo "=== 5. Копирование SSH-ключа на узлы ==="
for node in "${NODES[@]}"; do
    # Разбор строки user@host:port
    IFS=':@' read -r user host port <<< "$node"
    if [[ -z "$port" ]]; then
        port="22"
    fi
    echo "Копирование ключа на $user@$host (порт $port)..."
    sshpass -p "$PASSWORD" ssh-copy-id -o StrictHostKeyChecking=no -p "$port" "$user@$host" 2>/dev/null && \
        echo "  Успешно" || echo "  Ошибка: не удалось скопировать ключ на $user@$host"
done

echo "=== 6. Проверка подключений через Ansible ==="
ansible -m ping -i /etc/ansible/hosts all

echo "=== Настройка Ansible завершена ==="
