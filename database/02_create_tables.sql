USE [BookStreamDB];
GO

/*
    02_create_tables.sql

    Физическая структура BookStreamDB.
    Таблицы удаляются и создаются заново, поэтому файл предназначен
    для чистой сборки учебной базы данных.
*/

-- УДАЛЕНИЕ СТАРЫХ ТАБЛИЦ //////////////////////////////

DROP TABLE IF EXISTS dbo.ReadingProgress;
DROP TABLE IF EXISTS dbo.FavoriteBook;
DROP TABLE IF EXISTS dbo.Review;
DROP TABLE IF EXISTS dbo.UserSubscription;
DROP TABLE IF EXISTS dbo.Purchase;
DROP TABLE IF EXISTS dbo.Payment;
DROP TABLE IF EXISTS dbo.BookContent;
DROP TABLE IF EXISTS dbo.BookPromotion;
DROP TABLE IF EXISTS dbo.BookGenre;
DROP TABLE IF EXISTS dbo.BookAuthor;
DROP TABLE IF EXISTS dbo.Promotion;
DROP TABLE IF EXISTS dbo.Book;
DROP TABLE IF EXISTS dbo.SubscriptionPlan;
DROP TABLE IF EXISTS dbo.Genre;
DROP TABLE IF EXISTS dbo.Author;
DROP TABLE IF EXISTS dbo.Publisher;
DROP TABLE IF EXISTS dbo.AuditLog;
DROP TABLE IF EXISTS dbo.UserAccount;
DROP TABLE IF EXISTS dbo.Role;
GO

-- 1. РОЛИ ПОЛЬЗОВАТЕЛЕЙ //////////////////////////////

CREATE TABLE dbo.Role
(
    RoleId INT IDENTITY(1,1) NOT NULL,
    RoleName NVARCHAR(50) NOT NULL,

    CONSTRAINT PK_Role PRIMARY KEY (RoleId),
    CONSTRAINT UQ_Role_RoleName UNIQUE (RoleName)
);
GO

-- 2. ПОЛЬЗОВАТЕЛИ //////////////////////////////

CREATE TABLE dbo.UserAccount
(
    UserId INT IDENTITY(1,1) NOT NULL,
    RoleId INT NOT NULL,
    Username NVARCHAR(100) NOT NULL,
    Email NVARCHAR(255) NOT NULL,
    PasswordHash NVARCHAR(255) NOT NULL,
    DateOfBirth DATE NULL,
    RegistrationDate DATETIME2 NOT NULL CONSTRAINT DF_UserAccount_RegistrationDate DEFAULT SYSDATETIME(),
    IsActive BIT NOT NULL CONSTRAINT DF_UserAccount_IsActive DEFAULT 1,
    Balance DECIMAL(10,2) NOT NULL CONSTRAINT DF_UserAccount_Balance DEFAULT 0,

    CONSTRAINT PK_UserAccount PRIMARY KEY (UserId),
    CONSTRAINT UQ_UserAccount_Username UNIQUE (Username),
    CONSTRAINT UQ_UserAccount_Email UNIQUE (Email),
    CONSTRAINT CK_UserAccount_Email CHECK (Email LIKE N'%@%.%'),
    CONSTRAINT CK_UserAccount_Balance CHECK (Balance >= 0),
    CONSTRAINT CK_UserAccount_DateOfBirth CHECK (DateOfBirth IS NULL OR DateOfBirth >= '1900-01-01'),

    CONSTRAINT FK_UserAccount_Role FOREIGN KEY (RoleId)
        REFERENCES dbo.Role(RoleId)
        ON DELETE NO ACTION
        ON UPDATE CASCADE
);
GO

-- 3. ЖУРНАЛ ДЕЙСТВИЙ //////////////////////////////

CREATE TABLE dbo.AuditLog
(
    LogId INT IDENTITY(1,1) NOT NULL,
    TableName NVARCHAR(100) NOT NULL,
    ActionName NVARCHAR(50) NOT NULL,
    RecordId INT NULL,
    UserId INT NULL,
    Description NVARCHAR(1000) NULL,
    CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_AuditLog_CreatedAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_AuditLog PRIMARY KEY (LogId),
    CONSTRAINT FK_AuditLog_UserAccount FOREIGN KEY (UserId)
        REFERENCES dbo.UserAccount(UserId)
        ON DELETE SET NULL
        ON UPDATE CASCADE
);
GO

-- 4. ИЗДАТЕЛЬСТВА //////////////////////////////

CREATE TABLE dbo.Publisher
(
    PublisherId INT IDENTITY(1,1) NOT NULL,
    PublisherName NVARCHAR(255) NOT NULL,

    CONSTRAINT PK_Publisher PRIMARY KEY (PublisherId),
    CONSTRAINT UQ_Publisher_PublisherName UNIQUE (PublisherName)
);
GO

-- 5. АВТОРЫ //////////////////////////////

CREATE TABLE dbo.Author
(
    AuthorId INT IDENTITY(1,1) NOT NULL,
    FirstName NVARCHAR(100) NOT NULL,
    LastName NVARCHAR(100) NOT NULL,

    CONSTRAINT PK_Author PRIMARY KEY (AuthorId),
    CONSTRAINT UQ_Author_FullName UNIQUE (FirstName, LastName)
);
GO

-- 6. ЖАНРЫ //////////////////////////////

CREATE TABLE dbo.Genre
(
    GenreId INT IDENTITY(1,1) NOT NULL,
    GenreName NVARCHAR(100) NOT NULL,

    CONSTRAINT PK_Genre PRIMARY KEY (GenreId),
    CONSTRAINT UQ_Genre_GenreName UNIQUE (GenreName)
);
GO

-- 7. КНИГИ //////////////////////////////

CREATE TABLE dbo.Book
(
    BookId INT IDENTITY(1,1) NOT NULL,
    PublisherId INT NOT NULL,
    Title NVARCHAR(255) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    PublicationYear INT NULL,
    AgeLimit INT NOT NULL CONSTRAINT DF_Book_AgeLimit DEFAULT 0,
    PageCount INT NOT NULL,
    Price DECIMAL(10,2) NOT NULL CONSTRAINT DF_Book_Price DEFAULT 0,
    IsFree BIT NOT NULL CONSTRAINT DF_Book_IsFree DEFAULT 0,
    IsPremium BIT NOT NULL CONSTRAINT DF_Book_IsPremium DEFAULT 0,
    IsAvailableBySubscription BIT NOT NULL CONSTRAINT DF_Book_IsAvailableBySubscription DEFAULT 1,
    CoverImageUrl NVARCHAR(500) NULL,
    CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_Book_CreatedAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_Book PRIMARY KEY (BookId),
    CONSTRAINT CK_Book_PublicationYear CHECK (PublicationYear IS NULL OR PublicationYear BETWEEN 1450 AND YEAR(GETDATE()) + 1),
    CONSTRAINT CK_Book_AgeLimit CHECK (AgeLimit IN (0, 6, 12, 16, 18)),
    CONSTRAINT CK_Book_PageCount CHECK (PageCount > 0),
    CONSTRAINT CK_Book_Price CHECK (Price >= 0),
    CONSTRAINT CK_Book_Premium CHECK (IsPremium = 0 OR (IsFree = 0 AND IsAvailableBySubscription = 0)),

    CONSTRAINT FK_Book_Publisher FOREIGN KEY (PublisherId)
        REFERENCES dbo.Publisher(PublisherId)
        ON DELETE NO ACTION
        ON UPDATE CASCADE
);
GO

-- 8. КНИГИ И АВТОРЫ //////////////////////////////

CREATE TABLE dbo.BookAuthor
(
    BookId INT NOT NULL,
    AuthorId INT NOT NULL,

    CONSTRAINT PK_BookAuthor PRIMARY KEY (BookId, AuthorId),
    CONSTRAINT FK_BookAuthor_Book FOREIGN KEY (BookId)
        REFERENCES dbo.Book(BookId)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_BookAuthor_Author FOREIGN KEY (AuthorId)
        REFERENCES dbo.Author(AuthorId)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
GO

-- 9. КНИГИ И ЖАНРЫ //////////////////////////////

CREATE TABLE dbo.BookGenre
(
    BookId INT NOT NULL,
    GenreId INT NOT NULL,

    CONSTRAINT PK_BookGenre PRIMARY KEY (BookId, GenreId),
    CONSTRAINT FK_BookGenre_Book FOREIGN KEY (BookId)
        REFERENCES dbo.Book(BookId)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_BookGenre_Genre FOREIGN KEY (GenreId)
        REFERENCES dbo.Genre(GenreId)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
GO

-- 10. СОДЕРЖИМОЕ КНИГ //////////////////////////////

CREATE TABLE dbo.BookContent
(
    BookContentId INT IDENTITY(1,1) NOT NULL,
    BookId INT NOT NULL,
    ContentText NVARCHAR(MAX) NOT NULL,
    ContentFormat NVARCHAR(20) NOT NULL CONSTRAINT DF_BookContent_ContentFormat DEFAULT N'TEXT',
    UploadedAt DATETIME2 NOT NULL CONSTRAINT DF_BookContent_UploadedAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_BookContent PRIMARY KEY (BookContentId),
    CONSTRAINT UQ_BookContent_BookId UNIQUE (BookId),
    CONSTRAINT CK_BookContent_ContentFormat CHECK (ContentFormat IN (N'TEXT', N'HTML', N'EPUB', N'PDF')),
    CONSTRAINT FK_BookContent_Book FOREIGN KEY (BookId)
        REFERENCES dbo.Book(BookId)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
GO

-- 11. ТАРИФЫ ПОДПИСКИ //////////////////////////////

CREATE TABLE dbo.SubscriptionPlan
(
    PlanId INT IDENTITY(1,1) NOT NULL,
    PlanName NVARCHAR(100) NOT NULL,
    Price DECIMAL(10,2) NOT NULL,
    DurationDays INT NOT NULL,
    Description NVARCHAR(500) NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_SubscriptionPlan_IsActive DEFAULT 1,

    CONSTRAINT PK_SubscriptionPlan PRIMARY KEY (PlanId),
    CONSTRAINT UQ_SubscriptionPlan_PlanName UNIQUE (PlanName),
    CONSTRAINT CK_SubscriptionPlan_Price CHECK (Price >= 0),
    CONSTRAINT CK_SubscriptionPlan_DurationDays CHECK (DurationDays > 0)
);
GO

-- 12. ПЛАТЕЖИ //////////////////////////////

CREATE TABLE dbo.Payment
(
    PaymentId INT IDENTITY(1,1) NOT NULL,
    UserId INT NOT NULL,
    Amount DECIMAL(10,2) NOT NULL,
    PaymentDate DATETIME2 NOT NULL CONSTRAINT DF_Payment_PaymentDate DEFAULT SYSDATETIME(),
    PaymentMethod NVARCHAR(50) NOT NULL,
    PaymentStatus NVARCHAR(30) NOT NULL CONSTRAINT DF_Payment_PaymentStatus DEFAULT N'Success',
    TransactionNumber NVARCHAR(100) NULL,

    CONSTRAINT PK_Payment PRIMARY KEY (PaymentId),
    CONSTRAINT UQ_Payment_TransactionNumber UNIQUE (TransactionNumber),
    CONSTRAINT CK_Payment_Amount CHECK (Amount >= 0),
    CONSTRAINT CK_Payment_Method CHECK (PaymentMethod IN (N'Card', N'OnlineWallet', N'Bonus', N'Balance')),
    CONSTRAINT CK_Payment_Status CHECK (PaymentStatus IN (N'Success', N'Failed', N'Pending', N'Refunded')),
    CONSTRAINT FK_Payment_UserAccount FOREIGN KEY (UserId)
        REFERENCES dbo.UserAccount(UserId)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
GO

-- 13. ПОКУПКИ КНИГ //////////////////////////////

CREATE TABLE dbo.Purchase
(
    PurchaseId INT IDENTITY(1,1) NOT NULL,
    UserId INT NOT NULL,
    BookId INT NOT NULL,
    PaymentId INT NULL,
    PurchaseDate DATETIME2 NOT NULL CONSTRAINT DF_Purchase_PurchaseDate DEFAULT SYSDATETIME(),
    PurchasePrice DECIMAL(10,2) NOT NULL,
    AppliedPromoCode NVARCHAR(50) NULL,
    AppliedDiscountPercent DECIMAL(5,2) NOT NULL CONSTRAINT DF_Purchase_AppliedDiscount DEFAULT 0,

    CONSTRAINT PK_Purchase PRIMARY KEY (PurchaseId),
    CONSTRAINT UQ_Purchase_User_Book UNIQUE (UserId, BookId),
    CONSTRAINT CK_Purchase_Price CHECK (PurchasePrice >= 0),
    CONSTRAINT CK_Purchase_Discount CHECK (AppliedDiscountPercent BETWEEN 0 AND 100),
    CONSTRAINT FK_Purchase_UserAccount FOREIGN KEY (UserId)
        REFERENCES dbo.UserAccount(UserId)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_Purchase_Book FOREIGN KEY (BookId)
        REFERENCES dbo.Book(BookId)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_Purchase_Payment FOREIGN KEY (PaymentId)
        REFERENCES dbo.Payment(PaymentId)
        ON DELETE NO ACTION
        ON UPDATE NO ACTION
);
GO

-- 14. ПОДПИСКИ ПОЛЬЗОВАТЕЛЕЙ //////////////////////////////

CREATE TABLE dbo.UserSubscription
(
    SubscriptionId INT IDENTITY(1,1) NOT NULL,
    UserId INT NOT NULL,
    PlanId INT NOT NULL,
    PaymentId INT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_UserSubscription_IsActive DEFAULT 1,

    CONSTRAINT PK_UserSubscription PRIMARY KEY (SubscriptionId),
    CONSTRAINT CK_UserSubscription_Dates CHECK (EndDate > StartDate),
    CONSTRAINT FK_UserSubscription_UserAccount FOREIGN KEY (UserId)
        REFERENCES dbo.UserAccount(UserId)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_UserSubscription_SubscriptionPlan FOREIGN KEY (PlanId)
        REFERENCES dbo.SubscriptionPlan(PlanId)
        ON DELETE NO ACTION
        ON UPDATE CASCADE,
    CONSTRAINT FK_UserSubscription_Payment FOREIGN KEY (PaymentId)
        REFERENCES dbo.Payment(PaymentId)
        ON DELETE NO ACTION
        ON UPDATE NO ACTION
);
GO

-- 15. ОТЗЫВЫ //////////////////////////////

CREATE TABLE dbo.Review
(
    ReviewId INT IDENTITY(1,1) NOT NULL,
    UserId INT NOT NULL,
    BookId INT NOT NULL,
    Rating INT NOT NULL,
    ReviewText NVARCHAR(1000) NULL,
    CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_Review_CreatedAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_Review PRIMARY KEY (ReviewId),
    CONSTRAINT UQ_Review_User_Book UNIQUE (UserId, BookId),
    CONSTRAINT CK_Review_Rating CHECK (Rating BETWEEN 1 AND 5),
    CONSTRAINT FK_Review_UserAccount FOREIGN KEY (UserId)
        REFERENCES dbo.UserAccount(UserId)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_Review_Book FOREIGN KEY (BookId)
        REFERENCES dbo.Book(BookId)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
GO

-- 16. ИЗБРАННОЕ //////////////////////////////

CREATE TABLE dbo.FavoriteBook
(
    UserId INT NOT NULL,
    BookId INT NOT NULL,
    AddedAt DATETIME2 NOT NULL CONSTRAINT DF_FavoriteBook_AddedAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_FavoriteBook PRIMARY KEY (UserId, BookId),
    CONSTRAINT FK_FavoriteBook_UserAccount FOREIGN KEY (UserId)
        REFERENCES dbo.UserAccount(UserId)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_FavoriteBook_Book FOREIGN KEY (BookId)
        REFERENCES dbo.Book(BookId)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
GO

-- 17. ПРОГРЕСС ЧТЕНИЯ //////////////////////////////

CREATE TABLE dbo.ReadingProgress
(
    ProgressId INT IDENTITY(1,1) NOT NULL,
    UserId INT NOT NULL,
    BookId INT NOT NULL,
    CurrentPage INT NOT NULL CONSTRAINT DF_ReadingProgress_CurrentPage DEFAULT 1,
    ProgressPercent DECIMAL(5,2) NOT NULL CONSTRAINT DF_ReadingProgress_ProgressPercent DEFAULT 0,
    LastReadAt DATETIME2 NOT NULL CONSTRAINT DF_ReadingProgress_LastReadAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_ReadingProgress PRIMARY KEY (ProgressId),
    CONSTRAINT UQ_ReadingProgress_User_Book UNIQUE (UserId, BookId),
    CONSTRAINT CK_ReadingProgress_CurrentPage CHECK (CurrentPage > 0),
    CONSTRAINT CK_ReadingProgress_Percent CHECK (ProgressPercent BETWEEN 0 AND 100),
    CONSTRAINT FK_ReadingProgress_UserAccount FOREIGN KEY (UserId)
        REFERENCES dbo.UserAccount(UserId)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_ReadingProgress_Book FOREIGN KEY (BookId)
        REFERENCES dbo.Book(BookId)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
GO

-- 18. АКЦИИ И СКИДКИ //////////////////////////////

CREATE TABLE dbo.Promotion
(
    PromotionId INT IDENTITY(1,1) NOT NULL,
    PromotionName NVARCHAR(255) NOT NULL,
    PromoCode NVARCHAR(50) NOT NULL,
    DiscountPercent DECIMAL(5,2) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    IsActive BIT NOT NULL CONSTRAINT DF_Promotion_IsActive DEFAULT 1,
    AppliesToAllBooks BIT NOT NULL CONSTRAINT DF_Promotion_AppliesToAllBooks DEFAULT 0,
    RequiresBirthday BIT NOT NULL CONSTRAINT DF_Promotion_RequiresBirthday DEFAULT 0,
    IsSystem BIT NOT NULL CONSTRAINT DF_Promotion_IsSystem DEFAULT 0,
    CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_Promotion_CreatedAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_Promotion PRIMARY KEY (PromotionId),
    CONSTRAINT UQ_Promotion_PromoCode UNIQUE (PromoCode),
    CONSTRAINT CK_Promotion_DiscountPercent CHECK (DiscountPercent > 0 AND DiscountPercent <= 100),
    CONSTRAINT CK_Promotion_Dates CHECK (EndDate >= StartDate),
    CONSTRAINT CK_Promotion_Birthday CHECK (RequiresBirthday = 0 OR AppliesToAllBooks = 1)
);
GO

-- 19. КНИГИ И АКЦИИ //////////////////////////////

CREATE TABLE dbo.BookPromotion
(
    PromotionId INT NOT NULL,
    BookId INT NOT NULL,
    AssignedAt DATETIME2 NOT NULL CONSTRAINT DF_BookPromotion_AssignedAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_BookPromotion PRIMARY KEY (PromotionId, BookId),
    CONSTRAINT FK_BookPromotion_Promotion FOREIGN KEY (PromotionId)
        REFERENCES dbo.Promotion(PromotionId)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT FK_BookPromotion_Book FOREIGN KEY (BookId)
        REFERENCES dbo.Book(BookId)
        ON DELETE CASCADE
        ON UPDATE CASCADE
);
GO

SELECT TABLE_SCHEMA, TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
GO
