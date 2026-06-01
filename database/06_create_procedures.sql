USE [BookStreamDB];
GO

/*
    06_create_procedures.sql

    Хранимые процедуры содержат бизнес-операции приложения.
    Backend вызывает процедуры вместо размещения больших SQL-запросов в Python.
*/

-- 1. ПРОВЕРКА ПОДКЛЮЧЕНИЯ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_HealthCheck
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        DB_NAME() AS CurrentDatabase,
        CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(50)) AS SqlServerVersion;
END;
GO

-- 2. РЕГИСТРАЦИЯ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_RegisterUser
    @Username NVARCHAR(100),
    @Email NVARCHAR(255),
    @PasswordHash NVARCHAR(255),
    @DateOfBirth DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserRoleId INT;
    DECLARE @NewUserId INT;

    SELECT @UserRoleId = RoleId
    FROM dbo.Role
    WHERE RoleName = N'User';

    IF @UserRoleId IS NULL
    BEGIN
        RAISERROR(N'Роль User не найдена.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM dbo.UserAccount WHERE Username = @Username)
    BEGIN
        RAISERROR(N'Пользователь с таким Username уже существует.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM dbo.UserAccount WHERE Email = @Email)
    BEGIN
        RAISERROR(N'Пользователь с таким Email уже существует.', 16, 1);
        RETURN;
    END;

    IF @DateOfBirth IS NOT NULL AND @DateOfBirth > CAST(GETDATE() AS DATE)
    BEGIN
        RAISERROR(N'Дата рождения не может быть позже текущей даты.', 16, 1);
        RETURN;
    END;

    INSERT INTO dbo.UserAccount
        (RoleId, Username, Email, PasswordHash, DateOfBirth, Balance)
    VALUES
        (@UserRoleId, @Username, @Email, @PasswordHash, @DateOfBirth, 0);

    SET @NewUserId = CONVERT(INT, SCOPE_IDENTITY());

    SELECT
        U.UserId,
        U.RoleId,
        U.Username,
        U.Email,
        U.DateOfBirth,
        U.RegistrationDate,
        U.IsActive,
        U.Balance
    FROM dbo.UserAccount AS U
    WHERE U.UserId = @NewUserId;
END;
GO

-- 3. ДАННЫЕ ДЛЯ ВХОДА //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetUserForLogin
    @Login NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
        U.UserId,
        U.Username,
        U.Email,
        U.PasswordHash,
        U.DateOfBirth,
        U.IsActive,
        dbo.fn_GetUserBalance(U.UserId) AS Balance,
        R.RoleName
    FROM dbo.UserAccount AS U
        INNER JOIN dbo.Role AS R ON U.RoleId = R.RoleId
    WHERE U.Username = @Login
       OR U.Email = @Login;
END;
GO

-- 4. ТАРИФЫ ПОДПИСКИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetSubscriptionPlans
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        PlanId,
        PlanName,
        Price,
        DurationDays,
        Description,
        IsActive
    FROM dbo.SubscriptionPlan
    WHERE IsActive = 1
    ORDER BY Price ASC, DurationDays ASC;
END;
GO

-- 5. ПОПОЛНЕНИЕ БАЛАНСА //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_TopUpBalance
    @UserId INT,
    @Amount DECIMAL(10,2),
    @PaymentMethod NVARCHAR(50) = N'Card'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NewPaymentId INT;
    DECLARE @TransactionNumber NVARCHAR(100);

    IF @Amount <= 0
    BEGIN
        RAISERROR(N'Сумма пополнения должна быть больше 0.', 16, 1);
        RETURN;
    END;

    IF @PaymentMethod NOT IN (N'Card', N'OnlineWallet', N'Bonus')
    BEGIN
        RAISERROR(N'Недопустимый способ пополнения баланса.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.UserAccount WHERE UserId = @UserId AND IsActive = 1)
    BEGIN
        RAISERROR(N'Активный пользователь не найден.', 16, 1);
        RETURN;
    END;

    SET @TransactionNumber = N'TRX-TOPUP-' + CONVERT(NVARCHAR(36), NEWID());

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.UserAccount
        SET Balance = Balance + @Amount
        WHERE UserId = @UserId;

        INSERT INTO dbo.Payment
            (UserId, Amount, PaymentMethod, PaymentStatus, TransactionNumber)
        VALUES
            (@UserId, @Amount, @PaymentMethod, N'Success', @TransactionNumber);

        SET @NewPaymentId = CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;

        SELECT
            U.UserId,
            U.Username,
            U.Email,
            dbo.fn_GetUserBalance(U.UserId) AS Balance,
            P.PaymentId,
            P.Amount,
            P.PaymentMethod,
            P.PaymentStatus,
            P.TransactionNumber
        FROM dbo.UserAccount AS U
            INNER JOIN dbo.Payment AS P ON P.UserId = U.UserId
        WHERE U.UserId = @UserId
          AND P.PaymentId = @NewPaymentId;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);

        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;
GO

-- 6. ОФОРМЛЕНИЕ ПОДПИСКИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_CreateSubscription
    @UserId INT,
    @PlanId INT,
    @PaymentMethod NVARCHAR(50) = N'Balance'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PlanPrice DECIMAL(10,2);
    DECLARE @DurationDays INT;
    DECLARE @NewPaymentId INT;
    DECLARE @NewSubscriptionId INT;
    DECLARE @StartDate DATE = CAST(GETDATE() AS DATE);
    DECLARE @TransactionNumber NVARCHAR(100);

    IF @PaymentMethod <> N'Balance'
    BEGIN
        RAISERROR(N'Подписка оплачивается с внутреннего баланса.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.UserAccount WHERE UserId = @UserId AND IsActive = 1)
    BEGIN
        RAISERROR(N'Активный пользователь не найден.', 16, 1);
        RETURN;
    END;

    SELECT
        @PlanPrice = Price,
        @DurationDays = DurationDays
    FROM dbo.SubscriptionPlan
    WHERE PlanId = @PlanId
      AND IsActive = 1;

    IF @DurationDays IS NULL
    BEGIN
        RAISERROR(N'Активный тариф подписки не найден.', 16, 1);
        RETURN;
    END;

    IF dbo.fn_GetUserBalance(@UserId) < @PlanPrice
    BEGIN
        RAISERROR(N'Недостаточно средств для оформления подписки.', 16, 1);
        RETURN;
    END;

    SET @TransactionNumber = N'TRX-SUB-' + CONVERT(NVARCHAR(36), NEWID());

    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE dbo.UserAccount
        SET Balance = Balance - @PlanPrice
        WHERE UserId = @UserId;

        INSERT INTO dbo.Payment
            (UserId, Amount, PaymentMethod, PaymentStatus, TransactionNumber)
        VALUES
            (@UserId, @PlanPrice, @PaymentMethod, N'Success', @TransactionNumber);

        SET @NewPaymentId = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.UserSubscription
            (UserId, PlanId, PaymentId, StartDate, EndDate, IsActive)
        VALUES
            (@UserId, @PlanId, @NewPaymentId, @StartDate, DATEADD(DAY, @DurationDays, @StartDate), 1);

        SET @NewSubscriptionId = CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;

        SELECT
            US.SubscriptionId,
            US.UserId,
            U.Username,
            US.PlanId,
            SP.PlanName,
            SP.Price,
            US.PaymentId,
            US.StartDate,
            US.EndDate,
            US.IsActive,
            dbo.fn_GetUserBalance(US.UserId) AS Balance
        FROM dbo.UserSubscription AS US
            INNER JOIN dbo.UserAccount AS U ON US.UserId = U.UserId
            INNER JOIN dbo.SubscriptionPlan AS SP ON US.PlanId = SP.PlanId
        WHERE US.SubscriptionId = @NewSubscriptionId;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);

        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;
GO

-- 7. ПРОФИЛЬ ПОЛЬЗОВАТЕЛЯ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetUserProfile
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.UserAccount WHERE UserId = @UserId)
    BEGIN
        RAISERROR(N'Пользователь не найден.', 16, 1);
        RETURN;
    END;

    SELECT
        U.UserId,
        U.Username,
        U.Email,
        U.DateOfBirth,
        U.RegistrationDate,
        U.IsActive,
        dbo.fn_GetUserBalance(U.UserId) AS Balance,
        R.RoleName,
        dbo.fn_GetUserPurchasedBookCount(U.UserId) AS PurchasedBookCount,
        dbo.fn_GetUserFavoriteBookCount(U.UserId) AS FavoriteBookCount,
        dbo.fn_GetBirthdayPromoCode(U.UserId, CAST(GETDATE() AS DATE)) AS BirthdayPromoCode,
        CASE
            WHEN dbo.fn_GetBirthdayPromoCode(U.UserId, CAST(GETDATE() AS DATE)) IS NULL THEN CAST(0 AS BIT)
            ELSE CAST(1 AS BIT)
        END AS HasBirthdayPromo
    FROM dbo.UserAccount AS U
        INNER JOIN dbo.Role AS R ON U.RoleId = R.RoleId
    WHERE U.UserId = @UserId;

    SELECT *
    FROM dbo.vw_ActiveUserSubscriptions
    WHERE UserId = @UserId
    ORDER BY EndDate ASC;

    SELECT *
    FROM dbo.vw_UserPayments
    WHERE UserId = @UserId
    ORDER BY PaymentDate DESC;

    SELECT *
    FROM dbo.vw_UserReadingProgress
    WHERE UserId = @UserId
    ORDER BY LastReadAt DESC;
END;
GO

-- 8. ИЗБРАННЫЕ КНИГИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetUserFavorites
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        U.UserId,
        U.Username,
        BC.BookId,
        BC.Title,
        BC.Description,
        BC.Price,
        BC.DiscountPercent,
        BC.FinalPrice,
        BC.HasActivePromotion,
        BC.ActivePromotionName,
        BC.ActivePromoCode,
        BC.IsFree,
        BC.IsPremium,
        BC.IsAvailableBySubscription,
        BC.CoverImageUrl,
        BC.PublisherName,
        F.AddedAt
    FROM dbo.FavoriteBook AS F
        INNER JOIN dbo.UserAccount AS U ON F.UserId = U.UserId
        INNER JOIN dbo.vw_BookCatalog AS BC ON F.BookId = BC.BookId
    WHERE F.UserId = @UserId
    ORDER BY F.AddedAt DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AddFavoriteBook
    @UserId INT,
    @BookId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.UserAccount WHERE UserId = @UserId)
    BEGIN
        RAISERROR(N'Пользователь не найден.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.Book WHERE BookId = @BookId)
    BEGIN
        RAISERROR(N'Книга не найдена.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.FavoriteBook WHERE UserId = @UserId AND BookId = @BookId)
    BEGIN
        INSERT INTO dbo.FavoriteBook (UserId, BookId)
        VALUES (@UserId, @BookId);
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
    WHERE F.UserId = @UserId
      AND F.BookId = @BookId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RemoveFavoriteBook
    @UserId INT,
    @BookId INT
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.FavoriteBook
    WHERE UserId = @UserId
      AND BookId = @BookId;

    SELECT N'Книга удалена из избранного' AS Message;
END;
GO

-- 9. КАТАЛОГ КНИГ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetBookCatalog
    @SearchText NVARCHAR(255) = NULL,
    @GenreName NVARCHAR(100) = NULL,
    @OnlyFree BIT = NULL,
    @AvailableBySubscription BIT = NULL,
    @OnlyPremium BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM dbo.vw_BookCatalog
    WHERE
        (
            @SearchText IS NULL
            OR Title LIKE N'%' + @SearchText + N'%'
            OR Authors LIKE N'%' + @SearchText + N'%'
            OR Description LIKE N'%' + @SearchText + N'%'
            OR Genres LIKE N'%' + @SearchText + N'%'
            OR PublisherName LIKE N'%' + @SearchText + N'%'
        )
      AND (@GenreName IS NULL OR Genres LIKE N'%' + @GenreName + N'%')
      AND (@OnlyFree IS NULL OR IsFree = @OnlyFree)
      AND (@AvailableBySubscription IS NULL OR IsAvailableBySubscription = @AvailableBySubscription)
      AND (@OnlyPremium IS NULL OR IsPremium = @OnlyPremium)
    ORDER BY
        HasActivePromotion DESC,
        DiscountPercent DESC,
        AverageRating DESC,
        ReviewCount DESC,
        Title ASC;
END;
GO

-- 10. КАРТОЧКА КНИГИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetBookById
    @BookId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Book WHERE BookId = @BookId)
    BEGIN
        RAISERROR(N'Книга не найдена.', 16, 1);
        RETURN;
    END;

    SELECT *
    FROM dbo.vw_BookCatalog
    WHERE BookId = @BookId;

    SELECT *
    FROM dbo.vw_BookReviews
    WHERE BookId = @BookId
    ORDER BY CreatedAt DESC;
END;
GO

-- 11. ПРОВЕРКА ПРОМОКОДА //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetBookPricePreview
    @UserId INT,
    @BookId INT,
    @PromoCode NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CheckDate DATE = CAST(GETDATE() AS DATE);
    DECLARE @BasePrice DECIMAL(10,2);
    DECLARE @DiscountPercent DECIMAL(5,2);
    DECLARE @FinalPrice DECIMAL(10,2);
    DECLARE @AppliedPromoCode NVARCHAR(50);

    SELECT @BasePrice = Price
    FROM dbo.Book
    WHERE BookId = @BookId;

    IF @BasePrice IS NULL
    BEGIN
        RAISERROR(N'Книга не найдена.', 16, 1);
        RETURN;
    END;

    SET @DiscountPercent = dbo.fn_GetApplicableDiscountPercent(@UserId, @BookId, @PromoCode, @CheckDate);
    SET @FinalPrice = dbo.fn_GetBookFinalPrice(@UserId, @BookId, @PromoCode, @CheckDate);
    SET @AppliedPromoCode = dbo.fn_GetAppliedPromotionCode(@UserId, @BookId, @PromoCode, @CheckDate);

    SELECT
        @BookId AS BookId,
        @BasePrice AS BasePrice,
        @DiscountPercent AS DiscountPercent,
        @FinalPrice AS FinalPrice,
        @AppliedPromoCode AS AppliedPromoCode,
        CASE
            WHEN @PromoCode IS NULL OR LTRIM(RTRIM(@PromoCode)) = N'' THEN CAST(1 AS BIT)
            ELSE dbo.fn_IsPromoCodeApplicable(@UserId, @BookId, @PromoCode, @CheckDate)
        END AS PromoCodeAccepted;
END;
GO

-- 12. ПОКУПКА КНИГИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_BuyBook
    @UserId INT,
    @BookId INT,
    @PaymentMethod NVARCHAR(50) = N'Balance',
    @PromoCode NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CheckDate DATE = CAST(GETDATE() AS DATE);
    DECLARE @BasePrice DECIMAL(10,2);
    DECLARE @IsFree BIT;
    DECLARE @DiscountPercent DECIMAL(5,2);
    DECLARE @FinalPrice DECIMAL(10,2);
    DECLARE @AppliedPromoCode NVARCHAR(50);
    DECLARE @NewPaymentId INT;
    DECLARE @NewPurchaseId INT;
    DECLARE @TransactionNumber NVARCHAR(100);

    IF @PaymentMethod <> N'Balance'
    BEGIN
        RAISERROR(N'Покупка книги оплачивается с внутреннего баланса.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.UserAccount WHERE UserId = @UserId AND IsActive = 1)
    BEGIN
        RAISERROR(N'Активный пользователь не найден.', 16, 1);
        RETURN;
    END;

    SELECT
        @BasePrice = Price,
        @IsFree = IsFree
    FROM dbo.Book
    WHERE BookId = @BookId;

    IF @BasePrice IS NULL
    BEGIN
        RAISERROR(N'Книга не найдена.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM dbo.Purchase WHERE UserId = @UserId AND BookId = @BookId)
    BEGIN
        RAISERROR(N'Пользователь уже купил эту книгу.', 16, 1);
        RETURN;
    END;

    SET @AppliedPromoCode = dbo.fn_GetAppliedPromotionCode(@UserId, @BookId, @PromoCode, @CheckDate);

    IF @PromoCode IS NOT NULL
       AND LTRIM(RTRIM(@PromoCode)) <> N''
       AND dbo.fn_IsPromoCodeApplicable(@UserId, @BookId, @PromoCode, @CheckDate) = 0
    BEGIN
        RAISERROR(N'Промокод недействителен для этой книги или пользователя.', 16, 1);
        RETURN;
    END;

    SET @DiscountPercent = dbo.fn_GetApplicableDiscountPercent(@UserId, @BookId, @PromoCode, @CheckDate);
    SET @FinalPrice = dbo.fn_GetBookFinalPrice(@UserId, @BookId, @PromoCode, @CheckDate);

    IF dbo.fn_GetUserBalance(@UserId) < @FinalPrice
    BEGIN
        RAISERROR(N'Недостаточно средств на балансе для покупки книги.', 16, 1);
        RETURN;
    END;

    SET @TransactionNumber = N'TRX-PUR-' + CONVERT(NVARCHAR(36), NEWID());

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @FinalPrice > 0
        BEGIN
            UPDATE dbo.UserAccount
            SET Balance = Balance - @FinalPrice
            WHERE UserId = @UserId;

            INSERT INTO dbo.Payment
                (UserId, Amount, PaymentMethod, PaymentStatus, TransactionNumber)
            VALUES
                (@UserId, @FinalPrice, @PaymentMethod, N'Success', @TransactionNumber);

            SET @NewPaymentId = CONVERT(INT, SCOPE_IDENTITY());
        END;

        INSERT INTO dbo.Purchase
            (UserId, BookId, PaymentId, PurchasePrice, AppliedPromoCode, AppliedDiscountPercent)
        VALUES
            (@UserId, @BookId, @NewPaymentId, @FinalPrice, @AppliedPromoCode, @DiscountPercent);

        SET @NewPurchaseId = CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;

        SELECT
            P.PurchaseId,
            P.UserId,
            U.Username,
            dbo.fn_GetUserBalance(P.UserId) AS Balance,
            P.BookId,
            B.Title,
            @BasePrice AS BasePrice,
            P.AppliedDiscountPercent AS DiscountPercent,
            P.AppliedPromoCode,
            P.PurchasePrice AS FinalPrice,
            P.PaymentId,
            P.PurchaseDate,
            P.PurchasePrice
        FROM dbo.Purchase AS P
            INNER JOIN dbo.UserAccount AS U ON P.UserId = U.UserId
            INNER JOIN dbo.Book AS B ON P.BookId = B.BookId
        WHERE P.PurchaseId = @NewPurchaseId;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);

        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;
GO

-- 13. ТЕКСТ КНИГИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetBookContentForUser
    @UserId INT,
    @BookId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF dbo.fn_UserHasAccessToBook(@UserId, @BookId, CAST(GETDATE() AS DATE)) = 0
    BEGIN
        RAISERROR(N'У пользователя нет доступа к этой книге.', 16, 1);
        RETURN;
    END;

    SELECT
        B.BookId,
        B.Title,
        BC.ContentText,
        BC.ContentFormat,
        ISNULL(RP.CurrentPage, 1) AS CurrentPage,
        ISNULL(RP.ProgressPercent, 0) AS ProgressPercent
    FROM dbo.Book AS B
        INNER JOIN dbo.BookContent AS BC ON B.BookId = BC.BookId
        LEFT JOIN dbo.ReadingProgress AS RP
            ON RP.BookId = B.BookId
           AND RP.UserId = @UserId
    WHERE B.BookId = @BookId;
END;
GO

-- 14. ОТЗЫВ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_AddReview
    @UserId INT,
    @BookId INT,
    @Rating INT,
    @ReviewText NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @Rating NOT BETWEEN 1 AND 5
    BEGIN
        RAISERROR(N'Оценка должна быть от 1 до 5.', 16, 1);
        RETURN;
    END;

    IF dbo.fn_UserHasAccessToBook(@UserId, @BookId, CAST(GETDATE() AS DATE)) = 0
    BEGIN
        RAISERROR(N'Отзыв можно оставить только к доступной книге.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM dbo.Review WHERE UserId = @UserId AND BookId = @BookId)
    BEGIN
        UPDATE dbo.Review
        SET Rating = @Rating,
            ReviewText = @ReviewText,
            CreatedAt = SYSDATETIME()
        WHERE UserId = @UserId
          AND BookId = @BookId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.Review (UserId, BookId, Rating, ReviewText)
        VALUES (@UserId, @BookId, @Rating, @ReviewText);
    END;

    SELECT *
    FROM dbo.vw_BookReviews
    WHERE UserId = @UserId
      AND BookId = @BookId;
END;
GO

-- 15. ПРОГРЕСС ЧТЕНИЯ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_UpdateReadingProgress
    @UserId INT,
    @BookId INT,
    @CurrentPage INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PageCount INT;
    DECLARE @ProgressPercent DECIMAL(5,2);

    IF dbo.fn_UserHasAccessToBook(@UserId, @BookId, CAST(GETDATE() AS DATE)) = 0
    BEGIN
        RAISERROR(N'У пользователя нет доступа к этой книге.', 16, 1);
        RETURN;
    END;

    SELECT @PageCount = PageCount
    FROM dbo.Book
    WHERE BookId = @BookId;

    IF @CurrentPage < 1 OR @CurrentPage > @PageCount
    BEGIN
        RAISERROR(N'Текущая страница выходит за границы книги.', 16, 1);
        RETURN;
    END;

    SET @ProgressPercent = dbo.fn_CalculateReadingProgressPercent(@CurrentPage, @PageCount);

    IF EXISTS (SELECT 1 FROM dbo.ReadingProgress WHERE UserId = @UserId AND BookId = @BookId)
    BEGIN
        UPDATE dbo.ReadingProgress
        SET CurrentPage = @CurrentPage,
            ProgressPercent = @ProgressPercent,
            LastReadAt = SYSDATETIME()
        WHERE UserId = @UserId
          AND BookId = @BookId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.ReadingProgress
            (UserId, BookId, CurrentPage, ProgressPercent)
        VALUES
            (@UserId, @BookId, @CurrentPage, @ProgressPercent);
    END;

    SELECT *
    FROM dbo.vw_UserReadingProgress
    WHERE UserId = @UserId
      AND BookId = @BookId;
END;
GO

-- 16. ПРОВЕРКА АДМИНИСТРАТОРА //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetAdminUser
    @AdminUserId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        U.UserId,
        U.Username,
        R.RoleName
    FROM dbo.UserAccount AS U
        INNER JOIN dbo.Role AS R ON U.RoleId = R.RoleId
    WHERE U.UserId = @AdminUserId
      AND U.IsActive = 1
      AND LOWER(R.RoleName) IN (N'admin', N'administrator', N'администратор');
END;
GO

-- 17. СПРАВОЧНИКИ АДМИНКИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetAdminOptions
AS
BEGIN
    SET NOCOUNT ON;

    SELECT PublisherId, PublisherName
    FROM dbo.Publisher
    ORDER BY PublisherName;

    SELECT AuthorId, FirstName + N' ' + LastName AS AuthorName
    FROM dbo.Author
    ORDER BY LastName, FirstName;

    SELECT GenreId, GenreName
    FROM dbo.Genre
    ORDER BY GenreName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CreatePublisher
    @PublisherName NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PublisherId INT;

    SELECT @PublisherId = PublisherId
    FROM dbo.Publisher
    WHERE PublisherName = @PublisherName;

    IF @PublisherId IS NULL
    BEGIN
        INSERT INTO dbo.Publisher (PublisherName)
        VALUES (@PublisherName);

        SET @PublisherId = CONVERT(INT, SCOPE_IDENTITY());
    END;

    SELECT PublisherId, PublisherName
    FROM dbo.Publisher
    WHERE PublisherId = @PublisherId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CreateAuthor
    @FirstName NVARCHAR(100),
    @LastName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @AuthorId INT;

    SELECT @AuthorId = AuthorId
    FROM dbo.Author
    WHERE FirstName = @FirstName
      AND LastName = @LastName;

    IF @AuthorId IS NULL
    BEGIN
        INSERT INTO dbo.Author (FirstName, LastName)
        VALUES (@FirstName, @LastName);

        SET @AuthorId = CONVERT(INT, SCOPE_IDENTITY());
    END;

    SELECT
        AuthorId,
        FirstName,
        LastName,
        FirstName + N' ' + LastName AS AuthorName
    FROM dbo.Author
    WHERE AuthorId = @AuthorId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CreateGenre
    @GenreName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @GenreId INT;

    SELECT @GenreId = GenreId
    FROM dbo.Genre
    WHERE GenreName = @GenreName;

    IF @GenreId IS NULL
    BEGIN
        INSERT INTO dbo.Genre (GenreName)
        VALUES (@GenreName);

        SET @GenreId = CONVERT(INT, SCOPE_IDENTITY());
    END;

    SELECT GenreId, GenreName
    FROM dbo.Genre
    WHERE GenreId = @GenreId;
END;
GO

-- 18. ЖУРНАЛ И ОБЩАЯ СТАТИСТИКА //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetAuditLog
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 50
        LogId,
        TableName,
        ActionName,
        RecordId,
        UserId,
        Description,
        CreatedAt
    FROM dbo.AuditLog
    ORDER BY CreatedAt DESC, LogId DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_GetAdminStats
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        (SELECT COUNT(*) FROM dbo.Book) AS BookCount,
        (SELECT COUNT(*) FROM dbo.UserAccount) AS UserCount,
        (SELECT COUNT(*) FROM dbo.Purchase) AS PurchaseCount,
        (SELECT ISNULL(SUM(PurchasePrice), 0) FROM dbo.Purchase) AS TotalSales,
        (SELECT COUNT(*) FROM dbo.Review) AS ReviewCount,
        (SELECT ISNULL(AVG(CAST(Rating AS DECIMAL(4,2))), 0) FROM dbo.Review) AS AverageRating,
        (SELECT COUNT(*) FROM dbo.UserSubscription WHERE IsActive = 1 AND CAST(GETDATE() AS DATE) BETWEEN StartDate AND EndDate) AS ActiveSubscriptionCount,
        (SELECT COUNT(*) FROM dbo.Promotion) AS PromotionCount,
        (SELECT COUNT(*) FROM dbo.Promotion WHERE IsActive = 1 AND CAST(GETDATE() AS DATE) BETWEEN StartDate AND EndDate) AS ActivePromotionCount;

    SELECT TOP 5 *
    FROM dbo.vw_PopularBooks
    ORDER BY PurchaseCount DESC, FavoriteCount DESC, ReviewCount DESC, Title ASC;
END;
GO

-- 19. АКЦИИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetPromotions
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        P.PromotionId,
        P.PromotionName,
        P.PromoCode,
        P.DiscountPercent,
        P.StartDate,
        P.EndDate,
        P.IsActive,
        P.AppliesToAllBooks,
        P.RequiresBirthday,
        P.IsSystem,
        P.CreatedAt,
        CASE
            WHEN P.AppliesToAllBooks = 1 THEN (SELECT COUNT(*) FROM dbo.Book)
            ELSE COUNT(BP.BookId)
        END AS BookCount
    FROM dbo.Promotion AS P
        LEFT JOIN dbo.BookPromotion AS BP ON P.PromotionId = BP.PromotionId
    GROUP BY
        P.PromotionId,
        P.PromotionName,
        P.PromoCode,
        P.DiscountPercent,
        P.StartDate,
        P.EndDate,
        P.IsActive,
        P.AppliesToAllBooks,
        P.RequiresBirthday,
        P.IsSystem,
        P.CreatedAt
    ORDER BY P.IsSystem DESC, P.IsActive DESC, P.StartDate DESC, P.PromotionId DESC;

    SELECT
        BP.PromotionId,
        P.PromotionName,
        P.PromoCode,
        BP.BookId,
        B.Title,
        B.Price,
        dbo.fn_GetBookFinalPrice(NULL, B.BookId, NULL, CAST(GETDATE() AS DATE)) AS FinalPrice,
        BP.AssignedAt
    FROM dbo.BookPromotion AS BP
        INNER JOIN dbo.Promotion AS P ON BP.PromotionId = P.PromotionId
        INNER JOIN dbo.Book AS B ON BP.BookId = B.BookId
    ORDER BY P.PromotionId DESC, B.Title ASC;

    SELECT
        BookId,
        Title,
        Price,
        IsPremium,
        IsAvailableBySubscription
    FROM dbo.Book
    ORDER BY Title;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CreatePromotion
    @PromotionName NVARCHAR(255),
    @PromoCode NVARCHAR(50),
    @DiscountPercent DECIMAL(5,2),
    @StartDate DATE,
    @EndDate DATE,
    @IsActive BIT = 1,
    @AppliesToAllBooks BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PromotionId INT;

    IF @PromotionName IS NULL OR LTRIM(RTRIM(@PromotionName)) = N''
    BEGIN
        RAISERROR(N'Название акции не может быть пустым.', 16, 1);
        RETURN;
    END;

    IF @PromoCode IS NULL OR LTRIM(RTRIM(@PromoCode)) = N''
    BEGIN
        RAISERROR(N'Промокод не может быть пустым.', 16, 1);
        RETURN;
    END;

    IF @DiscountPercent <= 0 OR @DiscountPercent > 100
    BEGIN
        RAISERROR(N'Процент скидки должен быть больше 0 и не больше 100.', 16, 1);
        RETURN;
    END;

    IF @EndDate < @StartDate
    BEGIN
        RAISERROR(N'Дата окончания акции не может быть раньше даты начала.', 16, 1);
        RETURN;
    END;

    SELECT @PromotionId = PromotionId
    FROM dbo.Promotion
    WHERE PromoCode = UPPER(LTRIM(RTRIM(@PromoCode)));

    IF @PromotionId IS NULL
    BEGIN
        INSERT INTO dbo.Promotion
            (PromotionName, PromoCode, DiscountPercent, StartDate, EndDate, IsActive, AppliesToAllBooks, RequiresBirthday, IsSystem)
        VALUES
            (@PromotionName, UPPER(LTRIM(RTRIM(@PromoCode))), @DiscountPercent, @StartDate, @EndDate, @IsActive, @AppliesToAllBooks, 0, 0);

        SET @PromotionId = CONVERT(INT, SCOPE_IDENTITY());
    END
    ELSE
    BEGIN
        IF EXISTS (SELECT 1 FROM dbo.Promotion WHERE PromotionId = @PromotionId AND IsSystem = 1)
        BEGIN
            RAISERROR(N'Системную акцию нельзя изменять через обычную форму.', 16, 1);
            RETURN;
        END;

        UPDATE dbo.Promotion
        SET PromotionName = @PromotionName,
            DiscountPercent = @DiscountPercent,
            StartDate = @StartDate,
            EndDate = @EndDate,
            IsActive = @IsActive,
            AppliesToAllBooks = @AppliesToAllBooks
        WHERE PromotionId = @PromotionId;
    END;

    SELECT *
    FROM dbo.Promotion
    WHERE PromotionId = @PromotionId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AssignPromotionToBook
    @PromotionId INT,
    @BookId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Promotion WHERE PromotionId = @PromotionId)
    BEGIN
        RAISERROR(N'Акция не найдена.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM dbo.Promotion WHERE PromotionId = @PromotionId AND AppliesToAllBooks = 1)
    BEGIN
        RAISERROR(N'Эта акция уже действует на все книги и не требует ручной привязки.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.Book WHERE BookId = @BookId)
    BEGIN
        RAISERROR(N'Книга не найдена.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM dbo.BookPromotion WHERE PromotionId = @PromotionId AND BookId = @BookId)
    BEGIN
        INSERT INTO dbo.BookPromotion (PromotionId, BookId)
        VALUES (@PromotionId, @BookId);
    END;

    SELECT
        BP.PromotionId,
        P.PromotionName,
        P.PromoCode,
        BP.BookId,
        B.Title,
        B.Price,
        dbo.fn_GetBookFinalPrice(NULL, B.BookId, NULL, CAST(GETDATE() AS DATE)) AS FinalPrice,
        BP.AssignedAt
    FROM dbo.BookPromotion AS BP
        INNER JOIN dbo.Promotion AS P ON BP.PromotionId = P.PromotionId
        INNER JOIN dbo.Book AS B ON BP.BookId = B.BookId
    WHERE BP.PromotionId = @PromotionId
      AND BP.BookId = @BookId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_RemovePromotionFromBook
    @PromotionId INT,
    @BookId INT
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM dbo.BookPromotion
    WHERE PromotionId = @PromotionId
      AND BookId = @BookId;

    SELECT N'Книга удалена из акции' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_DeletePromotion
    @PromotionId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PromotionName NVARCHAR(255);
    DECLARE @PromoCode NVARCHAR(50);
    DECLARE @LinkedBookCount INT;

    SELECT
        @PromotionName = PromotionName,
        @PromoCode = PromoCode
    FROM dbo.Promotion
    WHERE PromotionId = @PromotionId;

    IF @PromotionName IS NULL
    BEGIN
        RAISERROR(N'Акция не найдена.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1 FROM dbo.Promotion WHERE PromotionId = @PromotionId AND IsSystem = 1)
    BEGIN
        RAISERROR(N'Системную акцию удалить нельзя.', 16, 1);
        RETURN;
    END;

    SELECT @LinkedBookCount = COUNT(*)
    FROM dbo.BookPromotion
    WHERE PromotionId = @PromotionId;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, Description)
    VALUES
        (N'Promotion', N'DELETE', @PromotionId, CONCAT(N'Удалена акция: ', @PromotionName, N'. Промокод: ', @PromoCode, N'. Связей с книгами: ', @LinkedBookCount, N'.'));

    DELETE FROM dbo.Promotion
    WHERE PromotionId = @PromotionId;

    SELECT
        @PromotionId AS PromotionId,
        @PromotionName AS PromotionName,
        @PromoCode AS PromoCode,
        @LinkedBookCount AS RemovedBookLinks,
        N'Акция удалена' AS Message;
END;
GO

-- 20. ДОБАВЛЕНИЕ КНИГИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_CreateBook
    @PublisherId INT,
    @AuthorIds NVARCHAR(MAX),
    @GenreIds NVARCHAR(MAX),
    @Title NVARCHAR(255),
    @Description NVARCHAR(MAX) = NULL,
    @PublicationYear INT = NULL,
    @AgeLimit INT,
    @PageCount INT,
    @Price DECIMAL(10,2),
    @IsFree BIT,
    @IsPremium BIT,
    @IsAvailableBySubscription BIT,
    @CoverImageUrl NVARCHAR(500) = NULL,
    @ContentText NVARCHAR(MAX),
    @ContentFormat NVARCHAR(20) = N'TEXT'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NewBookId INT;

    IF NOT EXISTS (SELECT 1 FROM dbo.Publisher WHERE PublisherId = @PublisherId)
    BEGIN
        RAISERROR(N'Издательство не найдено.', 16, 1);
        RETURN;
    END;

    IF @Title IS NULL OR LTRIM(RTRIM(@Title)) = N''
    BEGIN
        RAISERROR(N'Введите название книги.', 16, 1);
        RETURN;
    END;

    IF @ContentText IS NULL OR LTRIM(RTRIM(@ContentText)) = N''
    BEGIN
        RAISERROR(N'Добавьте текст книги.', 16, 1);
        RETURN;
    END;

    IF @IsPremium = 1 AND (@IsFree = 1 OR @IsAvailableBySubscription = 1)
    BEGIN
        RAISERROR(N'Премиальная книга должна быть платной и недоступной по подписке.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM STRING_SPLIT(@AuthorIds, N',')
        WHERE TRY_CONVERT(INT, value) IS NOT NULL
    )
    BEGIN
        RAISERROR(N'Выберите хотя бы одного автора.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
        FROM STRING_SPLIT(@GenreIds, N',')
        WHERE TRY_CONVERT(INT, value) IS NOT NULL
    )
    BEGIN
        RAISERROR(N'Выберите хотя бы один жанр.', 16, 1);
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.Book
            (PublisherId, Title, Description, PublicationYear, AgeLimit, PageCount, Price, IsFree, IsPremium, IsAvailableBySubscription, CoverImageUrl)
        VALUES
            (@PublisherId, @Title, @Description, @PublicationYear, @AgeLimit, @PageCount, @Price, @IsFree, @IsPremium, @IsAvailableBySubscription, @CoverImageUrl);

        SET @NewBookId = CONVERT(INT, SCOPE_IDENTITY());

        INSERT INTO dbo.BookAuthor (BookId, AuthorId)
        SELECT DISTINCT @NewBookId, TRY_CONVERT(INT, value)
        FROM STRING_SPLIT(@AuthorIds, N',')
        WHERE TRY_CONVERT(INT, value) IS NOT NULL;

        INSERT INTO dbo.BookGenre (BookId, GenreId)
        SELECT DISTINCT @NewBookId, TRY_CONVERT(INT, value)
        FROM STRING_SPLIT(@GenreIds, N',')
        WHERE TRY_CONVERT(INT, value) IS NOT NULL;

        INSERT INTO dbo.BookContent (BookId, ContentText, ContentFormat)
        VALUES (@NewBookId, @ContentText, @ContentFormat);

        COMMIT TRANSACTION;

        SELECT *
        FROM dbo.vw_BookCatalog
        WHERE BookId = @NewBookId;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);

        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
    END CATCH;
END;
GO

-- 21. ПАНЕЛЬ БАЗЫ ДАННЫХ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetDatabaseDashboard
AS
BEGIN
    SET NOCOUNT ON;

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
        (SELECT COUNT(*) FROM dbo.Promotion WHERE IsActive = 1 AND CAST(GETDATE() AS DATE) BETWEEN StartDate AND EndDate) AS ActivePromotionCount,
        (SELECT COUNT(*) FROM dbo.UserSubscription WHERE IsActive = 1 AND CAST(GETDATE() AS DATE) BETWEEN StartDate AND EndDate) AS ActiveSubscriptionCount,
        (SELECT ISNULL(SUM(Amount), 0) FROM dbo.Payment WHERE PaymentStatus = N'Success') AS SuccessfulPaymentAmount,
        (SELECT ISNULL(SUM(PurchasePrice), 0) FROM dbo.Purchase) AS TotalSales,
        (SELECT ISNULL(AVG(CAST(Rating AS DECIMAL(4,2))), 0) FROM dbo.Review) AS AverageRating;

    SELECT TOP 10
        P.PaymentId,
        U.Username,
        P.Amount,
        P.PaymentMethod,
        P.PaymentStatus,
        P.PaymentDate
    FROM dbo.Payment AS P
        INNER JOIN dbo.UserAccount AS U ON P.UserId = U.UserId
    ORDER BY P.PaymentDate DESC, P.PaymentId DESC;

    SELECT TOP 10
        PR.PurchaseId,
        U.Username,
        B.Title,
        PR.PurchasePrice,
        PR.AppliedPromoCode,
        PR.AppliedDiscountPercent,
        PR.PurchaseDate
    FROM dbo.Purchase AS PR
        INNER JOIN dbo.UserAccount AS U ON PR.UserId = U.UserId
        INNER JOIN dbo.Book AS B ON PR.BookId = B.BookId
    ORDER BY PR.PurchaseDate DESC, PR.PurchaseId DESC;

    SELECT TOP 10
        B.BookId,
        B.Title,
        COUNT(P.PurchaseId) AS PurchaseCount,
        ISNULL(SUM(P.PurchasePrice), 0) AS TotalSales
    FROM dbo.Book AS B
        LEFT JOIN dbo.Purchase AS P ON B.BookId = P.BookId
    GROUP BY B.BookId, B.Title
    ORDER BY TotalSales DESC, PurchaseCount DESC, B.Title ASC;

    SELECT TOP 10
        U.UserId,
        U.Username,
        COUNT(P.PurchaseId) AS PurchaseCount,
        ISNULL(SUM(P.PurchasePrice), 0) AS TotalPurchaseAmount
    FROM dbo.UserAccount AS U
        LEFT JOIN dbo.Purchase AS P ON U.UserId = P.UserId
    GROUP BY U.UserId, U.Username
    ORDER BY TotalPurchaseAmount DESC, PurchaseCount DESC, U.Username ASC;

    SELECT TOP 10 *
    FROM dbo.vw_PopularBooks
    ORDER BY FavoriteCount DESC, PurchaseCount DESC, ReviewCount DESC, Title ASC;

    SELECT TOP 10 *
    FROM dbo.vw_PopularBooks
    ORDER BY AverageRating DESC, ReviewCount DESC, Title ASC;

    SELECT TOP 10
        G.GenreId,
        G.GenreName,
        COUNT(DISTINCT BG.BookId) AS BookCount,
        COUNT(DISTINCT P.PurchaseId) AS PurchaseCount,
        ISNULL(SUM(P.PurchasePrice), 0) AS TotalSales
    FROM dbo.Genre AS G
        LEFT JOIN dbo.BookGenre AS BG ON G.GenreId = BG.GenreId
        LEFT JOIN dbo.Purchase AS P ON BG.BookId = P.BookId
    GROUP BY G.GenreId, G.GenreName
    ORDER BY TotalSales DESC, PurchaseCount DESC, BookCount DESC, G.GenreName ASC;

    SELECT TOP 10 *
    FROM dbo.vw_ActiveUserSubscriptions
    ORDER BY EndDate ASC, SubscriptionId DESC;

    SELECT TOP 10
        AP.PromotionId,
        AP.PromotionName,
        AP.PromoCode,
        AP.DiscountPercent,
        AP.StartDate,
        AP.EndDate,
        AP.AppliesToAllBooks,
        AP.RequiresBirthday,
        AP.IsSystem,
        COUNT(DISTINCT AP.BookId) AS BookCount
    FROM dbo.vw_ActiveBookPromotions AS AP
    GROUP BY
        AP.PromotionId,
        AP.PromotionName,
        AP.PromoCode,
        AP.DiscountPercent,
        AP.StartDate,
        AP.EndDate,
        AP.AppliesToAllBooks,
        AP.RequiresBirthday,
        AP.IsSystem
    ORDER BY AP.IsSystem DESC, AP.DiscountPercent DESC, AP.EndDate ASC;

    SELECT TOP 10
        LogId,
        TableName,
        ActionName,
        RecordId,
        UserId,
        Description,
        CreatedAt
    FROM dbo.AuditLog
    ORDER BY CreatedAt DESC, LogId DESC;

    SELECT
        O.name AS ObjectName,
        O.type_desc AS ObjectType,
        O.create_date AS CreatedAt,
        O.modify_date AS ModifiedAt
    FROM sys.objects AS O
    WHERE O.schema_id = SCHEMA_ID(N'dbo')
      AND O.type IN (N'V', N'P', N'FN', N'IF', N'TF', N'TR')
    ORDER BY O.type_desc, O.name;
END;
GO

-- 22. ОТЧЁТ ПО ПРОДАЖАМ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_AdminSalesReport
    @StartDate DATE = NULL,
    @EndDate DATE = NULL,
    @GroupBy NVARCHAR(20) = N'Book'
AS
BEGIN
    SET NOCOUNT ON;

    IF @GroupBy = N'User'
    BEGIN
        SELECT
            U.UserId,
            U.Username AS GroupName,
            COUNT(P.PurchaseId) AS PurchaseCount,
            CAST(ISNULL(SUM(P.PurchasePrice), 0) AS DECIMAL(10,2)) AS TotalSales,
            CAST(ISNULL(AVG(P.PurchasePrice), 0) AS DECIMAL(10,2)) AS AveragePurchasePrice
        FROM dbo.UserAccount AS U
            LEFT JOIN dbo.Purchase AS P
                ON U.UserId = P.UserId
               AND (@StartDate IS NULL OR P.PurchaseDate >= @StartDate)
               AND (@EndDate IS NULL OR P.PurchaseDate < DATEADD(DAY, 1, @EndDate))
        GROUP BY U.UserId, U.Username
        ORDER BY TotalSales DESC, PurchaseCount DESC, U.Username ASC;
        RETURN;
    END;

    IF @GroupBy = N'Day'
    BEGIN
        SELECT
            CAST(P.PurchaseDate AS DATE) AS SaleDate,
            CONVERT(NVARCHAR(10), CAST(P.PurchaseDate AS DATE), 23) AS GroupName,
            COUNT(P.PurchaseId) AS PurchaseCount,
            CAST(ISNULL(SUM(P.PurchasePrice), 0) AS DECIMAL(10,2)) AS TotalSales,
            CAST(ISNULL(AVG(P.PurchasePrice), 0) AS DECIMAL(10,2)) AS AveragePurchasePrice
        FROM dbo.Purchase AS P
        WHERE (@StartDate IS NULL OR P.PurchaseDate >= @StartDate)
          AND (@EndDate IS NULL OR P.PurchaseDate < DATEADD(DAY, 1, @EndDate))
        GROUP BY CAST(P.PurchaseDate AS DATE)
        ORDER BY SaleDate DESC;
        RETURN;
    END;

    SELECT
        B.BookId,
        B.Title AS GroupName,
        COUNT(P.PurchaseId) AS PurchaseCount,
        CAST(ISNULL(SUM(P.PurchasePrice), 0) AS DECIMAL(10,2)) AS TotalSales,
        CAST(ISNULL(AVG(P.PurchasePrice), 0) AS DECIMAL(10,2)) AS AveragePurchasePrice
    FROM dbo.Book AS B
        LEFT JOIN dbo.Purchase AS P
            ON B.BookId = P.BookId
           AND (@StartDate IS NULL OR P.PurchaseDate >= @StartDate)
           AND (@EndDate IS NULL OR P.PurchaseDate < DATEADD(DAY, 1, @EndDate))
    GROUP BY B.BookId, B.Title
    ORDER BY TotalSales DESC, PurchaseCount DESC, B.Title ASC;
END;
GO

-- 23. ОТЧЁТ ПО КНИГАМ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_AdminBookReport
    @GenreName NVARCHAR(100) = NULL,
    @PublisherId INT = NULL,
    @MinRating DECIMAL(4,2) = NULL,
    @OnlyWithDiscount BIT = NULL,
    @OnlyPremium BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    WITH PurchaseStats AS
    (
        SELECT
            BookId,
            COUNT(PurchaseId) AS PurchaseCount,
            CAST(ISNULL(SUM(PurchasePrice), 0) AS DECIMAL(10,2)) AS TotalSales
        FROM dbo.Purchase
        GROUP BY BookId
    )
    SELECT
        BC.BookId,
        BC.Title,
        BC.Authors,
        BC.Genres,
        BC.PublisherName,
        BC.PublicationYear,
        BC.Price,
        BC.DiscountPercent,
        BC.FinalPrice,
        BC.HasActivePromotion,
        BC.ActivePromotionName,
        BC.IsFree,
        BC.IsPremium,
        BC.IsAvailableBySubscription,
        BC.AverageRating,
        BC.ReviewCount,
        ISNULL(PS.PurchaseCount, 0) AS PurchaseCount,
        CAST(ISNULL(PS.TotalSales, 0) AS DECIMAL(10,2)) AS TotalSales
    FROM dbo.vw_BookCatalog AS BC
        LEFT JOIN PurchaseStats AS PS ON BC.BookId = PS.BookId
    WHERE (@GenreName IS NULL OR @GenreName = N'' OR BC.Genres LIKE N'%' + @GenreName + N'%')
      AND (@PublisherId IS NULL OR BC.PublisherId = @PublisherId)
      AND (@MinRating IS NULL OR BC.AverageRating >= @MinRating)
      AND (@OnlyWithDiscount IS NULL OR @OnlyWithDiscount = 0 OR BC.HasActivePromotion = 1)
      AND (@OnlyPremium IS NULL OR BC.IsPremium = @OnlyPremium)
    ORDER BY TotalSales DESC, PurchaseCount DESC, BC.AverageRating DESC, BC.Title ASC;
END;
GO

-- 24. ОТЧЁТ ПО ПОЛЬЗОВАТЕЛЯМ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_AdminUserReport
    @OnlyActive BIT = NULL,
    @MinPurchaseAmount DECIMAL(10,2) = NULL,
    @RegistrationStart DATE = NULL,
    @RegistrationEnd DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    WITH PurchaseStats AS
    (
        SELECT
            UserId,
            COUNT(PurchaseId) AS PurchaseCount,
            CAST(ISNULL(SUM(PurchasePrice), 0) AS DECIMAL(10,2)) AS TotalPurchaseAmount
        FROM dbo.Purchase
        GROUP BY UserId
    ),
    ReviewStats AS
    (
        SELECT
            UserId,
            COUNT(ReviewId) AS ReviewCount,
            CAST(ISNULL(AVG(CAST(Rating AS DECIMAL(4,2))), 0) AS DECIMAL(4,2)) AS AverageGivenRating
        FROM dbo.Review
        GROUP BY UserId
    ),
    FavoriteStats AS
    (
        SELECT UserId, COUNT(BookId) AS FavoriteCount
        FROM dbo.FavoriteBook
        GROUP BY UserId
    )
    SELECT
        U.UserId,
        U.Username,
        U.Email,
        U.DateOfBirth,
        R.RoleName,
        U.RegistrationDate,
        U.IsActive,
        dbo.fn_GetUserBalance(U.UserId) AS Balance,
        dbo.fn_GetBirthdayPromoCode(U.UserId, CAST(GETDATE() AS DATE)) AS BirthdayPromoCode,
        ISNULL(PS.PurchaseCount, 0) AS PurchaseCount,
        CAST(ISNULL(PS.TotalPurchaseAmount, 0) AS DECIMAL(10,2)) AS TotalPurchaseAmount,
        ISNULL(RS.ReviewCount, 0) AS ReviewCount,
        CAST(ISNULL(RS.AverageGivenRating, 0) AS DECIMAL(4,2)) AS AverageGivenRating,
        ISNULL(FS.FavoriteCount, 0) AS FavoriteCount,
        CASE WHEN dbo.fn_UserHasActiveSubscription(U.UserId, CAST(GETDATE() AS DATE)) = 1 THEN 1 ELSE 0 END AS ActiveSubscriptionCount
    FROM dbo.UserAccount AS U
        INNER JOIN dbo.Role AS R ON U.RoleId = R.RoleId
        LEFT JOIN PurchaseStats AS PS ON U.UserId = PS.UserId
        LEFT JOIN ReviewStats AS RS ON U.UserId = RS.UserId
        LEFT JOIN FavoriteStats AS FS ON U.UserId = FS.UserId
    WHERE (@OnlyActive IS NULL OR U.IsActive = @OnlyActive)
      AND (@MinPurchaseAmount IS NULL OR ISNULL(PS.TotalPurchaseAmount, 0) >= @MinPurchaseAmount)
      AND (@RegistrationStart IS NULL OR U.RegistrationDate >= @RegistrationStart)
      AND (@RegistrationEnd IS NULL OR U.RegistrationDate < DATEADD(DAY, 1, @RegistrationEnd))
    ORDER BY TotalPurchaseAmount DESC, PurchaseCount DESC, U.UserId ASC;
END;
GO

-- 25. ОТЧЁТ ПО ЖАНРАМ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_AdminGenreReport
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        G.GenreId,
        G.GenreName,
        COUNT(DISTINCT BG.BookId) AS BookCount,
        COUNT(DISTINCT P.PurchaseId) AS PurchaseCount,
        CAST(ISNULL(SUM(P.PurchasePrice), 0) AS DECIMAL(10,2)) AS TotalSales,
        COUNT(DISTINCT R.ReviewId) AS ReviewCount,
        CAST(ISNULL(AVG(CAST(R.Rating AS DECIMAL(4,2))), 0) AS DECIMAL(4,2)) AS AverageRating
    FROM dbo.Genre AS G
        LEFT JOIN dbo.BookGenre AS BG ON G.GenreId = BG.GenreId
        LEFT JOIN dbo.Purchase AS P
            ON BG.BookId = P.BookId
           AND (@StartDate IS NULL OR P.PurchaseDate >= @StartDate)
           AND (@EndDate IS NULL OR P.PurchaseDate < DATEADD(DAY, 1, @EndDate))
        LEFT JOIN dbo.Review AS R ON BG.BookId = R.BookId
    GROUP BY G.GenreId, G.GenreName
    ORDER BY TotalSales DESC, PurchaseCount DESC, BookCount DESC, G.GenreName ASC;
END;
GO

-- 26. ОТЧЁТ ПО ЖУРНАЛУ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_AdminAuditLogReport
    @TableName NVARCHAR(100) = NULL,
    @ActionName NVARCHAR(50) = NULL,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 200
        LogId,
        TableName,
        ActionName,
        RecordId,
        UserId,
        Description,
        CreatedAt
    FROM dbo.AuditLog
    WHERE (@TableName IS NULL OR @TableName = N'' OR TableName = @TableName)
      AND (@ActionName IS NULL OR @ActionName = N'' OR ActionName = @ActionName)
      AND (@StartDate IS NULL OR CreatedAt >= @StartDate)
      AND (@EndDate IS NULL OR CreatedAt < DATEADD(DAY, 1, @EndDate))
    ORDER BY CreatedAt DESC, LogId DESC;
END;
GO

SELECT ROUTINE_SCHEMA, ROUTINE_NAME, ROUTINE_TYPE
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_TYPE = 'PROCEDURE'
ORDER BY ROUTINE_NAME;
GO
