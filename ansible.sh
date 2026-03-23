#!/bin/bash
# ====================================================
# Скрипт автоматической настройки Ansible Control Node на BR-SRV
# для демоэкзамена (ALT Linux)
# ====================================================

set -e  # Прерывание при ошибке (критично)

# Параметры подключения
ANSIBLE_USER="sshuser"
ANSIBLE_PASS="P@ssw0rd"
NET_USER="net_admin"
NET_PASS="P@ssw0rd"
SSH_KEY="$HOME/.ssh/id_rsa"

echo "=== 1. Установка пакетов ==="
apt-get update
apt-get install -y ansible python3 sshpass

echo "=== 2. Создание пользователя $ANSIBLE_USER (если отсутствует) ==="
if ! id "$ANSIBLE_USER" &>/dev/null; then
    useradd -m -u 1010 "$ANSIBLE_USER"
    echo "$ANSIBLE_USER:$ANSIBLE_PASS" | chpasswd
    usermod -aG wheel "$ANSIBLE_USER"
fi

echo "=== 3. Генерация SSH-ключа без пароля ==="
if [ ! -f "$SSH_KEY" ]; then
    ssh-keygen -t rsa -b 4096 -N "" -f "$SSH_KEY"
else
    echo "Ключ уже существует, пропускаем генерацию"
fi

echo "=== 4. Копирование публичного ключа на управляемые хосты ==="
# Копирование на HQ-SRV (порт 2024)
sshpass -p "$ANSIBLE_PASS" ssh-copy-id -p 2024 -o StrictHostKeyChecking=no "$ANSIBLE_USER@hq-srv"

# Копирование на HQ-CLI (порт 22)
sshpass -p "$ANSIBLE_PASS" ssh-copy-id -o StrictHostKeyChecking=no "$ANSIBLE_USER@hq-cli"

# Копирование на BR-SRV (локально, порт 2024)
sshpass -p "$ANSIBLE_PASS" ssh-copy-id -p 2024 -o StrictHostKeyChecking=no "$ANSIBLE_USER@br-srv"

echo "=== 5. Конфигурация Ansible ==="
mkdir -p /etc/ansible
cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
interpreter_python = /usr/bin/python3
host_key_checking = False
EOF

cat > /etc/ansible/hosts <<'EOF'
[servers]
hq-srv ansible_ssh_user=sshuser ansible_ssh_port=2024
br-srv ansible_ssh_user=sshuser ansible_ssh_port=2024

[cli]
hq-cli ansible_ssh_user=sshuser

[eco]
hq-rtr ansible_user=net_admin ansible_password=P@ssw0rd ansible_connection=network_cli ansible_network_os=ios
br-rtr ansible_user=net_admin ansible_password=P@ssw0rd ansible_connection=network_cli ansible_network_os=ios
EOF

echo "=== 6. Отключение проверок безопасности на маршрутизаторах ==="
for router in hq-rtr br-rtr; do
    echo "Настройка $router..."
    sshpass -p "$NET_PASS" ssh -o StrictHostKeyChecking=no "$NET_USER@$router" <<EOF
en
conf t
security none
end
wr mem
exit
EOF
    if [ $? -eq 0 ]; then
        echo "$router: успешно"
    else
        echo "$router: ошибка подключения"
    fi
done

echo "=== 7. Запуск и проверка работоспособности Ansible ==="
ansible -m ping all

echo "=== Настройка Ansible Control Node на BR-SRV завершена ==="