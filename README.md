# Cahoot Developer Practical Test

## Tech Stack

- ASP.NET Core MVC
- SQL Server
- Dapper
- Docker (for local SQL Server on macOS)

## Local Setup

1. Start SQL Server Docker container
2. Ensure StackOverflow2013 database is attached
3. Update appsettings.Development.json with SQL connection string
4. Run the app with `dotnet run`

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

## Assumptions

- PostTypeId 1 = Question, 2 = Answer
- VoteTypeId 2 = Upvote, 3 = Downvote
- Active users = users who posted or voted in a week
- Accepted answers counted by accepted answer creation week

## Limitation

Full-Text Search was not available in the local SQL Server environment, so the app uses an indexed title-prefix search fallback instead of full-text title/body search.
