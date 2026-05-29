from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from app.database import call_db, get_connection, rows_to_dicts
from app.schemas import (
    AdminCreateAuthorRequest,
    AdminCreateBookRequest,
    AdminCreateGenreRequest,
    AdminCreatePublisherRequest,
)


router = APIRouter(prefix="/admin", tags=["Admin"])


class AdminCreatePromotionRequest(BaseModel):
    promotion_name: str = Field(..., min_length=1, max_length=255)
    promo_code: str = Field(..., min_length=1, max_length=50)
    discount_percent: float = Field(..., gt=0, le=100)
    start_date: str
    end_date: str
    is_active: bool = True


def raise_database_error(error: Exception):
    raise HTTPException(status_code=400, detail=str(error))

def require_admin(admin_user_id: int):
    result_sets = call_db(
        """
        SELECT
            U.UserId,
            U.Username,
            R.RoleName
        FROM dbo.UserAccount AS U
            INNER JOIN dbo.Role AS R ON U.RoleId = R.RoleId
        WHERE U.UserId = ?;
        """,
        (admin_user_id,),
    )

    user = result_sets[0][0] if result_sets and result_sets[0] else None

    if user is None:
        raise HTTPException(status_code=403, detail="Администратор не найден")

    role_name = str(user["RoleName"]).lower()

    if role_name not in ("admin", "administrator", "администратор"):
        raise HTTPException(status_code=403, detail="Доступ разрешён только администратору")

    return user

@router.get("/options")
def get_admin_options(admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db(
            """
            SELECT
                PublisherId,
                PublisherName
            FROM dbo.Publisher
            ORDER BY PublisherName;

            SELECT
                AuthorId,
                FirstName + N' ' + LastName AS AuthorName
            FROM dbo.Author
            ORDER BY LastName, FirstName;

            SELECT
                GenreId,
                GenreName
            FROM dbo.Genre
            ORDER BY GenreName;
            """
        )

        return {
            "publishers": result_sets[0] if len(result_sets) > 0 else [],
            "authors": result_sets[1] if len(result_sets) > 1 else [],
            "genres": result_sets[2] if len(result_sets) > 2 else [],
        }

    except Exception as error:
        raise_database_error(error)

@router.post("/publishers")
def create_publisher(request: AdminCreatePublisherRequest, admin_user_id: int):
    require_admin(admin_user_id)

    publisher_name = request.publisher_name.strip()

    if not publisher_name:
        raise HTTPException(status_code=400, detail="Введите название издательства")

    try:
        result_sets = call_db(
            """
            SET NOCOUNT ON;

            DECLARE @PublisherId INT;

            SELECT @PublisherId = PublisherId
            FROM dbo.Publisher
            WHERE PublisherName = ?;

            IF @PublisherId IS NULL
            BEGIN
                INSERT INTO dbo.Publisher
                    (PublisherName)
                VALUES
                    (?);

                SET @PublisherId = CONVERT(INT, SCOPE_IDENTITY());
            END;

            SELECT
                PublisherId,
                PublisherName
            FROM dbo.Publisher
            WHERE PublisherId = @PublisherId;
            """,
            (
                publisher_name,
                publisher_name,
            ),
        )

        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Издательство создано"
        }

    except Exception as error:
        raise_database_error(error)


@router.post("/authors")
def create_author(request: AdminCreateAuthorRequest, admin_user_id: int):
    require_admin(admin_user_id)

    first_name = request.first_name.strip()
    last_name = request.last_name.strip()

    if not first_name or not last_name:
        raise HTTPException(status_code=400, detail="Введите имя и фамилию автора")

    try:
        result_sets = call_db(
            """
            SET NOCOUNT ON;

            DECLARE @AuthorId INT;

            SELECT TOP 1 @AuthorId = AuthorId
            FROM dbo.Author
            WHERE FirstName = ?
              AND LastName = ?
            ORDER BY AuthorId;

            IF @AuthorId IS NULL
            BEGIN
                INSERT INTO dbo.Author
                    (FirstName, LastName)
                VALUES
                    (?, ?);

                SET @AuthorId = CONVERT(INT, SCOPE_IDENTITY());
            END;

            SELECT
                AuthorId,
                FirstName + N' ' + LastName AS AuthorName,
                FirstName,
                LastName
            FROM dbo.Author
            WHERE AuthorId = @AuthorId;
            """,
            (
                first_name,
                last_name,
                first_name,
                last_name,
            ),
        )

        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Автор создан"
        }

    except Exception as error:
        raise_database_error(error)


@router.post("/genres")
def create_genre(request: AdminCreateGenreRequest, admin_user_id: int):
    require_admin(admin_user_id)

    genre_name = request.genre_name.strip()

    if not genre_name:
        raise HTTPException(status_code=400, detail="Введите название жанра")

    try:
        result_sets = call_db(
            """
            SET NOCOUNT ON;

            DECLARE @GenreId INT;

            SELECT @GenreId = GenreId
            FROM dbo.Genre
            WHERE GenreName = ?;

            IF @GenreId IS NULL
            BEGIN
                INSERT INTO dbo.Genre
                    (GenreName)
                VALUES
                    (?);

                SET @GenreId = CONVERT(INT, SCOPE_IDENTITY());
            END;

            SELECT
                GenreId,
                GenreName
            FROM dbo.Genre
            WHERE GenreId = @GenreId;
            """,
            (
                genre_name,
                genre_name,
            ),
        )

        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Жанр создан"
        }

    except Exception as error:
        raise_database_error(error)



@router.get("/audit-log")
def get_audit_log(admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db(
            """
            SELECT TOP 50
                LogId,
                TableName,
                ActionName,
                RecordId,
                UserId,
                Description,
                CreatedAt
            FROM dbo.AuditLog
            ORDER BY LogId DESC;
            """
        )

        return result_sets[0] if result_sets else []

    except Exception as error:
        raise_database_error(error)


@router.get("/stats")
def get_admin_stats(admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db(
            """
            SELECT
                (SELECT COUNT(*) FROM dbo.Book) AS BookCount,
                (SELECT COUNT(*) FROM dbo.UserAccount) AS UserCount,
                (SELECT COUNT(*) FROM dbo.Purchase) AS PurchaseCount,
                (SELECT ISNULL(SUM(PurchasePrice), 0) FROM dbo.Purchase) AS TotalSales,
                (SELECT COUNT(*) FROM dbo.Review) AS ReviewCount,
                (SELECT ISNULL(AVG(CAST(Rating AS DECIMAL(4,2))), 0) FROM dbo.Review) AS AverageRating,
                (
                    SELECT COUNT(*)
                    FROM dbo.UserSubscription
                    WHERE IsActive = 1
                      AND CAST(GETDATE() AS DATE) BETWEEN StartDate AND EndDate
                ) AS ActiveSubscriptionCount,
                (SELECT COUNT(*) FROM dbo.Promotion) AS PromotionCount,
                (
                    SELECT COUNT(*)
                    FROM dbo.Promotion
                    WHERE IsActive = 1
                      AND CAST(GETDATE() AS DATE) BETWEEN StartDate AND EndDate
                ) AS ActivePromotionCount;

            SELECT TOP 5
                BookId,
                Title,
                PurchaseCount,
                FavoriteCount,
                ReviewCount,
                AverageRating
            FROM dbo.vw_PopularBooks
            ORDER BY
                PurchaseCount DESC,
                FavoriteCount DESC,
                ReviewCount DESC,
                AverageRating DESC;
            """
        )

        stats = result_sets[0][0] if len(result_sets) > 0 and result_sets[0] else {}
        popular_books = result_sets[1] if len(result_sets) > 1 else []

        return {
            "stats": stats,
            "popular_books": popular_books,
        }

    except Exception as error:
        raise_database_error(error)


@router.get("/promotions")
def get_promotions(admin_user_id: int):
    require_admin(admin_user_id)

    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_GetPromotions;

            SELECT
                BookId,
                Title,
                Price,
                DiscountPercent,
                FinalPrice,
                HasActivePromotion,
                ActivePromotionName,
                ActivePromoCode
            FROM dbo.vw_BookCatalog
            ORDER BY Title;
            """
        )

        return {
            "promotions": result_sets[0] if len(result_sets) > 0 else [],
            "promotion_books": result_sets[1] if len(result_sets) > 1 else [],
            "books": result_sets[2] if len(result_sets) > 2 else [],
        }

    except Exception as error:
        raise_database_error(error)


@router.post("/promotions")
def create_promotion(request: AdminCreatePromotionRequest, admin_user_id: int):
    require_admin(admin_user_id)

    promotion_name = request.promotion_name.strip()
    promo_code = request.promo_code.strip().upper()

    if not promotion_name:
        raise HTTPException(status_code=400, detail="Введите название акции")

    if not promo_code:
        raise HTTPException(status_code=400, detail="Введите промокод")

    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_CreatePromotion
                @PromotionName = ?,
                @PromoCode = ?,
                @DiscountPercent = ?,
                @StartDate = ?,
                @EndDate = ?,
                @IsActive = ?;
            """,
            (
                promotion_name,
                promo_code,
                request.discount_percent,
                request.start_date,
                request.end_date,
                1 if request.is_active else 0,
            ),
        )

        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Акция сохранена"
        }

    except Exception as error:
        raise_database_error(error)


@router.post("/promotions/{promotion_id}/books/{book_id}")
def assign_promotion_to_book(promotion_id: int, book_id: int, admin_user_id: int):
    require_admin(admin_user_id)

    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_AssignPromotionToBook
                @PromotionId = ?,
                @BookId = ?;
            """,
            (promotion_id, book_id),
        )

        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Книга добавлена в акцию"
        }

    except Exception as error:
        raise_database_error(error)


@router.delete("/promotions/{promotion_id}/books/{book_id}")
def remove_promotion_from_book(promotion_id: int, book_id: int, admin_user_id: int):
    require_admin(admin_user_id)

    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_RemovePromotionFromBook
                @PromotionId = ?,
                @BookId = ?;
            """,
            (promotion_id, book_id),
        )

        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Книга удалена из акции"
        }

    except Exception as error:
        raise_database_error(error)

@router.delete("/promotions/{promotion_id}")
def delete_promotion(promotion_id: int, admin_user_id: int):
    require_admin(admin_user_id)

    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_DeletePromotion
                @PromotionId = ?;
            """,
            (promotion_id,),
        )

        return result_sets[0][0] if result_sets and result_sets[0] else {
            "message": "Акция удалена"
        }

    except Exception as error:
        raise_database_error(error)

@router.get("/database-dashboard")
def get_database_dashboard(admin_user_id: int):
    require_admin(admin_user_id)

    try:
        result_sets = call_db(
            """
            -- 1. Общие метрики по основным сущностям базы данных
            SELECT
                (SELECT COUNT(*) FROM dbo.Role) AS RoleCount,
                (SELECT COUNT(*) FROM dbo.UserAccount) AS UserCount,
                (SELECT COUNT(*) FROM dbo.Publisher) AS PublisherCount,
                (SELECT COUNT(*) FROM dbo.Author) AS AuthorCount,
                (SELECT COUNT(*) FROM dbo.Genre) AS GenreCount,
                (SELECT COUNT(*) FROM dbo.Book) AS BookCount,
                (SELECT COUNT(*) FROM dbo.BookAuthor) AS BookAuthorLinkCount,
                (SELECT COUNT(*) FROM dbo.BookGenre) AS BookGenreLinkCount,
                (SELECT COUNT(*) FROM dbo.BookContent) AS BookContentCount,
                (SELECT COUNT(*) FROM dbo.SubscriptionPlan) AS SubscriptionPlanCount,
                (SELECT COUNT(*) FROM dbo.UserSubscription) AS UserSubscriptionCount,
                (SELECT COUNT(*) FROM dbo.Payment) AS PaymentCount,
                (SELECT COUNT(*) FROM dbo.Purchase) AS PurchaseCount,
                (SELECT COUNT(*) FROM dbo.Review) AS ReviewCount,
                (SELECT COUNT(*) FROM dbo.FavoriteBook) AS FavoriteCount,
                (SELECT COUNT(*) FROM dbo.ReadingProgress) AS ReadingProgressCount,
                (SELECT COUNT(*) FROM dbo.AuditLog) AS AuditLogCount,
                (SELECT COUNT(*) FROM dbo.Promotion) AS PromotionCount,
                (SELECT COUNT(*) FROM dbo.BookPromotion) AS BookPromotionLinkCount,
                (
                    SELECT COUNT(*)
                    FROM dbo.Promotion
                    WHERE IsActive = 1
                      AND CAST(GETDATE() AS DATE) BETWEEN StartDate AND EndDate
                ) AS ActivePromotionCount,
                (
                    SELECT COUNT(*)
                    FROM dbo.UserSubscription
                    WHERE IsActive = 1
                      AND CAST(GETDATE() AS DATE) BETWEEN StartDate AND EndDate
                ) AS ActiveSubscriptionCount,
                (SELECT ISNULL(SUM(Amount), 0) FROM dbo.Payment WHERE PaymentStatus = N'Success') AS SuccessfulPaymentAmount,
                (SELECT ISNULL(SUM(PurchasePrice), 0) FROM dbo.Purchase) AS TotalSales,
                (SELECT ISNULL(AVG(CAST(Rating AS DECIMAL(4,2))), 0) FROM dbo.Review) AS AverageRating;

            -- 2. Последние платежи
            SELECT TOP 10
                P.PaymentId,
                P.UserId,
                U.Username,
                P.Amount,
                P.PaymentMethod,
                P.PaymentStatus,
                P.TransactionNumber,
                P.PaymentDate
            FROM dbo.Payment AS P
                INNER JOIN dbo.UserAccount AS U ON P.UserId = U.UserId
            ORDER BY P.PaymentDate DESC, P.PaymentId DESC;

            -- 3. Последние покупки
            SELECT TOP 10
                PR.PurchaseId,
                PR.UserId,
                U.Username,
                PR.BookId,
                B.Title,
                PR.PurchasePrice,
                PR.PurchaseDate,
                PR.PaymentId
            FROM dbo.Purchase AS PR
                INNER JOIN dbo.UserAccount AS U ON PR.UserId = U.UserId
                INNER JOIN dbo.Book AS B ON PR.BookId = B.BookId
            ORDER BY PR.PurchaseDate DESC, PR.PurchaseId DESC;

            -- 4. Продажи по книгам
            SELECT TOP 10
                B.BookId,
                B.Title,
                COUNT(PR.PurchaseId) AS PurchaseCount,
                ISNULL(SUM(PR.PurchasePrice), 0) AS SalesAmount,
                ISNULL(AVG(NULLIF(PR.PurchasePrice, 0)), 0) AS AveragePurchasePrice
            FROM dbo.Book AS B
                LEFT JOIN dbo.Purchase AS PR ON B.BookId = PR.BookId
            GROUP BY B.BookId, B.Title
            ORDER BY SalesAmount DESC, PurchaseCount DESC, B.Title ASC;

            -- 5. Продажи по пользователям
            SELECT TOP 10
                U.UserId,
                U.Username,
                COUNT(PR.PurchaseId) AS PurchaseCount,
                ISNULL(SUM(PR.PurchasePrice), 0) AS SalesAmount,
                U.Balance
            FROM dbo.UserAccount AS U
                LEFT JOIN dbo.Purchase AS PR ON U.UserId = PR.UserId
            GROUP BY U.UserId, U.Username, U.Balance
            ORDER BY SalesAmount DESC, PurchaseCount DESC, U.Username ASC;

            -- 6. Популярные книги по избранному
            SELECT TOP 10
                B.BookId,
                B.Title,
                COUNT(F.BookId) AS FavoriteCount
            FROM dbo.Book AS B
                LEFT JOIN dbo.FavoriteBook AS F ON B.BookId = F.BookId
            GROUP BY B.BookId, B.Title
            ORDER BY FavoriteCount DESC, B.Title ASC;

            -- 7. Книги с лучшим рейтингом
            SELECT TOP 10
                B.BookId,
                B.Title,
                COUNT(R.ReviewId) AS ReviewCount,
                ISNULL(AVG(CAST(R.Rating AS DECIMAL(4,2))), 0) AS AverageRating
            FROM dbo.Book AS B
                LEFT JOIN dbo.Review AS R ON B.BookId = R.BookId
            GROUP BY B.BookId, B.Title
            HAVING COUNT(R.ReviewId) > 0
            ORDER BY AverageRating DESC, ReviewCount DESC, B.Title ASC;

            -- 8. Популярность жанров
            SELECT TOP 10
                G.GenreId,
                G.GenreName,
                COUNT(DISTINCT BG.BookId) AS BookCount,
                COUNT(DISTINCT PR.PurchaseId) AS PurchaseCount,
                COUNT(DISTINCT F.UserId) AS FavoriteCount
            FROM dbo.Genre AS G
                LEFT JOIN dbo.BookGenre AS BG ON G.GenreId = BG.GenreId
                LEFT JOIN dbo.Purchase AS PR ON BG.BookId = PR.BookId
                LEFT JOIN dbo.FavoriteBook AS F ON BG.BookId = F.BookId
            GROUP BY G.GenreId, G.GenreName
            ORDER BY PurchaseCount DESC, FavoriteCount DESC, BookCount DESC, G.GenreName ASC;

            -- 9. Активные подписки
            SELECT TOP 10
                US.SubscriptionId,
                US.UserId,
                U.Username,
                SP.PlanName,
                SP.Price,
                US.StartDate,
                US.EndDate,
                US.IsActive
            FROM dbo.UserSubscription AS US
                INNER JOIN dbo.UserAccount AS U ON US.UserId = U.UserId
                INNER JOIN dbo.SubscriptionPlan AS SP ON US.PlanId = SP.PlanId
            WHERE US.IsActive = 1
              AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate
            ORDER BY US.EndDate ASC, US.SubscriptionId DESC;

            -- 10. Активные акции
            SELECT TOP 10
                P.PromotionId,
                P.PromotionName,
                P.PromoCode,
                P.DiscountPercent,
                P.StartDate,
                P.EndDate,
                COUNT(BP.BookId) AS BookCount
            FROM dbo.Promotion AS P
                LEFT JOIN dbo.BookPromotion AS BP ON P.PromotionId = BP.PromotionId
            WHERE P.IsActive = 1
              AND CAST(GETDATE() AS DATE) BETWEEN P.StartDate AND P.EndDate
            GROUP BY
                P.PromotionId,
                P.PromotionName,
                P.PromoCode,
                P.DiscountPercent,
                P.StartDate,
                P.EndDate
            ORDER BY P.DiscountPercent DESC, P.EndDate ASC;

            -- 11. Последние действия из AuditLog
            SELECT TOP 10
                LogId,
                TableName,
                ActionName,
                RecordId,
                UserId,
                Description,
                CreatedAt
            FROM dbo.AuditLog
            ORDER BY LogId DESC;

            -- 12. SQL-объекты базы данных
            SELECT
                name AS ObjectName,
                type_desc AS ObjectType,
                create_date AS CreatedAt,
                modify_date AS ModifiedAt
            FROM sys.objects
            WHERE type IN ('V', 'P', 'FN', 'IF', 'TF', 'TR')
              AND is_ms_shipped = 0
            ORDER BY
                CASE type
                    WHEN 'V' THEN 1
                    WHEN 'P' THEN 2
                    WHEN 'FN' THEN 3
                    WHEN 'IF' THEN 4
                    WHEN 'TF' THEN 5
                    WHEN 'TR' THEN 6
                    ELSE 7
                END,
                name;
            """
        )

        return {
            "metrics": result_sets[0][0] if len(result_sets) > 0 and result_sets[0] else {},
            "latest_payments": result_sets[1] if len(result_sets) > 1 else [],
            "latest_purchases": result_sets[2] if len(result_sets) > 2 else [],
            "top_books_by_sales": result_sets[3] if len(result_sets) > 3 else [],
            "top_users_by_sales": result_sets[4] if len(result_sets) > 4 else [],
            "top_books_by_favorites": result_sets[5] if len(result_sets) > 5 else [],
            "top_books_by_rating": result_sets[6] if len(result_sets) > 6 else [],
            "top_genres": result_sets[7] if len(result_sets) > 7 else [],
            "active_subscriptions": result_sets[8] if len(result_sets) > 8 else [],
            "active_promotions": result_sets[9] if len(result_sets) > 9 else [],
            "recent_audit_log": result_sets[10] if len(result_sets) > 10 else [],
            "sql_objects": result_sets[11] if len(result_sets) > 11 else [],
        }

    except Exception as error:
        raise_database_error(error)


@router.post("/books")
def create_book(request: AdminCreateBookRequest, admin_user_id: int):
    require_admin(admin_user_id)
    if request.is_free and request.price != 0:
        raise HTTPException(
            status_code=400,
            detail="Если книга бесплатная, цена должна быть равна 0."
        )

    if len(request.author_ids) == 0:
        raise HTTPException(
            status_code=400,
            detail="Нужно выбрать хотя бы одного автора."
        )

    if len(request.genre_ids) == 0:
        raise HTTPException(
            status_code=400,
            detail="Нужно выбрать хотя бы один жанр."
        )

    try:
        with get_connection() as connection:
            cursor = connection.cursor()

            try:
                cursor.execute(
                    """
                    SET NOCOUNT ON;

                    INSERT INTO dbo.Book
                        (
                            PublisherId,
                            Title,
                            Description,
                            PublicationYear,
                            AgeLimit,
                            PageCount,
                            Price,
                            IsFree,
                            IsAvailableBySubscription,
                            CoverImageUrl
                        )
                    VALUES
                        (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);

                    SELECT CONVERT(INT, SCOPE_IDENTITY()) AS NewBookId;
                    """,
                    (
                        request.publisher_id,
                        request.title,
                        request.description,
                        request.publication_year,
                        request.age_limit,
                        request.page_count,
                        request.price,
                        request.is_free,
                        request.is_available_by_subscription,
                        request.cover_image_url,
                    ),
                )

                row = cursor.fetchone()

                if row is None:
                    raise RuntimeError("Не удалось получить BookId новой книги.")

                new_book_id = int(row[0])

                for author_id in request.author_ids:
                    cursor.execute(
                        """
                        INSERT INTO dbo.BookAuthor
                            (BookId, AuthorId)
                        VALUES
                            (?, ?);
                        """,
                        (new_book_id, author_id),
                    )

                for genre_id in request.genre_ids:
                    cursor.execute(
                        """
                        INSERT INTO dbo.BookGenre
                            (BookId, GenreId)
                        VALUES
                            (?, ?);
                        """,
                        (new_book_id, genre_id),
                    )

                cursor.execute(
                    """
                    INSERT INTO dbo.BookContent
                        (BookId, ContentText, ContentFormat)
                    VALUES
                        (?, ?, ?);
                    """,
                    (
                        new_book_id,
                        request.content_text,
                        request.content_format,
                    ),
                )

                connection.commit()

            except Exception:
                connection.rollback()
                raise

            cursor.execute(
                """
                SELECT *
                FROM dbo.vw_BookCatalog
                WHERE BookId = ?;
                """,
                (new_book_id,),
            )

            created_book = rows_to_dicts(cursor)

            return created_book[0] if created_book else {
                "message": "Книга создана",
                "BookId": new_book_id,
            }

    except Exception as error:
        raise_database_error(error)

# ============================================================
# ИНТЕРАКТИВНЫЕ АДМИНСКИЕ ОТЧЁТЫ
# Эти endpoints вызывают SQL-процедуры из database/12_admin_reports.sql
# ============================================================

@router.get("/reports/sales")
def get_admin_sales_report(
    admin_user_id: int,
    start_date: Optional[str] = Query(None, description="Дата начала периода в формате YYYY-MM-DD"),
    end_date: Optional[str] = Query(None, description="Дата окончания периода в формате YYYY-MM-DD"),
    group_by: str = Query("Book", description="Группировка: Book, User или Day"),
):
    require_admin(admin_user_id)

    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_AdminSalesReport
                @StartDate = ?,
                @EndDate = ?,
                @GroupBy = ?;
            """,
            (start_date, end_date, group_by),
        )

        return {
            "group_by": group_by,
            "rows": result_sets[0] if result_sets else [],
        }

    except Exception as error:
        raise_database_error(error)


@router.get("/reports/books")
def get_admin_books_report(
    admin_user_id: int,
    genre_name: Optional[str] = Query(None, description="Фильтр по жанру"),
    publisher_id: Optional[int] = Query(None, description="Фильтр по издательству"),
    min_rating: Optional[float] = Query(None, description="Минимальный средний рейтинг"),
    only_with_discount: Optional[bool] = Query(None, description="Показывать только книги с активной скидкой"),
):
    require_admin(admin_user_id)

    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_AdminBookReport
                @GenreName = ?,
                @PublisherId = ?,
                @MinRating = ?,
                @OnlyWithDiscount = ?;
            """,
            (
                genre_name,
                publisher_id,
                min_rating,
                None if only_with_discount is None else (1 if only_with_discount else 0),
            ),
        )

        return result_sets[0] if result_sets else []

    except Exception as error:
        raise_database_error(error)


@router.get("/reports/users")
def get_admin_users_report(
    admin_user_id: int,
    only_active: Optional[bool] = Query(None, description="Только активные пользователи"),
    min_purchase_amount: Optional[float] = Query(None, description="Минимальная сумма покупок"),
    registration_start: Optional[str] = Query(None, description="Дата регистрации от YYYY-MM-DD"),
    registration_end: Optional[str] = Query(None, description="Дата регистрации до YYYY-MM-DD"),
):
    require_admin(admin_user_id)

    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_AdminUserReport
                @OnlyActive = ?,
                @MinPurchaseAmount = ?,
                @RegistrationStart = ?,
                @RegistrationEnd = ?;
            """,
            (
                None if only_active is None else (1 if only_active else 0),
                min_purchase_amount,
                registration_start,
                registration_end,
            ),
        )

        return result_sets[0] if result_sets else []

    except Exception as error:
        raise_database_error(error)


@router.get("/reports/genres")
def get_admin_genres_report(
    admin_user_id: int,
    start_date: Optional[str] = Query(None, description="Дата начала периода продаж YYYY-MM-DD"),
    end_date: Optional[str] = Query(None, description="Дата окончания периода продаж YYYY-MM-DD"),
):
    require_admin(admin_user_id)

    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_AdminGenreReport
                @StartDate = ?,
                @EndDate = ?;
            """,
            (start_date, end_date),
        )

        return result_sets[0] if result_sets else []

    except Exception as error:
        raise_database_error(error)


@router.get("/reports/audit-log")
def get_admin_audit_log_report(
    admin_user_id: int,
    table_name: Optional[str] = Query(None, description="Название таблицы"),
    action_name: Optional[str] = Query(None, description="Действие: INSERT, UPDATE, DELETE"),
    start_date: Optional[str] = Query(None, description="Дата начала периода YYYY-MM-DD"),
    end_date: Optional[str] = Query(None, description="Дата окончания периода YYYY-MM-DD"),
):
    require_admin(admin_user_id)

    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_AdminAuditLogReport
                @TableName = ?,
                @ActionName = ?,
                @StartDate = ?,
                @EndDate = ?;
            """,
            (table_name, action_name, start_date, end_date),
        )

        return result_sets[0] if result_sets else []

    except Exception as error:
        raise_database_error(error)

