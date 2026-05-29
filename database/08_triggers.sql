USE [BookStreamDB];
GO

/*
    08_triggers.sql

    Триггеры для BookStreamDB.

    Триггеры реализуют:
    - логирование действий в таблицу AuditLog;
    - проверку доступа пользователя перед добавлением отзыва;
    - автоматическое создание прогресса чтения после покупки книги;
    - проверку корректности прогресса чтения;
    - логирование платежей, покупок, подписок и изменений книг.
*/

-- Таблица AuditLog создаётся в файле 02_create_tables.sql.
-- Здесь находятся только триггеры, которые записывают туда события.

-- 1. ТРИГГЕР НА ИЗМЕНЕНИЕ КНИГ //////////////////////////////
-- Проверяет правило:
-- если книга бесплатная, её цена должна быть 0.
-- Также логирует добавление и изменение книг.

CREATE OR ALTER TRIGGER dbo.trg_Book_AfterInsertUpdate
ON dbo.Book
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
    FROM inserted
    WHERE IsFree = 1
        AND Price <> 0
    )
    BEGIN
        RAISERROR(N'Бесплатная книга должна иметь цену 0.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    -- Если есть deleted, значит это UPDATE.
    IF EXISTS (SELECT 1
    FROM deleted)
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'Book',
            N'UPDATE',
            I.BookId,
            NULL,
            CONCAT
            (
                N'Изменена книга: ', I.Title,
                N'. Старая цена: ', CONVERT(NVARCHAR(50), D.Price),
                N', новая цена: ', CONVERT(NVARCHAR(50), I.Price),
                N'. Бесплатная: ', CONVERT(NVARCHAR(10), I.IsFree),
                N'. По подписке: ', CONVERT(NVARCHAR(10), I.IsAvailableBySubscription)
            )
        FROM inserted AS I
            INNER JOIN deleted AS D ON I.BookId = D.BookId
        WHERE
            ISNULL(I.Price, -1) <> ISNULL(D.Price, -1)
            OR ISNULL(I.IsFree, 0) <> ISNULL(D.IsFree, 0)
            OR ISNULL(I.IsAvailableBySubscription, 0) <> ISNULL(D.IsAvailableBySubscription, 0);
    END
    ELSE
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'Book',
            N'INSERT',
            I.BookId,
            NULL,
            CONCAT(N'Добавлена книга: ', I.Title)
        FROM inserted AS I;
    END;
END;
GO

-- 3. ТРИГГЕР НА ПЛАТЕЖИ //////////////////////////////
-- Логирует создание и изменение платежей.

CREATE OR ALTER TRIGGER dbo.trg_Payment_AfterInsertUpdate
ON dbo.Payment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
    FROM deleted)
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'Payment',
            N'UPDATE',
            I.PaymentId,
            I.UserId,
            CONCAT
            (
                N'Изменён платёж. Сумма: ',
                CONVERT(NVARCHAR(50), I.Amount),
                N'. Статус: ',
                I.PaymentStatus
            )
        FROM inserted AS I;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'Payment',
            N'INSERT',
            I.PaymentId,
            I.UserId,
            CONCAT
            (
                N'Создан платёж. Сумма: ',
                CONVERT(NVARCHAR(50), I.Amount),
                N'. Метод оплаты: ',
                I.PaymentMethod,
                N'. Статус: ',
                I.PaymentStatus
            )
        FROM inserted AS I;
    END;
END;
GO

-- 4. ТРИГГЕР НА ПОКУПКИ //////////////////////////////
-- После покупки:
-- 1) логирует покупку;
-- 2) автоматически создаёт прогресс чтения с первой страницы,
-- если прогресса ещё нет.

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
            N'Пользователь купил книгу: ',
            B.Title,
            N'. Цена покупки: ',
            CONVERT(NVARCHAR(50), I.PurchasePrice)
        )
    FROM inserted AS I
        INNER JOIN dbo.Book AS B ON I.BookId = B.BookId;

    INSERT INTO dbo.ReadingProgress
        (UserId, BookId, CurrentPage, ProgressPercent)
    SELECT
        I.UserId,
        I.BookId,
        1,
        0
    FROM inserted AS I
    WHERE NOT EXISTS
    (
        SELECT 1
    FROM dbo.ReadingProgress AS RP
    WHERE RP.UserId = I.UserId
        AND RP.BookId = I.BookId
    );
END;
GO

-- 5. ТРИГГЕР НА ПОДПИСКИ //////////////////////////////
-- Логирует создание и изменение подписки.

CREATE OR ALTER TRIGGER dbo.trg_UserSubscription_AfterInsertUpdate
ON dbo.UserSubscription
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS
    (
        SELECT 1
    FROM inserted
    WHERE EndDate <= StartDate
    )
    BEGIN
        RAISERROR(N'Дата окончания подписки должна быть больше даты начала.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    IF EXISTS (SELECT 1
    FROM deleted)
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'UserSubscription',
            N'UPDATE',
            I.SubscriptionId,
            I.UserId,
            CONCAT
            (
                N'Изменена подписка. PlanId: ',
                CONVERT(NVARCHAR(20), I.PlanId),
                N'. Период: ',
                CONVERT(NVARCHAR(30), I.StartDate),
                N' - ',
                CONVERT(NVARCHAR(30), I.EndDate),
                N'. Активна: ',
                CONVERT(NVARCHAR(10), I.IsActive)
            )
        FROM inserted AS I;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'UserSubscription',
            N'INSERT',
            I.SubscriptionId,
            I.UserId,
            CONCAT
            (
                N'Создана подписка. PlanId: ',
                CONVERT(NVARCHAR(20), I.PlanId),
                N'. Период: ',
                CONVERT(NVARCHAR(30), I.StartDate),
                N' - ',
                CONVERT(NVARCHAR(30), I.EndDate)
            )
        FROM inserted AS I;
    END;
END;
GO

-- 6. ТРИГГЕР НА ОТЗЫВЫ //////////////////////////////
-- Проверяет, что пользователь имеет доступ к книге.
-- Если доступа нет, отзыв запрещается.

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
        RAISERROR(N'Пользователь не имеет доступа к книге и не может оставить отзыв.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    IF EXISTS (SELECT 1
    FROM deleted)
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'Review',
            N'UPDATE',
            I.ReviewId,
            I.UserId,
            CONCAT
            (
                N'Изменён отзыв на книгу BookId=',
                CONVERT(NVARCHAR(20), I.BookId),
                N'. Рейтинг: ',
                CONVERT(NVARCHAR(20), I.Rating)
            )
        FROM inserted AS I;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'Review',
            N'INSERT',
            I.ReviewId,
            I.UserId,
            CONCAT
            (
                N'Добавлен отзыв на книгу BookId=',
                CONVERT(NVARCHAR(20), I.BookId),
                N'. Рейтинг: ',
                CONVERT(NVARCHAR(20), I.Rating)
            )
        FROM inserted AS I;
    END;
END;
GO

-- 7. ТРИГГЕР НА ПРОГРЕСС ЧТЕНИЯ //////////////////////////////
-- Проверяет:
-- 1) пользователь имеет доступ к книге;
-- 2) текущая страница не больше количества страниц книги.

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
        INNER JOIN dbo.Book AS B ON I.BookId = B.BookId
    WHERE I.CurrentPage > B.PageCount
    )
    BEGIN
        RAISERROR(N'Текущая страница не может быть больше количества страниц книги.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    IF EXISTS
    (
        SELECT 1
    FROM inserted AS I
    WHERE dbo.fn_UserHasAccessToBook(I.UserId, I.BookId, CAST(GETDATE() AS DATE)) = 0
    )
    BEGIN
        RAISERROR(N'Пользователь не имеет доступа к книге, поэтому прогресс чтения не может быть сохранён.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    IF EXISTS (SELECT 1
    FROM deleted)
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'ReadingProgress',
            N'UPDATE',
            I.ProgressId,
            I.UserId,
            CONCAT
            (
                N'Обновлён прогресс чтения. BookId=',
                CONVERT(NVARCHAR(20), I.BookId),
                N'. Страница: ',
                CONVERT(NVARCHAR(20), I.CurrentPage),
                N'. Процент: ',
                CONVERT(NVARCHAR(20), I.ProgressPercent)
            )
        FROM inserted AS I;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'ReadingProgress',
            N'INSERT',
            I.ProgressId,
            I.UserId,
            CONCAT
            (
                N'Создан прогресс чтения. BookId=',
                CONVERT(NVARCHAR(20), I.BookId),
                N'. Страница: ',
                CONVERT(NVARCHAR(20), I.CurrentPage),
                N'. Процент: ',
                CONVERT(NVARCHAR(20), I.ProgressPercent)
            )
        FROM inserted AS I;
    END;
END;
GO

-- 8. ТРИГГЕР НА УДАЛЕНИЕ ПОЛЬЗОВАТЕЛЯ //////////////////////////////
-- Логирует удаление пользователя.
-- В AuditLog нет внешнего ключа на UserAccount,
-- поэтому лог не удалится каскадно.

CREATE OR ALTER TRIGGER dbo.trg_UserAccount_AfterDelete
ON dbo.UserAccount
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, UserId, Description)
    SELECT
        N'UserAccount',
        N'DELETE',
        D.UserId,
        D.UserId,
        CONCAT
        (
            N'Удалён пользователь: ',
            D.Username,
            N', email: ',
            D.Email
        )
    FROM deleted AS D;
END;
GO

-- 9. ТРИГГЕРЫ ДЛЯ АКЦИЙ И ПРИВЯЗКИ КНИГ //////////////////////////////

CREATE OR ALTER TRIGGER dbo.trg_Promotion_AfterInsertUpdate
ON dbo.Promotion
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1
    FROM deleted)
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'Promotion',
            N'UPDATE',
            I.PromotionId,
            NULL,
            CONCAT
            (
                N'Изменена акция: ', I.PromotionName,
                N'. Промокод: ', I.PromoCode,
                N'. Скидка: ', CONVERT(NVARCHAR(20), I.DiscountPercent), N'%.',
                N' Активна: ', CONVERT(NVARCHAR(10), I.IsActive)
            )
        FROM inserted AS I;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.AuditLog
            (TableName, ActionName, RecordId, UserId, Description)
        SELECT
            N'Promotion',
            N'INSERT',
            I.PromotionId,
            NULL,
            CONCAT
            (
                N'Создана акция: ', I.PromotionName,
                N'. Промокод: ', I.PromoCode,
                N'. Скидка: ', CONVERT(NVARCHAR(20), I.DiscountPercent), N'%.'
            )
        FROM inserted AS I;
    END;
END;
GO

CREATE OR ALTER TRIGGER dbo.trg_BookPromotion_AfterInsertDelete
ON dbo.BookPromotion
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, UserId, Description)
    SELECT
        N'BookPromotion',
        N'INSERT',
        I.BookId,
        NULL,
        CONCAT
        (
            N'Книга добавлена в акцию. BookId: ',
            CONVERT(NVARCHAR(20), I.BookId),
            N', PromotionId: ',
            CONVERT(NVARCHAR(20), I.PromotionId)
        )
    FROM inserted AS I;

    INSERT INTO dbo.AuditLog
        (TableName, ActionName, RecordId, UserId, Description)
    SELECT
        N'BookPromotion',
        N'DELETE',
        D.BookId,
        NULL,
        CONCAT
        (
            N'Книга удалена из акции. BookId: ',
            CONVERT(NVARCHAR(20), D.BookId),
            N', PromotionId: ',
            CONVERT(NVARCHAR(20), D.PromotionId)
        )
    FROM deleted AS D;
END;
GO

-- ПРОВЕРКА СОЗДАННЫХ ТРИГГЕРОВ //////////////////////////////

SELECT
    T.name AS TriggerName,
    OBJECT_NAME(T.parent_id) AS TableName,
    T.is_disabled AS IsDisabled
FROM sys.triggers AS T
WHERE T.is_ms_shipped = 0
ORDER BY
    OBJECT_NAME(T.parent_id),
    T.name;
GO

-- БЕЗОПАСНЫЙ ТЕСТ ТРИГГЕРОВ //////////////////////////////
-- Тест выполняется внутри транзакции и затем откатывается.
-- То есть данные после теста не изменятся.

BEGIN TRANSACTION;

DECLARE @TestPaymentId INT;

IF NOT EXISTS
(
    SELECT 1
FROM dbo.Purchase
WHERE UserId = 3
    AND BookId = 3
)
BEGIN
    INSERT INTO dbo.Payment
        (UserId, Amount, PaymentMethod, PaymentStatus, TransactionNumber)
    VALUES
        (
            3,
            299.00,
            N'Card',
            N'Success',
            N'TRX-TRIGGER-TEST-' + CONVERT(NVARCHAR(36), NEWID())
        );

    SET @TestPaymentId = CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.Purchase
        (UserId, BookId, PaymentId, PurchasePrice)
    VALUES
        (3, 3, @TestPaymentId, 299.00);
END;

IF EXISTS
(
    SELECT 1
FROM dbo.Review
WHERE UserId = 3
    AND BookId = 3
)
BEGIN
    UPDATE dbo.Review
    SET
        Rating = 5,
        ReviewText = N'Тестовое обновление отзыва через триггер.',
        CreatedAt = SYSDATETIME()
    WHERE UserId = 3
        AND BookId = 3;
END
ELSE
BEGIN
    INSERT INTO dbo.Review
        (UserId, BookId, Rating, ReviewText)
    VALUES
        (3, 3, 5, N'Тестовый отзыв через триггер.');
END;

UPDATE dbo.ReadingProgress
SET
    CurrentPage = 10,
    ProgressPercent = dbo.fn_CalculateReadingProgressPercent(10, 328),
    LastReadAt = SYSDATETIME()
WHERE UserId = 3
    AND BookId = 3;

SELECT TOP 20
    LogId,
    TableName,
    ActionName,
    RecordId,
    UserId,
    Description,
    CreatedAt
FROM dbo.AuditLog
ORDER BY LogId DESC;

SELECT
    UserId,
    BookId,
    CurrentPage,
    ProgressPercent,
    LastReadAt
FROM dbo.ReadingProgress
WHERE UserId = 3
    AND BookId = 3;

ROLLBACK TRANSACTION;
GO

-- ПРОВЕРКА, ЧТО ПОСЛЕ ROLLBACK ТЕСТОВЫЕ ДАННЫЕ НЕ СОХРАНИЛИСЬ //////////////////////////////

SELECT TOP 20
    LogId,
    TableName,
    ActionName,
    RecordId,
    UserId,
    Description,
    CreatedAt
FROM dbo.AuditLog
ORDER BY LogId DESC;
GO

-- ПРИМЕРЫ ОШИБОК, КОТОРЫЕ ТРИГГЕРЫ ДОЛЖНЫ ЗАПРЕЩАТЬ //////////////////////////////
-- Пока оставлены закомментированными.

-- Ошибка: бесплатная книга с ценой больше 0.
-- UPDATE dbo.Book
-- SET IsFree = 1,
--     Price = 100
-- WHERE BookId = 1;
-- GO

-- Ошибка: отзыв на книгу без доступа.
-- INSERT INTO dbo.Review
--     (UserId, BookId, Rating, ReviewText)
-- VALUES
--     (2, 6, 5, N'Пытаюсь оставить отзыв без доступа.');
-- GO

-- Ошибка: прогресс чтения больше количества страниц.
-- UPDATE dbo.ReadingProgress
-- SET CurrentPage = 99999
-- WHERE UserId = 2
--   AND BookId = 1;
-- GO
