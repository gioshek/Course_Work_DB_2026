from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import call_db
from app.routers import admin, books, subscriptions, users


app = FastAPI(
    title="BookStream API",
    description="Backend API для сайта онлайн-чтения цифровых книг.",
    version="2.0.0",
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(books.router)
app.include_router(users.router)
app.include_router(subscriptions.router)
app.include_router(admin.router)


@app.get("/")
def root():
    return {
        "message": "BookStream API работает",
        "docs": "/docs",
    }


@app.get("/health")
def health_check():
    result_sets = call_db("EXEC dbo.usp_HealthCheck")
    database_info = result_sets[0][0] if result_sets and result_sets[0] else {}

    return {
        "status": "ok",
        "database": database_info,
    }
