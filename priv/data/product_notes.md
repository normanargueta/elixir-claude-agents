# Northwind Analytics - Product Notes

## What the product does

Northwind Analytics ingests event streams from web and mobile apps and turns
them into funnels, retention curves, and cohort reports. Customers send events
via a client SDK or a server-side HTTP endpoint.

## SDK quotas

The Free plan accepts up to 100,000 events per month. The Pro plan accepts up to
10 million events per month; overage is billed at $0.20 per additional 100,000
events. Enterprise volume is negotiated.

Events are processed within about two minutes of ingestion under normal load.
During a backfill or a traffic spike this can stretch to fifteen minutes.

## API access

API access is a Pro and Enterprise feature. Keys are created in
Settings > API Keys. A key has either read-only or read-write scope. Rate limits
are 10 requests per second for Pro and 100 requests per second for Enterprise.

The API returns HTTP 429 when a key is over its rate limit; clients should retry
with exponential backoff. A 401 means the key is missing or revoked, and a 403
means the key is valid but lacks the scope for that endpoint.

## Known limitations

- The funnel report supports at most 8 steps.
- Cohort reports are limited to a 12-month window.
- Deleting a project is irreversible and takes effect immediately.
- Timezone for all reports is UTC and cannot currently be changed per project.
