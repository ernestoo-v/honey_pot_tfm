#!/bin/bash

# Definir variables
dir="/honeypot"
IP_VPS2="10.0.9.14"  # Ajusta a la IP de tu VPS2

# Crear directorios
echo "Creando directorios..."
mkdir -p $dir/mysql
mkdir -p $dir/apache
mkdir -p $dir/proftpd
mkdir -p $dir/ssh
mkdir -p $dir/volumenes/ftp_logs
mkdir -p $dir/volumenes/mysql_logs
mkdir -p $dir/volumenes/apache_logs
mkdir -p $dir/volumenes/ssh_logs
mkdir -p $dir/promtail

# Instalar Docker y Docker Compose
echo "Instalando Docker y Docker Compose..."
apt-get update
apt-get install -y docker.io docker-compose
systemctl start docker
systemctl enable docker

# Configurar MySQL
echo "Generando configuración para MySQL..."
cat > $dir/mysql/Dockerfile << 'EOF'
FROM mysql:8.0
EXPOSE 3306
CMD ["mysqld"]
EOF

cat > $dir/mysql/my.cnf << 'EOF'
[mysqld]
general_log = 1
general_log_file = /var/log/mysql/mysql.log
log_error = /var/log/mysql/error.log
EOF

# Configurar Apache
echo "Generando configuración para Apache..."
cat > $dir/apache/Dockerfile << 'EOF'
FROM httpd:2.4
EXPOSE 80
CMD ["httpd-foreground"]
EOF

# Configurar FTP
echo "Generando configuración para FTP..."
cat > $dir/proftpd/Dockerfile << 'EOF'
FROM debian:bullseye-slim
RUN apt-get update && apt-get install -y proftpd-basic && rm -rf /var/lib/apt/lists/*
COPY proftpd.conf /etc/proftpd/proftpd.conf
RUN mkdir -p /var/log/proftpd /home/ftpuser && \
    useradd -m -d /home/ftpuser -s /bin/bash ftpuser && \
    echo "ftpuser:ftppass" | chpasswd && \
    chown -R ftpuser:ftpuser /home/ftpuser /var/log/proftpd
EXPOSE 21 21100-21110
CMD ["proftpd", "--nodaemon"]
EOF

cat > $dir/proftpd/proftpd.conf << 'EOF'
ServerName "ProFTPD Honeypot"
ServerType standalone
DefaultServer on
Port 21
PassivePorts 21100 21110
ExtendedLog /var/log/proftpd/access.log AUTH,READ,WRITE
TransferLog /var/log/proftpd/transfer.log
DefaultRoot ~
TimesGMT off
SetEnv TZ :/etc/localtime
ServerIdent on "FTP Honeypot Ready"
EOF

# Configurar SSH
echo "Generando configuración para SSH..."
cat > $dir/ssh/Dockerfile << 'EOF'
FROM ubuntu:20.04
RUN apt-get update && apt-get install -y openssh-server && rm -rf /var/lib/apt/lists/*
RUN mkdir /var/run/sshd
RUN useradd -m -s /bin/bash sshuser && echo "sshuser:sshpass" | chpasswd
EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
EOF

# Configurar docker-compose.yml
echo "Generando docker-compose.yml..."
cat > $dir/docker-compose.yml << 'EOF'
version: '3.8'
services:
  mi_mysql:
    build:
      context: ./mysql
      dockerfile: Dockerfile
    ports:
      - "3306:3306"
    environment:
      MYSQL_ROOT_PASSWORD: rootpass
    volumes:
      - ./volumenes/mysql_logs:/var/log/mysql
      - ./mysql/my.cnf:/etc/mysql/my.cnf

  mi_apache:
    build:
      context: ./apache
      dockerfile: Dockerfile
    ports:
      - "80:80"
    volumes:
      - ./volumenes/apache_logs:/usr/local/apache2/logs

  mi_ftp:
    build:
      context: ./proftpd
      dockerfile: Dockerfile
    ports:
      - "21:21"
      - "21100-21110:21100-21110"
    volumes:
      - ./volumenes/ftp_logs:/var/log/proftpd

  mi_ssh:
    build:
      context: ./ssh
      dockerfile: Dockerfile
    ports:
      - "22:22"
    volumes:
      - ./volumenes/ssh_logs:/var/log
EOF

# Instalar Promtail
echo "Instalando Promtail..."
wget https://github.com/grafana/loki/releases/download/v2.9.0/promtail-linux-amd64 -O /usr/local/bin/promtail
chmod +x /usr/local/bin/promtail

# Configurar Promtail
echo "Configurando Promtail..."
cat > $dir/promtail/promtail-config.yml << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://10.0.9.14:3100/loki/api/v1/push

scrape_configs:
  - job_name: ftp
    static_configs:
      - targets:
          - localhost
        labels:
          job: ftp
          host: vps1
          __path__: /honeypot/volumenes/ftp_logs/*.log

  - job_name: apache
    static_configs:
      - targets:
          - localhost
        labels:
          job: apache
          host: vps1
          __path__: /honeypot/volumenes/apache_logs/*.log

  - job_name: mysql
    static_configs:
      - targets:
          - localhost
        labels:
          job: mysql
          host: vps1
          __path__: /honeypot/volumenes/mysql_logs/*.log

  - job_name: ssh
    static_configs:
      - targets:
          - localhost
        labels:
          job: ssh
          host: vps1
          __path__: /honeypot/volumenes/ssh_logs/auth.log
EOF
# Ajusta la IP en clients.url según la IP de VPS2

# Crear servicio para Promtail
cat > /etc/systemd/system/promtail.service << 'EOF'
[Unit]
Description=Promtail service
After=network.target

[Service]
ExecStart=/usr/local/bin/promtail -config.file=/honeypot/promtail/promtail-config.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl enable promtail
systemctl start promtail

echo "Configuración de VPS1 completada. Ahora levanta los servicios con: cd $dir && docker-compose up -d"