# BookStreamDB Course Project

Учебный проект базы данных для онлайн-сервиса цифровых книг. Пользователь может зарегистрироваться, войти в аккаунт, пополнить баланс, купить книгу, оформить подписку, читать доступные произведения, сохранять прогресс, добавлять книги в избранное и оставлять отзывы. Администратор управляет каталогом, справочниками, акциями и отчётами через веб-интерфейс.

## Технологии

- **Microsoft SQL Server 2022** — таблицы, ограничения, индексы, представления, функции, процедуры и триггеры.
- **Python 3.11**, **FastAPI**, **pyodbc** — backend API.
- **RapidFuzz** — нечёткий поиск книг с учётом опечаток.
- **React**, **Vite**, **Axios** — frontend.
- **Swagger UI** — документация и ручная проверка API.

## Основные возможности

- баланс пользователя и история платежей;
- покупки книг с проверкой остатка средств;
- обычные книги, бесплатные книги и **премиальные книги**, доступные только после покупки;
- подписки, которые открывают обычные книги с признаком `IsAvailableBySubscription`;
- акции, промокоды и итоговая цена со скидкой;
- постоянный персональный промокод `BIRTHDAY15`: скидка 15% на любую книгу в день рождения пользователя;
- библиотека пользователя на основе представления `vw_UserLibrary`;
- административная панель со справочниками, отчётами, AuditLog и списком SQL-объектов.

## Структура проекта

```text
Course_Work_DB_2026/
├── backend/                         # FastAPI backend
│   ├── app/
│   │   ├── routers/                 # группы API-маршрутов
│   │   │   ├── books.py             # каталог, нечёткий поиск, карточка книги,
│   │   │   │                        # расчёт цены, покупка, чтение, отзывы и прогресс
│   │   │   ├── users.py             # регистрация, вход, профиль, библиотека,
│   │   │   │                        # баланс, подписки и избранное
│   │   │   ├── subscriptions.py     # получение доступных тарифов подписки
│   │   │   └── admin.py             # права администратора, справочники, книги,
│   │   │                            # акции, аудит, статистика и отчёты
│   │   ├── database.py              # подключение к SQL Server через pyodbc,
│   │   │                            # выполнение запросов, commit и rollback
│   │   ├── schemas.py               # Pydantic-модели и валидация входных данных
│   │   └── main.py                  # создание FastAPI-приложения,
│   │                                # подключение роутеров и health-check
│   ├── .env.example                 # пример параметров подключения к SQL Server
│   └── requirements.txt             # Python-зависимости backend
├── database/                        # SQL-файлы для чистой сборки БД
├── frontend/                        # клиентская часть React + Vite
│   └── src/
│       ├── api.js                   # Axios-клиент для обращения к backend
│       ├── App.jsx                  # страницы сайта и логика интерфейса
│       └── App.css                  # стили интерфейса
├── models/                          # CSV и PNG моделей для diagrams.net
├── scripts/                         # короткие скрипты запуска
└── README.md
```

## Запуск проекта

### 1. Запустить SQL Server

На Ubuntu:

```bash
sudo systemctl start mssql-server
sudo systemctl status mssql-server
```

В статусе должно быть:

```text
active (running)
```

### 2. Собрать базу данных с нуля

Открой папку `database` в VS Code и последовательно выполни файлы через расширение SQL Server. Выполняй их строго в таком порядке:

```text
01_create_database.sql
02_create_tables.sql
03_create_functions.sql
04_create_views.sql
05_create_indexes.sql
06_create_procedures.sql
07_create_triggers.sql
08_insert_test_data.sql
09_test_queries.sql
10_set_demo_passwords.sql
```

Первые восемь файлов полностью создают структуру и заполняют учебные данные. Девятый файл содержит проверочные запросы. Десятый устанавливает простые демонстрационные пароли.

> `01_create_database.sql` удаляет старую `BookStreamDB` и создаёт её заново. Перед запуском убедись, что в базе нет данных, которые нужно сохранить.

### 3. Настроить backend

Перейди в папку backend:

```bash
cd ~/CourseWorkeSpring2026/backend
```

Создай виртуальное окружение при первом запуске:

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Создай рабочий `.env` на основе примера:

```bash
cp .env.example .env
```

Открой `.env` и укажи пароль SQL Server:

```env
DB_DRIVER=ODBC Driver 18 for SQL Server
DB_SERVER=localhost
DB_DATABASE=BookStreamDB
DB_USER=SA
DB_PASSWORD=your_real_password_here
DB_ENCRYPT=yes
DB_TRUST_SERVER_CERTIFICATE=yes
```

Запусти backend:

```bash
source venv/bin/activate
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Проверка:

```text
http://127.0.0.1:8000/health
http://127.0.0.1:8000/docs
```

Также можно использовать скрипт из корня проекта:

```bash
./scripts/run_backend.sh
```

### 4. Запустить frontend

Открой второй терминал:

```bash
cd ~/CourseWorkeSpring2026/frontend
npm install
npm run dev
```

Открой сайт:

```text
http://localhost:5173
```

Также можно использовать скрипт:

```bash
./scripts/run_frontend.sh
```

## Демонстрационные аккаунты

```text
Администратор: admin / admin123
Пользователь:   giorgi / 1234
```

У пользователя `giorgi` дата рождения задаётся равной дню запуска `08_insert_test_data.sql`. Благодаря этому можно сразу проверить промокод:

```text
BIRTHDAY15
```

## Схема БД

Фактическая база содержит 19 таблиц, включая:

```text
Role, UserAccount, AuditLog, Publisher, Author, Genre, Book,
BookAuthor, BookGenre, BookContent, SubscriptionPlan, Payment,
Purchase, UserSubscription, Review, FavoriteBook, ReadingProgress,
Promotion, BookPromotion
```

Все крупные операции backend вынесены в хранимые процедуры SQL Server. Исключение — получение библиотеки пользователя: backend намеренно читает готовое представление `vw_UserLibrary`.

Для построения актуальных диаграмм импортируй в diagrams.net:

```text
models/ER-model.csv
models/Relational-model.csv
```

После импорта CSV и экспорта диаграмм сохрани новые PNG-изображения рядом с исходниками.

## Проверка frontend перед коммитом

```bash
cd frontend
npm run lint
npm run build
```

## Примечание о паролях

`10_set_demo_passwords.sql` задаёт простые пароли только для учебной демонстрации. При регистрации через сайт новый пароль хешируется backend-ом.
