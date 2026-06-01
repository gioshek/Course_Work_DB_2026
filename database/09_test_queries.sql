USE [BookStreamDB];
GO

/*
    09_test_queries.sql

    Безопасные проверки после чистой сборки базы.
    Запросы не удаляют данные и не выполняют повторные покупки.
*/

-- 1. ТАБЛИЦЫ //////////////////////////////

SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
GO

-- 2. ПРЕДСТАВЛЕНИЯ //////////////////////////////

SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.VIEWS
ORDER BY TABLE_NAME;
GO

-- 3. ФУНКЦИИ И ПРОЦЕДУРЫ //////////////////////////////

SELECT ROUTINE_TYPE, ROUTINE_NAME
FROM INFORMATION_SCHEMA.ROUTINES
ORDER BY ROUTINE_TYPE, ROUTINE_NAME;
GO

-- 4. КАТАЛОГ //////////////////////////////

EXEC dbo.usp_GetBookCatalog;
GO

EXEC dbo.usp_GetBookCatalog @OnlyPremium = 1;
GO

EXEC dbo.usp_GetBookCatalog @AvailableBySubscription = 1;
GO

-- 5. ПРЕМИАЛЬНЫЕ КНИГИ //////////////////////////////

SELECT BookId, Title, IsPremium, IsAvailableBySubscription
FROM dbo.Book
ORDER BY BookId;
GO

-- 6. БИБЛИОТЕКА ЧЕРЕЗ ПРЕДСТАВЛЕНИЕ //////////////////////////////

SELECT *
FROM dbo.vw_UserLibrary
WHERE UserId = 2
ORDER BY Title;
GO

-- 7. ПРОМОКОД КО ДНЮ РОЖДЕНИЯ //////////////////////////////

SELECT
    U.UserId,
    U.Username,
    U.DateOfBirth,
    dbo.fn_GetBirthdayPromoCode(U.UserId, CAST(GETDATE() AS DATE)) AS BirthdayPromoCode
FROM dbo.UserAccount AS U
ORDER BY U.UserId;
GO

EXEC dbo.usp_GetBookPricePreview
    @UserId = 2,
    @BookId = 7,
    @PromoCode = N'BIRTHDAY15';
GO

SELECT
    dbo.fn_IsPromoCodeApplicable(2, 7, N'BIRTHDAY15', CAST(GETDATE() AS DATE)) AS BirthdayPromoIsApplicable;
GO

-- 8. ПРОФИЛЬ //////////////////////////////

EXEC dbo.usp_GetUserProfile @UserId = 2;
GO

-- 9. АКЦИИ //////////////////////////////

EXEC dbo.usp_GetPromotions;
GO

SELECT *
FROM dbo.vw_ActiveBookPromotions
ORDER BY PromotionId, BookId;
GO

-- 10. ОТЧЁТЫ //////////////////////////////

EXEC dbo.usp_GetAdminStats;
GO

EXEC dbo.usp_GetDatabaseDashboard;
GO

EXEC dbo.usp_AdminSalesReport @GroupBy = N'Book';
GO

EXEC dbo.usp_AdminBookReport @OnlyPremium = 1;
GO

EXEC dbo.usp_AdminUserReport;
GO

EXEC dbo.usp_AdminGenreReport;
GO

EXEC dbo.usp_AdminAuditLogReport;
GO

-- 11. ДОСТУП К КНИГАМ //////////////////////////////

SELECT
    dbo.fn_UserHasAccessToBook(2, 1, CAST(GETDATE() AS DATE)) AS PurchasedBook,
    dbo.fn_UserHasAccessToBook(2, 5, CAST(GETDATE() AS DATE)) AS SubscriptionBook,
    dbo.fn_UserHasAccessToBook(2, 6, CAST(GETDATE() AS DATE)) AS PremiumBookWithoutPurchase,
    dbo.fn_UserHasAccessToBook(4, 6, CAST(GETDATE() AS DATE)) AS PurchasedPremiumBook;
GO

-- 12. ЗАКОММЕНТИРОВАННЫЕ ИЗМЕНЯЮЩИЕ ОПЕРАЦИИ //////////////////////////////
-- Запускайте вручную только при необходимости.

-- EXEC dbo.usp_TopUpBalance @UserId = 2, @Amount = 100.00, @PaymentMethod = N'Card';
-- GO

-- EXEC dbo.usp_CreateSubscription @UserId = 3, @PlanId = 1, @PaymentMethod = N'Balance';
-- GO

-- EXEC dbo.usp_BuyBook @UserId = 2, @BookId = 7, @PaymentMethod = N'Balance', @PromoCode = N'BIRTHDAY15';
-- GO
