# Failure Log & AI Decision Records

> **Graded requirement** (from the brief): *"document your process of implementation. If you
> used AI for certain parts you need to provide prompts and show the failures and errors that
> you got during your implementation."*
>
> Keep this live. Every time you hit an error, add an entry **with a screenshot**. Every time
> you use AI, record the **prompt**, what it produced, and whether it worked.

## How to use this file
- **Screenshots** go in `docs/screenshots/` and are linked from entries here.
- One entry per meaningful failure OR AI interaction. Don't batch at the end.
- Capture: Xcode build errors, runtime crashes, failed network calls, Supabase errors,
  sync bugs, constraint-logic edge cases.

---

## Template — copy for each entry

```
### [YYYY-MM-DD] <short title>
**Type:** build error | runtime crash | network | supabase | sync | logic | AI-prompt
**What I was doing:** …
**Error / output:**
    <paste the exact error text>
**Screenshot:** ![desc](screenshots/NNN-slug.png)
**Cause:** …
**Fix:** …
**AI prompt used (if any):**
    > <the exact prompt>
**AI result:** worked | partially | failed — <what happened>
```

---

## Entries

<!-- Add entries below as you build. Example shape:

### [2026-10-04] SwiftData @Model could not reference struct Step
**Type:** build error
**What I was doing:** Making the LocalStore back onto SwiftData.
**Error / output:**
    Type 'Step' does not conform to protocol 'PersistentModel'
**Screenshot:** ![error](screenshots/001-swiftdata-model.png)
**Cause:** Tried to persist the plain Domain struct directly.
**Fix:** Added separate @Model classes that mirror the Domain structs; map at the store boundary.
**AI prompt used:**
    > How do I persist a plain Swift struct with SwiftData without making it a @Model?
**AI result:** partially — suggested a mapping layer, which I adopted.
-->
