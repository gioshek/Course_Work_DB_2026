from fastapi import APIRouter, HTTPException
from passlib.hash import bcrypt

from app.database import call_db, get_connection, rows_to_dicts
from app.schemas import (
    CreateSubscriptionRequest,
    LoginUserRequest,
    RegisterUserRequest,
    TopUpBalanceRequest,
)


router = APIRouter(prefix="/users", tags=["Users"])


def raise_database_error(error: Exception):
    raise HTTPException(status_code=400, detail=str(error))


def get_single_row(cursor):
    rows = rows_to_dicts(cursor)
    return rows[0] if rows else None


@router.post("/register")
def register_user(request: RegisterUserRequest):
    try:
        password_hash = bcrypt.hash(request.password)

        result_sets = call_db(
            """
            EXEC dbo.usp_RegisterUser
                @Username = ?,
                @Email = ?,
                @PasswordHash = ?
            """,
            (request.username, str(request.email), password_hash),
        )

        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Пользователь зарегистрирован"
        }

    except Exception as error:
        raise_database_error(error)


def verify_password(password: str, stored_password: str) -> bool:
    if not stored_password:
        return False

    try:
        if stored_password.startswith("$2"):
            return bcrypt.verify(password, stored_password)
    except Exception:
        return False

    return password == stored_password


@router.post("/login")
def login_user(request: LoginUserRequest):
    try:
        result_sets = call_db(
            """
            SELECT TOP 1
                U.UserId,
                U.Username,
                U.Email,
                U.PasswordHash,
                U.IsActive,
                U.Balance,
                R.RoleName
            FROM dbo.UserAccount AS U
                INNER JOIN dbo.Role AS R ON U.RoleId = R.RoleId
            WHERE U.Username = ?
               OR U.Email = ?;
            """,
            (request.login, request.login),
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
            "RoleName": user["RoleName"],
            "Balance": user["Balance"],
        }

    except HTTPException:
        raise

    except Exception as error:
        raise_database_error(error)


@router.get("/{user_id}/library")
def get_user_library(user_id: int):
    try:
        result_sets = call_db(
            "EXEC dbo.usp_GetUserLibrary @UserId = ?",
            (user_id,),
        )

        return result_sets[0] if result_sets else []

    except Exception as error:
        raise_database_error(error)


@router.post("/{user_id}/balance/top-up")
def top_up_balance(user_id: int, request: TopUpBalanceRequest):
    try:
        with get_connection() as connection:
            cursor = connection.cursor()

            try:
                cursor.execute(
                    """
                    SELECT
                        UserId,
                        Username,
                        Balance,
                        IsActive
                    FROM dbo.UserAccount WITH (UPDLOCK, HOLDLOCK)
                    WHERE UserId = ?;
                    """,
                    (user_id,),
                )
                user = get_single_row(cursor)

                if user is None or not user["IsActive"]:
                    raise HTTPException(status_code=404, detail="Активный пользователь не найден")

                cursor.execute(
                    """
                    SET NOCOUNT ON;

                    UPDATE dbo.UserAccount
                    SET Balance = Balance + ?
                    WHERE UserId = ?;
                    """,
                    (request.amount, user_id),
                )

                cursor.execute(
                    """
                    SET NOCOUNT ON;

                    INSERT INTO dbo.Payment
                        (UserId, Amount, PaymentMethod, PaymentStatus, TransactionNumber)
                    VALUES
                        (?, ?, ?, N'Success', N'TRX-TOPUP-' + CONVERT(NVARCHAR(36), NEWID()));

                    SELECT CONVERT(INT, SCOPE_IDENTITY()) AS PaymentId;
                    """,
                    (user_id, request.amount, request.payment_method),
                )
                payment_identity = get_single_row(cursor)
                payment_id = payment_identity["PaymentId"] if payment_identity else None

                cursor.execute(
                    """
                    SELECT
                        UserId,
                        Username,
                        Email,
                        Balance
                    FROM dbo.UserAccount
                    WHERE UserId = ?;
                    """,
                    (user_id,),
                )
                updated_user = get_single_row(cursor)

                cursor.execute(
                    """
                    SELECT
                        PaymentId,
                        UserId,
                        Amount,
                        PaymentDate,
                        PaymentMethod,
                        PaymentStatus,
                        TransactionNumber
                    FROM dbo.Payment
                    WHERE PaymentId = ?;
                    """,
                    (payment_id,),
                )
                payment = get_single_row(cursor)

                connection.commit()

                return {
                    "message": "Баланс успешно пополнен",
                    "user": updated_user,
                    "payment": payment,
                    "Balance": updated_user["Balance"] if updated_user else None,
                }

            except HTTPException:
                connection.rollback()
                raise

            except Exception:
                connection.rollback()
                raise

    except HTTPException:
        raise

    except Exception as error:
        raise_database_error(error)


@router.post("/{user_id}/subscriptions")
def create_subscription(user_id: int, request: CreateSubscriptionRequest):
    try:
        with get_connection() as connection:
            cursor = connection.cursor()

            try:
                cursor.execute(
                    """
                    SELECT
                        UserId,
                        Username,
                        Balance,
                        IsActive
                    FROM dbo.UserAccount WITH (UPDLOCK, HOLDLOCK)
                    WHERE UserId = ?;
                    """,
                    (user_id,),
                )
                user = get_single_row(cursor)

                if user is None or not user["IsActive"]:
                    raise HTTPException(status_code=404, detail="Активный пользователь не найден")

                cursor.execute(
                    """
                    SELECT
                        PlanId,
                        PlanName,
                        Price,
                        DurationDays,
                        IsActive
                    FROM dbo.SubscriptionPlan
                    WHERE PlanId = ?
                      AND IsActive = 1;
                    """,
                    (request.plan_id,),
                )
                plan = get_single_row(cursor)

                if plan is None:
                    raise HTTPException(status_code=404, detail="Активный тариф подписки не найден")

                price = float(plan["Price"] or 0)
                current_balance = float(user["Balance"] or 0)

                if current_balance < price:
                    raise HTTPException(
                        status_code=400,
                        detail=f"Недостаточно средств. Нужно {price:.2f} ₽, на балансе {current_balance:.2f} ₽.",
                    )

                cursor.execute(
                    """
                    SET NOCOUNT ON;

                    INSERT INTO dbo.Payment
                        (UserId, Amount, PaymentMethod, PaymentStatus, TransactionNumber)
                    VALUES
                        (?, ?, ?, N'Success', N'TRX-SUB-' + CONVERT(NVARCHAR(36), NEWID()));

                    SELECT CONVERT(INT, SCOPE_IDENTITY()) AS PaymentId;
                    """,
                    (user_id, price, request.payment_method),
                )
                payment = get_single_row(cursor)
                payment_id = payment["PaymentId"] if payment else None

                cursor.execute(
                    """
                    UPDATE dbo.UserAccount
                    SET Balance = Balance - ?
                    WHERE UserId = ?;
                    """,
                    (price, user_id),
                )

                cursor.execute(
                    """
                    SET NOCOUNT ON;

                    DECLARE @StartDate DATE = CAST(GETDATE() AS DATE);
                    DECLARE @EndDate DATE = DATEADD(DAY, ?, @StartDate);

                    INSERT INTO dbo.UserSubscription
                        (UserId, PlanId, PaymentId, StartDate, EndDate, IsActive)
                    VALUES
                        (?, ?, ?, @StartDate, @EndDate, 1);

                    SELECT CONVERT(INT, SCOPE_IDENTITY()) AS SubscriptionId;
                    """,
                    (plan["DurationDays"], user_id, request.plan_id, payment_id),
                )
                subscription_identity = get_single_row(cursor)
                subscription_id = subscription_identity["SubscriptionId"] if subscription_identity else None

                cursor.execute(
                    """
                    SELECT
                        US.SubscriptionId,
                        US.UserId,
                        U.Username,
                        U.Balance,
                        US.PlanId,
                        SP.PlanName,
                        US.PaymentId,
                        US.StartDate,
                        US.EndDate,
                        US.IsActive
                    FROM dbo.UserSubscription AS US
                        INNER JOIN dbo.UserAccount AS U ON US.UserId = U.UserId
                        INNER JOIN dbo.SubscriptionPlan AS SP ON US.PlanId = SP.PlanId
                    WHERE US.SubscriptionId = ?;
                    """,
                    (subscription_id,),
                )
                subscription = get_single_row(cursor)

                connection.commit()

                return {
                    "message": "Подписка оформлена",
                    "subscription": subscription,
                    "Balance": float(subscription["Balance"]) if subscription and subscription.get("Balance") is not None else None,
                    "SubscriptionId": subscription_id,
                }

            except HTTPException:
                connection.rollback()
                raise

            except Exception:
                connection.rollback()
                raise

    except HTTPException:
        raise

    except Exception as error:
        raise_database_error(error)


@router.get("/{user_id}/profile")
def get_user_profile(user_id: int):
    try:
        result_sets = call_db(
            """
            SELECT
                U.UserId,
                U.Username,
                U.Email,
                U.RegistrationDate,
                U.IsActive,
                U.Balance,
                R.RoleName,
                dbo.fn_GetUserPurchasedBookCount(U.UserId) AS PurchasedBookCount,
                dbo.fn_GetUserFavoriteBookCount(U.UserId) AS FavoriteBookCount
            FROM dbo.UserAccount AS U
                INNER JOIN dbo.Role AS R ON U.RoleId = R.RoleId
            WHERE U.UserId = ?;

            SELECT
                SubscriptionId,
                Username,
                PlanName,
                Price,
                DurationDays,
                StartDate,
                EndDate,
                IsActive
            FROM dbo.vw_ActiveUserSubscriptions
            WHERE UserId = ?;

            SELECT
                PaymentId,
                Amount,
                PaymentDate,
                PaymentMethod,
                PaymentStatus,
                TransactionNumber
            FROM dbo.vw_UserPayments
            WHERE UserId = ?
            ORDER BY PaymentDate DESC;

            SELECT
                ProgressId,
                Title,
                CurrentPage,
                PageCount,
                ProgressPercent,
                LastReadAt
            FROM dbo.vw_UserReadingProgress
            WHERE UserId = ?
            ORDER BY LastReadAt DESC;
            """,
            (user_id, user_id, user_id, user_id),
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
            """
            SELECT
                U.UserId,
                U.Username,
                B.BookId,
                B.Title,
                B.Price,
                B.IsFree,
                B.IsAvailableBySubscription,
                B.CoverImageUrl,
                P.PublisherName,
                F.AddedAt
            FROM dbo.FavoriteBook AS F
                INNER JOIN dbo.UserAccount AS U ON F.UserId = U.UserId
                INNER JOIN dbo.Book AS B ON F.BookId = B.BookId
                INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId
            WHERE F.UserId = ?
            ORDER BY F.AddedAt DESC;
            """,
            (user_id,),
        )

        return result_sets[0] if result_sets else []

    except Exception as error:
        raise_database_error(error)


@router.post("/{user_id}/favorites/{book_id}")
def add_book_to_favorites(user_id: int, book_id: int):
    try:
        result_sets = call_db(
            """
            IF NOT EXISTS
            (
                SELECT 1
                FROM dbo.FavoriteBook
                WHERE UserId = ?
                  AND BookId = ?
            )
            BEGIN
                INSERT INTO dbo.FavoriteBook
                    (UserId, BookId)
                VALUES
                    (?, ?);
            END;

            SELECT
                F.UserId,
                U.Username,
                F.BookId,
                B.Title,
                F.AddedAt
            FROM dbo.FavoriteBook AS F
                INNER JOIN dbo.UserAccount AS U ON F.UserId = U.UserId
                INNER JOIN dbo.Book AS B ON F.BookId = B.BookId
            WHERE F.UserId = ?
              AND F.BookId = ?;
            """,
            (user_id, book_id, user_id, book_id, user_id, book_id),
        )

        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Книга добавлена в избранное"
        }

    except Exception as error:
        raise_database_error(error)


@router.delete("/{user_id}/favorites/{book_id}")
def remove_book_from_favorites(user_id: int, book_id: int):
    try:
        call_db(
            """
            DELETE FROM dbo.FavoriteBook
            WHERE UserId = ?
              AND BookId = ?;
            """,
            (user_id, book_id),
        )

        return {
            "message": "Книга удалена из избранного"
        }

    except Exception as error:
        raise_database_error(error)