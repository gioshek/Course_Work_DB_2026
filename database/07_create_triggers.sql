USE [BookStreamDB];
GO

/*
    07_create_triggers.sql

    Триггеры проверяют критичные операции и автоматически заполняют AuditLog.
*/

-- 1. КНИГИ //////////////////////////////

CREATE OR ALTER TRIGGER dbo.trg_Book_AfterInsertUpdate
ON dbo.Book
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, Description)
    SELECT
        N'Book',
        CASE WHEN D.BookId IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
        I.BookId,
        CONCAT
        (
            N'Книга: ', I.Title,
            N'. Цена: ', CONVERT(NVARCHAR(30), I.Price),
            N'. Премиальная: ', CONVERT(NVARCHAR(5), I.IsPremium),
            N'. Доступна по подписке: ', CONVERT(NVARCHAR(5), I.IsAvailableBySubscription), N'.'
        )
    FROM inserted AS I
        LEFT JOIN deleted AS D ON I.BookId = D.BookId;
END;
GO

-- 2. ПЛАТЕЖИ //////////////////////////////

CREATE OR ALTER TRIGGER dbo.trg_Payment_AfterInsertUpdate
ON dbo.Payment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, UserId, Description)
    SELECT
        N'Payment',
        CASE WHEN D.PaymentId IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
        I.PaymentId,
        I.UserId,
        CONCAT
        (
            N'Платёж: ', CONVERT(NVARCHAR(30), I.Amount),
            N'. Метод: ', I.PaymentMethod,
            N'. Статус: ', I.PaymentStatus,
            N'. Транзакция: ', ISNULL(I.TransactionNumber, N'без номера'), N'.'
        )
    FROM inserted AS I
        LEFT JOIN deleted AS D ON I.PaymentId = D.PaymentId;
END;
GO

-- 3. ПОКУПКИ //////////////////////////////

CREATE OR ALTER TRIGGER dbo.trg_Purchase_AfterInsert
ON dbo.Purchase
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, UserId, Description)
    SELECT
        N'Purchase',
        N'INSERT',
        I.PurchaseId,
        I.UserId,
        CONCAT
        (
            N'Куплена книга BookId=', CONVERT(NVARCHAR(20), I.BookId),
            N'. Итоговая цена: ', CONVERT(NVARCHAR(30), I.PurchasePrice),
            N'. Скидка: ', CONVERT(NVARCHAR(20), I.AppliedDiscountPercent), N'%',
            N'. Промокод: ', ISNULL(I.AppliedPromoCode, N'не применялся'), N'.'
        )
    FROM inserted AS I;
END;
GO

-- 4. ПОДПИСКИ //////////////////////////////

CREATE OR ALTER TRIGGER dbo.trg_UserSubscription_AfterInsertUpdate
ON dbo.UserSubscription
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, UserId, Description)
    SELECT
        N'UserSubscription',
        CASE WHEN D.SubscriptionId IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
        I.SubscriptionId,
        I.UserId,
        CONCAT
        (
            N'Подписка PlanId=', CONVERT(NVARCHAR(20), I.PlanId),
            N'. Период: ', CONVERT(NVARCHAR(10), I.StartDate, 23),
            N' — ', CONVERT(NVARCHAR(10), I.EndDate, 23),
            N'. Активна: ', CONVERT(NVARCHAR(5), I.IsActive), N'.'
        )
    FROM inserted AS I
        LEFT JOIN deleted AS D ON I.SubscriptionId = D.SubscriptionId;
END;
GO

-- 5. ОТЗЫВЫ //////////////////////////////

CREATE OR ALTER TRIGGER dbo.trg_Review_AfterInsertUpdate
ON dbo.Review
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
    FROM inserted AS I
    WHERE dbo.fn_UserHasAccessToBook(I.UserId, I.BookId, CAST(GETDATE() AS DATE)) = 0
    )
    BEGIN
        RAISERROR(N'Нельзя сохранить отзыв к книге без доступа.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, UserId, Description)
    SELECT
        N'Review',
        CASE WHEN D.ReviewId IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
        I.ReviewId,
        I.UserId,
        CONCAT(N'Отзыв к книге BookId=', CONVERT(NVARCHAR(20), I.BookId), N'. Оценка: ', CONVERT(NVARCHAR(5), I.Rating), N'.')
    FROM inserted AS I
        LEFT JOIN deleted AS D ON I.ReviewId = D.ReviewId;
END;
GO

-- 6. ПРОГРЕСС ЧТЕНИЯ //////////////////////////////

CREATE OR ALTER TRIGGER dbo.trg_ReadingProgress_AfterInsertUpdate
ON dbo.ReadingProgress
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
    FROM inserted AS I
    WHERE dbo.fn_UserHasAccessToBook(I.UserId, I.BookId, CAST(GETDATE() AS DATE)) = 0
    )
    BEGIN
        RAISERROR(N'Нельзя сохранить прогресс книги без доступа.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, UserId, Description)
    SELECT
        N'ReadingProgress',
        CASE WHEN D.ProgressId IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
        I.ProgressId,
        I.UserId,
        CONCAT
        (
            N'Книга BookId=', CONVERT(NVARCHAR(20), I.BookId),
            N'. Страница: ', CONVERT(NVARCHAR(20), I.CurrentPage),
            N'. Прогресс: ', CONVERT(NVARCHAR(20), I.ProgressPercent), N'%.')
    FROM inserted AS I
        LEFT JOIN deleted AS D ON I.ProgressId = D.ProgressId;
END;
GO

-- 7. УДАЛЕНИЕ ПОЛЬЗОВАТЕЛЯ //////////////////////////////

CREATE OR ALTER TRIGGER dbo.trg_UserAccount_AfterDelete
ON dbo.UserAccount
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, Description)
    SELECT
        N'UserAccount',
        N'DELETE',
        D.UserId,
        CONCAT(N'Удалён пользователь: ', D.Username, N'. Email: ', D.Email, N'.')
    FROM deleted AS D;
END;
GO

-- 8. АКЦИИ //////////////////////////////

CREATE OR ALTER TRIGGER dbo.trg_Promotion_AfterInsertUpdate
ON dbo.Promotion
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, Description)
    SELECT
        N'Promotion',
        CASE WHEN D.PromotionId IS NULL THEN N'INSERT' ELSE N'UPDATE' END,
        I.PromotionId,
        CONCAT
        (
            N'Акция: ', I.PromotionName,
            N'. Код: ', I.PromoCode,
            N'. Скидка: ', CONVERT(NVARCHAR(20), I.DiscountPercent), N'%',
            N'. На все книги: ', CONVERT(NVARCHAR(5), I.AppliesToAllBooks),
            N'. Только в день рождения: ', CONVERT(NVARCHAR(5), I.RequiresBirthday), N'.'
        )
    FROM inserted AS I
        LEFT JOIN deleted AS D ON I.PromotionId = D.PromotionId;
END;
GO

-- 9. КНИГИ В АКЦИЯХ //////////////////////////////

CREATE OR ALTER TRIGGER dbo.trg_BookPromotion_AfterInsertDelete
ON dbo.BookPromotion
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, Description)
    SELECT
        N'BookPromotion',
        N'INSERT',
        I.BookId,
        CONCAT(N'Книга BookId=', CONVERT(NVARCHAR(20), I.BookId), N' добавлена в акцию PromotionId=', CONVERT(NVARCHAR(20), I.PromotionId), N'.')
    FROM inserted AS I;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, Description)
    SELECT
        N'BookPromotion',
        N'DELETE',
        D.BookId,
        CONCAT(N'Книга BookId=', CONVERT(NVARCHAR(20), D.BookId), N' удалена из акции PromotionId=', CONVERT(NVARCHAR(20), D.PromotionId), N'.')
    FROM deleted AS D;
END;
GO

SELECT
    T.name AS TriggerName,
    OBJECT_NAME(T.parent_id) AS TableName,
    T.is_disabled AS IsDisabled
FROM sys.triggers AS T
WHERE T.parent_class_desc = N'OBJECT_OR_COLUMN'
ORDER BY T.name;
GO
