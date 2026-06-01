import re
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from rapidfuzz import fuzz

from app.database import call_db
from app.schemas import AddReviewRequest, PurchaseBookRequest, UpdateReadingProgressRequest


router = APIRouter(prefix="/books", tags=["Books"])


# ============================================================
# ОБРАБОТКА ОШИБОК И ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ БД
# ============================================================

def raise_database_error(error: Exception):
    raise HTTPException(status_code=400, detail=str(error))


# ============================================================
# НЕЧЁТКИЙ ПОИСК ПО КАТАЛОГУ КНИГ
# ============================================================

RUSSIAN_STOPWORDS = {
    "и", "в", "во", "на", "над", "под", "по", "о", "об", "обо",
    "а", "но", "или", "для", "с", "со", "к", "ко", "от", "до",
    "из", "за", "у", "же", "ли", "бы", "то", "это", "как"
}


def normalize_search_text(value: str | None) -> str:
    """
    Приводит строку к удобному виду для сравнения:
    - нижний регистр;
    - ё -> е;
    - удаление знаков препинания;
    - сжатие лишних пробелов.
    """
    if value is None:
        return ""

    text = str(value).lower()
    text = text.replace("ё", "е")

    text = re.sub(r"[^a-zа-я0-9\s]+", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"\s+", " ", text).strip()

    return text


def tokenize_search_text(value: str | None) -> list[str]:
    """
    Делит строку на значимые слова.
    Стоп-слова вроде 'и', 'в', 'на' убираются.
    """
    normalized = normalize_search_text(value)

    if not normalized:
        return []

    return [
        token
        for token in normalized.split()
        if token and token not in RUSSIAN_STOPWORDS
    ]


def book_field(book: dict, field_name: str) -> str:
    value = book.get(field_name)

    if value is None:
        return ""

    return normalize_search_text(value)


def get_token_threshold(token: str) -> int:
    """
    Порог похожести для отдельного слова.
    Короткие слова проверяем строже, длинные допускают небольшие опечатки.
    """
    token_length = len(token)

    if token_length <= 2:
        return 100

    if token_length <= 4:
        return 72

    if token_length <= 7:
        return 68

    return 70


def best_token_score(query_token: str, target_tokens: list[str]) -> float:
    """
    Находит лучший процент похожести одного слова запроса
    среди слов конкретного поля книги.
    """
    if not query_token or not target_tokens:
        return 0.0

    scores = []

    for target_token in target_tokens:
        if query_token == target_token:
            scores.append(100.0)

        elif query_token in target_token or target_token in query_token:
            # Например:
            # мар -> маргарита
            # наказан -> наказание
            scores.append(92.0)

        else:
            scores.append(float(fuzz.ratio(query_token, target_token)))

    return max(scores) if scores else 0.0


def all_query_tokens_are_covered(query_tokens: list[str], target_tokens: list[str]) -> bool:
    """
    Для запроса из нескольких слов требуем, чтобы каждое важное слово
    было найдено в книге с достаточной похожестью.
    Это убирает лишние результаты.
    """
    if not query_tokens:
        return True

    if not target_tokens:
        return False

    for query_token in query_tokens:
        score = best_token_score(query_token, target_tokens)

        if score < get_token_threshold(query_token):
            return False

    return True


def average_token_score(query_tokens: list[str], target_tokens: list[str]) -> float:
    if not query_tokens or not target_tokens:
        return 0.0

    scores = [
        best_token_score(query_token, target_tokens)
        for query_token in query_tokens
    ]

    return sum(scores) / len(scores)


def calculate_book_search_score(book: dict, query: str | None) -> float:
    """
    Возвращает оценку похожести книги на поисковый запрос.
    0 означает, что книгу показывать не надо.
    """
    normalized_query = normalize_search_text(query)
    query_tokens = tokenize_search_text(query)

    if not normalized_query or not query_tokens:
        return 100.0

    title = book_field(book, "Title")
    authors = book_field(book, "Authors")
    genres = book_field(book, "Genres")
    description = book_field(book, "Description")
    publisher = book_field(book, "PublisherName")

    title_tokens = tokenize_search_text(title)
    authors_tokens = tokenize_search_text(authors)
    genres_tokens = tokenize_search_text(genres)
    publisher_tokens = tokenize_search_text(publisher)
    description_tokens = tokenize_search_text(description)

    strong_tokens = title_tokens + authors_tokens + genres_tokens + publisher_tokens
    full_tokens = strong_tokens + description_tokens

    # ------------------------------------------------------------
    # 1. Точные и почти точные фразовые совпадения
    # ------------------------------------------------------------

    if normalized_query == title:
        return 100.0

    if normalized_query in title:
        return 98.0

    if normalized_query in authors:
        return 94.0

    if normalized_query in genres:
        return 90.0

    if normalized_query in publisher:
        return 86.0

    # ------------------------------------------------------------
    # 2. Запрос из нескольких слов
    # ------------------------------------------------------------
    # Например:
    # "мастер маргарита"
    # "трих тел"
    # "приступление наказан"
    #
    # Здесь нельзя просто брать общий процент похожести всей строки,
    # потому что тогда начинают вылезать лишние книги.
    # Требуем, чтобы каждое важное слово запроса было покрыто.
    # ------------------------------------------------------------

    if len(query_tokens) >= 2:
        if all_query_tokens_are_covered(query_tokens, strong_tokens):
            title_score = average_token_score(query_tokens, title_tokens)
            authors_score = average_token_score(query_tokens, authors_tokens)
            genres_score = average_token_score(query_tokens, genres_tokens)
            publisher_score = average_token_score(query_tokens, publisher_tokens)

            phrase_score = max(
                fuzz.WRatio(normalized_query, title),
                fuzz.token_set_ratio(normalized_query, title),
                fuzz.WRatio(normalized_query, authors),
                fuzz.token_set_ratio(normalized_query, authors),
                fuzz.WRatio(normalized_query, genres),
                fuzz.token_set_ratio(normalized_query, genres),
                fuzz.WRatio(normalized_query, publisher),
                fuzz.token_set_ratio(normalized_query, publisher),
            )

            return min(
                100.0,
                max(
                    title_score * 1.00,
                    authors_score * 0.95,
                    genres_score * 0.90,
                    publisher_score * 0.80,
                    phrase_score * 0.90,
                ),
            )

        # Описание используем только как слабый дополнительный источник.
        # Иначе по общим словам будет слишком много мусора.
        if all_query_tokens_are_covered(query_tokens, full_tokens):
            description_phrase_score = max(
                fuzz.WRatio(normalized_query, description),
                fuzz.token_set_ratio(normalized_query, description),
            )

            if description_phrase_score >= 82:
                return min(80.0, description_phrase_score * 0.75)

        return 0.0

    # ------------------------------------------------------------
    # 3. Запрос из одного слова
    # ------------------------------------------------------------
    # Например:
    # "достаевский"
    # "винланд"
    # "фантастика"
    # ------------------------------------------------------------

    query_token = query_tokens[0]

    title_score = best_token_score(query_token, title_tokens)
    authors_score = best_token_score(query_token, authors_tokens)
    genres_score = best_token_score(query_token, genres_tokens)
    publisher_score = best_token_score(query_token, publisher_tokens)
    description_score = best_token_score(query_token, description_tokens)

    threshold = get_token_threshold(query_token)

    best_score = max(
        title_score * 1.00,
        authors_score * 0.97,
        genres_score * 0.93,
        publisher_score * 0.85,
        description_score * 0.65,
    )

    if best_score < threshold:
        return 0.0

    return min(100.0, best_score)


def apply_fuzzy_book_search(books: list[dict], query: str | None) -> list[dict]:
    normalized_query = normalize_search_text(query)

    if not normalized_query:
        return books

    filtered_books = []

    for book in books:
        score = calculate_book_search_score(book, normalized_query)

        if score > 0:
            book_with_score = dict(book)
            book_with_score["SearchScore"] = round(float(score), 2)
            filtered_books.append(book_with_score)

    filtered_books.sort(
        key=lambda item: (
            item.get("SearchScore", 0),
            item.get("AverageRating") or 0,
            item.get("ReviewCount") or 0,
        ),
        reverse=True,
    )

    return filtered_books


def apply_fuzzy_genre_filter(books: list[dict], genre_query: str | None) -> list[dict]:
    normalized_genre = normalize_search_text(genre_query)
    genre_tokens = tokenize_search_text(genre_query)

    if not normalized_genre or not genre_tokens:
        return books

    filtered_books = []

    for book in books:
        genres = book_field(book, "Genres")
        genre_field_tokens = tokenize_search_text(genres)

        if not genres or not genre_field_tokens:
            continue

        if normalized_genre in genres:
            score = 100.0

        elif all_query_tokens_are_covered(genre_tokens, genre_field_tokens):
            score = average_token_score(genre_tokens, genre_field_tokens)

        else:
            score = 0.0

        if score > 0:
            book_with_score = dict(book)
            book_with_score["GenreSearchScore"] = round(float(score), 2)
            filtered_books.append(book_with_score)

    filtered_books.sort(
        key=lambda item: (
            item.get("GenreSearchScore", 0),
            item.get("AverageRating") or 0,
            item.get("ReviewCount") or 0,
        ),
        reverse=True,
    )

    return filtered_books


# ============================================================
# КАТАЛОГ КНИГ
# ============================================================

@router.get("/")
def get_book_catalog(
    search: Optional[str] = Query(None, description="Нечёткий поиск по названию, автору, жанру, издательству или описанию"),
    genre: Optional[str] = Query(None, description="Фильтр по жанру"),
    only_free: bool = Query(False, description="Показать только бесплатные книги"),
    available_by_subscription: Optional[bool] = Query(None, description="Доступность по подписке"),
    only_premium: bool = Query(False, description="Показать только премиальные книги"),
    search_text: Optional[str] = Query(None, include_in_schema=False),
    genre_name: Optional[str] = Query(None, include_in_schema=False),
):
    try:
        effective_search = search_text if search_text is not None else search
        effective_genre = genre_name if genre_name is not None else genre

        result_sets = call_db(
            """
            EXEC dbo.usp_GetBookCatalog
                @SearchText = ?,
                @GenreName = ?,
                @OnlyFree = ?,
                @AvailableBySubscription = ?,
                @OnlyPremium = ?
            """,
            (
                None,
                None,
                1 if only_free else None,
                available_by_subscription,
                1 if only_premium else None,
            ),
        )

        books = result_sets[0] if result_sets else []
        books = apply_fuzzy_genre_filter(books, effective_genre)
        books = apply_fuzzy_book_search(books, effective_search)
        return books
    except Exception as error:
        raise_database_error(error)


@router.get("/{book_id}")
def get_book_by_id(book_id: int):
    try:
        result_sets = call_db("EXEC dbo.usp_GetBookById @BookId = ?", (book_id,))
        book = result_sets[0][0] if result_sets and result_sets[0] else None
        reviews = result_sets[1] if len(result_sets) > 1 else []
        return {"book": book, "reviews": reviews}
    except Exception as error:
        raise_database_error(error)


@router.get("/{book_id}/price-preview")
def get_book_price_preview(book_id: int, user_id: int = Query(...), promo_code: Optional[str] = Query(None)):
    try:
        result_sets = call_db(
            "EXEC dbo.usp_GetBookPricePreview @UserId = ?, @BookId = ?, @PromoCode = ?",
            (user_id, book_id, promo_code),
        )
        return result_sets[0][0] if result_sets and result_sets[0] else None
    except Exception as error:
        raise_database_error(error)


@router.get("/{book_id}/content")
def get_book_content(book_id: int, user_id: int = Query(...)):
    try:
        result_sets = call_db("EXEC dbo.usp_GetBookContentForUser @UserId = ?, @BookId = ?", (user_id, book_id))
        return result_sets[0][0] if result_sets and result_sets[0] else None
    except Exception as error:
        raise_database_error(error)


@router.post("/{book_id}/purchase")
def buy_book(book_id: int, request: PurchaseBookRequest):
    try:
        result_sets = call_db(
            "EXEC dbo.usp_BuyBook @UserId = ?, @BookId = ?, @PaymentMethod = ?, @PromoCode = ?",
            (request.user_id, book_id, request.payment_method, request.promo_code),
        )
        purchase = result_sets[0][0] if result_sets and result_sets[0] else None
        return {
            "message": "Книга успешно куплена",
            "purchase": purchase,
            "Balance": purchase.get("Balance") if purchase else None,
        }
    except Exception as error:
        raise_database_error(error)


@router.post("/{book_id}/reviews")
def add_review(book_id: int, request: AddReviewRequest):
    try:
        result_sets = call_db(
            "EXEC dbo.usp_AddReview @UserId = ?, @BookId = ?, @Rating = ?, @ReviewText = ?",
            (request.user_id, book_id, request.rating, request.review_text),
        )
        return result_sets[0][0] if result_sets and result_sets[0] else {"message": "Отзыв сохранён"}
    except Exception as error:
        raise_database_error(error)


@router.put("/{book_id}/progress")
def update_reading_progress(book_id: int, request: UpdateReadingProgressRequest):
    try:
        result_sets = call_db(
            "EXEC dbo.usp_UpdateReadingProgress @UserId = ?, @BookId = ?, @CurrentPage = ?",
            (request.user_id, book_id, request.current_page),
        )
        return result_sets[0][0] if result_sets and result_sets[0] else {"message": "Прогресс чтения обновлён"}
    except Exception as error:
        raise_database_error(error)
