#!/bin/bash

echo "===== ВЫБОР УЗЛА ====="
echo "1 - HQ-SRV (RAID5 + NFS)"
echo "2 - ISP (Chrony сервер)"
echo "3 - HQ-CLI (Chrony клиент)"
read -p "Выберите номер: " NODE

# ---------------- HQ-SRV ----------------
if [ "$NODE" == "1" ]; then
    echo "===== НАСТРОЙКА RAID5 ====="

    read -p "Созданы ли 3 диска (sd b,c,d)? (Y/N): " answer
    if [[ "$answer" != "Y" && "$answer" != "y" ]]; then
        echo "Создай диски и запусти снова."
        exit 1
    fi

    apt-get update
    apt-get install -y mdadm nfs-kernel-server

    mdadm --create /dev/md0 -l 5 -n 3 /dev/sd{b,c,d} --force

    sleep 5
    lsblk

    echo "DEVICE partitions" > /etc/mdadm/mdadm.conf
    mdadm --detail --scan | awk '/ARRAY/ {print}' >> /etc/mdadm/mdadm.conf

    mkfs.ext4 /dev/md0

    mkdir -p /raid5

    UUID=$(blkid -s UUID -o value /dev/md0)
    echo "UUID=$UUID /raid5 ext4 defaults 0 0" >> /etc/fstab

    mount -a
    df -h /raid5

    mkdir -p /raid5/nfs
    echo "/raid5/nfs 192.168.100.64/28(rw,sync,no_root_squash)" >> /etc/exports

    systemctl enable --now nfs-kernel-server

    exportfs

    echo "===== RAID5 ГОТОВО ====="
fi

# ---------------- ISP ----------------
if [ "$NODE" == "2" ]; then
    echo "===== НАСТРОЙКА CHRONY (ISP) ====="

    apt-get update
    apt-get install -y chrony

    CONF="/etc/chrony/chrony.conf"

    sed -i 's/^pool .*/pool 2.ru.pool.ntp.org iburst/' $CONF
    echo "local stratum 5" >> $CONF
    echo "allow 0/0" >> $CONF

    systemctl enable --now chrony

    systemctl status chrony --no-pager

    echo ""
    echo "ПРОВЕРКА:"
    echo "chronyc clients"
fi

# ---------------- HQ-CLI ----------------
if [ "$NODE" == "3" ]; then
    echo "===== НАСТРОЙКА CHRONY (HQ-CLI) ====="

    read -p "Введите IP ISP (например 172.16.4.1): " ISP_IP

    CONF="/etc/chrony/chrony.conf"

    sed -i "s/^pool .*/pool $ISP_IP iburst/" $CONF

    systemctl restart chrony

    echo "===== ГОТОВО ====="

    echo ""
    echo "===== НАСТРОЙКА РОУТЕРОВ ====="

    echo "HQ-RTR:"
    echo "en"
    echo "conf t"
    echo "ntp server 172.16.4.1"

    echo ""
    echo "BR-RTR:"
    echo "en"
    echo "conf t"
    echo "ntp server 172.16.5.1"
fi
