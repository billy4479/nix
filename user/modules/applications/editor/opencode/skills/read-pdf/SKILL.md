---
name: read-pdf 
description: Use this skill to read the content of a PDF file.
---

You have access to the `liteparse` tool which you can use to extract text from PDFs and other documents.

## Usage

This is the output of `liteparse --help` 

```
Usage: lit [options] [command]

OSS document parsing tool (supports PDF, DOCX, XLSX, images, and more)

Options:
  -V, --version                                   output the version number
  -h, --help                                      display help for command

Commands:
  parse [options] <file>                          Parse a document file (PDF, DOCX, XLSX, PPTX, images, etc.)
  screenshot [options] <file>                     Generate screenshots of PDF pages
  batch-parse [options] <input-dir> <output-dir>  Parse multiple documents in batch mode
  help [command]                                  display help for command
```

and `liteparse parse --help`

```
Usage: lit parse [options] <file>

Parse a document file (PDF, DOCX, XLSX, PPTX, images, etc.)

Options:
  -o, --output <file>     Output file path
  --format <format>       Output format: json|text (default: "text")
  --ocr-server-url <url>  HTTP OCR server URL (uses Tesseract if not provided)
  --no-ocr                Disable OCR
  --ocr-language <lang>   OCR language(s) (default: "en")
  --num-workers <n>       Number of pages to OCR in parallel. Defaults to number of CPU cores minus one.
  --max-pages <n>         Max pages to parse (default: "10000")
  --target-pages <pages>  Target pages (e.g., "1-5,10,15-20")
  --dpi <dpi>             DPI for rendering (default: "150")
  --no-precise-bbox       Disable precise bounding boxes
  --preserve-small-text   Preserve very small text
  --password <password>   Password for encrypted/protected documents
  --config <file>         Config file (JSON)
  -q, --quiet             Suppress progress output
  -h, --help              display help for command
```

## Recommended workflow

1. If the PDF is an online resource, download it to a temporary work directory with `curl`
2. Parse it using `liteparse parse /some/work/directory/some_document.pdf -o /some/work/directory/some_document.txt`
3. Use existing tools to read the txt file. Now that you have it saved locally you can also `grep` on it or use it as input to some other script.
