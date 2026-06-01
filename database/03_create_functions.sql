USE [BookStreamDB];
GO

/*
    03_create_functions.sql

    Переиспользуемые вычисления BookStreamDB.
    Функции вызываются представлениями, процедурами и триггерами.
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

-- 2. КОЛИЧЕСТВО ОТЗЫВОВ //////////////////////////////

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

-- 3. КОЛИЧЕСТВО КУПЛЕННЫХ КНИГ //////////////////////////////

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

-- 4. КОЛИЧЕСТВО ИЗБРАННЫХ КНИГ //////////////////////////////

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

-- 5. ТЕКУЩИЙ БАЛАНС //////////////////////////////

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

-- 6. АКТИВНАЯ ПОДПИСКА //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_UserHasActiveSubscription
(
    @UserId INT,
    @CheckDate DATE
)
RETURNS BIT
AS
BEGIN
    DECLARE @HasActiveSubscription BIT = 0;

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

-- 7. ДОСТУП К КНИГЕ //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_UserHasAccessToBook
(
    @UserId INT,
    @BookId INT,
    @CheckDate DATE
)
RETURNS BIT
AS
BEGIN
    DECLARE @HasAccess BIT = 0;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.UserAccount AS U
            INNER JOIN dbo.Book AS B ON B.BookId = @BookId
        WHERE U.UserId = @UserId
          AND U.IsActive = 1
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
                    B.IsPremium = 0
                    AND B.IsAvailableBySubscription = 1
                    AND dbo.fn_UserHasActiveSubscription(@UserId, @CheckDate) = 1
                 )
          )
    )
    BEGIN
        SET @HasAccess = 1;
    END;

    RETURN @HasAccess;
END;
GO

-- 8. ПРОЦЕНТ ЧТЕНИЯ //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_CalculateReadingProgressPercent
(
    @CurrentPage INT,
    @PageCount INT
)
RETURNS DECIMAL(5,2)
AS
BEGIN
    IF @PageCount IS NULL OR @PageCount <= 0 OR @CurrentPage IS NULL OR @CurrentPage <= 0
        RETURN 0;

    IF @CurrentPage >= @PageCount
        RETURN 100;

    RETURN CAST
    (
        CAST(@CurrentPage AS DECIMAL(10,2)) / CAST(@PageCount AS DECIMAL(10,2)) * 100
        AS DECIMAL(5,2)
    );
END;
GO

-- 9. АВТОМАТИЧЕСКАЯ СКИДКА КНИГИ //////////////////////////////
-- Учитываются обычные акции, привязанные к книге, и глобальные акции.
-- Персональная скидка ко дню рождения здесь не применяется.

CREATE OR ALTER FUNCTION dbo.fn_GetBookActiveDiscountPercent
(
    @BookId INT,
    @CheckDate DATE
)
RETURNS DECIMAL(5,2)
AS
BEGIN
    DECLARE @DiscountPercent DECIMAL(5,2);

    SELECT @DiscountPercent = MAX(P.DiscountPercent)
    FROM dbo.Promotion AS P
    WHERE P.IsActive = 1
      AND P.RequiresBirthday = 0
      AND @CheckDate BETWEEN P.StartDate AND P.EndDate
      AND
      (
          P.AppliesToAllBooks = 1
          OR EXISTS
             (
                SELECT 1
                FROM dbo.BookPromotion AS BP
                WHERE BP.PromotionId = P.PromotionId
                  AND BP.BookId = @BookId
             )
      );

    RETURN ISNULL(@DiscountPercent, 0);
END;
GO

-- 10. ПРОМОКОД КО ДНЮ РОЖДЕНИЯ //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_GetBirthdayPromoCode
(
    @UserId INT,
    @CheckDate DATE
)
RETURNS NVARCHAR(50)
AS
BEGIN
    DECLARE @PromoCode NVARCHAR(50);

    IF EXISTS
    (
        SELECT 1
        FROM dbo.UserAccount
        WHERE UserId = @UserId
          AND IsActive = 1
          AND DateOfBirth IS NOT NULL
          AND MONTH(DateOfBirth) = MONTH(@CheckDate)
          AND DAY(DateOfBirth) = DAY(@CheckDate)
    )
    BEGIN
        SELECT TOP 1 @PromoCode = PromoCode
        FROM dbo.Promotion
        WHERE IsActive = 1
          AND AppliesToAllBooks = 1
          AND RequiresBirthday = 1
          AND @CheckDate BETWEEN StartDate AND EndDate
        ORDER BY DiscountPercent DESC, PromotionId ASC;
    END;

    RETURN @PromoCode;
END;
GO

-- 11. ПРОВЕРКА ПРОМОКОДА //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_IsPromoCodeApplicable
(
    @UserId INT,
    @BookId INT,
    @PromoCode NVARCHAR(50),
    @CheckDate DATE
)
RETURNS BIT
AS
BEGIN
    DECLARE @IsApplicable BIT = 0;

    IF @PromoCode IS NULL OR LTRIM(RTRIM(@PromoCode)) = N''
        RETURN 0;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.Promotion AS P
        WHERE UPPER(P.PromoCode) = UPPER(LTRIM(RTRIM(@PromoCode)))
          AND P.IsActive = 1
          AND @CheckDate BETWEEN P.StartDate AND P.EndDate
          AND
          (
              P.AppliesToAllBooks = 1
              OR EXISTS
                 (
                    SELECT 1
                    FROM dbo.BookPromotion AS BP
                    WHERE BP.PromotionId = P.PromotionId
                      AND BP.BookId = @BookId
                 )
          )
          AND
          (
              P.RequiresBirthday = 0
              OR
              (
                  @UserId IS NOT NULL
                  AND EXISTS
                      (
                          SELECT 1
                          FROM dbo.UserAccount AS U
                          WHERE U.UserId = @UserId
                            AND U.IsActive = 1
                            AND U.DateOfBirth IS NOT NULL
                            AND MONTH(U.DateOfBirth) = MONTH(@CheckDate)
                            AND DAY(U.DateOfBirth) = DAY(@CheckDate)
                      )
              )
          )
    )
    BEGIN
        SET @IsApplicable = 1;
    END;

    RETURN @IsApplicable;
END;
GO

-- 12. ПРИМЕНИМАЯ СКИДКА //////////////////////////////
-- Сравнивает автоматическую скидку книги и введённый промокод.
-- Если промокод требует день рождения, дата проверяется по UserAccount.DateOfBirth.

CREATE OR ALTER FUNCTION dbo.fn_GetApplicableDiscountPercent
(
    @UserId INT,
    @BookId INT,
    @PromoCode NVARCHAR(50),
    @CheckDate DATE
)
RETURNS DECIMAL(5,2)
AS
BEGIN
    DECLARE @AutomaticDiscount DECIMAL(5,2);
    DECLARE @PromoDiscount DECIMAL(5,2);

    SET @AutomaticDiscount = dbo.fn_GetBookActiveDiscountPercent(@BookId, @CheckDate);

    SELECT @PromoDiscount = MAX(P.DiscountPercent)
    FROM dbo.Promotion AS P
    WHERE @PromoCode IS NOT NULL
      AND LTRIM(RTRIM(@PromoCode)) <> N''
      AND UPPER(P.PromoCode) = UPPER(LTRIM(RTRIM(@PromoCode)))
      AND P.IsActive = 1
      AND @CheckDate BETWEEN P.StartDate AND P.EndDate
      AND
      (
          P.AppliesToAllBooks = 1
          OR EXISTS
             (
                SELECT 1
                FROM dbo.BookPromotion AS BP
                WHERE BP.PromotionId = P.PromotionId
                  AND BP.BookId = @BookId
             )
      )
      AND
      (
          P.RequiresBirthday = 0
          OR
          (
              @UserId IS NOT NULL
              AND EXISTS
                  (
                      SELECT 1
                      FROM dbo.UserAccount AS U
                      WHERE U.UserId = @UserId
                        AND U.IsActive = 1
                        AND U.DateOfBirth IS NOT NULL
                        AND MONTH(U.DateOfBirth) = MONTH(@CheckDate)
                        AND DAY(U.DateOfBirth) = DAY(@CheckDate)
                  )
          )
      );

    RETURN
    (
        CASE
            WHEN ISNULL(@PromoDiscount, 0) > ISNULL(@AutomaticDiscount, 0)
                THEN ISNULL(@PromoDiscount, 0)
            ELSE ISNULL(@AutomaticDiscount, 0)
        END
    );
END;
GO

-- 13. ПРИМЕНЁННЫЙ ПРОМОКОД //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_GetAppliedPromotionCode
(
    @UserId INT,
    @BookId INT,
    @PromoCode NVARCHAR(50),
    @CheckDate DATE
)
RETURNS NVARCHAR(50)
AS
BEGIN
    DECLARE @AppliedCode NVARCHAR(50);

    SELECT TOP 1 @AppliedCode = P.PromoCode
    FROM dbo.Promotion AS P
    WHERE P.IsActive = 1
      AND @CheckDate BETWEEN P.StartDate AND P.EndDate
      AND
      (
          P.AppliesToAllBooks = 1
          OR EXISTS
             (
                SELECT 1
                FROM dbo.BookPromotion AS BP
                WHERE BP.PromotionId = P.PromotionId
                  AND BP.BookId = @BookId
             )
      )
      AND
      (
          P.RequiresBirthday = 0
          OR
          (
              @PromoCode IS NOT NULL
              AND UPPER(P.PromoCode) = UPPER(LTRIM(RTRIM(@PromoCode)))
              AND @UserId IS NOT NULL
              AND EXISTS
                  (
                      SELECT 1
                      FROM dbo.UserAccount AS U
                      WHERE U.UserId = @UserId
                        AND U.IsActive = 1
                        AND U.DateOfBirth IS NOT NULL
                        AND MONTH(U.DateOfBirth) = MONTH(@CheckDate)
                        AND DAY(U.DateOfBirth) = DAY(@CheckDate)
                  )
          )
      )
      AND P.DiscountPercent = dbo.fn_GetApplicableDiscountPercent(@UserId, @BookId, @PromoCode, @CheckDate)
    ORDER BY
        CASE WHEN @PromoCode IS NOT NULL AND UPPER(P.PromoCode) = UPPER(LTRIM(RTRIM(@PromoCode))) THEN 0 ELSE 1 END,
        P.PromotionId ASC;

    RETURN @AppliedCode;
END;
GO

-- 14. ИТОГОВАЯ ЦЕНА //////////////////////////////

CREATE OR ALTER FUNCTION dbo.fn_GetBookFinalPrice
(
    @UserId INT,
    @BookId INT,
    @PromoCode NVARCHAR(50),
    @CheckDate DATE
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @BasePrice DECIMAL(10,2);
    DECLARE @IsFree BIT;
    DECLARE @DiscountPercent DECIMAL(5,2);

    SELECT
        @BasePrice = Price,
        @IsFree = IsFree
    FROM dbo.Book
    WHERE BookId = @BookId;

    IF @BasePrice IS NULL
        RETURN NULL;

    IF @IsFree = 1
        RETURN 0;

    SET @DiscountPercent = dbo.fn_GetApplicableDiscountPercent(@UserId, @BookId, @PromoCode, @CheckDate);

    RETURN CAST(ROUND(@BasePrice * (100 - @DiscountPercent) / 100, 2) AS DECIMAL(10,2));
END;
GO

SELECT ROUTINE_SCHEMA, ROUTINE_NAME, ROUTINE_TYPE
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_TYPE = 'FUNCTION'
ORDER BY ROUTINE_NAME;
GO
