---
name: web-search
description: Search the web for up-to-date information.
---

Use the `searxng` cli to do a web search:
```
searxng "some topic"
```

Advanced use:
```
Usage: searxng [OPTIONS] <QUERY>

Arguments:
  <QUERY>  Lookup word(s)

Options:
  -c, --categories <CATEGORIES>    Categories (e.g. general,images,videos)
  -e, --engines <ENGINES>          Selected engines (e.g. google,bing)
  -l, --language <LANGUAGE>        Search language (e.g. fr, en)
  -p, --page <PAGE>                Page number
  -t, --time-range <TIME_RANGE>    Time range (day, week, month, year)
  -s, --safe-search <SAFE_SEARCH>  Safe search level (0, 1, 2)
  -j, --json                       Print the full JSON response instead of compact output
  -n, --limit <LIMIT>              Maximum number of results to show, from 1 to 20 [default: 10]
  -h, --help                       Print help
  -V, --version                    Print version
```


