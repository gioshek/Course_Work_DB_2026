from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from app.database import call_db
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
    applies_to_all_books: bool = False


def raise_database_error(error: Exception):
    raise HTTPException(status_code=400, detail=str(error))


def require_admin(admin_user_id: int):
    result_sets = call_db("EXEC dbo.usp_GetAdminUser @AdminUserId = ?", (admin_user_id,))
    user = result_sets[0][0] if result_sets and result_sets[0] else None

    if user is None:
        raise HTTPException(status_code=403, detail="Доступ разрешён только администратору")

    return user


@router.get("/options")
def get_admin_options(admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_GetAdminOptions")
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
    try:
        result_sets = call_db("EXEC dbo.usp_CreatePublisher @PublisherName = ?", (request.publisher_name.strip(),))
        return result_sets[0][0] if result_sets and result_sets[0] else None
    except Exception as error:
        raise_database_error(error)


@router.post("/authors")
def create_author(request: AdminCreateAuthorRequest, admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db(
            "EXEC dbo.usp_CreateAuthor @FirstName = ?, @LastName = ?",
            (request.first_name.strip(), request.last_name.strip()),
        )
        return result_sets[0][0] if result_sets and result_sets[0] else None
    except Exception as error:
        raise_database_error(error)


@router.post("/genres")
def create_genre(request: AdminCreateGenreRequest, admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_CreateGenre @GenreName = ?", (request.genre_name.strip(),))
        return result_sets[0][0] if result_sets and result_sets[0] else None
    except Exception as error:
        raise_database_error(error)


@router.get("/audit-log")
def get_audit_log(admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_GetAuditLog")
        return result_sets[0] if result_sets else []
    except Exception as error:
        raise_database_error(error)


@router.get("/stats")
def get_admin_stats(admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_GetAdminStats")
        return {
            "stats": result_sets[0][0] if result_sets and result_sets[0] else {},
            "popular_books": result_sets[1] if len(result_sets) > 1 else [],
        }
    except Exception as error:
        raise_database_error(error)


@router.get("/promotions")
def get_promotions(admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_GetPromotions")
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
    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_CreatePromotion
                @PromotionName = ?,
                @PromoCode = ?,
                @DiscountPercent = ?,
                @StartDate = ?,
                @EndDate = ?,
                @IsActive = ?,
                @AppliesToAllBooks = ?
            """,
            (
                request.promotion_name.strip(),
                request.promo_code.strip().upper(),
                request.discount_percent,
                request.start_date,
                request.end_date,
                request.is_active,
                request.applies_to_all_books,
            ),
        )
        return result_sets[0][0] if result_sets and result_sets[0] else None
    except Exception as error:
        raise_database_error(error)


@router.post("/promotions/{promotion_id}/books/{book_id}")
def assign_promotion_to_book(promotion_id: int, book_id: int, admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_AssignPromotionToBook @PromotionId = ?, @BookId = ?", (promotion_id, book_id))
        return result_sets[0][0] if result_sets and result_sets[0] else None
    except Exception as error:
        raise_database_error(error)


@router.delete("/promotions/{promotion_id}/books/{book_id}")
def remove_promotion_from_book(promotion_id: int, book_id: int, admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_RemovePromotionFromBook @PromotionId = ?, @BookId = ?", (promotion_id, book_id))
        return result_sets[0][0] if result_sets and result_sets[0] else None
    except Exception as error:
        raise_database_error(error)


@router.delete("/promotions/{promotion_id}")
def delete_promotion(promotion_id: int, admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_DeletePromotion @PromotionId = ?", (promotion_id,))
        return result_sets[0][0] if result_sets and result_sets[0] else None
    except Exception as error:
        raise_database_error(error)


@router.get("/database-dashboard")
def get_database_dashboard(admin_user_id: int):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_GetDatabaseDashboard")
        return {
            "metrics": result_sets[0][0] if result_sets and result_sets[0] else {},
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
    try:
        result_sets = call_db(
            """
            EXEC dbo.usp_CreateBook
                @PublisherId = ?,
                @AuthorIds = ?,
                @GenreIds = ?,
                @Title = ?,
                @Description = ?,
                @PublicationYear = ?,
                @AgeLimit = ?,
                @PageCount = ?,
                @Price = ?,
                @IsFree = ?,
                @IsPremium = ?,
                @IsAvailableBySubscription = ?,
                @CoverImageUrl = ?,
                @ContentText = ?,
                @ContentFormat = ?
            """,
            (
                request.publisher_id,
                ",".join(str(item) for item in request.author_ids),
                ",".join(str(item) for item in request.genre_ids),
                request.title.strip(),
                request.description,
                request.publication_year,
                request.age_limit,
                request.page_count,
                request.price,
                request.is_free,
                request.is_premium,
                request.is_available_by_subscription,
                request.cover_image_url,
                request.content_text,
                request.content_format,
            ),
        )
        return result_sets[0][0] if result_sets and result_sets[0] else None
    except Exception as error:
        raise_database_error(error)


@router.get("/reports/sales")
def get_admin_sales_report(admin_user_id: int, start_date: Optional[str] = None, end_date: Optional[str] = None, group_by: str = "Book"):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_AdminSalesReport @StartDate = ?, @EndDate = ?, @GroupBy = ?", (start_date, end_date, group_by))
        return {"group_by": group_by, "rows": result_sets[0] if result_sets else []}
    except Exception as error:
        raise_database_error(error)


@router.get("/reports/books")
def get_admin_books_report(admin_user_id: int, genre_name: Optional[str] = None, publisher_id: Optional[int] = None, min_rating: Optional[float] = None, only_with_discount: Optional[bool] = None, only_premium: Optional[bool] = None):
    require_admin(admin_user_id)
    try:
        result_sets = call_db(
            "EXEC dbo.usp_AdminBookReport @GenreName = ?, @PublisherId = ?, @MinRating = ?, @OnlyWithDiscount = ?, @OnlyPremium = ?",
            (genre_name, publisher_id, min_rating, only_with_discount, only_premium),
        )
        return result_sets[0] if result_sets else []
    except Exception as error:
        raise_database_error(error)


@router.get("/reports/users")
def get_admin_users_report(admin_user_id: int, only_active: Optional[bool] = None, min_purchase_amount: Optional[float] = None, registration_start: Optional[str] = None, registration_end: Optional[str] = None):
    require_admin(admin_user_id)
    try:
        result_sets = call_db(
            "EXEC dbo.usp_AdminUserReport @OnlyActive = ?, @MinPurchaseAmount = ?, @RegistrationStart = ?, @RegistrationEnd = ?",
            (only_active, min_purchase_amount, registration_start, registration_end),
        )
        return result_sets[0] if result_sets else []
    except Exception as error:
        raise_database_error(error)


@router.get("/reports/genres")
def get_admin_genres_report(admin_user_id: int, start_date: Optional[str] = None, end_date: Optional[str] = None):
    require_admin(admin_user_id)
    try:
        result_sets = call_db("EXEC dbo.usp_AdminGenreReport @StartDate = ?, @EndDate = ?", (start_date, end_date))
        return result_sets[0] if result_sets else []
    except Exception as error:
        raise_database_error(error)


@router.get("/reports/audit-log")
def get_admin_audit_log_report(admin_user_id: int, table_name: Optional[str] = None, action_name: Optional[str] = Query(None, description="INSERT, UPDATE или DELETE"), start_date: Optional[str] = None, end_date: Optional[str] = None):
    require_admin(admin_user_id)
    try:
        result_sets = call_db(
            "EXEC dbo.usp_AdminAuditLogReport @TableName = ?, @ActionName = ?, @StartDate = ?, @EndDate = ?",
            (table_name, action_name, start_date, end_date),
        )
        return result_sets[0] if result_sets else []
    except Exception as error:
        raise_database_error(error)
