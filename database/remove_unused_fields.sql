USE [BookStreamDB];
GO

EXEC dbo.usp_GetBookCatalog
    @SearchText = NULL,
    @GenreName = NULL,
    @OnlyFree = NULL,
    @AvailableBySubscription = NULL,
    @OnlyPremium = NULL;
GO