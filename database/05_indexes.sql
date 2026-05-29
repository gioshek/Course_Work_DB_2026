USE [BookStreamDB];
GO

/*
    05_indexes.sql

    Индексы для базы данных BookStreamDB.

    Индексы нужны для ускорения:
    - поиска книг по названию;
    - фильтрации книг по году, цене, доступности;
    - соединений таблиц по внешним ключам;
    - поиска покупок, подписок, отзывов и прогресса чтения пользователя.
*/

-- УДАЛЕНИЕ СТАРЫХ ИНДЕКСОВ, ЕСЛИ ОНИ УЖЕ ЕСТЬ //////////////////////////////

DROP INDEX IF EXISTS IX_UserAccount_RoleId ON dbo.UserAccount;
DROP INDEX IF EXISTS IX_UserAccount_Username ON dbo.UserAccount;
DROP INDEX IF EXISTS IX_UserAccount_Email ON dbo.UserAccount;
DROP INDEX IF EXISTS IX_UserAccount_Balance ON dbo.UserAccount;

DROP INDEX IF EXISTS IX_Book_PublisherId ON dbo.Book;
DROP INDEX IF EXISTS IX_Book_Title ON dbo.Book;
DROP INDEX IF EXISTS IX_Book_PublicationYear ON dbo.Book;
DROP INDEX IF EXISTS IX_Book_Price ON dbo.Book;
DROP INDEX IF EXISTS IX_Book_Access ON dbo.Book;

DROP INDEX IF EXISTS IX_Promotion_PromoCode ON dbo.Promotion;
DROP INDEX IF EXISTS IX_Promotion_ActiveDates ON dbo.Promotion;
DROP INDEX IF EXISTS IX_BookPromotion_BookId ON dbo.BookPromotion;

DROP INDEX IF EXISTS IX_BookAuthor_AuthorId ON dbo.BookAuthor;
DROP INDEX IF EXISTS IX_BookGenre_GenreId ON dbo.BookGenre;

DROP INDEX IF EXISTS IX_Purchase_UserId ON dbo.Purchase;
DROP INDEX IF EXISTS IX_Purchase_BookId ON dbo.Purchase;
DROP INDEX IF EXISTS IX_Purchase_PaymentId ON dbo.Purchase;

DROP INDEX IF EXISTS IX_Payment_UserId ON dbo.Payment;
DROP INDEX IF EXISTS IX_Payment_Status_Date ON dbo.Payment;

DROP INDEX IF EXISTS IX_UserSubscription_UserId ON dbo.UserSubscription;
DROP INDEX IF EXISTS IX_UserSubscription_ActiveDates ON dbo.UserSubscription;

DROP INDEX IF EXISTS IX_Review_BookId ON dbo.Review;
DROP INDEX IF EXISTS IX_Review_UserId ON dbo.Review;
DROP INDEX IF EXISTS IX_Review_Rating ON dbo.Review;

DROP INDEX IF EXISTS IX_FavoriteBook_BookId ON dbo.FavoriteBook;

DROP INDEX IF EXISTS IX_ReadingProgress_BookId ON dbo.ReadingProgress;
DROP INDEX IF EXISTS IX_ReadingProgress_LastReadAt ON dbo.ReadingProgress;
GO

-- 1. ИНДЕКСЫ ДЛЯ ПОЛЬЗОВАТЕЛЕЙ //////////////////////////////

CREATE NONCLUSTERED INDEX IX_UserAccount_RoleId
ON dbo.UserAccount (RoleId);
GO

CREATE NONCLUSTERED INDEX IX_UserAccount_Username
ON dbo.UserAccount (Username);
GO

CREATE NONCLUSTERED INDEX IX_UserAccount_Email
ON dbo.UserAccount (Email);
GO

-- Для сортировки/фильтрации пользователей по балансу.
CREATE NONCLUSTERED INDEX IX_UserAccount_Balance
ON dbo.UserAccount (Balance);
GO

-- 2. ИНДЕКСЫ ДЛЯ КНИГ //////////////////////////////

CREATE NONCLUSTERED INDEX IX_Book_PublisherId
ON dbo.Book (PublisherId);
GO

-- Для поиска книг по названию.
CREATE NONCLUSTERED INDEX IX_Book_Title
ON dbo.Book (Title);
GO

-- Для фильтрации по году публикации.
CREATE NONCLUSTERED INDEX IX_Book_PublicationYear
ON dbo.Book (PublicationYear);
GO

-- Для сортировки/фильтрации по цене.
CREATE NONCLUSTERED INDEX IX_Book_Price
ON dbo.Book (Price);
GO

-- Для поиска бесплатных книг и книг по подписке.
CREATE NONCLUSTERED INDEX IX_Book_Access
ON dbo.Book (IsFree, IsAvailableBySubscription);
GO

-- 3. ИНДЕКСЫ ДЛЯ СВЯЗЕЙ КНИГ С АВТОРАМИ И ЖАНРАМИ //////////////////////////////

-- Первичный ключ BookAuthor уже индексирует (BookId, AuthorId),
-- но для поиска всех книг конкретного автора нужен отдельный индекс по AuthorId.
CREATE NONCLUSTERED INDEX IX_BookAuthor_AuthorId
ON dbo.BookAuthor (AuthorId);
GO

-- Первичный ключ BookGenre уже индексирует (BookId, GenreId),
-- но для поиска всех книг конкретного жанра нужен отдельный индекс по GenreId.
CREATE NONCLUSTERED INDEX IX_BookGenre_GenreId
ON dbo.BookGenre (GenreId);
GO

-- 4. ИНДЕКСЫ ДЛЯ ПОКУПОК //////////////////////////////

CREATE NONCLUSTERED INDEX IX_Purchase_UserId
ON dbo.Purchase (UserId)
INCLUDE (BookId, PurchaseDate, PurchasePrice);
GO

CREATE NONCLUSTERED INDEX IX_Purchase_BookId
ON dbo.Purchase (BookId)
INCLUDE (UserId, PurchaseDate, PurchasePrice);
GO

CREATE NONCLUSTERED INDEX IX_Purchase_PaymentId
ON dbo.Purchase (PaymentId);
GO

-- 5. ИНДЕКСЫ ДЛЯ ПЛАТЕЖЕЙ //////////////////////////////

CREATE NONCLUSTERED INDEX IX_Payment_UserId
ON dbo.Payment (UserId)
INCLUDE (Amount, PaymentDate, PaymentMethod, PaymentStatus);
GO

CREATE NONCLUSTERED INDEX IX_Payment_Status_Date
ON dbo.Payment (PaymentStatus, PaymentDate);
GO

-- 6. ИНДЕКСЫ ДЛЯ ПОДПИСОК //////////////////////////////

CREATE NONCLUSTERED INDEX IX_UserSubscription_UserId
ON dbo.UserSubscription (UserId)
INCLUDE (PlanId, StartDate, EndDate, IsActive);
GO

-- Для быстрой проверки активной подписки.
CREATE NONCLUSTERED INDEX IX_UserSubscription_ActiveDates
ON dbo.UserSubscription (IsActive, StartDate, EndDate)
INCLUDE (UserId, PlanId);
GO

-- 7. ИНДЕКСЫ ДЛЯ ОТЗЫВОВ //////////////////////////////

CREATE NONCLUSTERED INDEX IX_Review_BookId
ON dbo.Review (BookId)
INCLUDE (UserId, Rating, CreatedAt);
GO

CREATE NONCLUSTERED INDEX IX_Review_UserId
ON dbo.Review (UserId)
INCLUDE (BookId, Rating, CreatedAt);
GO

CREATE NONCLUSTERED INDEX IX_Review_Rating
ON dbo.Review (Rating);
GO

-- 8. ИНДЕКСЫ ДЛЯ ИЗБРАННОГО //////////////////////////////

-- Первичный ключ FavoriteBook индексирует (UserId, BookId),
-- но для подсчёта количества добавлений конкретной книги нужен индекс по BookId.
CREATE NONCLUSTERED INDEX IX_FavoriteBook_BookId
ON dbo.FavoriteBook (BookId)
INCLUDE (UserId, AddedAt);
GO

-- 9. ИНДЕКСЫ ДЛЯ ПРОГРЕССА ЧТЕНИЯ //////////////////////////////

CREATE NONCLUSTERED INDEX IX_ReadingProgress_BookId
ON dbo.ReadingProgress (BookId)
INCLUDE (UserId, CurrentPage, ProgressPercent, LastReadAt);
GO

CREATE NONCLUSTERED INDEX IX_ReadingProgress_LastReadAt
ON dbo.ReadingProgress (LastReadAt);
GO

-- 10. ИНДЕКСЫ ДЛЯ АКЦИЙ И СКИДОК //////////////////////////////

CREATE INDEX IX_Promotion_PromoCode
ON dbo.Promotion(PromoCode);
GO

CREATE INDEX IX_Promotion_ActiveDates
ON dbo.Promotion(IsActive, StartDate, EndDate);
GO

CREATE INDEX IX_BookPromotion_BookId
ON dbo.BookPromotion(BookId);
GO

-- ПРОВЕРКА СОЗДАННЫХ ИНДЕКСОВ //////////////////////////////

SELECT
    T.name AS TableName,
    I.name AS IndexName,
    I.type_desc AS IndexType,
    I.is_unique AS IsUnique,
    I.is_primary_key AS IsPrimaryKey
FROM sys.indexes AS I
    INNER JOIN sys.tables AS T ON I.object_id = T.object_id
WHERE 
    I.name IS NOT NULL
    AND T.is_ms_shipped = 0
ORDER BY
    T.name,
    I.name;
GO

-- ТЕСТОВЫЕ ЗАПРОСЫ, ДЛЯ КОТОРЫХ ИНДЕКСЫ ПОЛЕЗНЫ //////////////////////////////

-- Поиск книги по названию.
SELECT *
FROM dbo.Book
WHERE Title LIKE N'%1984%';
GO

-- Поиск книг конкретного жанра.
SELECT
    B.BookId,
    B.Title,
    G.GenreName
FROM dbo.Book AS B
    INNER JOIN dbo.BookGenre AS BG ON B.BookId = BG.BookId
    INNER JOIN dbo.Genre AS G ON BG.GenreId = G.GenreId
WHERE G.GenreName = N'Фантастика';
GO

-- Получение библиотеки пользователя.
SELECT
    U.Username,
    B.Title,
    P.PurchaseDate,
    P.PurchasePrice
FROM dbo.Purchase AS P
    INNER JOIN dbo.UserAccount AS U ON P.UserId = U.UserId
    INNER JOIN dbo.Book AS B ON P.BookId = B.BookId
WHERE U.UserId = 2;
GO

-- Проверка активных подписок.
SELECT
    US.SubscriptionId,
    US.UserId,
    US.StartDate,
    US.EndDate,
    US.IsActive
FROM dbo.UserSubscription AS US
WHERE 
    US.UserId = 2
    AND US.IsActive = 1
    AND CAST(GETDATE() AS DATE) BETWEEN US.StartDate AND US.EndDate;
GO

-- Средний рейтинг книги.
SELECT
    B.Title,
    AVG(CAST(R.Rating AS DECIMAL(4,2))) AS AverageRating,
    COUNT(R.ReviewId) AS ReviewCount
FROM dbo.Book AS B
    LEFT JOIN dbo.Review AS R ON B.BookId = R.BookId
GROUP BY
    B.BookId,
    B.Title
ORDER BY AverageRating DESC;
GO
