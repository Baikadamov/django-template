#!/bin/sh
set -e

echo "Ждём, пока база данных станет доступна..."
while ! nc -z "$POSTGRES_HOST" "$POSTGRES_PORT"; do
  sleep 0.5
done

echo "База данных запущена — применяем миграции..."
python manage.py migrate --noinput

echo "Собираем статику..."
python manage.py collectstatic --noinput

echo "Запускаем Gunicorn..."
exec gunicorn --bind 0.0.0.0:8000 config.wsgi:application