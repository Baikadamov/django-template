FROM python:3.12-slim

# Устанавливаем переменные окружения для Python
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# Рабочая директория в контейнере
WORKDIR /app

# Устанавливаем системные зависимости (для psycopg2, Pillow и т.д.)
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    gcc \
    musl-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Устанавливаем зависимости проекта
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# Копируем проект
COPY . .

# Указываем переменную окружения для Django
ENV DJANGO_ENV=dev

# Запускаем gunicorn в продакшене
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]
