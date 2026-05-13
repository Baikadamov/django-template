# Backend Project Overview

## Инфраструктура (Docker Compose)

| Сервис | Пример Image | Порт |
|---|---|---|
| `backend` | Custom (Python / Django) | 8000 |
| `db` | `postgis/postgis:15-3.3` или `postgres:15` | 5432 |
| `storage` | `minio/minio:RELEASE.2023-12-23T07-19-11Z` | 9000 / 9001 (console) |
| `cache` *(опц.)* | `redis:7` | 6379 |

> PostGIS — если нужны геоданные. Redis — для Celery / кэша.

---

## Подключение MinIO (S3-совместимое хранилище)

MinIO используется для хранения медиафайлов. Работает через `django-storages` + `boto3`.

**Установка:**
```bash
pip install django-storages boto3
```

**`settings.py`:**
```python
AWS_ACCESS_KEY_ID = os.getenv('MINIO_ROOT_USER')
AWS_SECRET_ACCESS_KEY = os.getenv('MINIO_ROOT_PASSWORD')
AWS_STORAGE_BUCKET_NAME = os.getenv('MINIO_BUCKET_NAME')
AWS_S3_ENDPOINT_URL = os.getenv('MINIO_ENDPOINT_URL')  # http://minio:9000

AWS_S3_FILE_OVERWRITE = False
AWS_QUERYSTRING_AUTH = True
AWS_S3_VERIFY = False
AWS_S3_USE_SSL = False
AWS_S3_REGION_NAME = None

MEDIA_URL = f'{AWS_S3_ENDPOINT_URL}/{AWS_STORAGE_BUCKET_NAME}/'

# Django 4.2+ — новый формат STORAGES (вместо DEFAULT_FILE_STORAGE)
STORAGES = {
    'default': {
        'BACKEND': 'storages.backends.s3boto3.S3Boto3Storage',
    },
    'staticfiles': {
        'BACKEND': 'django.contrib.staticfiles.storage.StaticFilesStorage',
    },
}
```

> До Django 4.2 использовалось `DEFAULT_FILE_STORAGE = 'storages.backends.s3boto3.S3Boto3Storage'`. Сейчас это deprecated — используй `STORAGES`.

**`.env`:**
```env
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=secret
MINIO_BUCKET_NAME=media
MINIO_ENDPOINT_URL=http://minio:9000
```

Бакет нужно создать вручную при первом запуске через консоль MinIO (`localhost:9001`) или через `mc` CLI.

---

## Структура приложений (`apps/`)

Каждое приложение — отдельная предметная область. Внутри единый паттерн:

```
apps/<name>/
  models/        # модели, __init__.py реэкспортирует всё
  serializers/   # DRF-сериализаторы
  views/         # ViewSet'ы или APIView
  services/      # бизнес-логика
  filters.py     # DjangoFilterBackend фильтры
  urls.py        # роутер
  admin.py
  migrations/
  tests/
```

### Типичные приложения

| Приложение | Назначение |
|---|---|
| `common` | BaseModel, кастомные exceptions, permissions, validators |
| `users` | Пользователи, аутентификация, роли |
| `<domain>` | Основная предметная область проекта |
| `notifications` *(опц.)* | Push, Email, SMS |
| `analytics` *(опц.)* | Агрегированные отчёты |

---

## Слои внутри приложения

```
Request → View → Serializer (валидация) → Service (бизнес-логика) → Model/DB
```

- **View** — только роутинг, проверка прав, вызов сервиса, возврат ответа. Никакой логики.
- **Serializer** — валидация входных данных, сериализация ответа. Отдельные сериализаторы на чтение и запись при необходимости.
- **Service** — вся логика: транзакции, расчёты, отправка уведомлений. Чистые функции или классы без состояния.
- **Model** — только структура данных и базовые constraints. Никакой бизнес-логики в методах модели.

Пример разбивки ViewSet:

```python
class OrderViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated]
    serializer_class = OrderSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        order = OrderService.create(user=request.user, data=serializer.validated_data)
        return Response(OrderSerializer(order).data, status=201)
```

---

## BaseModel

Общий абстрактный класс для всех моделей. Располагается в `apps/common/models/base.py`.

```python
class BaseModel(models.Model):
    id = models.AutoField(primary_key=True)  # или UUIDField если нужен UUID
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True
```

> UUID в качестве PK уместен, когда ID не должен быть предсказуемым (публичные API, прямые ссылки на ресурсы). Для внутренних таблиц обычный `AutoField` проще и быстрее по индексам.

---

## Обработка ошибок

Единый формат ответа на ошибки через кастомный DRF exception handler.

```python
# apps/common/exceptions.py
class ApplicationError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message

# apps/common/exception_handler.py
def custom_exception_handler(exc, context):
    if isinstance(exc, ApplicationError):
        return Response({'code': exc.code, 'message': exc.message}, status=400)
    return exception_handler(exc, context)
```

```python
# settings.py
REST_FRAMEWORK = {
    'EXCEPTION_HANDLER': 'apps.common.exception_handler.custom_exception_handler',
}
```

---

## Разграничение доступа

Роли хранятся в модели пользователя (`User.role`). Пермишены реализуются в `apps/common/permissions.py` и подключаются на уровне ViewSet.

Принцип: каждый ViewSet явно объявляет, кто имеет доступ. Никаких открытых эндпоинтов по умолчанию.

```python
# apps/common/permissions.py
class IsAdmin(BasePermission):
    def has_permission(self, request, view):
        return request.user.role == 'ADMIN'

# использование
class UserViewSet(ModelViewSet):
    permission_classes = [IsAuthenticated, IsAdmin]
```

Для разных действий одного ViewSet можно переопределять `get_permissions()`:

```python
def get_permissions(self):
    if self.action in ('list', 'retrieve'):
        return [IsAuthenticated()]
    return [IsAuthenticated(), IsAdmin()]
```

---

## Ключевые технические решения

- **ImmutableModel** *(опц.)* — абстрактная модель, блокирующая `save()` на существующих записях и `delete()`. Используется для аудит-таблиц (логи, транзакции).
- **Атомарные обновления** через F-выражения или `select_for_update` там, где важна консистентность при конкурентных запросах.
- **Мультитенантность** *(если нужна)* — фильтрация queryset'ов по tenant (организация, регион и т.п.) на уровне базового ViewSet или кастомного менеджера.
- **JWT** через `djangorestframework-simplejwt` с ротацией и блэклистом токенов.
- **`django-filter`** — стандартный способ фильтрации queryset'ов через query params без ручного парсинга.
- **`django-cleanup`** — автоматически удаляет файлы из хранилища при удалении/замене объекта модели.

---

## Окружения

```
envs/
  dev/.env
  prod/.env
  .env.example   # шаблон — коммитится в репо, реальные файлы — нет
```

Переключение через переменную `DJANGO_ENV`. Загрузка в `settings.py`:

```python
env = os.getenv('DJANGO_ENV', 'dev')
load_dotenv(f'envs/{env}/.env')
```

---

## Зависимости (типичный `requirements.txt`)

```
django>=5.0
djangorestframework
djangorestframework-simplejwt
django-storages
boto3
django-filter
django-cors-headers
django-cleanup
psycopg2-binary        # или psycopg[binary] для psycopg3
python-dotenv
drf-spectacular        # OpenAPI / Swagger
```
