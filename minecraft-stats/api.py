from flask import Flask, jsonify, Response, stream_with_context, request, g
from flask_cors import CORS
from mcstatus import JavaServer
import json
import os
import time
import threading
import logging
from datetime import datetime
from queue import Queue, Empty
import sys
import traceback
import psutil
import random

app = Flask(__name__)
CORS(app)

# Configuration - ОБЯЗАТЕЛЬНО ИЗМЕНИ ЭТИ ПУТИ!
MINECRAFT_SERVER = "127.0.0.1:25565"  # Твой адрес сервера
STATS_FOLDER = "/home/donatkauler/McServer/world/stats"  # Папка со статистикой игроков
USERCACHE_FILE = "/home/donatkauler/McServer/usercache.json"  # Файл с кэшем пользователей
MINECRAFT_LOG_FILE = "/home/donatkauler/McServer/logs/latest.log"  # Логи Minecraft

# Log queue for real-time streaming
log_queue = Queue()
log_listeners = []

# Setup logging
def setup_logging():
    # Создаем папку для логов если нет
    os.makedirs('logs', exist_ok=True)
    
    # Настраиваем логирование
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s',
        handlers=[
            logging.FileHandler('logs/api.log'),
            logging.StreamHandler(sys.stdout)
        ]
    )
    return logging.getLogger('api_server')

logger = setup_logging()

# Middleware для логирования всех запросов
@app.before_request
def log_request():
    g.start_time = time.time()
    request_id = request.headers.get('X-Request-ID', os.urandom(4).hex())
    g.request_id = request_id
    
    # Логируем запрос
    log_entry = {
        'timestamp': datetime.now().isoformat(),
        'source': 'api',
        'message': f"{request.method} {request.path} | IP: {request.remote_addr} | ID: {request_id}",
        'level': 'info'
    }
    log_queue.put(log_entry)
    
    logger.info(f"Request: {request.method} {request.path} from {request.remote_addr}")

@app.after_request
def log_response(response):
    duration = time.time() - g.start_time
    request_id = getattr(g, 'request_id', 'unknown')
    
    # Логируем ответ
    log_entry = {
        'timestamp': datetime.now().isoformat(),
        'source': 'api',
        'message': f"{request.method} {request.path} | Status: {response.status_code} | Duration: {duration:.3f}s | ID: {request_id}",
        'level': 'info'
    }
    log_queue.put(log_entry)
    
    logger.info(f"Response: {response.status_code} for {request.path} in {duration:.3f}s")
    
    return response

# Эндпоинт для получения статистики
@app.route('/api/stats', methods=['GET'])
def get_server_stats():
    try:
        server = JavaServer.lookup(MINECRAFT_SERVER)
        status = server.status()
        
        # Логируем успешное получение статистики
        log_queue.put({
            'timestamp': datetime.now().isoformat(),
            'source': 'minecraft',
            'message': f"Сервер онлайн: {status.players.online}/{status.players.max} игроков, версия: {status.version.name}",
            'level': 'info'
        })
        
        players_list = []
        if status.players.sample:
            players_list = [{"name": player.name} for player in status.players.sample]
        
        response = {
            "online": True,
            "serverAddress": MINECRAFT_SERVER,
            "version": status.version.name,
            "players": {
                "online": status.players.online,
                "max": status.players.max,
                "list": players_list
            },
            "motd": status.description,
            "latency": status.latency
        }
        
        return jsonify(response)
    
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Server stats error: {error_msg}")
        logger.error(traceback.format_exc())
        
        # Логируем ошибку
        log_queue.put({
            'timestamp': datetime.now().isoformat(),
            'source': 'minecraft',
            'message': f"Ошибка подключения к серверу: {error_msg}",
            'level': 'error'
        })
        
        return jsonify({
            "online": False,
            "serverAddress": MINECRAFT_SERVER,
            "error": error_msg,
            "players": {"online": 0, "max": 0, "list": []}
        }), 200

# SSE эндпоинт для потоковой передачи логов
@app.route('/api/logs/stream')
def stream_logs():
    def generate():
        # Отправляем тестовое сообщение при подключении
        yield f"data: {json.dumps({
            'timestamp': datetime.now().isoformat(),
            'source': 'system',
            'message': 'Подключение к потоку логов установлено',
            'level': 'info'
        })}\n\n"
        
        while True:
            try:
                # Ждем лог из очереди
                log_entry = log_queue.get(timeout=1.0)
                yield f"data: {json.dumps(log_entry)}\n\n"
            except Empty:
                # Heartbeat для поддержания соединения
                yield f"data: {json.dumps({
                    'timestamp': datetime.now().isoformat(),
                    'source': 'system',
                    'message': 'heartbeat',
                    'level': 'debug'
                })}\n\n"
    
    return Response(stream_with_context(generate()), mimetype='text/event-stream')

# Фоновый поток для мониторинга логов Minecraft
def monitor_minecraft_logs():
    if not os.path.exists(MINECRAFT_LOG_FILE):
        logger.error(f"Minecraft log file not found: {MINECRAFT_LOG_FILE}")
        return
    
    logger.info(f"Starting Minecraft log monitoring: {MINECRAFT_LOG_FILE}")
    
    try:
        with open(MINECRAFT_LOG_FILE, 'r') as f:
            # Перемещаемся в конец файла
            f.seek(0, os.SEEK_END)
            
            while True:
                line = f.readline()
                if not line:
                    time.sleep(0.1)  # Небольшая задержка если нет новых строк
                    continue
                
                if line.strip():
                    # Определяем уровень лога
                    level = 'info'
                    line_upper = line.upper()
                    if 'ERROR' in line_upper or 'EXCEPTION' in line_upper or 'FAILED' in line_upper:
                        level = 'error'
                    elif 'WARN' in line_upper:
                        level = 'warning'
                    
                    log_entry = {
                        'timestamp': datetime.now().isoformat(),
                        'source': 'minecraft',
                        'message': line.strip(),
                        'level': level
                    }
                    log_queue.put(log_entry)
    
    except Exception as e:
        logger.error(f"Minecraft log monitoring error: {str(e)}")
        logger.error(traceback.format_exc())

# Фоновый поток для генерации системных логов
def generate_system_logs():
    while True:
        try:
            # Генерируем рандомные системные логи для демонстрации
            services = ['api', 'db', 'web', 'cache', 'auth', 'storage']
            actions = ['started', 'stopped', 'restarted', 'connected', 'disconnected']
            service = random.choice(services)
            action = random.choice(actions)
            
            log_entry = {
                'timestamp': datetime.now().isoformat(),
                'source': service,
                'message': f"Service '{service}' {action} successfully",
                'level': 'info' if random.random() > 0.2 else 'error'
            }
            log_queue.put(log_entry)
            
            # Добавляем рандомные веб-запросы
            if random.random() > 0.7:
                methods = ['GET', 'POST', 'PUT', 'DELETE']
                paths = ['/api/stats', '/api/logs', '/status', '/metrics', '/health']
                method = random.choice(methods)
                path = random.choice(paths)
                status = 200 if random.random() > 0.1 else 500
                
                log_entry = {
                    'timestamp': datetime.now().isoformat(),
                    'source': 'web',
                    'message': f"{method} {path} {status}",
                    'level': 'info' if status == 200 else 'error'
                }
                log_queue.put(log_entry)
            
            time.sleep(random.uniform(1, 5))  # Рандомная задержка
            
        except Exception as e:
            logger.error(f"System log generation error: {str(e)}")
            time.sleep(10)

# Запуск фоновых потоков
def start_background_threads():
    # Поток для мониторинга логов Minecraft
    if os.path.exists(MINECRAFT_LOG_FILE):
        minecraft_thread = threading.Thread(target=monitor_minecraft_logs, daemon=True)
        minecraft_thread.start()
        logger.info("Minecraft log monitoring thread started")
    else:
        logger.warning(f"Minecraft log file not found: {MINECRAFT_LOG_FILE}")
    
    # Поток для системных логов
    system_thread = threading.Thread(target=generate_system_logs, daemon=True)
    system_thread.start()
    logger.info("System log generation thread started")
    
    # Начальный лог
    log_queue.put({
        'timestamp': datetime.now().isoformat(),
        'source': 'system',
        'message': 'Система мониторинга запущена',
        'level': 'info'
    })

if __name__ == '__main__':
    # Запускаем фоновые потоки
    start_background_threads()
    
    # Запускаем Flask сервер
    app.run(
        host='0.0.0.0',
        port=5000,
        debug=False,
        threaded=True
    )
