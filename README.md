[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-blue)]()

## Описание

Комплексное решение для запуска Minecraft сервера с интеграцией веб-статистики и системой управления через LuckPerms.

## Требования к системе

- Ubuntu/Debian (рекомендуется)
- Python 3.8+
- Java 17+
- MariaDB 10.3+
- Nginx 1.18+
- 4GB+ RAM (рекомендуется)

## Инструкция по установке

### 1. Клонирование репозитория
```bash
git clone https://github.com/ProjectENIUS/McMinecraftProject
cd McMinecraftProject
```

### 2. Установка зависимостей
```bash
sudo apt update
sudo apt install -y python3 python3-pip nginx mariadb-server openjdk-17-jre
```

### 3. Настройка базы данных
```sql
CREATE DATABASE minecraft_server;
CREATE USER 'minecraft'@'localhost' IDENTIFIED BY 'secure_password_123';
GRANT ALL PRIVILEGES ON minecraft_server.* TO 'minecraft'@'localhost';
FLUSH PRIVILEGES;
```

### 4. Конфигурация LuckPerms
Отредактируйте файл `McServer/Plugins/Luckperms/config.yml`:
```yaml
data-storage:
  enabled: true
  type: mysql
  address: localhost:3306
  database: minecraft_server
  username: minecraft
  password: secure_password_123
```

### 5. Настройка веб-сервера
- Разместите веб-приложение: `sudo cp -r Minecraft-stat /var/www/minecraft`
- Настройте Nginx reverse proxy для порта 5000 (указан в `api.py`)
- Настройте SSL с помощью Let's Encrypt

### 6. Запуск сервера
```bash
cd McServer
screen -S minecraft
java -jar paper-1.21.8-60.jar
```

## Параметры конфигурации

| Компонент | Параметр | Значение по умолчанию |
|-----------|----------|----------------------|
| Веб-порт | `api.py` | 5000 |
| База данных | MariaDB | localhost:3306 |
| Сервер Minecraft | Java | paper-1.21.8-60.jar |

## Поддержка

Для получения помощи:
- Создайте issue в репозитории
- Проверьте документацию в Wiki
- Присоединитесь к нашему Discord серверу (ссылка в профиле)

---

**© 2025 ProjectENIUS**  
Лицензия: MIT
