# Run Instructions

## Prerequisites

- .NET 9 SDK
- SQL Server running locally or in Docker
- `StackOverflow2013` database restored or attached

## Configure the Database

Update the `StackOverflowDb` connection string in `src/StackOverflowSearchWeb/appsettings.json` if your SQL Server credentials or port differ from the local defaults.

Apply the SQL deliverables before testing the app:

```bash
docker exec -i sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong!Passw0rd' -C \
  -d StackOverflow2013 < sql/03-search-query.sql

docker exec -i sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong!Passw0rd' -C \
  -d StackOverflow2013 < sql/01-task-2.sql

docker exec -i sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong!Passw0rd' -C \
  -d StackOverflow2013 < sql/02-task-3.sql
```

If SQL Server is not running in Docker, run the same scripts from SQL Server Management Studio, Azure Data Studio, or `sqlcmd`.

## Build and Run

```bash
dotnet build CahootPractical.sln
dotnet run --project src/StackOverflowSearchWeb/StackOverflowSearchWeb.csproj
```

Open the URL printed by ASP.NET Core. The default route opens the search page.

## App Verification

Try searches such as:

- `java`
- `java 8`
- `controllers`

The page returns 10 results at a time. Use `Load More` for progressive loading. If the browser grants notification permission, the app sends a notification after loading an additional page of results.
