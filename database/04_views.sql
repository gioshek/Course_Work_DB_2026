USE [BookStreamDB];
GO

/*
    04_views.sql

    Представления для базы данных BookStreamDB.
    Они нужны, чтобы удобно получать данные для сайта:
    - каталог книг;
    - отзывы;
    - библиотеку пользователя;
    - активные подписки;
    - прогресс чтения;
    - популярные книги.
*/

-- 1. КАТАЛОГ КНИГ //////////////////////////////
-- Представление собирает книгу, издательство, авторов, жанры,
-- средний рейтинг и количество отзывов.

CREATE OR ALTER VIEW dbo.vw_BookCatalog
AS
    WITH
        AuthorList
        AS
        (
            SELECT
                BA.BookId,
                STRING_AGG(A.FirstName + N' ' + A.LastName, N', ') AS Authors
            FROM dbo.BookAuthor AS BA
                INNER JOIN dbo.Author AS A ON BA.AuthorId = A.AuthorId
            GROUP BY BA.BookId
        ),
        GenreList
        AS
        (
            SELECT
                BG.BookId,
                STRING_AGG(G.GenreName, N', ') AS Genres
            FROM dbo.BookGenre AS BG
                INNER JOIN dbo.Genre AS G ON BG.GenreId = G.GenreId
            GROUP BY BG.BookId
        ),
        ReviewStats
        AS
        (
            SELECT
                R.BookId,
                AVG(CAST(R.Rating AS DECIMAL(4,2))) AS AverageRating,
                COUNT(R.ReviewId) AS ReviewCount
            FROM dbo.Review AS R
            GROUP BY R.BookId
        )
    SELECT
        B.BookId,
        B.Title,
        B.Description,
        ISNULL(AL.Authors, N'Автор не указан') AS Authors,
        ISNULL(GL.Genres, N'Жанр не указан') AS Genres,
        P.PublisherName,
        B.PublicationYear,
        B.AgeLimit,
        B.PageCount,
        B.Price,
        CAST(ISNULL(PR.DiscountPercent, 0) AS DECIMAL(5,2)) AS DiscountPercent,
        CAST
        (
            CASE
                WHEN B.IsFree = 1 THEN 0
                ELSE ROUND(B.Price * (100 - ISNULL(PR.DiscountPercent, 0)) / 100, 2)
            END
            AS DECIMAL(10,2)
        ) AS FinalPrice,
        CASE
            WHEN PR.PromotionId IS NULL THEN CAST(0 AS BIT)
            ELSE CAST(1 AS BIT)
        END AS HasActivePromotion,
        PR.PromotionName AS ActivePromotionName,
        PR.PromoCode AS ActivePromoCode,
        B.IsFree,
        B.IsAvailableBySubscription,
        B.CoverImageUrl,
        ISNULL(RS.AverageRating, 0) AS AverageRating,
        ISNULL(RS.ReviewCount, 0) AS ReviewCount,
        B.CreatedAt
    FROM dbo.Book AS B
        INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId
        LEFT JOIN AuthorList AS AL ON B.BookId = AL.BookId
        LEFT JOIN GenreList AS GL ON B.BookId = GL.BookId
        LEFT JOIN ReviewStats AS RS ON B.BookId = RS.BookId

        OUTER APPLY
        (
            SELECT TOP 1
            P2.PromotionId,
            P2.PromotionName,
            P2.PromoCode,
            P2.DiscountPercent
        FROM dbo.BookPromotion AS BP2
            INNER JOIN dbo.Promotion AS P2 ON BP2.PromotionId = P2.PromotionId
        WHERE BP2.BookId = B.BookId
            AND P2.IsActive = 1
            AND CAST(GETDATE() AS DATE) BETWEEN P2.StartDate AND P2.EndDate
        ORDER BY
                P2.DiscountPercent DESC,
                P2.EndDate ASC,
                P2.PromotionId ASC
        ) AS PR;
GO

-- 2. АКТИВНЫЕ АКЦИИ НА КНИГИ //////////////////////////////

CREATE OR ALTER VIEW dbo.vw_ActiveBookPromotions
AS
    SELECT
        BP.BookId,
        B.Title,
        P.PromotionId,
        P.PromotionName,
        P.PromoCode,
        P.DiscountPercent,
        P.StartDate,
        P.EndDate,
        P.IsActive
    FROM dbo.BookPromotion AS BP
        INNER JOIN dbo.Book AS B ON BP.BookId = B.BookId
        INNER JOIN dbo.Promotion AS P ON BP.PromotionId = P.PromotionId
    WHERE P.IsActive = 1
        AND CAST(GETDATE() AS DATE) BETWEEN P.StartDate AND P.EndDate;
GO

-- 3. ОТЗЫВЫ НА КНИГИ //////////////////////////////
-- Представление показывает отзывы вместе с пользователями и книгами.

CREATE OR ALTER VIEW dbo.vw_BookReviews
AS
    SELECT
        R.ReviewId,
        R.BookId,
        B.Title AS BookTitle,
        R.UserId,
        U.Username,
        R.Rating,
        R.ReviewText,
        R.CreatedAt
    FROM dbo.Review AS R
        INNER JOIN dbo.Book AS B ON R.BookId = B.BookId
        INNER JOIN dbo.UserAccount AS U ON R.UserId = U.UserId;
GO

-- 4. АКТИВНЫЕ ПОДПИСКИ ПОЛЬЗОВАТЕЛЕЙ //////////////////////////////

CREATE OR ALTER VIEW dbo.vw_ActiveUserSubscriptions
AS
    SELECT
        US.SubscriptionId,
        US.UserId,
        U.Username,
        U.Email,
        SP.PlanId,
        SP.PlanName,
        SP.Price,
        SP.DurationDays,
        US.StartDate,
        US.EndDate,
        US.IsActive,
        US.PaymentId
    FROM dbo.UserSubscription AS US
        INNER JOIN dbo.UserAccount AS U ON US.UserId = U.UserId
        INNER JOIN dbo.SubscriptionPlan AS SP ON US.PlanId = SP.PlanId
    WHERE 
        US.IsActive = 1
        AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate;
GO

-- 5. БИБЛИОТЕКА ПОЛЬЗОВАТЕЛЯ //////////////////////////////
-- Представление показывает, какие книги доступны пользователю.
-- Доступ есть, если:
-- 1) книга бесплатная;
-- 2) пользователь купил книгу;
-- 3) книга доступна по подписке и у пользователя есть активная подписка.

CREATE OR ALTER VIEW dbo.vw_UserLibrary
AS
    SELECT
        U.UserId,
        U.Username,
        B.BookId,
        B.Title,
        P.PublisherName,
        B.Price,
        B.IsFree,
        B.IsAvailableBySubscription,

        CASE
            WHEN EXISTS
            (
                SELECT 1
        FROM dbo.Purchase AS PR
        WHERE PR.UserId = U.UserId
            AND PR.BookId = B.BookId
            )
                THEN N'Покупка'

            WHEN B.IsFree = 1
                THEN N'Бесплатная книга'

            WHEN B.IsAvailableBySubscription = 1
            AND EXISTS
                 (
                    SELECT 1
            FROM dbo.UserSubscription AS US
            WHERE US.UserId = U.UserId
                AND US.IsActive = 1
                AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate
                 )
                THEN N'Подписка'

            ELSE N'Нет доступа'
        END AS AccessType

    FROM dbo.UserAccount AS U
        CROSS JOIN dbo.Book AS B
        INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId
    WHERE
        B.IsFree = 1
        OR EXISTS
        (
            SELECT 1
        FROM dbo.Purchase AS PR
        WHERE PR.UserId = U.UserId
            AND PR.BookId = B.BookId
        )
        OR
        (
            B.IsAvailableBySubscription = 1
        AND EXISTS
            (
                SELECT 1
        FROM dbo.UserSubscription AS US
        WHERE US.UserId = U.UserId
            AND US.IsActive = 1
            AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate
            )
        );
GO

-- 6. ПРОГРЕСС ЧТЕНИЯ //////////////////////////////

CREATE OR ALTER VIEW dbo.vw_UserReadingProgress
AS
    SELECT
        RP.ProgressId,
        RP.UserId,
        U.Username,
        RP.BookId,
        B.Title,
        RP.CurrentPage,
        B.PageCount,
        RP.ProgressPercent,
        RP.LastReadAt
    FROM dbo.ReadingProgress AS RP
        INNER JOIN dbo.UserAccount AS U ON RP.UserId = U.UserId
        INNER JOIN dbo.Book AS B ON RP.BookId = B.BookId;
GO

-- 7. ПОПУЛЯРНЫЕ КНИГИ //////////////////////////////
-- Считает покупки, избранное, отзывы и средний рейтинг.

CREATE OR ALTER VIEW dbo.vw_PopularBooks
AS
    SELECT
        B.BookId,
        B.Title,
        COUNT(DISTINCT P.PurchaseId) AS PurchaseCount,
        COUNT(DISTINCT F.UserId) AS FavoriteCount,
        COUNT(DISTINCT R.ReviewId) AS ReviewCount,
        ISNULL(AVG(CAST(R.Rating AS DECIMAL(4,2))), 0) AS AverageRating
    FROM dbo.Book AS B
        LEFT JOIN dbo.Purchase AS P ON B.BookId = P.BookId
        LEFT JOIN dbo.FavoriteBook AS F ON B.BookId = F.BookId
        LEFT JOIN dbo.Review AS R ON B.BookId = R.BookId
    GROUP BY
        B.BookId,
        B.Title;
GO

-- 8. ПЛАТЕЖИ ПОЛЬЗОВАТЕЛЕЙ //////////////////////////////

CREATE OR ALTER VIEW dbo.vw_UserPayments
AS
    SELECT
        P.PaymentId,
        P.UserId,
        U.Username,
        U.Balance AS CurrentBalance,
        P.Amount,
        P.PaymentDate,
        P.PaymentMethod,
        P.PaymentStatus,
        P.TransactionNumber,
        CASE
            WHEN EXISTS (SELECT 1 FROM dbo.Purchase AS PR WHERE PR.PaymentId = P.PaymentId)
                THEN N'Покупка книги'
            WHEN EXISTS (SELECT 1 FROM dbo.UserSubscription AS US WHERE US.PaymentId = P.PaymentId)
                THEN N'Подписка'
            ELSE N'Пополнение баланса'
        END AS PaymentPurpose
    FROM dbo.Payment AS P
        INNER JOIN dbo.UserAccount AS U ON P.UserId = U.UserId;
GO

-- 9. БАЛАНС ПОЛЬЗОВАТЕЛЕЙ //////////////////////////////

CREATE OR ALTER VIEW dbo.vw_UserBalance
AS
    SELECT
        U.UserId,
        U.Username,
        U.Email,
        U.Balance,
        ISNULL(SUM(CASE WHEN P.PaymentMethod <> N'Balance' THEN P.Amount ELSE 0 END), 0) AS TotalTopUps,
        ISNULL(SUM(CASE WHEN P.PaymentMethod = N'Balance' THEN P.Amount ELSE 0 END), 0) AS TotalSpent
    FROM dbo.UserAccount AS U
        LEFT JOIN dbo.Payment AS P ON U.UserId = P.UserId
    GROUP BY
        U.UserId,
        U.Username,
        U.Email,
        U.Balance;
GO

-- ПРОВЕРКА СОЗДАННЫХ ПРЕДСТАВЛЕНИЙ //////////////////////////////

SELECT
    TABLE_SCHEMA,
    TABLE_NAME
FROM INFORMATION_SCHEMA.VIEWS
ORDER BY TABLE_NAME;
GO

-- ТЕСТЫ ПРЕДСТАВЛЕНИЙ //////////////////////////////

SELECT *
FROM dbo.vw_BookCatalog;
GO

SELECT *
FROM dbo.vw_UserLibrary
WHERE UserId = 2;
GO

SELECT *
FROM dbo.vw_BookReviews;
GO

SELECT *
FROM dbo.vw_ActiveUserSubscriptions;
GO

SELECT *
FROM dbo.vw_UserReadingProgress;
GO

SELECT *
FROM dbo.vw_PopularBooks;
GO

SELECT *
FROM dbo.vw_UserPayments
WHERE UserId = 2
ORDER BY PaymentDate DESC;
GO

SELECT *
FROM dbo.vw_UserBalance
ORDER BY UserId;
GO
