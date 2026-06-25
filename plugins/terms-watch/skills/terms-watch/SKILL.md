---
name: terms-watch
description: >-
  Query Terms Watch (termswatch.io) for tracked changes to Terms of Service and
  Privacy Policies across major platforms (social, AI, and more). Use when the
  user asks what changed in a service's ToS or privacy policy, wants recent
  policy changes or diffs, or wants to monitor or track terms updates. Paginated
  JSON API over HTTPS, no authentication.
version: 0.1.0
license: MIT
metadata:
  hermes:
    category: research
    tags: [terms-of-service, privacy-policy, monitoring, compliance]
    requires_toolsets: [web]
---

# Terms Watch

**Terms Watch** (https://termswatch.io/) tracks changes to Terms of Service and
Privacy Policies across major platforms. Each tracked edit is a "change".

## When to use this

- The user asks **what changed** in a service's Terms of Service or Privacy
  Policy (e.g. "did YouTube update its community guidelines?").
- The user wants **recent policy changes** or the **diff** of a specific change.
- The user wants to **monitor or track** terms updates across services or a
  category (social, AI, …).

## Endpoint

```
GET https://termswatch.io/api/changes?limit=200&offset=0
```

- `limit` — page size (default 200)
- `offset` — rows to skip (default 0)
- No authentication. Returns `application/json`, changes newest-first.

## Response shape

```json
{ "changes": [ ... ], "total": 1234, "limit": 200, "offset": 0 }
```

Each item in `changes` carries:

| Field           | Meaning                                                        |
|-----------------|----------------------------------------------------------------|
| `id`            | unique change id                                               |
| `service`       | platform name, e.g. `YouTube`                                  |
| `category`      | grouping, e.g. `social`, `ai`                                  |
| `documentType`  | e.g. `Terms of Service`, `Privacy Policy`, `Community Guidelines` |
| `filename`      | source document path                                           |
| `commitSha`     | git commit of the tracked edit                                 |
| `commitDate`    | when the document changed (ISO 8601)                           |
| `commitUrl`     | link to the source diff on GitHub                              |
| `diffContent`   | the raw unified diff of the change                             |
| `diffSummary`   | a ready-made human-readable summary of what changed            |
| `isMinorChange` | `true` for trivial/cosmetic edits                             |
| `processed`     | whether the change has been processed                         |
| `createdAt`     | when Terms Watch recorded the change (ISO 8601)               |

## Paging

Start at `offset=0`; add `limit` to `offset` for each next page. Stop when
`offset + limit >= total`.

```
page 1: offset=0
page 2: offset=200
page 3: offset=400 ...
```

A runnable loop that streams a compact view of every change:

```bash
offset=0; limit=200
while :; do
  page=$(curl -s "https://termswatch.io/api/changes?limit=$limit&offset=$offset")
  echo "$page" | jq -c '.changes[] | {service, documentType, commitDate, diffSummary}'
  total=$(echo "$page" | jq .total)
  offset=$((offset + limit))
  [ "$offset" -ge "$total" ] && break
done
```

## Tips

- The first page is usually enough — changes are newest-first, so recent updates
  are at `offset=0`.
- Filter client-side by `service`, `category`, or `isMinorChange` (drop minor
  edits with `select(.isMinorChange == false)`).
- `diffSummary` is the fastest way to answer "what changed" without parsing
  `diffContent`; fall back to `diffContent` for the exact wording.
- `commitUrl` links straight to the source diff for citation.
