USE [BookStreamDB];
GO

/*
    09_test_queries.sql

    Контрольные SQL-запросы для курсовой работы.

    Здесь показаны:
    - SELECT;
    - DISTINCT;
    - псевдонимы полей и таблиц;
    - ORDER BY ASC / DESC;
    - INNER JOIN / LEFT JOIN / RIGHT JOIN / FULL OUTER JOIN;
    - WHERE с LIKE / BETWEEN / IN / EXISTS / NULL;
    - GROUP BY + HAVING;
    - COUNT / AVG / SUM / MIN / MAX;
    - UNION / UNION ALL / EXCEPT / INTERSECT;
    - вложенные запросы;
    - INSERT / INSERT SELECT / UPDATE / DELETE;
    - вызов представлений, функций и процедур.
*/

-- 1. ПРОСТОЙ SELECT //////////////////////////////

SELECT
    BookId,
    Title,
    PublicationYear,
    Price,
    IsFree,
    IsAvailableBySubscription
FROM dbo.Book;
GO

-- 2. SELECT С ПСЕВДОНИМАМИ ПОЛЕЙ И ТАБЛИЦ //////////////////////////////

SELECT
    B.BookId AS BookIdentifier,
    B.Title AS BookTitle,
    B.Price AS BookPrice,
    P.PublisherName AS Publisher
FROM dbo.Book AS B
    INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId;
GO

-- 3. DISTINCT //////////////////////////////
-- Вывод уникальных стран авторов.

SELECT DISTINCT
    Country
FROM dbo.Author
WHERE Country IS NOT NULL
ORDER BY Country ASC;
GO

-- 4. ORDER BY ASC / DESC //////////////////////////////

SELECT
    Title,
    Price
FROM dbo.Book
ORDER BY Price DESC;
GO

SELECT
    Title,
    PublicationYear
FROM dbo.Book
ORDER BY PublicationYear ASC;
GO

-- 5. INNER JOIN //////////////////////////////
-- Книги, авторы и издательства.

SELECT
    B.Title,
    A.FirstName + N' ' + A.LastName AS AuthorName,
    P.PublisherName
FROM dbo.Book AS B
    INNER JOIN dbo.BookAuthor AS BA ON B.BookId = BA.BookId
    INNER JOIN dbo.Author AS A ON BA.AuthorId = A.AuthorId
    INNER JOIN dbo.Publisher AS P ON B.PublisherId = P.PublisherId
ORDER BY B.Title;
GO

-- 6. LEFT JOIN //////////////////////////////
-- Все книги и их отзывы, включая книги без отзывов.

SELECT
    B.Title,
    R.Rating,
    R.ReviewText
FROM dbo.Book AS B
    LEFT JOIN dbo.Review AS R ON B.BookId = R.BookId
ORDER BY B.Title;
GO

-- 7. RIGHT JOIN //////////////////////////////
-- Все жанры и книги в этих жанрах.
-- Даже если у жанра нет книги, жанр всё равно попадёт в результат.

SELECT
    G.GenreName,
    B.Title
FROM dbo.Book AS B
    INNER JOIN dbo.BookGenre AS BG ON B.BookId = BG.BookId
    RIGHT JOIN dbo.Genre AS G ON BG.GenreId = G.GenreId
ORDER BY G.GenreName, B.Title;
GO

-- 8. FULL OUTER JOIN //////////////////////////////
-- Все книги и все покупки, включая книги без покупок.

SELECT
    B.Title,
    P.PurchaseId,
    P.UserId,
    P.PurchasePrice
FROM dbo.Book AS B
    FULL OUTER JOIN dbo.Purchase AS P ON B.BookId = P.BookId
ORDER BY B.Title;
GO

-- 9. LIKE //////////////////////////////
-- Поиск книг, где в названии есть слово.

SELECT
    BookId,
    Title,
    Description
FROM dbo.Book
WHERE Title LIKE N'%1984%'
    OR Description LIKE N'%антиутопия%';
GO

-- 10. BETWEEN //////////////////////////////
-- Книги, опубликованные в заданном диапазоне лет.

SELECT
    Title,
    PublicationYear
FROM dbo.Book
WHERE PublicationYear BETWEEN 1900 AND 2008
ORDER BY PublicationYear;
GO

-- 11. IN //////////////////////////////
-- Книги с возрастным ограничением 16 или 18.

SELECT
    Title,
    AgeLimit
FROM dbo.Book
WHERE AgeLimit IN (16, 18)
ORDER BY AgeLimit, Title;
GO

-- 12. EXISTS //////////////////////////////
-- Пользователи, у которых есть хотя бы одна покупка.

SELECT
    U.UserId,
    U.Username,
    U.Email,
    U.Balance
FROM dbo.UserAccount AS U
WHERE EXISTS
(
    SELECT 1
FROM dbo.Purchase AS P
WHERE P.UserId = U.UserId
);
GO

-- 13. NULL / NOT NULL //////////////////////////////
-- Книги, у которых есть ссылка на обложку.

SELECT
    Title,
    CoverImageUrl
FROM dbo.Book
WHERE CoverImageUrl IS NOT NULL;
GO

-- 14. GROUP BY + COUNT //////////////////////////////
-- Количество книг по жанрам.

SELECT
    G.GenreName,
    COUNT(B.BookId) AS BookCount
FROM dbo.Genre AS G
    LEFT JOIN dbo.BookGenre AS BG ON G.GenreId = BG.GenreId
    LEFT JOIN dbo.Book AS B ON BG.BookId = B.BookId
GROUP BY G.GenreName
ORDER BY BookCount DESC;
GO

-- 15. GROUP BY + HAVING //////////////////////////////
-- Жанры, где больше одной книги.

SELECT
    G.GenreName,
    COUNT(B.BookId) AS BookCount
FROM dbo.Genre AS G
    INNER JOIN dbo.BookGenre AS BG ON G.GenreId = BG.GenreId
    INNER JOIN dbo.Book AS B ON BG.BookId = B.BookId
GROUP BY G.GenreName
HAVING COUNT(B.BookId) > 1
ORDER BY BookCount DESC;
GO

-- 16. АГРЕГАТНЫЕ ФУНКЦИИ //////////////////////////////
-- COUNT / AVG / SUM / MIN / MAX

SELECT
    COUNT(*) AS TotalBooks,
    AVG(Price) AS AverageBookPrice,
    SUM(Price) AS TotalCatalogPrice,
    MIN(Price) AS MinBookPrice,
    MAX(Price) AS MaxBookPrice
FROM dbo.Book;
GO

-- 17. Средний рейтинг и количество отзывов по книгам. //////////////////////////////

SELECT
    B.Title,
    COUNT(R.ReviewId) AS ReviewCount,
    ISNULL(AVG(CAST(R.Rating AS DECIMAL(4,2))), 0) AS AverageRating
FROM dbo.Book AS B
    LEFT JOIN dbo.Review AS R ON B.BookId = R.BookId
GROUP BY B.BookId, B.Title
ORDER BY AverageRating DESC, ReviewCount DESC;
GO

-- 18. UNION //////////////////////////////
-- Общий список имён авторов и пользователей без повторений.

    SELECT
        A.FirstName AS NameValue
    FROM dbo.Author AS A
UNION
    SELECT
        U.Username AS NameValue
    FROM dbo.UserAccount AS U;
GO

-- 19. UNION ALL //////////////////////////////
-- Общий список имён авторов и пользователей с повторами.

    SELECT
        A.FirstName AS NameValue
    FROM dbo.Author AS A
UNION ALL
    SELECT
        U.Username AS NameValue
    FROM dbo.UserAccount AS U;
GO

-- 20. EXCEPT //////////////////////////////
-- Все книги, которые ещё никто не покупал.

    SELECT
        B.BookId,
        B.Title
    FROM dbo.Book AS B
EXCEPT
    SELECT
        B.BookId,
        B.Title
    FROM dbo.Book AS B
        INNER JOIN dbo.Purchase AS P ON B.BookId = P.BookId;
GO

-- 21. INTERSECT //////////////////////////////
-- Книги, которые одновременно есть в избранном и имеют отзывы.

    SELECT
        B.BookId,
        B.Title
    FROM dbo.Book AS B
        INNER JOIN dbo.FavoriteBook AS F ON B.BookId = F.BookId
INTERSECT
    SELECT
        B.BookId,
        B.Title
    FROM dbo.Book AS B
        INNER JOIN dbo.Review AS R ON B.BookId = R.BookId;
GO

-- 22. ВЛОЖЕННЫЙ ЗАПРОС //////////////////////////////
-- Книги дороже средней цены.

SELECT
    Title,
    Price
FROM dbo.Book
WHERE Price >
(
    SELECT AVG(Price)
FROM dbo.Book
)
ORDER BY Price DESC;
GO

-- 23. ВЛОЖЕННЫЙ ЗАПРОС С IN //////////////////////////////
-- Книги, которые купил пользователь giorgi.

SELECT
    BookId,
    Title,
    Price
FROM dbo.Book
WHERE BookId IN
(
    SELECT P.BookId
FROM dbo.Purchase AS P
    INNER JOIN dbo.UserAccount AS U ON P.UserId = U.UserId
WHERE U.Username = N'giorgi'
);
GO

-- 24. ВЛОЖЕННЫЙ ЗАПРОС С EXISTS //////////////////////////////
-- Книги, у которых есть хотя бы один отзыв с рейтингом 5.

SELECT
    B.BookId,
    B.Title
FROM dbo.Book AS B
WHERE EXISTS
(
    SELECT 1
FROM dbo.Review AS R
WHERE R.BookId = B.BookId
    AND R.Rating = 5
);
GO

-- 25. ЗАПРОС К ПРЕДСТАВЛЕНИЮ //////////////////////////////
-- Каталог книг.

SELECT
    BookId,
    Title,
    Authors,
    Genres,
    PublisherName,
    Price,
    AverageRating,
    ReviewCount
FROM dbo.vw_BookCatalog
ORDER BY AverageRating DESC, Title ASC;
GO

-- 26. ЗАПРОС К ПРЕДСТАВЛЕНИЮ //////////////////////////////
-- Библиотека пользователя.

SELECT
    UserId,
    Username,
    BookId,
    Title,
    AccessType
FROM dbo.vw_UserLibrary
WHERE UserId = 2
ORDER BY Title;
GO

-- 27. ВЫЗОВ СКАЛЯРНЫХ ФУНКЦИЙ //////////////////////////////

SELECT
    B.BookId,
    B.Title,
    dbo.fn_GetBookAverageRating(B.BookId) AS AverageRating,
    dbo.fn_GetBookReviewCount(B.BookId) AS ReviewCount
FROM dbo.Book AS B
ORDER BY AverageRating DESC;
GO

-- 28. ВЫЗОВ ТАБЛИЧНОЙ ФУНКЦИИ //////////////////////////////

SELECT *
FROM dbo.fn_GetBooksByGenre(N'Фантастика');
GO

-- 29. ПРОВЕРКА ДОСТУПА ПОЛЬЗОВАТЕЛЯ К КНИГАМ //////////////////////////////

SELECT
    B.BookId,
    B.Title,
    dbo.fn_UserHasAccessToBook(2, B.BookId, '2026-05-25') AS HasAccess
FROM dbo.Book AS B
ORDER BY B.BookId;
GO

-- 29.1. ПРОВЕРКА БАЛАНСА ПОЛЬЗОВАТЕЛЯ //////////////////////////////

SELECT
    UserId,
    Username,
    Balance
FROM dbo.UserAccount
ORDER BY UserId;
GO

SELECT
    dbo.fn_GetUserBalance(2) AS User2Balance;
GO

SELECT
    PaymentId,
    Username,
    CurrentBalance,
    Amount,
    PaymentMethod,
    PaymentPurpose,
    TransactionNumber
FROM dbo.vw_UserPayments
WHERE UserId = 2
ORDER BY PaymentId;
GO

-- 30. ВЫЗОВ ХРАНИМОЙ ПРОЦЕДУРЫ //////////////////////////////

EXEC dbo.usp_GetBookCatalog;
GO

EXEC dbo.usp_GetUserLibrary @UserId = 2;
GO

EXEC dbo.usp_GetBookContentForUser @UserId = 2, @BookId = 1;
GO

-- Пополнение баланса меняет данные, поэтому ниже пример оставлен закомментированным.
-- EXEC dbo.usp_TopUpBalance @UserId = 2, @Amount = 500.00, @PaymentMethod = N'Card';
-- GO

-- 31. DML: INSERT / INSERT SELECT / UPDATE / DELETE //////////////////////////////
-- Демонстрация выполняется внутри транзакции.
-- В конце ROLLBACK, поэтому реальные данные не меняются.

BEGIN TRANSACTION;

DECLARE @TempUserId INT;
DECLARE @TempPublisherId INT;
DECLARE @TempAuthorId INT;
DECLARE @TempGenreId INT;
DECLARE @TempBookId INT;
DECLARE @TempPaymentId INT;

-- INSERT пользователя.
INSERT INTO dbo.UserAccount
    (RoleId, Username, Email, PasswordHash, Balance)
VALUES
    (
        2,
        N'test_dml_user',
        N'test_dml_user@example.com',
        N'hashed_test_password',
        1000.00
    );

SET @TempUserId = CONVERT(INT, SCOPE_IDENTITY());

-- INSERT издательства.
INSERT INTO dbo.Publisher
    (PublisherName, Email, Website)
VALUES
    (
        N'Test Publisher',
        N'testpublisher@example.com',
        N'https://testpublisher.example.com'
    );

SET @TempPublisherId = CONVERT(INT, SCOPE_IDENTITY());

-- INSERT автора.
INSERT INTO dbo.Author
    (FirstName, LastName, Country, BirthDate)
VALUES
    (
        N'Тестовый',
        N'Автор',
        N'Грузия',
        '1990-01-01'
    );

SET @TempAuthorId = CONVERT(INT, SCOPE_IDENTITY());

-- INSERT жанра.
INSERT INTO dbo.Genre
    (GenreName)
VALUES
    (
        N'Тестовый жанр'
    );

SET @TempGenreId = CONVERT(INT, SCOPE_IDENTITY());

-- INSERT книги.
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
        @TempPublisherId,
        N'Тестовая цифровая книга',
        N'Книга добавлена для демонстрации INSERT, UPDATE и DELETE.',
        2026,
        12,
        150,
        199.00,
        0,
        1,
        N'/covers/test_book.jpg'
    );

SET @TempBookId = CONVERT(INT, SCOPE_IDENTITY());

-- Связь книги с автором и жанром.
INSERT INTO dbo.BookAuthor
    (BookId, AuthorId)
VALUES
    (@TempBookId, @TempAuthorId);

INSERT INTO dbo.BookGenre
    (BookId, GenreId)
VALUES
    (@TempBookId, @TempGenreId);

-- INSERT содержимого книги.
INSERT INTO dbo.BookContent
    (BookId, ContentText, ContentFormat)
VALUES
    (
        @TempBookId,
        N'Тестовый текст цифровой книги.',
        N'TEXT'
    );

-- INSERT SELECT.
-- Добавим пользователю в избранное все бесплатные книги.
INSERT INTO dbo.FavoriteBook
    (UserId, BookId)
SELECT
    @TempUserId,
    B.BookId
FROM dbo.Book AS B
WHERE B.IsFree = 1;

-- Платёж и покупка тестовой книги.
INSERT INTO dbo.Payment
    (UserId, Amount, PaymentMethod, PaymentStatus, TransactionNumber)
VALUES
    (
        @TempUserId,
        199.00,
        N'Balance',
        N'Success',
        N'TRX-DML-TEST-' + CONVERT(NVARCHAR(36), NEWID())
    );

UPDATE dbo.UserAccount
SET Balance = Balance - 199.00
WHERE UserId = @TempUserId;

SET @TempPaymentId = CONVERT(INT, SCOPE_IDENTITY());

INSERT INTO dbo.Purchase
    (UserId, BookId, PaymentId, PurchasePrice)
VALUES
    (
        @TempUserId,
        @TempBookId,
        @TempPaymentId,
        199.00
    );

-- UPDATE.
UPDATE dbo.Book
SET
    Price = 249.00,
    Description = N'Описание изменено с помощью UPDATE.'
WHERE BookId = @TempBookId;

-- DELETE.
DELETE FROM dbo.FavoriteBook
WHERE UserId = @TempUserId
    AND BookId IN
  (
      SELECT BookId
    FROM dbo.Book
    WHERE IsFree = 1
  );

-- Проверка результата внутри транзакции.
SELECT
    U.UserId,
    U.Username,
    U.Balance,
    B.BookId,
    B.Title,
    B.Price,
    P.PurchasePrice
FROM dbo.UserAccount AS U
    INNER JOIN dbo.Purchase AS P ON U.UserId = P.UserId
    INNER JOIN dbo.Book AS B ON P.BookId = B.BookId
WHERE U.UserId = @TempUserId;

-- Откатываем демонстрационные изменения.
ROLLBACK TRANSACTION;
GO

-- 32. Проверка, что временные DML-данные не сохранились. //////////////////////////////

SELECT
    Username,
    Email
FROM dbo.UserAccount
WHERE Username = N'test_dml_user';
GO

-- 16. ПРОВЕРКА АКЦИЙ И СКИДОК //////////////////////////////

SELECT
    PromotionId,
    PromotionName,
    PromoCode,
    DiscountPercent,
    StartDate,
    EndDate,
    IsActive
FROM dbo.Promotion
ORDER BY PromotionId;
GO

SELECT
    BP.PromotionId,
    P.PromotionName,
    BP.BookId,
    B.Title
FROM dbo.BookPromotion AS BP
    INNER JOIN dbo.Promotion AS P ON BP.PromotionId = P.PromotionId
    INNER JOIN dbo.Book AS B ON BP.BookId = B.BookId
ORDER BY BP.PromotionId, B.Title;
GO

SELECT
    BookId,
    Title,
    Price,
    DiscountPercent,
    FinalPrice,
    HasActivePromotion,
    ActivePromotionName,
    ActivePromoCode
FROM dbo.vw_BookCatalog
ORDER BY BookId;
GO

EXEC dbo.usp_GetPromotions;
GO

-- 17. ПРОВЕРКА АДМИНСКИХ ОТЧЁТОВ //////////////////////////////

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
