USE [BookStreamDB];
GO

/*
    07_functions.sql

    Пользовательские функции для BookStreamDB.

    Функции нужны для:
    - вычисления среднего рейтинга книги;
    - подсчёта отзывов;
    - проверки активной подписки;
    - проверки доступа пользователя к книге;
    - подсчёта купленных книг;
    - подсчёта избранных книг;
    - расчёта процента чтения;
    - получения книг по жанру;
    - получения доступных книг пользователя.
*/

-- 1. СРЕДНИЙ РЕЙТИНГ КНИГИ //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_GetBookAverageRating
(
    @BookId INT
)
RETURNS DECIMAL(4,2)
AS
BEGIN
    DECLARE @AverageRating DECIMAL(4,2);

    SELECT @AverageRating = AVG(CAST(Rating AS DECIMAL(4,2)))
    FROM dbo.Review
    WHERE BookId = @BookId;

    RETURN ISNULL(@AverageRating, 0);
END;
GO

-- 2. КОЛИЧЕСТВО ОТЗЫВОВ НА КНИГУ //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_GetBookReviewCount
(
    @BookId INT
)
RETURNS INT
AS
BEGIN
    DECLARE @ReviewCount INT;

    SELECT @ReviewCount = COUNT(*)
    FROM dbo.Review
    WHERE BookId = @BookId;

    RETURN ISNULL(@ReviewCount, 0);
END;
GO

-- 3. КОЛИЧЕСТВО КУПЛЕННЫХ КНИГ ПОЛЬЗОВАТЕЛЯ //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_GetUserPurchasedBookCount
(
    @UserId INT
)
RETURNS INT
AS
BEGIN
    DECLARE @PurchasedBookCount INT;

    SELECT @PurchasedBookCount = COUNT(*)
    FROM dbo.Purchase
    WHERE UserId = @UserId;

    RETURN ISNULL(@PurchasedBookCount, 0);
END;
GO

-- 4. КОЛИЧЕСТВО ИЗБРАННЫХ КНИГ ПОЛЬЗОВАТЕЛЯ //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_GetUserFavoriteBookCount
(
    @UserId INT
)
RETURNS INT
AS
BEGIN
    DECLARE @FavoriteBookCount INT;

    SELECT @FavoriteBookCount = COUNT(*)
    FROM dbo.FavoriteBook
    WHERE UserId = @UserId;

    RETURN ISNULL(@FavoriteBookCount, 0);
END;
GO

-- 5. ПРОВЕРКА АКТИВНОЙ ПОДПИСКИ ПОЛЬЗОВАТЕЛЯ //////////////////////////////
-- @CheckDate передаём параметром, чтобы функция была стабильной
-- и не зависела напрямую от GETDATE().

CREATE OR ALTER FUNCTION dbo.fn_UserHasActiveSubscription
(
    @UserId INT,
    @CheckDate DATE
)
RETURNS BIT
AS
BEGIN
    DECLARE @HasActiveSubscription BIT;

    SET @HasActiveSubscription = 0;

    IF EXISTS
    (
        SELECT 1
    FROM dbo.UserSubscription
    WHERE UserId = @UserId
        AND IsActive = 1
        AND @CheckDate BETWEEN StartDate AND EndDate
    )
    BEGIN
        SET @HasActiveSubscription = 1;
    END;

    RETURN @HasActiveSubscription;
END;
GO

-- 6. ПРОВЕРКА ДОСТУПА ПОЛЬЗОВАТЕЛЯ К КНИГЕ //////////////////////////////
-- Доступ есть, если:
-- 1) пользователь активен;
-- 2) книга бесплатная;
-- 3) книга куплена;
-- 4) книга доступна по подписке, и у пользователя есть активная подписка.

CREATE OR ALTER FUNCTION dbo.fn_UserHasAccessToBook
(
    @UserId INT,
    @BookId INT,
    @CheckDate DATE
)
RETURNS BIT
AS
BEGIN
    DECLARE @HasAccess BIT;

    SET @HasAccess = 0;

    IF EXISTS
    (
        SELECT 1
    FROM dbo.UserAccount AS U
            CROSS JOIN dbo.Book AS B
    WHERE U.UserId = @UserId
        AND U.IsActive = 1
        AND B.BookId = @BookId
        AND
        (
                B.IsFree = 1

        OR EXISTS
                (
                    SELECT 1
        FROM dbo.Purchase AS P
        WHERE P.UserId = @UserId
            AND P.BookId = @BookId
                )

        OR
        (
                    B.IsAvailableBySubscription = 1
        AND EXISTS
                    (
                        SELECT 1
        FROM dbo.UserSubscription AS US
        WHERE US.UserId = @UserId
            AND US.IsActive = 1
            AND @CheckDate BETWEEN US.StartDate AND US.EndDate
                    )
                )
          )
    )
    BEGIN
        SET @HasAccess = 1;
    END;

    RETURN @HasAccess;
END;
GO

-- 7. РАСЧЁТ ПРОЦЕНТА ПРОЧТЕНИЯ //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_CalculateReadingProgressPercent
(
    @CurrentPage INT,
    @PageCount INT
)
RETURNS DECIMAL(5,2)
AS
BEGIN
    DECLARE @ProgressPercent DECIMAL(5,2);

    IF @PageCount IS NULL OR @PageCount <= 0
    BEGIN
        RETURN 0;
    END;

    IF @CurrentPage IS NULL OR @CurrentPage <= 0
    BEGIN
        RETURN 0;
    END;

    IF @CurrentPage >= @PageCount
    BEGIN
        RETURN 100;
    END;

    SET @ProgressPercent = CAST
    (
        (CAST(@CurrentPage AS DECIMAL(10,2)) / CAST(@PageCount AS DECIMAL(10,2))) * 100
        AS DECIMAL(5,2)
    );

    RETURN @ProgressPercent;
END;
GO

-- 8. ПОЛУЧЕНИЕ КНИГ ПО ЖАНРУ //////////////////////////////
-- Табличная функция.
-- Версия без зависимости от представления vw_BookCatalog.

CREATE OR ALTER FUNCTION dbo.fn_GetBooksByGenre
(
    @GenreName NVARCHAR(100)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
    B.BookId,
    B.Title,
    ISNULL(AL.Authors, N'Автор не указан') AS Authors,
    ISNULL(GL.Genres, N'Жанр не указан') AS Genres,
    P.PublisherName,
    B.PublicationYear,
    B.Price,
    B.IsFree,
    B.IsAvailableBySubscription,
    ISNULL(RS.AverageRating, 0) AS AverageRating,
    ISNULL(RS.ReviewCount, 0) AS ReviewCount
FROM dbo.Book AS B
    INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId

        OUTER APPLY
        (
            SELECT
        STRING_AGG(A.FirstName + N' ' + A.LastName, N', ') AS Authors
    FROM dbo.BookAuthor AS BA
        INNER JOIN dbo.Author AS A ON BA.AuthorId = A.AuthorId
    WHERE BA.BookId = B.BookId
                ) AS AL

        OUTER APPLY
        (
            SELECT
        STRING_AGG(G.GenreName, N', ') AS Genres
    FROM dbo.BookGenre AS BG
        INNER JOIN dbo.Genre AS G ON BG.GenreId = G.GenreId
    WHERE BG.BookId = B.BookId
                ) AS GL

        OUTER APPLY
        (
            SELECT
        AVG(CAST(R.Rating AS DECIMAL(4,2))) AS AverageRating,
        COUNT(R.ReviewId) AS ReviewCount
    FROM dbo.Review AS R
    WHERE R.BookId = B.BookId
                ) AS RS
WHERE EXISTS
            (
                SELECT 1
FROM dbo.BookGenre AS BG2
    INNER JOIN dbo.Genre AS G2 ON BG2.GenreId = G2.GenreId
WHERE BG2.BookId = B.BookId
    AND G2.GenreName LIKE N'%' + @GenreName + N'%'
        )
);
GO

-- 9. ПОЛУЧЕНИЕ ДОСТУПНЫХ КНИГ ПОЛЬЗОВАТЕЛЯ //////////////////////////////
-- Табличная функция.
-- Версия без зависимости от представления vw_BookCatalog.

CREATE OR ALTER FUNCTION dbo.fn_GetAccessibleBooksForUser
(
    @UserId INT,
    @CheckDate DATE
)
RETURNS TABLE
AS
RETURN
(
    SELECT
    B.BookId,
    B.Title,
    ISNULL(AL.Authors, N'Автор не указан') AS Authors,
    ISNULL(GL.Genres, N'Жанр не указан') AS Genres,
    P.PublisherName,
    B.PublicationYear,
    B.Price,
    B.IsFree,
    B.IsAvailableBySubscription,
    ISNULL(RS.AverageRating, 0) AS AverageRating,
    ISNULL(RS.ReviewCount, 0) AS ReviewCount,

    CASE
            WHEN B.IsFree = 1
                THEN N'Бесплатная книга'

            WHEN EXISTS
            (
                SELECT 1
    FROM dbo.Purchase AS PR
    WHERE PR.UserId = @UserId
        AND PR.BookId = B.BookId
            )
                THEN N'Покупка'

            WHEN B.IsAvailableBySubscription = 1
        AND dbo.fn_UserHasActiveSubscription(@UserId, @CheckDate) = 1
                THEN N'Подписка'

            ELSE N'Нет доступа'
        END AS AccessType
FROM dbo.Book AS B
    INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId

        OUTER APPLY
        (
            SELECT
        STRING_AGG(A.FirstName + N' ' + A.LastName, N', ') AS Authors
    FROM dbo.BookAuthor AS BA
        INNER JOIN dbo.Author AS A ON BA.AuthorId = A.AuthorId
    WHERE BA.BookId = B.BookId
        ) AS AL

        OUTER APPLY
        (
            SELECT
        STRING_AGG(G.GenreName, N', ') AS Genres
    FROM dbo.BookGenre AS BG
        INNER JOIN dbo.Genre AS G ON BG.GenreId = G.GenreId
    WHERE BG.BookId = B.BookId
        ) AS GL

        OUTER APPLY
        (
            SELECT
        AVG(CAST(R.Rating AS DECIMAL(4,2))) AS AverageRating,
        COUNT(R.ReviewId) AS ReviewCount
    FROM dbo.Review AS R
    WHERE R.BookId = B.BookId
        ) AS RS
WHERE dbo.fn_UserHasAccessToBook(@UserId, B.BookId, @CheckDate) = 1
);
GO

-- 10. ПОЛУЧЕНИЕ ТЕКУЩЕГО БАЛАНСА ПОЛЬЗОВАТЕЛЯ //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_GetUserBalance
(
    @UserId INT
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @Balance DECIMAL(10,2);

    SELECT @Balance = Balance
    FROM dbo.UserAccount
    WHERE UserId = @UserId;

    RETURN ISNULL(@Balance, 0);
END;
GO

-- 11. ФУНКЦИИ ДЛЯ АКЦИЙ И ИТОГОВОЙ ЦЕНЫ //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_GetBookActiveDiscountPercent
(
    @BookId INT,
    @CheckDate DATE
)
RETURNS DECIMAL(5,2)
AS
BEGIN
    DECLARE @DiscountPercent DECIMAL(5,2);

    SELECT
        @DiscountPercent = MAX(P.DiscountPercent)
    FROM dbo.BookPromotion AS BP
        INNER JOIN dbo.Promotion AS P ON BP.PromotionId = P.PromotionId
    WHERE BP.BookId = @BookId
        AND P.IsActive = 1
        AND @CheckDate BETWEEN P.StartDate AND P.EndDate;

    RETURN ISNULL(@DiscountPercent, 0);
END;
GO

CREATE OR ALTER FUNCTION dbo.fn_GetBookFinalPrice
(
    @BookId INT,
    @CheckDate DATE
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @BasePrice DECIMAL(10,2);
    DECLARE @IsFree BIT;
    DECLARE @DiscountPercent DECIMAL(5,2);
    DECLARE @FinalPrice DECIMAL(10,2);

    SELECT
        @BasePrice = Price,
        @IsFree = IsFree
    FROM dbo.Book
    WHERE BookId = @BookId;

    IF @BasePrice IS NULL
        RETURN NULL;

    IF @IsFree = 1
        RETURN 0;

    SET @DiscountPercent = dbo.fn_GetBookActiveDiscountPercent(@BookId, @CheckDate);

    SET @FinalPrice = ROUND(@BasePrice * (100 - @DiscountPercent) / 100, 2);

    IF @FinalPrice < 0
        SET @FinalPrice = 0;

    RETURN @FinalPrice;
END;
GO

-- ПРОВЕРКА СОЗДАННЫХ ФУНКЦИЙ //////////////////////////////

SELECT
    ROUTINE_SCHEMA,
    ROUTINE_NAME,
    ROUTINE_TYPE
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_TYPE = 'FUNCTION'
ORDER BY ROUTINE_NAME;
GO

-- ТЕСТЫ СКАЛЯРНЫХ ФУНКЦИЙ //////////////////////////////

SELECT
    dbo.fn_GetBookAverageRating(1) AS AverageRatingForBook1,
    dbo.fn_GetBookReviewCount(1) AS ReviewCountForBook1;
GO

SELECT
    dbo.fn_GetUserPurchasedBookCount(2) AS PurchasedBooksForUser2,
    dbo.fn_GetUserFavoriteBookCount(2) AS FavoriteBooksForUser2,
    dbo.fn_GetUserBalance(2) AS BalanceForUser2;
GO

SELECT
    dbo.fn_UserHasActiveSubscription(2, '2026-05-25') AS User2HasActiveSubscription;
GO

SELECT
    dbo.fn_UserHasAccessToBook(2, 1, '2026-05-25') AS User2AccessToBook1,
    dbo.fn_UserHasAccessToBook(2, 4, '2026-05-25') AS User2AccessToFreeBook4,
    dbo.fn_UserHasAccessToBook(2, 5, '2026-05-25') AS User2AccessToSubscriptionBook5,
    dbo.fn_UserHasAccessToBook(2, 6, '2026-05-25') AS User2AccessToBook6;
GO

SELECT
    dbo.fn_CalculateReadingProgressPercent(125, 672) AS ProgressPercent1,
    dbo.fn_CalculateReadingProgressPercent(220, 220) AS ProgressPercent2,
    dbo.fn_CalculateReadingProgressPercent(0, 220) AS ProgressPercent3;
GO

-- ТЕСТЫ ТАБЛИЧНЫХ ФУНКЦИЙ //////////////////////////////

SELECT *
FROM dbo.fn_GetBooksByGenre(N'Фантастика');
GO

SELECT *
FROM dbo.fn_GetAccessibleBooksForUser(2, '2026-05-25');
GO
