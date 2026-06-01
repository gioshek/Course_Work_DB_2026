USE [BookStreamDB];
GO

/*
    Учебные демонстрационные пароли.
    Для production-системы нужно хранить только bcrypt-хеши.
*/

UPDATE dbo.UserAccount SET PasswordHash = N'admin123' WHERE Username = N'admin';
UPDATE dbo.UserAccount SET PasswordHash = N'1234' WHERE Username IN (N'giorgi', N'anna_reader', N'besik_books');
GO

SELECT UserId, Username, Email, DateOfBirth, IsActive, Balance
FROM dbo.UserAccount
ORDER BY UserId;
GO
