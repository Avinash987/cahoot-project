# Cahoot Developer Practical Test

## Tech Stack

- ASP.NET Core MVC
- SQL Server
- Dapper
- Docker (for local SQL Server on macOS)

## Local Setup

1. Start SQL Server locally or in Docker on port 1433.
2. Attach or restore the `StackOverflow2013` database.
3. Update `src/StackOverflowSearchWeb/appsettings.json` or user secrets with the `StackOverflowDb` connection string.
4. Apply the supporting indexes by running the SQL scripts in `sql/`.
5. Run the app:

```bash
dotnet run --project src/StackOverflowSearchWeb/StackOverflowSearchWeb.csproj
```

## Search Behavior

- Question-only search
- Title-prefix matching
- 10 results per page
- Progressive loading via Load More
- Browser notification after loading more results

## SQL Deliverables

- sql/01-task-2.sql
- sql/02-task-3.sql
- sql/03-search-query.sql

## Documentation

- docs/run-instructions.md
- docs/methodology.md

## Assumptions

- PostTypeId 1 = Question, 2 = Answer
- VoteTypeId 2 = Upvote, 3 = Downvote
- Active users = users who posted or voted in a week
- Accepted answers counted by accepted answer creation week

## Limitation

Full-Text Search was not available in the local SQL Server environment, so the app uses an indexed title-prefix search fallback instead of full-text title/body search.
