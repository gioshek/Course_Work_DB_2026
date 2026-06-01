USE [BookStreamDB];
GO

/*
    04_create_views.sql

    Представления подготавливают готовые выборки для сайта и отчётов.
    Избыточное отдельное представление баланса не создаётся: баланс берётся
    через dbo.fn_GetUserBalance и профиль пользователя.
*/

-- 1. КАТАЛОГ КНИГ //////////////////////////////

CREATE OR ALTER VIEW dbo.vw_BookCatalog
AS
    WITH AuthorList AS
    (
        SELECT
            BA.BookId,
            STRING_AGG(A.FirstName + N' ' + A.LastName, N', ') AS Authors
        FROM dbo.BookAuthor AS BA
            INNER JOIN dbo.Author AS A ON BA.AuthorId = A.AuthorId
        GROUP BY BA.BookId
    ),
    GenreList AS
    (
        SELECT
            BG.BookId,
            STRING_AGG(G.GenreName, N', ') AS Genres
        FROM dbo.BookGenre AS BG
            INNER JOIN dbo.Genre AS G ON BG.GenreId = G.GenreId
        GROUP BY BG.BookId
    )
    SELECT
        B.BookId,
        B.Title,
        B.Description,
        ISNULL(AL.Authors, N'Автор не указан') AS Authors,
        ISNULL(GL.Genres, N'Жанр не указан') AS Genres,
        P.PublisherId,
        P.PublisherName,
        B.PublicationYear,
        B.AgeLimit,
        B.PageCount,
        B.Price,
        dbo.fn_GetBookActiveDiscountPercent(B.BookId, CAST(GETDATE() AS DATE)) AS DiscountPercent,
        dbo.fn_GetBookFinalPrice(NULL, B.BookId, NULL, CAST(GETDATE() AS DATE)) AS FinalPrice,
        CASE
            WHEN dbo.fn_GetBookActiveDiscountPercent(B.BookId, CAST(GETDATE() AS DATE)) > 0
                THEN CAST(1 AS BIT)
            ELSE CAST(0 AS BIT)
        END AS HasActivePromotion,
        AP.PromotionName AS ActivePromotionName,
        AP.PromoCode AS ActivePromoCode,
        B.IsFree,
        B.IsPremium,
        B.IsAvailableBySubscription,
        B.CoverImageUrl,
        dbo.fn_GetBookAverageRating(B.BookId) AS AverageRating,
        dbo.fn_GetBookReviewCount(B.BookId) AS ReviewCount,
        B.CreatedAt
    FROM dbo.Book AS B
        INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId
        LEFT JOIN AuthorList AS AL ON B.BookId = AL.BookId
        LEFT JOIN GenreList AS GL ON B.BookId = GL.BookId
        OUTER APPLY
        (
            SELECT TOP 1
                PR.PromotionName,
                PR.PromoCode
            FROM dbo.Promotion AS PR
            WHERE PR.IsActive = 1
              AND PR.RequiresBirthday = 0
              AND CAST(GETDATE() AS DATE) BETWEEN PR.StartDate AND PR.EndDate
              AND
              (
                  PR.AppliesToAllBooks = 1
                  OR EXISTS
                     (
                        SELECT 1
                        FROM dbo.BookPromotion AS BP
                        WHERE BP.PromotionId = PR.PromotionId
                          AND BP.BookId = B.BookId
                     )
              )
            ORDER BY PR.DiscountPercent DESC, PR.PromotionId ASC
        ) AS AP;
GO

-- 2. АКТИВНЫЕ АКЦИИ НА КНИГИ //////////////////////////////

CREATE OR ALTER VIEW dbo.vw_ActiveBookPromotions
AS
    SELECT
        B.BookId,
        B.Title,
        P.PromotionId,
        P.PromotionName,
        P.PromoCode,
        P.DiscountPercent,
        P.StartDate,
        P.EndDate,
        P.AppliesToAllBooks,
        P.RequiresBirthday,
        P.IsSystem
    FROM dbo.Promotion AS P
        CROSS JOIN dbo.Book AS B
    WHERE P.IsActive = 1
      AND CAST(GETDATE() AS DATE) BETWEEN P.StartDate AND P.EndDate
      AND
      (
          P.AppliesToAllBooks = 1
          OR EXISTS
             (
                SELECT 1
                FROM dbo.BookPromotion AS BP
                WHERE BP.PromotionId = P.PromotionId
                  AND BP.BookId = B.BookId
             )
      );
GO

-- 3. ОТЗЫВЫ //////////////////////////////

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

-- 4. АКТИВНЫЕ ПОДПИСКИ //////////////////////////////

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
    WHERE US.IsActive = 1
      AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate;
GO

-- 5. БИБЛИОТЕКА ПОЛЬЗОВАТЕЛЯ //////////////////////////////
-- Доступ определяется функцией dbo.fn_UserHasAccessToBook.
-- Премиальные книги не открываются подпиской: их нужно купить.

CREATE OR ALTER VIEW dbo.vw_UserLibrary
AS
    SELECT
        U.UserId,
        U.Username,
        B.BookId,
        B.Title,
        B.Description,
        B.CoverImageUrl,
        P.PublisherName,
        B.PublicationYear,
        B.PageCount,
        B.Price,
        B.IsFree,
        B.IsPremium,
        B.IsAvailableBySubscription,
        CASE
            WHEN EXISTS
                 (
                    SELECT 1
                    FROM dbo.Purchase AS PR
                    WHERE PR.UserId = U.UserId
                      AND PR.BookId = B.BookId
                 )
                THEN N'Куплена'
            WHEN B.IsFree = 1
                THEN N'Бесплатная книга'
            WHEN B.IsPremium = 0
                 AND B.IsAvailableBySubscription = 1
                 AND dbo.fn_UserHasActiveSubscription(U.UserId, CAST(GETDATE() AS DATE)) = 1
                THEN N'По подписке'
            ELSE N'Нет доступа'
        END AS AccessType
    FROM dbo.UserAccount AS U
        CROSS JOIN dbo.Book AS B
        INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId
    WHERE dbo.fn_UserHasAccessToBook(U.UserId, B.BookId, CAST(GETDATE() AS DATE)) = 1;
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

CREATE OR ALTER VIEW dbo.vw_PopularBooks
AS
    SELECT
        B.BookId,
        B.Title,
        COUNT(DISTINCT P.PurchaseId) AS PurchaseCount,
        COUNT(DISTINCT F.UserId) AS FavoriteCount,
        COUNT(DISTINCT R.ReviewId) AS ReviewCount,
        dbo.fn_GetBookAverageRating(B.BookId) AS AverageRating
    FROM dbo.Book AS B
        LEFT JOIN dbo.Purchase AS P ON B.BookId = P.BookId
        LEFT JOIN dbo.FavoriteBook AS F ON B.BookId = F.BookId
        LEFT JOIN dbo.Review AS R ON B.BookId = R.BookId
    GROUP BY B.BookId, B.Title;
GO

-- 8. ПЛАТЕЖИ ПОЛЬЗОВАТЕЛЕЙ //////////////////////////////

CREATE OR ALTER VIEW dbo.vw_UserPayments
AS
    SELECT
        P.PaymentId,
        P.UserId,
        U.Username,
        dbo.fn_GetUserBalance(P.UserId) AS CurrentBalance,
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

SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.VIEWS
ORDER BY TABLE_NAME;
GO
