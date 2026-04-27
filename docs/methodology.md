# Methodology and Assumptions

## Task 1 - Search Web App

I built the search app as an ASP.NET Core MVC application using Dapper for SQL access. I kept the flow simple: the controller accepts the query and page, the search service runs the SQL query, and the Razor views render 10 results at a time. The page supports progressive loading with a `Load More` button, so the next page is fetched asynchronously and appended without a full page reload.

Each result shows the question title, a cleaned 140-character preview, net vote score, answer count, asking user, reputation, and badge count. I used a badge count instead of concatenating badge names because it is compact, fast to calculate, and fits better in a search result row.

My first search approach used broad text matching, but that was too slow on the local StackOverflow database because SQL Server Full-Text Search was not installed in this environment. I changed the search to a practical indexed fallback: collect bounded question candidates from title and tag matches, add answer rows under those matching questions, and only enrich the current page with votes, answer counts, users, and badges. That kept the UI responsive while still using the real database.

I added supporting indexes for the search access path: question title lookup, tag lookup, answer lookup by parent question, vote lookup by post and vote type, and badge lookup by user. The main tradeoff is that this local version favors fast, explainable search behavior over full semantic title/body search.

I also added a browser notification tied to progressive loading. When the browser allows notifications, the app can notify the user after more results are loaded. I added an explicit button for requesting notification permission and a visible fallback alert when notifications are unsupported or blocked.

For the Credential Management API extra-credit item, I added a small browser-side demo that can remember a display name using `PasswordCredential` where the browser supports it. This is intentionally not a full login system or real cross-device authentication.

## Task 2 - Day-of-Week Vote Ratio Query

For Task 2, I treated `PostTypeId = 1` as questions and `PostTypeId = 2` as answers. I grouped posts by the weekday of `Posts.CreationDate`, because the requirement asks for question and answer counts by day of the week.

I did not join raw vote rows directly into the final grouping. Instead, I first aggregated votes by `PostId`, using `VoteTypeId = 2` for upvotes and `VoteTypeId = 3` for downvotes. Then I joined those post-level vote totals back to posts and rolled the data up by post type and weekday. This keeps the row volume lower and avoids accidentally inflating post counts.

For the upvote-to-downvote ratio, I used `NULLIF` so the query does not fail when a group has zero downvotes. The most useful supporting index for this query pattern is on `Votes(PostId, VoteTypeId)`, because the expensive part is getting vote totals per post.

My assumptions for this task were:

- `PostTypeId = 1` means question and `PostTypeId = 2` means answer.
- `VoteTypeId = 2` means upvote and `VoteTypeId = 3` means downvote.
- Day-of-week grouping is based on post creation date, not vote creation date.

## Task 3 - Weekly Aggregate Query

For Task 3, I mapped each metric to the table and date column that best represented it. Questions and answers come from `Posts.CreationDate`, votes come from `Votes.CreationDate`, and new users come from `Users.CreationDate`. Accepted answers are found by joining a question to its `AcceptedAnswerId`; because the schema does not include an explicit acceptance timestamp, I counted accepted answers by the accepted answer post's creation week.

I defined active users as distinct users who either posted or voted during the week. That definition is simple, traceable to the available schema, and uses activity that exists in the database.

I first wrote the report as one combined query to validate the logic, but the full version was too slow and hard for SQL Server to optimize. I changed the shape to staged aggregation: each weekly metric is written into its own temp table, each temp table gets a clustered index on `WeekStart`, and the final query joins compact weekly summaries instead of repeatedly processing the large base tables.

I also added targeted indexes for the base-table access patterns: accepted-answer lookup, post creation date grouping, vote creation date and user grouping, and user creation date grouping. This kept the query understandable while making it much more practical to run on the provided dataset.

My assumptions for this task were:

- Accepted answers are counted by the accepted answer post's creation week.
- Active users are distinct users who either posted or voted in that week.
- The first date of the week is calculated with SQL Server's `DATEADD(WEEK, DATEDIFF(WEEK, 0, date), 0)` expression.
- The Credential Management API work is a small browser API demo, not a full authentication system.
