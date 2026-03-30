#!/bin/bash
# Автоматическая настройка Docker и MediaWiki на BR-SRV
set -e

if [[ $EUID -ne 0 ]]; then
    echo "Запустите скрипт от root (sudo)."
    exit 1
fi

echo "=== 1. Разрешение root-логина по SSH ==="
if ! grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config; then
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    systemctl restart sshd
    echo "SSH-доступ root разрешён."
else
    echo "Уже разрешён."
fi

echo "=== 2. Установка Docker и Docker Compose ==="
apt-get update
apt-get install -y docker-engine docker-compose

echo "=== 3. Создание wiki.yaml ==="
cat > wiki.yaml <<'EOF'
version: '3'
services:
  wiki:
    image: mediawiki
    container_name: wiki
    ports:
      - "80:80"
    volumes:
      - ./LocalSettings.php:/var/www/html/LocalSettings.php
    depends_on:
      - mariadb
    environment:
      - MW_DB=mariadb
      - MW_DB_USER=wiki
      - MW_DB_PASSWORD=WikiP@ssw0rd
      - MW_DB_HOST=mariadb
  mariadb:
    image: mariadb
    container_name: mariadb
    environment:
      - MYSQL_ROOT_PASSWORD=WikiP@ssw0rd
      - MYSQL_DATABASE=mariadb
      - MYSQL_USER=wiki
      - MYSQL_PASSWORD=WikiP@ssw0rd
    volumes:
      - ./db_data:/var/lib/mysql
EOF

# Примечание: в исходной инструкции после редактирования 24 строка "mediawiki_db" меняется на "mariadb" (это соответствует переменной MYSQL_DATABASE)
# Мы уже использовали mariadb, пароли и имена приведены в соответствие.

echo "=== 4. Запуск Docker и контейнеров ==="
systemctl enable --now docker
docker-compose -f wiki.yaml up -d

echo "=== 5. Инструкция по завершению настройки MediaWiki ==="
echo "1. Откройте в браузере http://br-srv"
echo "2. Пройдите установку MediaWiki:"
echo "   - Хост базы данных: mariadb"
echo "   - Имя базы данных: mariadb"
echo "   - Имя пользователя базы данных: wiki"
echo "   - Пароль базы данных: WikiP@ssw0rd"
echo "   - Название вики: wiki"
echo "   - Ваше имя участника: admin"
echo "   - Пароль: WikiP@ssw0rd"
echo "   - Почта: mediawiki@gmail.com"
echo "   - Поставьте галочку 'Хватит уже, просто установите вики'"
echo "3. После установки скачайте файл LocalSettings.php (он будет предложен браузером) и сохраните его на HQ-CLI."
echo "4. На HQ-CLI выполните: scp administrator@hq-cli:/путь/к/LocalSettings.php root@br-srv:/root/ (или в каталог, где лежит wiki.yaml)"
echo "5. На BR-SRV остановите контейнеры: docker-compose -f wiki.yaml down"
echo "6. Отредактируйте wiki.yaml: раскомментируйте строку монтирования LocalSettings.php (удалите # в строке '- ./LocalSettings.php:/var/www/html/LocalSettings.php')"
echo "7. Запустите контейнеры снова: docker-compose -f wiki.yaml up -d"
echo "8. Проверьте вики в браузере."
echo ""
echo "Внимание: если на HQ-CLI был добавлен nameserver 8.8.8.8, не забудьте его удалить из /etc/resolv.conf."

echo "=== Установка Docker завершена ==="
