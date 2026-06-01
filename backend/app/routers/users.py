from fastapi import APIRouter, HTTPException
from passlib.hash import bcrypt

from app.database import call_db
from app.schemas import (
    CreateSubscriptionRequest,
    LoginUserRequest,
    RegisterUserRequest,
    TopUpBalanceRequest,
)


router = APIRouter(prefix="/users", tags=["Users"])


def raise_database_error(error: Exception):
    raise HTTPException(status_code=400, detail=str(error))


def verify_password(password: str, stored_password: str) -> bool:
    if not stored_password:
        return False

    try:
        if stored_password.startswith("$2"):
            return bcrypt.verify(password, stored_password)
    except Exception:
        return False

    return password == stored_password


@router.post("/register")
def register_user(request: RegisterUserRequest):
    try:
        password_hash = bcrypt.hash(request.password)

        result_sets = call_db(
            """
            EXEC dbo.usp_RegisterUser
                @Username = ?,
                @Email = ?,
                @PasswordHash = ?,
                @DateOfBirth = ?
            """,
            (
                request.username,
                str(request.email),
                password_hash,
                request.date_of_birth,
            ),
        )

        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Пользователь зарегистрирован"
        }
    except Exception as error:
        raise_database_error(error)


@router.post("/login")
def login_user(request: LoginUserRequest):
    try:
        result_sets = call_db(
            "EXEC dbo.usp_GetUserForLogin @Login = ?",
            (request.login,),
        )

        user = result_sets[0][0] if result_sets and result_sets[0] else None

        if user is None:
            raise HTTPException(status_code=401, detail="Неверный логин или пароль")

        if not user["IsActive"]:
            raise HTTPException(status_code=403, detail="Пользователь заблокирован")

        if not verify_password(request.password, user["PasswordHash"]):
            raise HTTPException(status_code=401, detail="Неверный логин или пароль")

        return {
            "UserId": user["UserId"],
            "Username": user["Username"],
            "Email": user["Email"],
            "DateOfBirth": user["DateOfBirth"],
            "RoleName": user["RoleName"],
            "Balance": user["Balance"],
        }
    except HTTPException:
        raise
    except Exception as error:
        raise_database_error(error)


@router.get("/{user_id}/library")
def get_user_library(user_id: int):
    """
    Библиотека читается прямо из vw_UserLibrary.
    Отдельная процедура для этой выборки не нужна: представление уже содержит
    готовую логику доступа через покупку, бесплатность и подписку.
    """
    try:
        result_sets = call_db(
            """
            SELECT *
            FROM dbo.vw_UserLibrary
            WHERE UserId = ?
            ORDER BY Title;
            """,
            (user_id,),
        )

        return result_sets[0] if result_sets else []
    except Exception as error:
        raise_database_error(error)


@router.post("/{user_id}/balance/top-up")
def top_up_balance(user_id: int, request: TopUpBalanceRequest):
    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_TopUpBalance
                @UserId = ?,
                @Amount = ?,
                @PaymentMethod = ?
            """,
            (user_id, request.amount, request.payment_method),
        )

        row = result_sets[0][0] if result_sets and result_sets[0] else None

        return {
            "message": "Баланс успешно пополнен",
            "user": row,
            "payment": row,
            "Balance": row.get("Balance") if row else None,
        }
    except Exception as error:
        raise_database_error(error)


@router.post("/{user_id}/subscriptions")
def create_subscription(user_id: int, request: CreateSubscriptionRequest):
    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_CreateSubscription
                @UserId = ?,
                @PlanId = ?,
                @PaymentMethod = ?
            """,
            (user_id, request.plan_id, request.payment_method),
        )

        subscription = result_sets[0][0] if result_sets and result_sets[0] else None

        return {
            "message": "Подписка оформлена",
            "subscription": subscription,
            "Balance": subscription.get("Balance") if subscription else None,
        }
    except Exception as error:
        raise_database_error(error)


@router.get("/{user_id}/profile")
def get_user_profile(user_id: int):
    try:
        result_sets = call_db(
            "EXEC dbo.usp_GetUserProfile @UserId = ?",
            (user_id,),
        )

        profile = result_sets[0][0] if len(result_sets) > 0 and result_sets[0] else None

        if profile is None:
            raise HTTPException(status_code=404, detail="Пользователь не найден")

        return {
            "profile": profile,
            "subscriptions": result_sets[1] if len(result_sets) > 1 else [],
            "payments": result_sets[2] if len(result_sets) > 2 else [],
            "reading_progress": result_sets[3] if len(result_sets) > 3 else [],
        }
    except HTTPException:
        raise
    except Exception as error:
        raise_database_error(error)


@router.get("/{user_id}/favorites")
def get_user_favorites(user_id: int):
    try:
        result_sets = call_db(
            "EXEC dbo.usp_GetUserFavorites @UserId = ?",
            (user_id,),
        )
        return result_sets[0] if result_sets else []
    except Exception as error:
        raise_database_error(error)


@router.post("/{user_id}/favorites/{book_id}")
def add_book_to_favorites(user_id: int, book_id: int):
    try:
        result_sets = call_db(
            "EXEC dbo.usp_AddFavoriteBook @UserId = ?, @BookId = ?",
            (user_id, book_id),
        )
        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Книга добавлена в избранное"
        }
    except Exception as error:
        raise_database_error(error)


@router.delete("/{user_id}/favorites/{book_id}")
def remove_book_from_favorites(user_id: int, book_id: int):
    try:
        result_sets = call_db(
            "EXEC dbo.usp_RemoveFavoriteBook @UserId = ?, @BookId = ?",
            (user_id, book_id),
        )
        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Книга удалена из избранного"
        }
    except Exception as error:
        raise_database_error(error)
