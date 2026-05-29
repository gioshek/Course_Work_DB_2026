USE [BookStreamDB];
GO

/*
    06_procedures.sql

    Хранимые процедуры для BookStreamDB.
    Версия без THROW, через RAISERROR, чтобы VS Code не ругался в Problems.
*/

-- 1. ПОЛУЧЕНИЕ КАТАЛОГА КНИГ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetBookCatalog
    @SearchText NVARCHAR(255) = NULL,
    @GenreName NVARCHAR(100) = NULL,
    @OnlyFree BIT = NULL,
    @AvailableBySubscription BIT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        BookId,
        Title,
        Description,
        Authors,
        Genres,
        PublisherName,
        PublicationYear,
        AgeLimit,
        PageCount,
        Price,
        DiscountPercent,
        FinalPrice,
        HasActivePromotion,
        ActivePromotionName,
        ActivePromoCode,
        IsFree,
        IsAvailableBySubscription,
        CoverImageUrl,
        AverageRating,
        ReviewCount,
        CreatedAt
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
    ORDER BY
        HasActivePromotion DESC,
        DiscountPercent DESC,
        AverageRating DESC,
        ReviewCount DESC,
        Title ASC;
END;
GO

-- 2. ПОЛУЧЕНИЕ КНИГИ ПО ID //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetBookById
    @BookId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1
    FROM dbo.Book
    WHERE BookId = @BookId)
    BEGIN
        RAISERROR(N'Книга с указанным BookId не найдена.', 16, 1);
        RETURN;
    END;

    SELECT
        BookId,
        Title,
        Description,
        Authors,
        Genres,
        PublisherName,
        PublicationYear,
        AgeLimit,
        PageCount,
        Price,
        DiscountPercent,
        FinalPrice,
        HasActivePromotion,
        ActivePromotionName,
        ActivePromoCode,
        IsFree,
        IsAvailableBySubscription,
        CoverImageUrl,
        AverageRating,
        ReviewCount,
        CreatedAt
    FROM dbo.vw_BookCatalog
    WHERE BookId = @BookId;

    SELECT
        ReviewId,
        BookId,
        BookTitle,
        UserId,
        Username,
        Rating,
        ReviewText,
        CreatedAt
    FROM dbo.vw_BookReviews
    WHERE BookId = @BookId
    ORDER BY CreatedAt DESC;
END;
GO

-- 3. ПОЛУЧЕНИЕ БИБЛИОТЕКИ ПОЛЬЗОВАТЕЛЯ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetUserLibrary
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT
        B.BookId,
        B.Title,
        B.CoverImageUrl,
        P.PublisherName,
        B.PublicationYear,
        B.PageCount,
        B.Price,
        B.IsFree,
        B.IsAvailableBySubscription,
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
                THEN N'Куплена'

            WHEN B.IsAvailableBySubscription = 1
                 AND EXISTS
                 (
                    SELECT 1
                    FROM dbo.UserSubscription AS US
                    WHERE US.UserId = @UserId
                      AND US.IsActive = 1
                      AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate
                 )
                THEN N'По подписке'

            ELSE N'Нет доступа'
        END AS AccessType
    FROM dbo.Book AS B
        INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId
    WHERE
        B.IsFree = 1
        OR EXISTS
        (
            SELECT 1
            FROM dbo.Purchase AS PR
            WHERE PR.UserId = @UserId
              AND PR.BookId = B.BookId
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
                  AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate
            )
        )
    ORDER BY B.Title;
END;
GO

-- 4. РЕГИСТРАЦИЯ ПОЛЬЗОВАТЕЛЯ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_RegisterUser
    @Username NVARCHAR(100),
    @Email NVARCHAR(255),
    @PasswordHash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserRoleId INT;

    SELECT @UserRoleId = RoleId
    FROM dbo.Role
    WHERE RoleName = N'User';

    IF @UserRoleId IS NULL
    BEGIN
        RAISERROR(N'Роль User не найдена.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1
    FROM dbo.UserAccount
    WHERE Username = @Username)
    BEGIN
        RAISERROR(N'Пользователь с таким Username уже существует.', 16, 1);
        RETURN;
    END;

    IF EXISTS (SELECT 1
    FROM dbo.UserAccount
    WHERE Email = @Email)
    BEGIN
        RAISERROR(N'Пользователь с таким Email уже существует.', 16, 1);
        RETURN;
    END;

    INSERT INTO dbo.UserAccount
        (RoleId, Username, Email, PasswordHash, Balance)
    VALUES
        (@UserRoleId, @Username, @Email, @PasswordHash, 0);

    SELECT
        UserId,
        RoleId,
        Username,
        Email,
        RegistrationDate,
        IsActive,
        Balance
    FROM dbo.UserAccount
    WHERE UserId = SCOPE_IDENTITY();
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

    IF NOT EXISTS (SELECT 1
    FROM dbo.UserAccount
    WHERE UserId = @UserId AND IsActive = 1)
    BEGIN
        RAISERROR(N'Активный пользователь с указанным UserId не найден.', 16, 1);
        RETURN;
    END;

    IF @PaymentMethod NOT IN (N'Card', N'OnlineWallet', N'Bonus')
    BEGIN
        RAISERROR(N'Недопустимый способ пополнения баланса.', 16, 1);
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
            U.Balance,
            P.PaymentId,
            P.Amount,
            P.PaymentMethod,
            P.PaymentStatus,
            P.TransactionNumber
        FROM dbo.UserAccount AS U
            INNER JOIN dbo.Payment AS P ON U.UserId = P.UserId
        WHERE U.UserId = @UserId
            AND P.PaymentId = @NewPaymentId;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN;
    END CATCH;
END;
GO

-- 6. ПОКУПКА КНИГИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_BuyBook
    @UserId INT,
    @BookId INT,
    @PaymentMethod NVARCHAR(50) = N'Balance'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BasePrice DECIMAL(10,2);
    DECLARE @FinalPrice DECIMAL(10,2);
    DECLARE @DiscountPercent DECIMAL(5,2);
    DECLARE @IsFree BIT;
    DECLARE @UserBalance DECIMAL(10,2);
    DECLARE @NewPaymentId INT;
    DECLARE @NewPurchaseId INT;
    DECLARE @TransactionNumber NVARCHAR(100);

    IF NOT EXISTS (SELECT 1
    FROM dbo.UserAccount
    WHERE UserId = @UserId AND IsActive = 1)
    BEGIN
        RAISERROR(N'Активный пользователь с указанным UserId не найден.', 16, 1);
        RETURN;
    END;

    SELECT
        @BasePrice = Price,
        @IsFree = IsFree
    FROM dbo.Book
    WHERE BookId = @BookId;

    IF @BasePrice IS NULL
    BEGIN
        RAISERROR(N'Книга с указанным BookId не найдена.', 16, 1);
        RETURN;
    END;

    IF @PaymentMethod NOT IN (N'Balance', N'Bonus')
    BEGIN
        RAISERROR(N'Покупка книги должна выполняться с внутреннего баланса.', 16, 1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
    FROM dbo.Purchase
    WHERE UserId = @UserId
        AND BookId = @BookId
    )
    BEGIN
        RAISERROR(N'Пользователь уже купил эту книгу.', 16, 1);
        RETURN;
    END;

    SELECT
        @DiscountPercent = ISNULL(MAX(P.DiscountPercent), 0)
    FROM dbo.BookPromotion AS BP
        INNER JOIN dbo.Promotion AS P ON BP.PromotionId = P.PromotionId
    WHERE BP.BookId = @BookId
      AND P.IsActive = 1
      AND CAST(GETDATE() AS DATE) BETWEEN P.StartDate AND P.EndDate;

    SET @DiscountPercent = ISNULL(@DiscountPercent, 0);

    IF @IsFree = 1
        SET @FinalPrice = 0;
    ELSE
        SET @FinalPrice = ROUND(@BasePrice * (100 - @DiscountPercent) / 100, 2);

    SELECT @UserBalance = Balance
    FROM dbo.UserAccount
    WHERE UserId = @UserId;

    IF @IsFree = 0 AND @UserBalance < @FinalPrice
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
    END
        ELSE
        BEGIN
        SET @NewPaymentId = NULL;
    END;

        INSERT INTO dbo.Purchase
        (UserId, BookId, PaymentId, PurchasePrice)
    VALUES
        (@UserId, @BookId, @NewPaymentId, @FinalPrice);

        SET @NewPurchaseId = CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;

        SELECT
        P.PurchaseId,
        P.UserId,
        U.Username,
        U.Balance,
        P.BookId,
        B.Title,
        @BasePrice AS BasePrice,
        @DiscountPercent AS DiscountPercent,
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

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN;
    END CATCH;
END;
GO

-- 7. ОФОРМЛЕНИЕ ПОДПИСКИ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_CreateSubscription
    @UserId INT,
    @PlanId INT,
    @PaymentMethod NVARCHAR(50) = N'Balance'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PlanPrice DECIMAL(10,2);
    DECLARE @DurationDays INT;
    DECLARE @UserBalance DECIMAL(10,2);
    DECLARE @NewPaymentId INT;
    DECLARE @NewSubscriptionId INT;
    DECLARE @StartDate DATE;
    DECLARE @EndDate DATE;
    DECLARE @TransactionNumber NVARCHAR(100);

    IF NOT EXISTS (SELECT 1
    FROM dbo.UserAccount
    WHERE UserId = @UserId AND IsActive = 1)
    BEGIN
        RAISERROR(N'Активный пользователь с указанным UserId не найден.', 16, 1);
        RETURN;
    END;

    SELECT
        @PlanPrice = Price,
        @DurationDays = DurationDays
    FROM dbo.SubscriptionPlan
    WHERE PlanId = @PlanId
        AND IsActive = 1;

    IF @PlanPrice IS NULL
    BEGIN
        RAISERROR(N'Активный тариф подписки с указанным PlanId не найден.', 16, 1);
        RETURN;
    END;

    IF @PaymentMethod NOT IN (N'Balance', N'Bonus')
    BEGIN
        RAISERROR(N'Подписка должна оплачиваться с внутреннего баланса.', 16, 1);
        RETURN;
    END;

    SELECT @UserBalance = Balance
    FROM dbo.UserAccount
    WHERE UserId = @UserId;

    IF @PlanPrice > 0 AND @UserBalance < @PlanPrice
    BEGIN
        RAISERROR(N'Недостаточно средств на балансе для оформления подписки.', 16, 1);
        RETURN;
    END;

    SET @StartDate = CAST(GETDATE() AS DATE);
    SET @EndDate = DATEADD(DAY, @DurationDays, @StartDate);
    SET @TransactionNumber = N'TRX-SUB-' + CONVERT(NVARCHAR(36), NEWID());

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @PlanPrice > 0
        BEGIN
            UPDATE dbo.UserAccount
            SET Balance = Balance - @PlanPrice
            WHERE UserId = @UserId;

            INSERT INTO dbo.Payment
                (UserId, Amount, PaymentMethod, PaymentStatus, TransactionNumber)
            VALUES
                (@UserId, @PlanPrice, @PaymentMethod, N'Success', @TransactionNumber);

            SET @NewPaymentId = CONVERT(INT, SCOPE_IDENTITY());
        END
        ELSE
        BEGIN
            SET @NewPaymentId = NULL;
        END;

        INSERT INTO dbo.UserSubscription
            (UserId, PlanId, PaymentId, StartDate, EndDate, IsActive)
        VALUES
            (@UserId, @PlanId, @NewPaymentId, @StartDate, @EndDate, 1);

        SET @NewSubscriptionId = CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;

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
        WHERE US.SubscriptionId = @NewSubscriptionId;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN;
    END CATCH;
END;
GO

-- 8. ДОБАВЛЕНИЕ ИЛИ ОБНОВЛЕНИЕ ОТЗЫВА //////////////////////////////

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
        RAISERROR(N'Рейтинг должен быть от 1 до 5.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1
    FROM dbo.UserAccount
    WHERE UserId = @UserId AND IsActive = 1)
    BEGIN
        RAISERROR(N'Активный пользователь с указанным UserId не найден.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1
    FROM dbo.Book
    WHERE BookId = @BookId)
    BEGIN
        RAISERROR(N'Книга с указанным BookId не найдена.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
    FROM dbo.Book AS B
    WHERE B.BookId = @BookId
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
            AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate
                    )
                )
          )
    )
    BEGIN
        RAISERROR(N'Пользователь не имеет доступа к этой книге и не может оставить отзыв.', 16, 1);
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
    FROM dbo.Review
    WHERE UserId = @UserId
        AND BookId = @BookId
    )
    BEGIN
        UPDATE dbo.Review
        SET
            Rating = @Rating,
            ReviewText = @ReviewText,
            CreatedAt = SYSDATETIME()
        WHERE UserId = @UserId
            AND BookId = @BookId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.Review
            (UserId, BookId, Rating, ReviewText)
        VALUES
            (@UserId, @BookId, @Rating, @ReviewText);
    END;

    SELECT
        ReviewId,
        UserId,
        BookId,
        Rating,
        ReviewText,
        CreatedAt
    FROM dbo.Review
    WHERE UserId = @UserId
        AND BookId = @BookId;
END;
GO

-- 9. ОБНОВЛЕНИЕ ПРОГРЕССА ЧТЕНИЯ //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_UpdateReadingProgress
    @UserId INT,
    @BookId INT,
    @CurrentPage INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PageCount INT;
    DECLARE @ProgressPercent DECIMAL(5,2);

    IF NOT EXISTS (SELECT 1
    FROM dbo.UserAccount
    WHERE UserId = @UserId AND IsActive = 1)
    BEGIN
        RAISERROR(N'Активный пользователь с указанным UserId не найден.', 16, 1);
        RETURN;
    END;

    SELECT @PageCount = PageCount
    FROM dbo.Book
    WHERE BookId = @BookId;

    IF @PageCount IS NULL
    BEGIN
        RAISERROR(N'Книга с указанным BookId не найдена.', 16, 1);
        RETURN;
    END;

    IF @CurrentPage < 1 OR @CurrentPage > @PageCount
    BEGIN
        RAISERROR(N'Текущая страница должна быть в пределах количества страниц книги.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
    FROM dbo.Book AS B
    WHERE B.BookId = @BookId
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
            AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate
                    )
                )
          )
    )
    BEGIN
        RAISERROR(N'Пользователь не имеет доступа к этой книге.', 16, 1);
        RETURN;
    END;

    SET @ProgressPercent = CAST((CAST(@CurrentPage AS DECIMAL(10,2)) / @PageCount) * 100 AS DECIMAL(5,2));

    IF EXISTS
    (
        SELECT 1
    FROM dbo.ReadingProgress
    WHERE UserId = @UserId
        AND BookId = @BookId
    )
    BEGIN
        UPDATE dbo.ReadingProgress
        SET
            CurrentPage = @CurrentPage,
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

    SELECT
        ProgressId,
        UserId,
        BookId,
        CurrentPage,
        ProgressPercent,
        LastReadAt
    FROM dbo.ReadingProgress
    WHERE UserId = @UserId
        AND BookId = @BookId;
END;
GO

-- 10. ПОЛУЧЕНИЕ СОДЕРЖИМОГО КНИГИ С ПРОВЕРКОЙ ДОСТУПА //////////////////////////////

CREATE OR ALTER PROCEDURE dbo.usp_GetBookContentForUser
    @UserId INT,
    @BookId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1
    FROM dbo.UserAccount
    WHERE UserId = @UserId AND IsActive = 1)
    BEGIN
        RAISERROR(N'Активный пользователь с указанным UserId не найден.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1
    FROM dbo.Book
    WHERE BookId = @BookId)
    BEGIN
        RAISERROR(N'Книга с указанным BookId не найдена.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
    FROM dbo.Book AS B
    WHERE B.BookId = @BookId
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
            AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate
                    )
                )
          )
    )
    BEGIN
        RAISERROR(N'Пользователь не имеет доступа к содержимому этой книги.', 16, 1);
        RETURN;
    END;

    SELECT
        B.BookId,
        B.Title,
        BC.ContentText,
        BC.ContentFormat,
        RP.CurrentPage,
        RP.ProgressPercent,
        RP.LastReadAt
    FROM dbo.Book AS B
        INNER JOIN dbo.BookContent AS BC ON B.BookId = BC.BookId
        LEFT JOIN dbo.ReadingProgress AS RP
        ON B.BookId = RP.BookId
            AND RP.UserId = @UserId
    WHERE B.BookId = @BookId;
END;
GO

-- 11. УПРАВЛЕНИЕ АКЦИЯМИ И ОТЧЁТЫ АДМИНИСТРАТОРА //////////////////////////////

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
        P.CreatedAt,
        COUNT(BP.BookId) AS BookCount
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
        P.CreatedAt
    ORDER BY
        P.IsActive DESC,
        P.StartDate DESC,
        P.PromotionId DESC;

    SELECT
        BP.PromotionId,
        P.PromotionName,
        P.PromoCode,
        BP.BookId,
        B.Title,
        B.Price,
        ISNULL(V.FinalPrice, B.Price) AS FinalPrice,
        BP.AssignedAt
    FROM dbo.BookPromotion AS BP
        INNER JOIN dbo.Promotion AS P ON BP.PromotionId = P.PromotionId
        INNER JOIN dbo.Book AS B ON BP.BookId = B.BookId
        LEFT JOIN dbo.vw_BookCatalog AS V ON B.BookId = V.BookId
    ORDER BY
        P.PromotionId DESC,
        B.Title ASC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_CreatePromotion
    @PromotionName NVARCHAR(255),
    @PromoCode NVARCHAR(50),
    @DiscountPercent DECIMAL(5,2),
    @StartDate DATE,
    @EndDate DATE,
    @IsActive BIT = 1
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
    WHERE PromoCode = @PromoCode;

    IF @PromotionId IS NULL
    BEGIN
        INSERT INTO dbo.Promotion
            (PromotionName, PromoCode, DiscountPercent, StartDate, EndDate, IsActive)
        VALUES
            (@PromotionName, @PromoCode, @DiscountPercent, @StartDate, @EndDate, @IsActive);

        SET @PromotionId = CONVERT(INT, SCOPE_IDENTITY());
    END
    ELSE
    BEGIN
        UPDATE dbo.Promotion
        SET
            PromotionName = @PromotionName,
            DiscountPercent = @DiscountPercent,
            StartDate = @StartDate,
            EndDate = @EndDate,
            IsActive = @IsActive
        WHERE PromotionId = @PromotionId;
    END;

    SELECT
        PromotionId,
        PromotionName,
        PromoCode,
        DiscountPercent,
        StartDate,
        EndDate,
        IsActive,
        CreatedAt
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

    IF NOT EXISTS (SELECT 1
    FROM dbo.Promotion
    WHERE PromotionId = @PromotionId)
    BEGIN
        RAISERROR(N'Акция с указанным PromotionId не найдена.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1
    FROM dbo.Book
    WHERE BookId = @BookId)
    BEGIN
        RAISERROR(N'Книга с указанным BookId не найдена.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1
    FROM dbo.BookPromotion
    WHERE PromotionId = @PromotionId
        AND BookId = @BookId
    )
    BEGIN
        INSERT INTO dbo.BookPromotion
            (PromotionId, BookId)
        VALUES
            (@PromotionId, @BookId);
    END;

    SELECT
        BP.PromotionId,
        P.PromotionName,
        P.PromoCode,
        P.DiscountPercent,
        BP.BookId,
        B.Title,
        B.Price,
        ISNULL(V.FinalPrice, B.Price) AS FinalPrice,
        BP.AssignedAt
    FROM dbo.BookPromotion AS BP
        INNER JOIN dbo.Promotion AS P ON BP.PromotionId = P.PromotionId
        INNER JOIN dbo.Book AS B ON BP.BookId = B.BookId
        LEFT JOIN dbo.vw_BookCatalog AS V ON B.BookId = V.BookId
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

    SELECT
        @PromotionId AS PromotionId,
        @BookId AS BookId,
        N'Книга удалена из акции' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminSalesReport
    @StartDate DATE = NULL,
    @EndDate DATE = NULL,
    @GroupBy NVARCHAR(20) = N'Book'
AS
BEGIN
    SET NOCOUNT ON;

    IF @GroupBy IS NULL OR @GroupBy NOT IN (N'Book', N'User', N'Day')
        SET @GroupBy = N'Book';

    IF @GroupBy = N'Book'
    BEGIN
        SELECT
            B.BookId,
            B.Title,
            COUNT(P.PurchaseId) AS PurchaseCount,
            CAST(ISNULL(SUM(P.PurchasePrice), 0) AS DECIMAL(10,2)) AS TotalSales,
            CAST(ISNULL(AVG(CAST(P.PurchasePrice AS DECIMAL(10,2))), 0) AS DECIMAL(10,2)) AS AveragePurchasePrice,
            MIN(P.PurchaseDate) AS FirstPurchaseDate,
            MAX(P.PurchaseDate) AS LastPurchaseDate
        FROM dbo.Purchase AS P
            INNER JOIN dbo.Book AS B ON P.BookId = B.BookId
        WHERE (@StartDate IS NULL OR P.PurchaseDate >= @StartDate)
          AND (@EndDate IS NULL OR P.PurchaseDate < DATEADD(DAY, 1, @EndDate))
        GROUP BY B.BookId, B.Title
        ORDER BY TotalSales DESC, PurchaseCount DESC, B.Title ASC;

        RETURN;
    END;

    IF @GroupBy = N'User'
    BEGIN
        SELECT
            U.UserId,
            U.Username,
            U.Email,
            COUNT(P.PurchaseId) AS PurchaseCount,
            CAST(ISNULL(SUM(P.PurchasePrice), 0) AS DECIMAL(10,2)) AS TotalSales,
            CAST(ISNULL(AVG(CAST(P.PurchasePrice AS DECIMAL(10,2))), 0) AS DECIMAL(10,2)) AS AveragePurchasePrice,
            MIN(P.PurchaseDate) AS FirstPurchaseDate,
            MAX(P.PurchaseDate) AS LastPurchaseDate
        FROM dbo.Purchase AS P
            INNER JOIN dbo.UserAccount AS U ON P.UserId = U.UserId
        WHERE (@StartDate IS NULL OR P.PurchaseDate >= @StartDate)
          AND (@EndDate IS NULL OR P.PurchaseDate < DATEADD(DAY, 1, @EndDate))
        GROUP BY U.UserId, U.Username, U.Email
        ORDER BY TotalSales DESC, PurchaseCount DESC, U.Username ASC;

        RETURN;
    END;

    IF @GroupBy = N'Day'
    BEGIN
        SELECT
            CAST(P.PurchaseDate AS DATE) AS SaleDate,
            COUNT(P.PurchaseId) AS PurchaseCount,
            CAST(ISNULL(SUM(P.PurchasePrice), 0) AS DECIMAL(10,2)) AS TotalSales,
            CAST(ISNULL(AVG(CAST(P.PurchasePrice AS DECIMAL(10,2))), 0) AS DECIMAL(10,2)) AS AveragePurchasePrice
        FROM dbo.Purchase AS P
        WHERE (@StartDate IS NULL OR P.PurchaseDate >= @StartDate)
          AND (@EndDate IS NULL OR P.PurchaseDate < DATEADD(DAY, 1, @EndDate))
        GROUP BY CAST(P.PurchaseDate AS DATE)
        ORDER BY SaleDate DESC;

        RETURN;
    END;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_AdminBookReport
    @GenreName NVARCHAR(100) = NULL,
    @PublisherId INT = NULL,
    @MinRating DECIMAL(4,2) = NULL,
    @OnlyWithDiscount BIT = NULL
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
        BC.IsAvailableBySubscription,
        CAST(ISNULL(BC.AverageRating, 0) AS DECIMAL(4,2)) AS AverageRating,
        ISNULL(BC.ReviewCount, 0) AS ReviewCount,
        ISNULL(PS.PurchaseCount, 0) AS PurchaseCount,
        CAST(ISNULL(PS.TotalSales, 0) AS DECIMAL(10,2)) AS TotalSales
    FROM dbo.vw_BookCatalog AS BC
        INNER JOIN dbo.Book AS B ON BC.BookId = B.BookId
        LEFT JOIN PurchaseStats AS PS ON BC.BookId = PS.BookId
    WHERE (@GenreName IS NULL OR @GenreName = N'' OR BC.Genres LIKE N'%' + @GenreName + N'%')
      AND (@PublisherId IS NULL OR B.PublisherId = @PublisherId)
      AND (@MinRating IS NULL OR ISNULL(BC.AverageRating, 0) >= @MinRating)
      AND (@OnlyWithDiscount IS NULL OR @OnlyWithDiscount = 0 OR BC.HasActivePromotion = 1)
    ORDER BY
        ISNULL(PS.TotalSales, 0) DESC,
        ISNULL(PS.PurchaseCount, 0) DESC,
        ISNULL(BC.AverageRating, 0) DESC,
        BC.Title ASC;
END;
GO

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
        SELECT
            UserId,
            COUNT(BookId) AS FavoriteCount
        FROM dbo.FavoriteBook
        GROUP BY UserId
    ),
    ActiveSubscriptions AS
    (
        SELECT
            UserId,
            COUNT(SubscriptionId) AS ActiveSubscriptionCount
        FROM dbo.UserSubscription
        WHERE IsActive = 1
          AND CAST(GETDATE() AS DATE) BETWEEN StartDate AND EndDate
        GROUP BY UserId
    )
    SELECT
        U.UserId,
        U.Username,
        U.Email,
        R.RoleName,
        U.RegistrationDate,
        U.IsActive,
        U.Balance,
        ISNULL(PS.PurchaseCount, 0) AS PurchaseCount,
        CAST(ISNULL(PS.TotalPurchaseAmount, 0) AS DECIMAL(10,2)) AS TotalPurchaseAmount,
        ISNULL(RS.ReviewCount, 0) AS ReviewCount,
        CAST(ISNULL(RS.AverageGivenRating, 0) AS DECIMAL(4,2)) AS AverageGivenRating,
        ISNULL(FS.FavoriteCount, 0) AS FavoriteCount,
        ISNULL(ASB.ActiveSubscriptionCount, 0) AS ActiveSubscriptionCount
    FROM dbo.UserAccount AS U
        INNER JOIN dbo.Role AS R ON U.RoleId = R.RoleId
        LEFT JOIN PurchaseStats AS PS ON U.UserId = PS.UserId
        LEFT JOIN ReviewStats AS RS ON U.UserId = RS.UserId
        LEFT JOIN FavoriteStats AS FS ON U.UserId = FS.UserId
        LEFT JOIN ActiveSubscriptions AS ASB ON U.UserId = ASB.UserId
    WHERE (@OnlyActive IS NULL OR U.IsActive = @OnlyActive)
      AND (@MinPurchaseAmount IS NULL OR ISNULL(PS.TotalPurchaseAmount, 0) >= @MinPurchaseAmount)
      AND (@RegistrationStart IS NULL OR U.RegistrationDate >= @RegistrationStart)
      AND (@RegistrationEnd IS NULL OR U.RegistrationDate < DATEADD(DAY, 1, @RegistrationEnd))
    ORDER BY
        ISNULL(PS.TotalPurchaseAmount, 0) DESC,
        ISNULL(PS.PurchaseCount, 0) DESC,
        U.UserId ASC;
END;
GO

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

CREATE OR ALTER PROCEDURE dbo.usp_DeletePromotion
    @PromotionId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PromotionName NVARCHAR(255);
    DECLARE @PromoCode NVARCHAR(50);
    DECLARE @DiscountPercent DECIMAL(5,2);
    DECLARE @LinkedBookCount INT;

    SELECT
        @PromotionName = PromotionName,
        @PromoCode = PromoCode,
        @DiscountPercent = DiscountPercent
    FROM dbo.Promotion
    WHERE PromotionId = @PromotionId;

    IF @PromotionName IS NULL
    BEGIN
        RAISERROR(N'Акция с указанным PromotionId не найдена.', 16, 1);
        RETURN;
    END;

    SELECT
        @LinkedBookCount = COUNT(*)
    FROM dbo.BookPromotion
    WHERE PromotionId = @PromotionId;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        VALUES
            (
                N'Promotion',
                N'DELETE',
                @PromotionId,
                NULL,
                CONCAT
                (
                    N'Удалена акция: ', @PromotionName,
                    N'. Промокод: ', @PromoCode,
                    N'. Скидка: ', CONVERT(NVARCHAR(20), @DiscountPercent), N'%.',
                    N' Связанных книг до удаления: ', CONVERT(NVARCHAR(20), @LinkedBookCount), N'.'
                )
            );

        DELETE FROM dbo.Promotion
        WHERE PromotionId = @PromotionId;

        COMMIT TRANSACTION;

        SELECT
            @PromotionId AS PromotionId,
            @PromotionName AS PromotionName,
            @PromoCode AS PromoCode,
            @LinkedBookCount AS RemovedBookLinks,
            N'Акция удалена' AS Message;
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000);

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @ErrorMessage = ERROR_MESSAGE();
        RAISERROR(@ErrorMessage, 16, 1);
        RETURN;
    END CATCH;
END;
GO

-- ПРОВЕРКА СОЗДАННЫХ ПРОЦЕДУР //////////////////////////////

SELECT
    ROUTINE_SCHEMA,
    ROUTINE_NAME,
    ROUTINE_TYPE
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_TYPE = 'PROCEDURE'
ORDER BY ROUTINE_NAME;
GO

-- БЕЗОПАСНЫЕ ТЕСТЫ ПРОЦЕДУР //////////////////////////////

EXEC dbo.usp_GetBookCatalog;
GO

EXEC dbo.usp_GetBookCatalog @SearchText = N'1984';
GO

EXEC dbo.usp_GetBookCatalog @GenreName = N'Фантастика';
GO

EXEC dbo.usp_GetBookById @BookId = 1;
GO

EXEC dbo.usp_GetUserLibrary @UserId = 2;
GO

EXEC dbo.usp_GetBookContentForUser @UserId = 2, @BookId = 1;
GO

EXEC dbo.usp_GetPromotions;
GO

EXEC dbo.usp_AdminSalesReport @StartDate = NULL, @EndDate = NULL, @GroupBy = N'Book';
GO

EXEC dbo.usp_AdminBookReport @GenreName = NULL, @PublisherId = NULL, @MinRating = NULL, @OnlyWithDiscount = NULL;
GO

EXEC dbo.usp_AdminUserReport @OnlyActive = NULL, @MinPurchaseAmount = NULL, @RegistrationStart = NULL, @RegistrationEnd = NULL;
GO

EXEC dbo.usp_AdminGenreReport @StartDate = NULL, @EndDate = NULL;
GO

EXEC dbo.usp_AdminAuditLogReport @TableName = NULL, @ActionName = NULL, @StartDate = NULL, @EndDate = NULL;
GO

-- ПРОЦЕДУРЫ, КОТОРЫЕ МЕНЯЮТ ДАННЫЕ //////////////////////////////
-- Пока оставлены закомментированными.

-- EXEC dbo.usp_RegisterUser
--     @Username = N'test_user',
--     @Email = N'test_user@example.com',
--     @PasswordHash = N'hashed_test_password';
-- GO

-- EXEC dbo.usp_TopUpBalance
--     @UserId = 2,
--     @Amount = 500.00,
--     @PaymentMethod = N'Card';
-- GO

-- EXEC dbo.usp_BuyBook
--     @UserId = 2,
--     @BookId = 2,
--     @PaymentMethod = N'Balance';
-- GO

-- EXEC dbo.usp_CreateSubscription
--     @UserId = 3,
--     @PlanId = 1,
--     @PaymentMethod = N'Balance';
-- GO

-- EXEC dbo.usp_AddReview
--     @UserId = 2,
--     @BookId = 2,
--     @Rating = 5,
--     @ReviewText = N'Отличная книга, понравилась атмосфера.';
-- GO

-- EXEC dbo.usp_UpdateReadingProgress
--     @UserId = 2,
--     @BookId = 1,
--     @CurrentPage = 200;
-- GO
