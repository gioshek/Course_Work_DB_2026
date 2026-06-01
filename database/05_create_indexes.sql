USE [BookStreamDB];
GO

/*
    05_create_indexes.sql

    Индексы ускоряют поиск, связи и отчёты.
*/

-- 1. ПОЛЬЗОВАТЕЛИ //////////////////////////////

CREATE INDEX IX_UserAccount_RoleId ON dbo.UserAccount(RoleId);
CREATE INDEX IX_UserAccount_DateOfBirth ON dbo.UserAccount(DateOfBirth);
GO

-- 2. КНИГИ И СПРАВОЧНИКИ //////////////////////////////

CREATE INDEX IX_Book_PublisherId ON dbo.Book(PublisherId);
CREATE INDEX IX_Book_Title ON dbo.Book(Title);
CREATE INDEX IX_Book_SubscriptionPremium ON dbo.Book(IsAvailableBySubscription, IsPremium);
CREATE INDEX IX_BookAuthor_AuthorId ON dbo.BookAuthor(AuthorId, BookId);
CREATE INDEX IX_BookGenre_GenreId ON dbo.BookGenre(GenreId, BookId);
GO

-- 3. ФИНАНСЫ И ПОДПИСКИ //////////////////////////////

CREATE INDEX IX_Payment_UserDate ON dbo.Payment(UserId, PaymentDate DESC);
CREATE INDEX IX_Purchase_BookId ON dbo.Purchase(BookId, PurchaseDate DESC);
CREATE INDEX IX_UserSubscription_UserDates ON dbo.UserSubscription(UserId, IsActive, StartDate, EndDate);
GO

-- 4. ПОЛЬЗОВАТЕЛЬСКАЯ АКТИВНОСТЬ //////////////////////////////

CREATE INDEX IX_Review_BookId ON dbo.Review(BookId, CreatedAt DESC);
CREATE INDEX IX_FavoriteBook_BookId ON dbo.FavoriteBook(BookId, AddedAt DESC);
CREATE INDEX IX_ReadingProgress_UserId ON dbo.ReadingProgress(UserId, LastReadAt DESC);
GO

-- 5. АКЦИИ //////////////////////////////

CREATE INDEX IX_Promotion_ActiveDates ON dbo.Promotion(IsActive, StartDate, EndDate);
CREATE INDEX IX_Promotion_GlobalBirthday ON dbo.Promotion(AppliesToAllBooks, RequiresBirthday, IsSystem);
CREATE INDEX IX_BookPromotion_BookId ON dbo.BookPromotion(BookId, PromotionId);
GO
