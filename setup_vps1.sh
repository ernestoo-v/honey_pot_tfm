#!/usr/bin/env bash
# Script para generar la estructura y ficheros de un honeypot de media interacción
# con Cowrie (SSH), Proftpd (FTP), un servicio web Apache+PHP y herramientas de observabilidad.

set -e

# Base directory
dir="honeypot"

# Crear estructura de carpetas
mkdir -p $dir/{cowrie,mi_ftp,web,volumenes/apache_logs,volumenes/mysql_log,volumenes/ftp_logs,volumenes/cowrie_logs,config}
echo "Creando directorios necesarios..."

# Instalar Docker y Docker Compose
echo "Instalando Docker y Docker Compose..."
apt-get update
apt-get install -y docker.io docker-compose
systemctl start docker
systemctl enable docker

# Generar docker-compose.yml
echo "Generando docker-compose.yml..."
cat > $dir/docker-compose.yml << 'EOF'
version: "3.8"

services:
  cowrie:
    build: ./cowrie
    container_name: honeypot_cowrie
    restart: unless-stopped
    networks:
      dmz:
        ipv4_address: 172.18.0.10
    volumes:
      - type: bind
        source: ./cowrie/cowrie.cfg
        target: /cowrie/etc/cowrie.cfg
      - ./volumenes/cowrie_logs:/cowrie/log

  mi_ftp:
    build: ./proftpd
    container_name: mi_ftp
    environment:
      - PASV_ADDRESS=0.0.0.0
      - PASV_MIN_PORT=21100
      - PASV_MAX_PORT=21110
    volumes:
      - ./proftpd/proftpd.conf:/etc/proftpd/proftpd.conf
      - ./volumenes/ftp_logs:/var/log/proftpd
    ports:
      - "21:21"
      - "21100-21110:21100-21110"
    networks:
      dmz:
        ipv4_address: 172.18.0.11
  
  mi_mysql:
    image: mysql:5.7
    container_name: mi_mysql
    restart: unless-stopped
    environment:
      - MYSQL_DATABASE=bbdd
      - MYSQL_ROOT_PASSWORD=vagrant
      - MYSQL_USER=usuario
      - MYSQL_PASSWORD=passwd
    volumes:
      - ./volumenes/mysql_data:/var/lib/mysql
      - ./volumenes/mysql_log:/var/log/mysql
      - ./config/my.cnf:/etc/my.cnf
    ports:
      - "3306:3306"
    networks:
      dmz:
        ipv4_address: 172.18.0.18
  
  mi_apache:
    build:
      context: ./apache
      dockerfile: Dockerfile
    image: mi_apache_custom
    container_name: mi_apache
    restart: unless-stopped
    depends_on:
      - mi_mysql
    environment:
      - DB_HOST=mi_mysql
      - DB_NAME=bbdd
      - DB_USER=usuario
      - DB_PASS=passwd
    volumes:
      - ./web/:/var/www/html:ro
      - ./volumenes/apache_logs:/var/log/apache2
    ports:
      - "80:80"
    networks:
      dmz:
        ipv4_address: 172.18.0.12

  mi_promtail:
    image: grafana/promtail:2.9.0
    container_name: mi_promtail
    volumes:
      - ./volumenes/apache_logs:/var/log/apache2
      - ./volumenes/mysql_log:/var/log/mysql
      - ./volumenes/ftp_logs:/var/log/proftpd
      - ./volumenes/cowrie_logs:/cowrie/log
      - ./config/promtail-config.yaml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml
    networks:
      dmz:
        ipv4_address: 172.18.0.15

networks:
  dmz:
    driver: bridge
    ipam:
      config:
        - subnet: 172.18.0.0/16
          gateway: 172.18.0.1
EOF

# Cowrie
echo "Generando configuración para Cowrie..."
cat > $dir/cowrie/Dockerfile << 'EOF'
FROM cowrie/cowrie:latest
COPY cowrie.cfg /cowrie/etc/cowrie.cfg
EOF

cat > $dir/cowrie/cowrie.cfg << 'EOF'
[honeypot]
hostname = honeypot-ssh
listen_addr = 0.0.0.0
listen_port = 22
log_path = /cowrie/log
download_path = /cowrie/dl

auth_class = AuthRandom
auth_class_parameters = 2,5,10

[output_jsonlog]
enabled = true
EOF

# mi_ftp
echo "Generando configuración para mi_ftp..."

mkdir -p $dir/proftpd

cat > $dir/proftpd/Dockerfile << 'EOF'
FROM debian:bullseye-slim
RUN apt-get update && apt-get install -y proftpd-basic && rm -rf /var/lib/apt/lists/*
COPY proftpd.conf /etc/proftpd/proftpd.conf
RUN mkdir -p /var/log/proftpd && \
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

SystemLog /var/log/proftpd/proftpd.log
ExtendedLog /var/log/proftpd/access.log AUTH,READ,WRITE
TransferLog /var/log/proftpd/transfer.log
LogFormat commandLog "%h %l %u %t \"%r\" %s"
ExtendedLog /var/log/proftpd/commands.log ALL commandLog

DefaultRoot ~

TimesGMT off
SetEnv TZ :/etc/localtime

ServerIdent on "FTP Honeypot Listo"
EOF

# Servicio web Apache+PHP
echo "Generando servicio web Apache+PHP..."
# Generar Dockerfile para Apache+PHP en directorio apache/
echo "Creando directorio apache/ y Dockerfile de build..."
mkdir -p $dir/apache
cat > $dir/apache/Dockerfile << 'EOF'
FROM php:7-apache

# Instala las extensiones PDO y PDO_MySQL
RUN apt-get update \
 && docker-php-ext-install pdo pdo_mysql \
 && rm -rf /var/lib/apt/lists/*
EOF
echo "Dockerfile generado en $dir/apache/Dockerfile"

# Crear directorio web si no existe
mkdir -p $dir/web
mkdir -p $dir/web/assets/css
mkdir -p $dir/web/assets/js
# Web estática y PHP
echo "Generando archivos web..."
# index.php
cat > $dir/web/index.php << 'EOF'
<?php
include 'config.php';
?><!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>Restaurante Ejemplo - Inicio</title><link rel="stylesheet" href="assets/css/style.css"></head><body><header><h1>Bienvenidos</h1><nav><a href="index.php">Inicio</a><a href="menu.php">Menú</a><a href="contact.php">Contacto</a></nav></header><main><h2>Sobre Nosotros</h2><?php $stmt = $pdo->query("SELECT 'Historia del restaurante...' AS historia"); echo '<blockquote>' . $stmt->fetch()['historia'] . '</blockquote>'; ?></main><footer>&copy;<?=date('Y')?></footer><script src="assets/js/script.js"></script></body></html>
EOF

# config.php
cat > $dir/web/config.php << 'EOF'
<?php
$host = getenv('DB_HOST') ?: 'mi_mysql';
$db   = getenv('DB_NAME') ?: 'bbdd';
$user = getenv('DB_USER') ?: 'usuario';
$pass = getenv('DB_PASS') ?: 'passwd';
$dsn = "mysql:host={$host};dbname={$db};charset=utf8mb4";
try { $pdo = new PDO($dsn, $user, $pass, [PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE=>PDO::FETCH_ASSOC]); } catch (PDOException $e) { echo "Error BD: " . $e->getMessage(); exit(1);} 
EOF

# menu.php
cat > $dir/web/menu.php << 'EOF'
<?php include 'config.php'; ?><!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>Menú</title><link rel="stylesheet" href="assets/css/style.css"></head><body><header><h1>Menú</h1><nav><a href="index.php">Inicio</a><a href="menu.php">Menú</a><a href="contact.php">Contacto</a></nav></header><main><h2>Platos</h2><ul><?php $platos=[['nombre'=>'Ensalada','precio'=>'8€'],['nombre'=>'Paella','precio'=>'12€'],['nombre'=>'Tarta','precio'=>'5€']]; foreach($platos as $p) echo "<li>{$p['nombre']} - <strong>{$p['precio']}</strong></li>"; ?></ul></main><footer>&copy;<?=date('Y')?></footer><script src="assets/js/script.js"></script></body></html>
EOF

# contact.php
cat > $dir/web/contact.php << 'EOF'
<?php include 'config.php'; ?><!DOCTYPE html><html lang="es"><head><meta charset="UTF-8"><title>Contacto</title><link rel="stylesheet" href="assets/css/style.css"></head><body><header><h1>Contacto</h1><nav><a href="index.php">Inicio</a><a href="menu.php">Menú</a><a href="contact.php">Contacto</a></nav></header><main><h2>Mensaje</h2><form id="contactForm"><label>Nombre:<input required name="name"></label><label>Email:<input type="email" required name="email"></label><label>Mensaje:<textarea required name="message"></textarea></label><button>Enviar</button></form><div id="formResult"></div></main><footer>&copy;<?=date('Y')?></footer><script src="assets/js/script.js"></script></body></html>
EOF

# Assets CSS y JS
cat > $dir/web/assets/css/style.css << 'EOF'
body{font-family:Arial,sans-serif;margin:0;padding:0;background:#fafafa;color:#333}header{background:#c0392b;color:#fff;padding:1rem;text-align:center}nav a{color:#fff;margin:0 1rem;text-decoration:none}main{padding:2rem}h2{color:#c0392b}footer{background:#2c3e50;color:#fff;text-align:center;padding:1rem;position:fixed;bottom:0;width:100%}form label{display:block;margin:0.5rem 0}form input,form textarea{width:100%;padding:0.5rem;border:1px solid #ccc;border-radius:4px}button{background:#c0392b;color:#fff;padding:0.5rem 1rem;border:none;border-radius:4px;cursor:pointer}button:hover{background:#e74c3c}
EOF

cat > $dir/web/assets/js/script.js << 'EOF'
document.addEventListener('DOMContentLoaded',function(){const form=document.getElementById('contactForm');if(form){form.addEventListener('submit',function(e){e.preventDefault();const data=new FormData(form);document.getElementById('formResult').innerText=`Gracias, ${data.get('name')}! Tu mensaje ha sido enviado.`;form.reset();}});
EOF

echo "Web de restaurante integrada correctamente."

# Configuración de MySQL (my.cnf)
echo "Generando my.cnf para MySQL..."
cat > $dir/config/my.cnf << 'EOF'
# For advice on how to change settings please see
# http://dev.mysql.com/doc/refman/5.7/en/server-configuration-defaults.html

[mysqld]
#
# Remove leading # and set to the amount of RAM for the most important data
# cache in MySQL. Start at 70% of total RAM for dedicated server, else 10%.
# innodb_buffer_pool_size = 128M
#
# Remove leading # to turn on a very important data integrity option: logging
# changes to the binary log between backups.
# log_bin
#
# Remove leading # to set options mainly useful for reporting servers.
# The server defaults are faster for transactions and fast SELECTs.
# Adjust sizes as needed, experiment to find the optimal values.
# join_buffer_size = 128M
# sort_buffer_size = 2M
# read_rnd_buffer_size = 2M
skip-host-cache
skip-name-resolve
datadir=/var/lib/mysql
socket=/var/run/mysqld/mysqld.sock
secure-file-priv=/var/lib/mysql-files
user=mysql

# Disabling symbolic-links is recommended to prevent assorted security risks
symbolic-links=0

log-error=/var/log/mysql/error.log
general_log = 1
general_log_file = /var/log/mysql/general.log
pid-file=/var/run/mysqld/mysqld.pid
[client]
socket=/var/run/mysqld/mysqld.sock

!includedir /etc/mysql/conf.d/
!includedir /etc/mysql/mysql.conf.d/
EOF

echo "my.cnf generado para MySQL."

# Configuración de Promtail
echo "Generando configuración para Promtail..."
cat > $dir/config/promtail-config.yaml << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://10.0.9.14:3100/loki/api/v1/push

scrape_configs:
  - job_name: apache
    static_configs:
      - targets:
          - localhost
        labels:
          job: apache
          __path__: /var/log/apache2/*.log

  - job_name: mysql
    static_configs:
      - targets:
          - localhost
        labels:
          job: mysql
          __path__: /var/log/mysql/*.log

  - job_name: ftp
    static_configs:
      - targets:
          - localhost
        labels:
          job: ftp
          __path__: /var/log/proftpd/*.log

  - job_name: cowrie
    static_configs:
      - targets:
          - localhost
        labels:
          job: cowrie
          host: vps1
          __path__: /cowrie/log/*.json
EOF

echo "Estructura y ficheros generados en ./$dir"
