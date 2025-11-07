#!/bin/bash
# Быстрая установка Minecraft Stats без домена
# Запустите этот скрипт на вашем Linux сервере

echo "🚀 Установка Minecraft Stats Dashboard..."

# Обновляем систему
sudo apt update && sudo apt upgrade -y

# Устанавливаем зависимости
echo "📦 Установка зависимостей..."
sudo apt install -y python3 python3-pip python3-venv nginx

# Создаем директорию проекта
echo "📁 Создание структуры проекта..."
sudo mkdir -p /var/www/minecraft-stats/public
cd /var/www/minecraft-stats

# Создаем виртуальное окружение
python3 -m venv venv
source venv/bin/activate

# Устанавливаем Python пакеты
echo "🐍 Установка Python библиотек..."
pip install flask flask-cors mcstatus gunicorn

# Создаем API файл
echo "📝 Создание API..."
cat > api.py << 'EOF'
from flask import Flask, jsonify
from flask_cors import CORS
from mcstatus import JavaServer
import json
import os

app = Flask(__name__)
CORS(app)

# ВАЖНО: Замените эти пути на ваши!
MINECRAFT_SERVER = "localhost:25565"
STATS_FILE = "/путь/к/minecraft/world/stats"
USERCACHE_FILE = "/путь/к/minecraft/usercache.json"

@app.route('/api/stats', methods=['GET'])
def get_server_stats():
    try:
        server = JavaServer.lookup(MINECRAFT_SERVER)
        status = server.status()
        
        players_list = []
        if status.players.sample:
            players_list = [{"name": player.name} for player in status.players.sample]
        
        top_players = get_top_players()
        
        response = {
            "online": True,
            "serverAddress": MINECRAFT_SERVER,
            "version": status.version.name,
            "players": {
                "online": status.players.online,
                "max": status.players.max,
                "list": players_list
            },
            "topPlayers": top_players,
            "motd": status.description,
            "latency": status.latency
        }
        
        return jsonify(response)
    
    except Exception as e:
        return jsonify({
            "online": False,
            "serverAddress": MINECRAFT_SERVER,
            "error": str(e),
            "players": {"online": 0, "max": 0, "list": []},
            "topPlayers": []
        }), 200

def get_top_players():
    top_players = []
    
    try:
        if not os.path.exists(STATS_FILE):
            return top_players
        
        player_stats = []
        
        for filename in os.listdir(STATS_FILE):
            if filename.endswith('.json'):
                uuid = filename[:-5]
                filepath = os.path.join(STATS_FILE, filename)
                
                with open(filepath, 'r') as f:
                    data = json.load(f)
                    playtime_ticks = data.get('stats', {}).get('minecraft:custom', {}).get('minecraft:play_time', 0)
                    playtime_minutes = playtime_ticks // 20 // 60
                    player_name = get_player_name(uuid)
                    
                    player_stats.append({
                        "name": player_name,
                        "playtime": playtime_minutes
                    })
        
        player_stats.sort(key=lambda x: x['playtime'], reverse=True)
        top_players = player_stats[:10]
        
    except Exception as e:
        print(f"Error: {e}")
    
    return top_players

def get_player_name(uuid):
    try:
        if os.path.exists(USERCACHE_FILE):
            with open(USERCACHE_FILE, 'r') as f:
                cache = json.load(f)
                for entry in cache:
                    if entry['uuid'] == uuid:
                        return entry['name']
    except Exception as e:
        print(f"Error: {e}")
    
    return uuid[:8]

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Создаем HTML файл
echo "🌐 Создание веб-интерфейса..."
cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Статистика Minecraft Сервера</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #0f3460 100%);
            color: #fff;
            min-height: 100vh;
            padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        header {
            text-align: center;
            padding: 40px 20px;
            background: rgba(255, 255, 255, 0.05);
            border-radius: 20px;
            backdrop-filter: blur(10px);
            margin-bottom: 30px;
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        h1 { font-size: 3em; margin-bottom: 10px; text-shadow: 0 0 20px rgba(74, 144, 226, 0.5); }
        .server-address { font-size: 1.2em; color: #4a90e2; margin-top: 10px; }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: rgba(255, 255, 255, 0.08);
            padding: 25px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.1);
            transition: transform 0.3s;
        }
        .stat-card:hover { transform: translateY(-5px); }
        .stat-label {
            font-size: 0.9em;
            color: #aaa;
            margin-bottom: 10px;
            text-transform: uppercase;
        }
        .stat-value { font-size: 2.5em; font-weight: bold; color: #4a90e2; }
        .status-online { color: #50fa7b; }
        .status-offline { color: #ff5555; }
        .loading { text-align: center; padding: 40px; font-size: 1.2em; color: #4a90e2; }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>⛏️ Minecraft Server Stats</h1>
            <div class="server-address" id="serverAddress">Загрузка...</div>
        </header>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-label">Статус сервера</div>
                <div class="stat-value" id="serverStatus">Загрузка...</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Онлайн игроков</div>
                <div class="stat-value" id="playersOnline">-</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Максимум слотов</div>
                <div class="stat-value" id="maxPlayers">-</div>
            </div>
            <div class="stat-card">
                <div class="stat-label">Версия</div>
                <div class="stat-value" style="font-size: 1.8em;" id="version">-</div>
            </div>
        </div>
    </div>
    <script>
        const API_URL = '/api';
        async function fetchStats() {
            try {
                const response = await fetch(`${API_URL}/stats`);
                const data = await response.json();
                document.getElementById('serverAddress').textContent = data.serverAddress || 'N/A';
                const statusEl = document.getElementById('serverStatus');
                statusEl.textContent = data.online ? 'Онлайн' : 'Оффлайн';
                statusEl.className = 'stat-value ' + (data.online ? 'status-online' : 'status-offline');
                document.getElementById('playersOnline').textContent = data.players?.online || 0;
                document.getElementById('maxPlayers').textContent = data.players?.max || 0;
                document.getElementById('version').textContent = data.version || 'N/A';
            } catch (error) {
                console.error('Error:', error);
            }
        }
        fetchStats();
        setInterval(fetchStats, 30000);
    </script>
</body>
</html>
EOF

# Создаем systemd сервис
echo "⚙️ Создание systemd сервиса..."
sudo tee /etc/systemd/system/minecraft-api.service > /dev/null << EOF
[Unit]
Description=Minecraft Stats API
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/minecraft-stats
Environment="PATH=/var/www/minecraft-stats/venv/bin"
ExecStart=/var/www/minecraft-stats/venv/bin/gunicorn -w 4 -b 127.0.0.1:5000 api:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Создаем конфигурацию Nginx
echo "🌐 Настройка Nginx..."
sudo tee /etc/nginx/sites-available/minecraft-stats > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;
    root /var/www/minecraft-stats/public;
    index index.html;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location /api/ {
        proxy_pass http://127.0.0.1:5000/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

# Активируем конфигурацию
sudo ln -sf /etc/nginx/sites-available/minecraft-stats /etc/nginx/sites-enabled/

# Устанавливаем права доступа
sudo chown -R www-data:www-data /var/www/minecraft-stats
sudo chmod -R 755 /var/www/minecraft-stats

# Запускаем сервисы
echo "🚀 Запуск сервисов..."
sudo systemctl daemon-reload
sudo systemctl enable minecraft-api
sudo systemctl start minecraft-api
sudo systemctl restart nginx

# Открываем порт в firewall (если используется)
if command -v ufw &> /dev/null; then
    echo "🔥 Настройка firewall..."
    sudo ufw allow 80/tcp
fi

# Получаем IP адрес
IP=$(hostname -I | awk '{print $1}')
EXTERNAL_IP=$(curl -s ifconfig.me)

echo ""
echo "✅ Установка завершена!"
echo ""
echo "🌐 Ваш сайт доступен по адресу:"
echo "   Локальная сеть: http://$IP"
echo "   Интернет: http://$EXTERNAL_IP"
echo ""
echo "⚠️  ВАЖНО: Не забудьте отредактировать файл /var/www/minecraft-stats/api.py"
echo "   и указать правильные пути к вашему Minecraft серверу!"
echo ""
echo "📝 Команды для управления:"
echo "   sudo systemctl status minecraft-api   # Статус API"
echo "   sudo systemctl restart minecraft-api  # Перезапуск API"
echo "   sudo journalctl -u minecraft-api -f   # Логи API"
echo ""
