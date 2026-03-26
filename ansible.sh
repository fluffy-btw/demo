#!/bin/bash
# Скрипт локальной настройки Ansible на сервере BR-SRV
# Выполняет установку, конфигурацию и подготовку SSH-ключа без внешних подключений

set -e

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo "Скрипт должен выполняться от root (sudo)."
    exit 1
fi

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
hq-srv ansible_ssh_user=sshuser ansible_ssh_port=2024
br-srv ansible_ssh_user=sshuser ansible_ssh_port=2024

[cli]
hq-cli ansible_ssh_user=sshuser

[eco]
hq-rtr ansible_user=net_admin ansible_password=P@ssw0rd ansible_connection=network_cli ansible_network_os=ios
br-rtr ansible_user=net_admin ansible_password=P@ssw0rd ansible_connection=network_cli ansible_network_os=ios
EOF

echo "=== 5. Готово ==="
echo "Ansible настроен локально."
echo "Для копирования ключей на удалённые узлы выполните вручную:"
echo "  ssh-copy-id -p 2024 sshuser@hq-srv"
echo "  ssh-copy-id -p 2024 sshuser@br-srv"
echo "  ssh-copy-id sshuser@hq-cli"
echo "  ssh-copy-id net_admin@hq-rtr"
echo "  ssh-copy-id net_admin@br-rtr"
echo "После этого проверьте подключения: ansible -m ping all"
