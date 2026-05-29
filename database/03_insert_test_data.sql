USE [BookStreamDB];
GO

/*
    03_insert_test_data.sql

    Тестовое заполнение базы данных BookStreamDB.
    Файл очищает данные и заново вставляет тестовые записи.
*/

SET NOCOUNT ON;
GO

-- ПРОВЕРКА, ЧТО ОСНОВНЫЕ ТАБЛИЦЫ СУЩЕСТВУЮТ //////////////////////////////

IF OBJECT_ID(N'dbo.Role', N'U') IS NULL
BEGIN
    RAISERROR(N'Таблицы не найдены. Сначала запустите файл 02_create_tables.sql.', 16, 1);
    RETURN;
END
GO

-- ОЧИСТКА ТАБЛИЦ //////////////////////////////
-- Сначала дочерние таблицы, потом родительские.

DELETE FROM dbo.ReadingProgress;
DELETE FROM dbo.FavoriteBook;
DELETE FROM dbo.Review;
DELETE FROM dbo.UserSubscription;
DELETE FROM dbo.Purchase;
DELETE FROM dbo.Payment;
DELETE FROM dbo.BookContent;
DELETE FROM dbo.BookPromotion;
DELETE FROM dbo.BookGenre;
DELETE FROM dbo.BookAuthor;
DELETE FROM dbo.Promotion;
DELETE FROM dbo.Book;
DELETE FROM dbo.SubscriptionPlan;
DELETE FROM dbo.Genre;
DELETE FROM dbo.Author;
DELETE FROM dbo.Publisher;
DELETE FROM dbo.UserAccount;
DELETE FROM dbo.Role;
GO

-- СБРОС IDENTITY //////////////////////////////

DBCC CHECKIDENT ('dbo.Role', RESEED, 0);
DBCC CHECKIDENT ('dbo.UserAccount', RESEED, 0);
DBCC CHECKIDENT ('dbo.Publisher', RESEED, 0);
DBCC CHECKIDENT ('dbo.Author', RESEED, 0);
DBCC CHECKIDENT ('dbo.Genre', RESEED, 0);
DBCC CHECKIDENT ('dbo.Book', RESEED, 0);
DBCC CHECKIDENT ('dbo.Promotion', RESEED, 0);
DBCC CHECKIDENT ('dbo.BookContent', RESEED, 0);
DBCC CHECKIDENT ('dbo.SubscriptionPlan', RESEED, 0);
DBCC CHECKIDENT ('dbo.Payment', RESEED, 0);
DBCC CHECKIDENT ('dbo.Purchase', RESEED, 0);
DBCC CHECKIDENT ('dbo.UserSubscription', RESEED, 0);
DBCC CHECKIDENT ('dbo.Review', RESEED, 0);
DBCC CHECKIDENT ('dbo.ReadingProgress', RESEED, 0);
GO

-- 1. РОЛИ //////////////////////////////

INSERT INTO dbo.Role
    (RoleName)
VALUES
    (N'Admin'),
    (N'User');
GO

-- 2. ПОЛЬЗОВАТЕЛИ //////////////////////////////

INSERT INTO dbo.UserAccount
    (RoleId, Username, Email, PasswordHash, Balance)
VALUES
    (1, N'admin', N'admin@bookstream.com', N'admin123', 5000.00),
    (2, N'giorgi', N'giorgi@example.com', N'1234', 1102.00),
    (2, N'anna_reader', N'anna@example.com', N'hashed_user_password_2', 901.00),
    (2, N'besik_books', N'besik_books@example.com', N'hashed_user_password_3', 501.00);
GO

-- 3. ИЗДАТЕЛЬСТВА //////////////////////////////

INSERT INTO dbo.Publisher
    (PublisherName, Email, Website)
VALUES
    (N'Азбука', N'info@azbooka.ru', N'https://azbooka.ru'),
    (N'Эксмо', N'info@eksmo.ru', N'https://eksmo.ru'),
    (N'Penguin Classics', N'contact@penguin.com', N'https://penguin.com'),
    (N'Manga Digital Press', N'info@mangadigital.com', N'https://mangadigital.com');
GO

-- 4. АВТОРЫ //////////////////////////////

INSERT INTO dbo.Author
    (FirstName, LastName, Country, BirthDate)
VALUES
    (N'Фёдор', N'Достоевский', N'Россия', '1821-11-11'),
    (N'Михаил', N'Булгаков', N'Россия', '1891-05-15'),
    (N'Джордж', N'Оруэлл', N'Великобритания', '1903-06-25'),
    (N'Джейн', N'Остин', N'Великобритания', '1775-12-16'),
    (N'Лю', N'Цысинь', N'Китай', '1963-06-23'),
    (N'Макото', N'Юкимура', N'Япония', '1976-05-08');
GO

-- 5. ЖАНРЫ //////////////////////////////

INSERT INTO dbo.Genre
    (GenreName)
VALUES
    (N'Классика'),
    (N'Фантастика'),
    (N'Антиутопия'),
    (N'Роман'),
    (N'Историческое'),
    (N'Манга'),
    (N'Драма'),
    (N'Приключения');
GO

-- 6. КНИГИ //////////////////////////////

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
    (
        1,
        N'Преступление и наказание',
        N'Психологический роман о преступлении, вине и нравственном выборе.',
        1866,
        16,
        672,
        399.00,
        0,
        1,
        N'/covers/crime_and_punishment.jpg'
    ),
    (
        2,
        N'Мастер и Маргарита',
        N'Роман, соединяющий сатиру, мистику, философию и историю любви.',
        1967,
        16,
        480,
        449.00,
        0,
        1,
        N'/covers/master_margarita.jpg'
    ),
    (
        3,
        N'1984',
        N'Антиутопия о тоталитарном обществе, контроле информации и свободе личности.',
        1949,
        16,
        328,
        299.00,
        0,
        1,
        N'/covers/1984.jpg'
    ),
    (
        3,
        N'Гордость и предубеждение',
        N'Классический роман о любви, социальных условностях и личном достоинстве.',
        1813,
        12,
        416,
        0.00,
        1,
        1,
        NULL
    ),
    (
        2,
        N'Задача трёх тел',
        N'Научно-фантастический роман о первом контакте человечества с иной цивилизацией.',
        2008,
        16,
        512,
        599.00,
        0,
        1,
        N'/covers/three_body_problem.jpeg'
    ),
    (
        4,
        N'Сага о Винланде. Том 1',
        N'Историческая манга о викингах, мести, взрослении и поиске смысла жизни.',
        2005,
        18,
        220,
        699.00,
        0,
        0,
        N'/covers/vinland_saga.jpg'
    );
GO

-- 7. КНИГИ И АВТОРЫ //////////////////////////////

INSERT INTO dbo.BookAuthor
    (BookId, AuthorId)
VALUES
    (1, 1),
    (2, 2),
    (3, 3),
    (4, 4),
    (5, 5),
    (6, 6);
GO

-- 8. КНИГИ И ЖАНРЫ //////////////////////////////

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
    (6, 8);
GO

-- 9. СОДЕРЖИМОЕ КНИГ //////////////////////////////

INSERT INTO dbo.BookContent
    (BookId, ContentText, ContentFormat)
VALUES
    (
        1,
        N'Тестовый фрагмент книги "Преступление и наказание". Здесь будет цифровой текст книги для чтения на сайте.',
        N'TEXT'
    ),
    (
        2,
        N'Тестовый фрагмент книги "Мастер и Маргарита". Здесь будет содержимое книги, доступное после покупки или по подписке.',
        N'TEXT'
    ),
    (
        3,
        N'Тестовый фрагмент книги "1984". Здесь будет текст для онлайн-чтения.',
        N'TEXT'
    ),
    (
        4,
        N'Тестовый фрагмент книги "Гордость и предубеждение". Бесплатная книга доступна всем пользователям.',
        N'TEXT'
    ),
    (
        5,
        N'Тестовый фрагмент книги "Задача трёх тел". Доступна по подписке или после покупки.',
        N'TEXT'
    ),
    (
        6,
        N'Тестовый фрагмент манги "Сага о Винланде. Том 1". Доступна только после покупки.',
        N'TEXT'
    );
GO

-- 10. ТАРИФЫ ПОДПИСКИ //////////////////////////////

INSERT INTO dbo.SubscriptionPlan
    (PlanName, Price, DurationDays, Description)
VALUES
    (
        N'Месячная подписка',
        499.00,
        30,
        N'Доступ к книгам, доступным по подписке, на 30 дней.'
    ),
    (
        N'Годовая подписка',
        4990.00,
        365,
        N'Доступ к книгам, доступным по подписке, на 365 дней.'
    ),
    (
        N'Пробный период',
        0.00,
        7,
        N'Бесплатный тестовый доступ на 7 дней.'
    );
GO

-- 11. ПЛАТЕЖИ //////////////////////////////
-- Payment хранит историю денежных операций:
-- - пополнение баланса;
-- - оплату покупки книги с баланса;
-- - оплату подписки с баланса.
-- Текущий баланс хранится в UserAccount.Balance.

INSERT INTO dbo.Payment
    (UserId, Amount, PaymentMethod, PaymentStatus, TransactionNumber)
VALUES
    -- Начальные пополнения баланса.
    (1, 5000.00, N'Card', N'Success', N'TRX-TOPUP-ADMIN-0001'),
    (2, 2000.00, N'Card', N'Success', N'TRX-TOPUP-GIORGI-0002'),
    (3, 1500.00, N'OnlineWallet', N'Success', N'TRX-TOPUP-ANNA-0003'),
    (4, 1200.00, N'Card', N'Success', N'TRX-TOPUP-BESIK-0004'),

    -- Списания с баланса за покупки и подписки.
    (2, 399.00, N'Balance', N'Success', N'TRX-BOOK-0005'),
    (2, 499.00, N'Balance', N'Success', N'TRX-SUB-0006'),
    (3, 599.00, N'Balance', N'Success', N'TRX-BOOK-0007'),
    (4, 699.00, N'Balance', N'Success', N'TRX-BOOK-0008'),
    (4, 0.00, N'Bonus', N'Success', N'TRX-TRIAL-0009');
GO

-- 12. ПОКУПКИ //////////////////////////////

INSERT INTO dbo.Purchase
    (UserId, BookId, PaymentId, PurchasePrice)
VALUES
    (2, 1, 5, 399.00),
    (3, 5, 7, 599.00),
    (4, 6, 8, 699.00);
GO

-- 13. ПОДПИСКИ //////////////////////////////

INSERT INTO dbo.UserSubscription
    (UserId, PlanId, PaymentId, StartDate, EndDate, IsActive)
VALUES
    (2, 1, 6, '2026-05-01', '2026-05-31', 1),
    (4, 3, 9, '2026-05-20', '2026-05-27', 1);
GO

-- 14. ОТЗЫВЫ //////////////////////////////

INSERT INTO dbo.Review
    (UserId, BookId, Rating, ReviewText)
VALUES
    (
        2,
        1,
        5,
        N'Сильная психологическая книга. Очень понравилась глубина конфликта героя.'
    ),
    (
        2,
        3,
        4,
        N'Мрачная, но важная антиутопия.'
    ),
    (
        3,
        5,
        5,
        N'Отличная научная фантастика с необычной идеей первого контакта.'
    ),
    (
        4,
        6,
        5,
        N'Очень атмосферная историческая манга.'
    ),
    (
        3,
        4,
        4,
        N'Приятная классика, читается спокойно и интересно.'
    );
GO

-- 15. ИЗБРАННОЕ //////////////////////////////

INSERT INTO dbo.FavoriteBook
    (UserId, BookId)
SELECT
    U.UserId,
    B.BookId
FROM
    (
    VALUES
        (N'giorgi', N'Преступление и наказание'),
        (N'giorgi', N'Мастер и Маргарита'),
        (N'giorgi', N'Задача трёх тел'),
        (N'anna_reader', N'1984'),
        (N'anna_reader', N'Задача трёх тел'),
        (N'besik_books', N'Сага о Винланде. Том 1')
) AS V(Username, Title)
    INNER JOIN dbo.UserAccount AS U ON U.Username = V.Username
    INNER JOIN dbo.Book AS B ON B.Title = V.Title;
GO

-- 16. ПРОГРЕСС ЧТЕНИЯ //////////////////////////////

INSERT INTO dbo.ReadingProgress
    (UserId, BookId, CurrentPage, ProgressPercent)
SELECT
    U.UserId,
    B.BookId,
    V.CurrentPage,
    V.ProgressPercent
FROM
    (
    VALUES
        (N'giorgi', N'Преступление и наказание', 125, CAST(18.60 AS DECIMAL(5,2))),
        (N'giorgi', N'Мастер и Маргарита', 45, CAST(9.40 AS DECIMAL(5,2))),
        (N'anna_reader', N'Задача трёх тел', 300, CAST(58.59 AS DECIMAL(5,2))),
        (N'besik_books', N'Сага о Винланде. Том 1', 180, CAST(81.82 AS DECIMAL(5,2))),
        (N'anna_reader', N'Гордость и предубеждение', 100, CAST(24.04 AS DECIMAL(5,2)))
) AS V(Username, Title, CurrentPage, ProgressPercent)
    INNER JOIN dbo.UserAccount AS U ON U.Username = V.Username
    INNER JOIN dbo.Book AS B ON B.Title = V.Title;
GO


-- 17. ТЕСТОВЫЕ АКЦИИ И СКИДКИ //////////////////////////////
-- Эти данные нужны, чтобы сущность сразу была задействована.

DECLARE @DramaPromoId INT;
DECLARE @ScifiPromoId INT;

IF NOT EXISTS (SELECT 1
FROM dbo.Promotion
WHERE PromoCode = N'DRAMA15')
BEGIN
    INSERT INTO dbo.Promotion
        (PromotionName, PromoCode, DiscountPercent, StartDate, EndDate, IsActive)
    VALUES
        (N'Скидка на драму и классику', N'DRAMA15', 15.00, '2026-01-01', '2026-12-31', 1);
END;

SELECT @DramaPromoId = PromotionId
FROM dbo.Promotion
WHERE PromoCode = N'DRAMA15';

IF NOT EXISTS (SELECT 1
FROM dbo.Promotion
WHERE PromoCode = N'SCIFI10')
BEGIN
    INSERT INTO dbo.Promotion
        (PromotionName, PromoCode, DiscountPercent, StartDate, EndDate, IsActive)
    VALUES
        (N'Фантастика недели', N'SCIFI10', 10.00, '2026-01-01', '2026-12-31', 1);
END;

SELECT @ScifiPromoId = PromotionId
FROM dbo.Promotion
WHERE PromoCode = N'SCIFI10';

INSERT INTO dbo.BookPromotion
    (PromotionId, BookId)
SELECT
    @DramaPromoId,
    B.BookId
FROM dbo.Book AS B
WHERE B.Title IN (N'Преступление и наказание', N'Мастер и Маргарита')
    AND NOT EXISTS
  (
    SELECT 1
    FROM dbo.BookPromotion AS BP
    WHERE BP.PromotionId = @DramaPromoId
        AND BP.BookId = B.BookId
  );

INSERT INTO dbo.BookPromotion
    (PromotionId, BookId)
SELECT
    @ScifiPromoId,
    B.BookId
FROM dbo.Book AS B
WHERE B.Title = N'Задача трёх тел'
    AND NOT EXISTS
  (
    SELECT 1
    FROM dbo.BookPromotion AS BP
    WHERE BP.PromotionId = @ScifiPromoId
        AND BP.BookId = B.BookId
  );
GO

-- ПРОВЕРКА КОЛИЧЕСТВА ЗАПИСЕЙ В ТАБЛИЦАХ //////////////////////////////

    SELECT N'Role' AS TableName, COUNT(*) AS [RecordCount]
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
    SELECT N'BookAuthor', COUNT(*)
    FROM dbo.BookAuthor
UNION ALL
    SELECT N'BookGenre', COUNT(*)
    FROM dbo.BookGenre
UNION ALL
    SELECT N'BookContent', COUNT(*)
    FROM dbo.BookContent
UNION ALL
    SELECT N'SubscriptionPlan', COUNT(*)
    FROM dbo.SubscriptionPlan
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

-- ПРОВЕРКА КАТАЛОГА КНИГ //////////////////////////////

SELECT
    B.BookId,
    B.Title,
    A.FirstName + N' ' + A.LastName AS AuthorName,
    P.PublisherName,
    B.PublicationYear,
    B.Price,
    B.IsFree,
    B.IsAvailableBySubscription
FROM dbo.Book AS B
    INNER JOIN dbo.BookAuthor AS BA ON B.BookId = BA.BookId
    INNER JOIN dbo.Author AS A ON BA.AuthorId = A.AuthorId
    INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId
ORDER BY B.BookId;
GO

-- ПРОВЕРКА БАЛАНСА ПОЛЬЗОВАТЕЛЕЙ //////////////////////////////

SELECT
    UserId,
    Username,
    Email,
    Balance
FROM dbo.UserAccount
ORDER BY UserId;
GO
