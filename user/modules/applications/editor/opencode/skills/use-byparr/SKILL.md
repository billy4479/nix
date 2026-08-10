---
name: use-byparr
description: Use when curl, webfetch, or a direct download is blocked by a CAPTCHA, Cloudflare, or another anti-bot challenge; fetch the resource through the existing Byparr instance instead.
---

# Fetching CAPTCHA-protected resources with Byparr

Use Byparr only after a normal fetch returns a CAPTCHA, challenge page, or an
anti-bot denial. Do not repeatedly retry the same direct `curl` request.

The existing instance is available at:

```text
https://byparr.internal.polpetta.online
```

Only use it for public resources the user is entitled to access. Do not send
credentials, authorization headers, signed URLs, or other secrets to Byparr,
and do not use it to bypass a login or an access-control decision.

## Preferred workflow

1. For a web page that only needs to be read, call `searxng_web_url_read` first.
   It is already configured to fall back to Byparr when its direct fetch is
   challenged.
2. Use the `/v1` API below when the response must be saved locally, especially
   for a PDF.
3. Work in `/tmp/opencode`, not in the repository, unless the fetched file is
   an intentional project artifact.

## Request

Create the temporary directory first if necessary, then make one request. Use
`jq` to construct the JSON so arbitrary URL characters are escaped correctly.

```sh
mkdir -p /tmp/opencode

url='https://example.com/protected-resource'
jq -n \
  --arg url "$url" \
  '{cmd: "request.get", url: $url, max_timeout: 120}' \
  > /tmp/opencode/byparr-request.json

curl --fail-with-body --silent --show-error \
  --max-time 130 \
  --header 'Content-Type: application/json' \
  --data-binary @/tmp/opencode/byparr-request.json \
  'https://byparr.internal.polpetta.online/v1' \
  --output /tmp/opencode/byparr-response.json
```

`max_timeout` is measured in seconds and is intentionally snake_case for this
installed Byparr version. Keep curl's `--max-time` slightly larger.

## Validate and extract

Inspect the metadata before writing the payload:

```sh
jq '{status, message, solution: {
  url: .solution.url,
  status: .solution.status,
  contentType: .solution.contentType
}}' /tmp/opencode/byparr-response.json
```

Require a successful Byparr response:

```sh
jq -e '
  .status == "ok" and
  (.solution.status >= 200 and .solution.status < 400)
' /tmp/opencode/byparr-response.json >/dev/null
```

For HTML or other page content, extract the response as text:

```sh
jq -r '.solution.response' \
  /tmp/opencode/byparr-response.json \
  > /tmp/opencode/resource.html
```

For a PDF, Byparr returns base64-encoded bytes. Verify `contentType` first, then
decode them:

```sh
jq -e '.solution.contentType == "application/pdf"' \
  /tmp/opencode/byparr-response.json >/dev/null

jq -r '.solution.response' \
  /tmp/opencode/byparr-response.json \
  | base64 --decode \
  > /tmp/opencode/resource.pdf
```

After extraction, use the normal file-reading or PDF-processing tools.

## Failure handling

- HTTP `408` means Byparr timed out while loading or solving the challenge.
  Retry at most once with `max_timeout` and curl's `--max-time` increased by
  the same amount.
- A successful HTTP request is not enough. Always validate `.status` and
  `.solution.status` before trusting `.solution.response`.
- If `contentType` is `text/html` when a PDF was expected, inspect the HTML. It
  may be a challenge, an error page, or a browser PDF viewer fallback; do not
  save it with a `.pdf` extension.
- Byparr only returns raw binary bytes specially for PDFs. For other downloads,
  it may return browser-rendered HTML rather than the original binary file.
- If Byparr still cannot solve the challenge, report the blocked URL and the
  returned status. Do not loop indefinitely or attempt unrelated bypasses.
