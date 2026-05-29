USE [BookStreamDB];
GO

UPDATE dbo.UserAccount
SET
    PasswordHash = N'admin123',
    Balance = 5000.00
WHERE Username = N'admin';
GO

UPDATE dbo.UserAccount
SET
    PasswordHash = N'1234',
    Balance = 1102.00
WHERE Username = N'giorgi';
GO

SELECT
    U.UserId,
    U.Username,
    U.Email,
    U.Balance,
    R.RoleName
FROM dbo.UserAccount AS U
    INNER JOIN dbo.Role AS R ON U.RoleId = R.RoleId
ORDER BY U.UserId;
GO
