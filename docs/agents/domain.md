# Domain documentation

Use a single-context domain layout until the project demonstrates multiple bounded contexts:

- `CONTEXT.md` records the ubiquitous language, preferred terms, and terms to avoid.
- `docs/adr/` records numbered architectural decisions.

If distinct contexts emerge, update this file before splitting the glossary or ADR ownership. Bootstrap is mechanical and asks no domain questions; establish the first domain language with `grill-with-docs`.
