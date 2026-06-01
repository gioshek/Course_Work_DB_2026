USE [BookStreamDB];
GO

/*
    08_insert_test_data.sql

    Тестовые данные для демонстрации пользовательского сайта и админки.
    Скрипт можно запускать повторно: старые демонстрационные данные удаляются,
    а идентификаторы задаются явно, чтобы внешние ключи не зависели
    от текущего состояния счётчиков IDENTITY.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- ОЧИСТКА //////////////////////////////

    DELETE FROM dbo.ReadingProgress;
    DELETE FROM dbo.FavoriteBook;
    DELETE FROM dbo.Review;
    DELETE FROM dbo.UserSubscription;
    DELETE FROM dbo.Purchase;
    DELETE FROM dbo.Payment;
    DELETE FROM dbo.BookContent;
    DELETE FROM dbo.BookPromotion;
    DELETE FROM dbo.Promotion;
    DELETE FROM dbo.BookGenre;
    DELETE FROM dbo.BookAuthor;
    DELETE FROM dbo.Book;
    DELETE FROM dbo.SubscriptionPlan;
    DELETE FROM dbo.Genre;
    DELETE FROM dbo.Author;
    DELETE FROM dbo.Publisher;
    DELETE FROM dbo.UserAccount;
    DELETE FROM dbo.Role;

    -- Триггеры могли добавить записи во время очистки.
    DELETE FROM dbo.AuditLog;

    -- 1. РОЛИ //////////////////////////////

    SET IDENTITY_INSERT dbo.Role ON;

    INSERT INTO dbo.Role
    (RoleId, RoleName)
VALUES
    (1, N'Admin'),
    (2, N'User');

    SET IDENTITY_INSERT dbo.Role OFF;

    -- 2. ПОЛЬЗОВАТЕЛИ //////////////////////////////

    SET IDENTITY_INSERT dbo.UserAccount ON;

    INSERT INTO dbo.UserAccount
    (UserId, RoleId, Username, Email, PasswordHash, DateOfBirth, Balance)
VALUES
    (1, 1, N'admin', N'admin@bookstream.com', N'admin123', '1990-01-01', 5000.00),
    (2, 2, N'giorgi', N'giorgi@example.com', N'1234', DATEFROMPARTS(2002, MONTH(GETDATE()), DAY(GETDATE())), 1102.00),
    (3, 2, N'anna_reader', N'anna@example.com', N'1234', '2001-09-15', 901.00),
    (4, 2, N'besik_books', N'besik_books@example.com', N'1234', '2002-05-10', 501.00);

    SET IDENTITY_INSERT dbo.UserAccount OFF;

    -- 3. ИЗДАТЕЛЬСТВА //////////////////////////////

    SET IDENTITY_INSERT dbo.Publisher ON;

    INSERT INTO dbo.Publisher
    (PublisherId, PublisherName)
VALUES
    (1, N'Азбука'),
    (2, N'Эксмо'),
    (3, N'Penguin Classics'),
    (4, N'Manga Digital Press');

    SET IDENTITY_INSERT dbo.Publisher OFF;

    -- 4. АВТОРЫ //////////////////////////////

    SET IDENTITY_INSERT dbo.Author ON;

    INSERT INTO dbo.Author
    (AuthorId, FirstName, LastName)
VALUES
    (1, N'Фёдор', N'Достоевский'),
    (2, N'Михаил', N'Булгаков'),
    (3, N'Джордж', N'Оруэлл'),
    (4, N'Джейн', N'Остин'),
    (5, N'Лю', N'Цысинь'),
    (6, N'Макото', N'Юкимура'),
    (7, N'Лев', N'Толстой');

    SET IDENTITY_INSERT dbo.Author OFF;

    -- 5. ЖАНРЫ //////////////////////////////

    SET IDENTITY_INSERT dbo.Genre ON;

    INSERT INTO dbo.Genre
    (GenreId, GenreName)
VALUES
    (1, N'Классика'),
    (2, N'Фантастика'),
    (3, N'Антиутопия'),
    (4, N'Роман'),
    (5, N'Историческое'),
    (6, N'Манга'),
    (7, N'Драма'),
    (8, N'Приключения'),
    (9, N'Роман-эпопея');

    SET IDENTITY_INSERT dbo.Genre OFF;

    -- 6. КНИГИ //////////////////////////////

    SET IDENTITY_INSERT dbo.Book ON;

    INSERT INTO dbo.Book
    (BookId, PublisherId, Title, Description, PublicationYear, AgeLimit, PageCount, Price, IsFree, IsPremium, IsAvailableBySubscription, CoverImageUrl)
VALUES
    (1, 1, N'Преступление и наказание', N'Психологический роман о преступлении, вине и нравственном выборе.', 1866, 16, 672, 399.00, 0, 0, 1, N'/covers/crime_and_punishment.jpg'),
    (2, 2, N'Мастер и Маргарита', N'Роман, соединяющий сатиру, мистику, философию и историю любви.', 1967, 16, 480, 449.00, 0, 0, 1, N'/covers/master_margarita.jpg'),
    (3, 3, N'1984', N'Антиутопия о тоталитарном обществе, контроле информации и свободе личности.', 1949, 16, 328, 299.00, 0, 0, 1, N'/covers/1984.jpg'),
    (4, 3, N'Гордость и предубеждение', N'Классический роман о любви, социальных условностях и личном достоинстве.', 1813, 12, 416, 0.00, 1, 0, 1, NULL),
    (5, 2, N'Задача трёх тел', N'Научно-фантастический роман о первом контакте человечества с иной цивилизацией.', 2008, 16, 512, 599.00, 0, 0, 1, N'/covers/three_body_problem.jpeg'),
    (6, 4, N'Сага о Винланде. Том 1', N'Историческая манга о викингах, мести, взрослении и поиске смысла жизни.', 2005, 18, 220, 699.00, 0, 1, 0, N'/covers/vinland_saga.jpg'),
    (7, 1, N'Война и мир. Том 1', N'Великая классика: роман-эпопея о людях, истории, любви и нравственном поиске.', 1865, 12, 480, 550.00, 0, 1, 0, N'/covers/war_and_piece.jpg');

    SET IDENTITY_INSERT dbo.Book OFF;

    -- 7. АВТОРЫ КНИГ //////////////////////////////

    INSERT INTO dbo.BookAuthor
    (BookId, AuthorId)
VALUES
    (1, 1),
    (2, 2),
    (3, 3),
    (4, 4),
    (5, 5),
    (6, 6),
    (7, 7);

    -- 8. ЖАНРЫ КНИГ //////////////////////////////

    INSERT INTO dbo.BookGenre
    (BookId, GenreId)
VALUES
    (1, 1),
    (1, 7),
    (2, 1),
    (2, 4),
    (2, 7),
    (3, 2),
    (3, 3),
    (4, 1),
    (4, 4),
    (5, 2),
    (6, 5),
    (6, 6),
    (6, 7),
    (6, 8),
    (7, 1),
    (7, 5),
    (7, 7),
    (7, 8),
    (7, 9);

    -- 9. ТЕКСТЫ КНИГ //////////////////////////////

    SET IDENTITY_INSERT dbo.BookContent ON;

    INSERT INTO dbo.BookContent
    (BookContentId, BookId, ContentText, ContentFormat)
VALUES
    (1, 1, N'Тестовый фрагмент книги «Преступление и наказание».', N'TEXT'),
    (2, 2, N'Тестовый фрагмент книги «Мастер и Маргарита».', N'TEXT'),
    (3, 3, N'Тестовый фрагмент книги «1984».', N'TEXT'),
    (4, 4, N'Тестовый фрагмент книги «Гордость и предубеждение».', N'TEXT'),
    (5, 5, N'Тестовый фрагмент книги «Задача трёх тел».', N'TEXT'),
    (6, 6, N'Тестовый фрагмент манги «Сага о Винланде. Том 1».', N'TEXT'),
    (7, 7, N'Тестовый фрагмент книги «Война и мир. Том 1».', N'TEXT');

    SET IDENTITY_INSERT dbo.BookContent OFF;

    -- 10. ТАРИФЫ //////////////////////////////

    SET IDENTITY_INSERT dbo.SubscriptionPlan ON;

    INSERT INTO dbo.SubscriptionPlan
    (PlanId, PlanName, Price, DurationDays, Description)
VALUES
    (1, N'Месячная подписка', 499.00, 30, N'Доступ к обычным книгам по подписке на 30 дней.'),
    (2, N'Годовая подписка', 4990.00, 365, N'Доступ к обычным книгам по подписке на 365 дней.'),
    (3, N'Пробный период', 0.00, 7, N'Бесплатный тестовый доступ к обычным книгам на 7 дней.');

    SET IDENTITY_INSERT dbo.SubscriptionPlan OFF;

    -- 11. АКЦИИ //////////////////////////////

    SET IDENTITY_INSERT dbo.Promotion ON;

    INSERT INTO dbo.Promotion
    (PromotionId, PromotionName, PromoCode, DiscountPercent, StartDate, EndDate, IsActive, AppliesToAllBooks, RequiresBirthday, IsSystem)
VALUES
    (1, N'Подарок ко дню рождения', N'BIRTHDAY15', 15.00, '2000-01-01', '9999-12-31', 1, 1, 1, 1),
    (2, N'Скидка на драму и классику', N'DRAMA15', 15.00, DATEADD(DAY, -30, CAST(GETDATE() AS DATE)), DATEADD(DAY, 365, CAST(GETDATE() AS DATE)), 1, 0, 0, 0),
    (3, N'Фантастика недели', N'SCIFI10', 10.00, DATEADD(DAY, -7, CAST(GETDATE() AS DATE)), DATEADD(DAY, 30, CAST(GETDATE() AS DATE)), 1, 0, 0, 0);

    SET IDENTITY_INSERT dbo.Promotion OFF;

    INSERT INTO dbo.BookPromotion
    (PromotionId, BookId)
VALUES
    (2, 1),
    (2, 2),
    (3, 5);

    -- 12. ПЛАТЕЖИ //////////////////////////////

    SET IDENTITY_INSERT dbo.Payment ON;

    INSERT INTO dbo.Payment
    (PaymentId, UserId, Amount, PaymentMethod, PaymentStatus, TransactionNumber)
VALUES
    (1, 1, 5000.00, N'Card', N'Success', N'TRX-TOPUP-ADMIN-0001'),
    (2, 2, 2000.00, N'Card', N'Success', N'TRX-TOPUP-GIORGI-0002'),
    (3, 3, 1500.00, N'OnlineWallet', N'Success', N'TRX-TOPUP-ANNA-0003'),
    (4, 4, 1200.00, N'Card', N'Success', N'TRX-TOPUP-BESIK-0004'),
    (5, 2, 399.00, N'Balance', N'Success', N'TRX-BOOK-0005'),
    (6, 2, 499.00, N'Balance', N'Success', N'TRX-SUB-0006'),
    (7, 3, 599.00, N'Balance', N'Success', N'TRX-BOOK-0007'),
    (8, 4, 699.00, N'Balance', N'Success', N'TRX-BOOK-0008'),
    (9, 4, 0.00, N'Bonus', N'Success', N'TRX-TRIAL-0009');

    SET IDENTITY_INSERT dbo.Payment OFF;

    -- 13. ПОКУПКИ //////////////////////////////

    SET IDENTITY_INSERT dbo.Purchase ON;

    INSERT INTO dbo.Purchase
    (PurchaseId, UserId, BookId, PaymentId, PurchasePrice, AppliedPromoCode, AppliedDiscountPercent)
VALUES
    (1, 2, 1, 5, 399.00, NULL, 0),
    (2, 3, 5, 7, 599.00, NULL, 0),
    (3, 4, 6, 8, 699.00, NULL, 0);

    SET IDENTITY_INSERT dbo.Purchase OFF;

    -- 14. ПОДПИСКИ //////////////////////////////

    SET IDENTITY_INSERT dbo.UserSubscription ON;

    INSERT INTO dbo.UserSubscription
    (SubscriptionId, UserId, PlanId, PaymentId, StartDate, EndDate, IsActive)
VALUES
    (1, 2, 1, 6, DATEADD(DAY, -5, CAST(GETDATE() AS DATE)), DATEADD(DAY, 25, CAST(GETDATE() AS DATE)), 1),
    (2, 4, 3, 9, DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), DATEADD(DAY, 6, CAST(GETDATE() AS DATE)), 1);

    SET IDENTITY_INSERT dbo.UserSubscription OFF;

    -- 15. ОТЗЫВЫ //////////////////////////////

    SET IDENTITY_INSERT dbo.Review ON;

    INSERT INTO dbo.Review
    (ReviewId, UserId, BookId, Rating, ReviewText)
VALUES
    (1, 2, 1, 5, N'Сильная психологическая книга.'),
    (2, 2, 3, 4, N'Мрачная, но важная антиутопия.'),
    (3, 3, 5, 5, N'Отличная научная фантастика.'),
    (4, 4, 6, 5, N'Очень атмосферная историческая манга.'),
    (5, 3, 4, 4, N'Приятная классика.');

    SET IDENTITY_INSERT dbo.Review OFF;

    -- 16. ИЗБРАННОЕ //////////////////////////////

    INSERT INTO dbo.FavoriteBook
    (UserId, BookId)
VALUES
    (2, 1),
    (2, 2),
    (2, 5),
    (3, 3),
    (3, 5),
    (4, 6),
    (4, 7);

    -- 17. ПРОГРЕСС ЧТЕНИЯ //////////////////////////////

    SET IDENTITY_INSERT dbo.ReadingProgress ON;

    INSERT INTO dbo.ReadingProgress
    (ProgressId, UserId, BookId, CurrentPage, ProgressPercent)
VALUES
    (1, 2, 1, 125, dbo.fn_CalculateReadingProgressPercent(125,672)),
    (2, 2, 2, 45, dbo.fn_CalculateReadingProgressPercent(45,480)),
    (3, 3, 5, 300, dbo.fn_CalculateReadingProgressPercent(300,512)),
    (4, 4, 6, 180, dbo.fn_CalculateReadingProgressPercent(180,220)),
    (5, 3, 4, 100, dbo.fn_CalculateReadingProgressPercent(100,416));

    SET IDENTITY_INSERT dbo.ReadingProgress OFF;

    -- СИНХРОНИЗАЦИЯ СЧЁТЧИКОВ IDENTITY //////////////////////////////

    DBCC CHECKIDENT ('dbo.Role', RESEED, 2);
    DBCC CHECKIDENT ('dbo.UserAccount', RESEED, 4);
    DBCC CHECKIDENT ('dbo.Publisher', RESEED, 4);
    DBCC CHECKIDENT ('dbo.Author', RESEED, 7);
    DBCC CHECKIDENT ('dbo.Genre', RESEED, 9);
    DBCC CHECKIDENT ('dbo.Book', RESEED, 7);
    DBCC CHECKIDENT ('dbo.BookContent', RESEED, 7);
    DBCC CHECKIDENT ('dbo.SubscriptionPlan', RESEED, 3);
    DBCC CHECKIDENT ('dbo.Payment', RESEED, 9);
    DBCC CHECKIDENT ('dbo.Purchase', RESEED, 3);
    DBCC CHECKIDENT ('dbo.UserSubscription', RESEED, 2);
    DBCC CHECKIDENT ('dbo.Review', RESEED, 5);
    DBCC CHECKIDENT ('dbo.ReadingProgress', RESEED, 5);
    DBCC CHECKIDENT ('dbo.Promotion', RESEED, 3);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

    SELECT N'Role' AS TableName, COUNT(*) AS RecordCount
    FROM dbo.Role
UNION ALL
    SELECT N'UserAccount', COUNT(*)
    FROM dbo.UserAccount
UNION ALL
    SELECT N'Publisher', COUNT(*)
    FROM dbo.Publisher
UNION ALL
    SELECT N'Author', COUNT(*)
    FROM dbo.Author
UNION ALL
    SELECT N'Genre', COUNT(*)
    FROM dbo.Genre
UNION ALL
    SELECT N'Book', COUNT(*)
    FROM dbo.Book
UNION ALL
    SELECT N'Promotion', COUNT(*)
    FROM dbo.Promotion
UNION ALL
    SELECT N'BookPromotion', COUNT(*)
    FROM dbo.BookPromotion
UNION ALL
    SELECT N'Payment', COUNT(*)
    FROM dbo.Payment
UNION ALL
    SELECT N'Purchase', COUNT(*)
    FROM dbo.Purchase
UNION ALL
    SELECT N'UserSubscription', COUNT(*)
    FROM dbo.UserSubscription
UNION ALL
    SELECT N'Review', COUNT(*)
    FROM dbo.Review
UNION ALL
    SELECT N'FavoriteBook', COUNT(*)
    FROM dbo.FavoriteBook
UNION ALL
    SELECT N'ReadingProgress', COUNT(*)
    FROM dbo.ReadingProgress;
GO