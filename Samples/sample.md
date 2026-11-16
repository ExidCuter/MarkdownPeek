---
title: MarkdownPeek sample
tags: [quicklook, markdown]
---

# MarkdownPeek

Press **Space** on any `.md` file in Finder to see it rendered like this.
Jump to the [code section](#syntax-highlighting) or read about [GitHub Flavored Markdown](https://github.github.com/gfm/).

## Text

Plain text with *emphasis*, **strong**, ~~strikethrough~~, `inline code`, and an autolink: https://www.markdownguide.org.

> Blockquotes work too.
> They can span multiple lines.

## Lists

1. First
2. Second
   - Nested bullet
   - Another one

### Task list

- [x] Render GitHub Flavored Markdown
- [x] Highlight code blocks
- [ ] Take over the world

## Table

| Feature            | Supported | Notes                       |
| :----------------- | :-------: | --------------------------: |
| Tables             |    ✅     | with column alignment       |
| Footnotes          |    ✅     | see below[^1]               |
| Local images       |    ✅     | inlined, no network needed  |

## Syntax highlighting

```swift
struct Greeter {
    let name: String
    func greet() -> String { "Hello, \(name)!" }
}
print(Greeter(name: "Finder").greet())
```

```python
def fib(n: int) -> int:
    return n if n < 2 else fib(n - 1) + fib(n - 2)
```

```json
{ "preview": true, "theme": "auto", "fontSize": 15 }
```

```
A block with no language stays plain.
```

## Image

![MarkdownPeek icon](img.png)

---

[^1]: Footnotes render at the bottom of the page.
