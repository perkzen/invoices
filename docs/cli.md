# The command-line tool

The tool ships inside the app, at `Invoices.app/Contents/Helpers/invoices`, so every
release carries it and a Sparkle update replaces it along with the app. Putting it on
the PATH is a symlink into the bundle, and the skill that teaches Claude Code to use it
is printed by the tool itself:

```bash
sudo ln -sfn /Applications/Invoices.app/Contents/Helpers/invoices /usr/local/bin/invoices
mkdir -p ~/.claude/skills/invoices && invoices skill > ~/.claude/skills/invoices/SKILL.md
```

`Scripts/install-cli.sh` does both (pass another directory as the first argument), and
clears the quarantine flag a disk-image install leaves on the helper, which Gatekeeper
would otherwise hold against it separately from the app.

**Invoices › Install Command Line Tool…** and **Install…** under Command line tool in
Settings make the same link from inside the app, for when a terminal is not at hand.
Either asks which folder to link into, because a sandboxed app may write only where the
user has pointed it, and it offers `~/.local/bin`: `/usr/local/bin` belongs to root, so
the app is refused there and the `sudo` line above stays the way in. It links the tool
and nothing else — the skill is still `invoices skill`. Only the release build offers
either; the development build would link a copy of itself in `build/`, which the next
clean build empties. Then:

```bash
invoices --help
invoices invoice list --overdue
invoices invoice create --client parakeet --service-date 2026-08-01 --service-end month \
  --line '{"description": "Software development", "quantity": 80, "unit": "h", "unitPrice": 45}'
invoices invoice issue draft
invoices invoice pdf 2026-003
invoices overview --year 2026 --xlsx ~/Desktop/invoices-2026.xlsx
```

The tool is not a second implementation. Its target compiles the app's `Models/`,
`Core/` and `Services/` — the same `Ledger`, the same numbering, the same PDF page and
spreadsheet — and opens the app's SwiftData store by path, inside the app's sandbox
container. That is why it is Swift and lives in this project: a tool in another
language would have to re-derive the Core Data schema and every rule in the ledger, and
break the first time either moved.

Three things follow from opening the store directly, and one from living in the bundle:

- It opens the **installed app's** store, the one under `com.domenperko.Invoices`. `--dev`
  opens the development build's instead; `--store <path>` (or `INVOICES_STORE`) opens a
  file outright, and creates it when it does not exist, which is what the CI smoke test
  runs against. The app's own store is never created by the tool: launch the app once.
- The first time a terminal opens a store in `~/Library/Containers`, macOS asks whether
  Terminal may access data from other apps. Allow it once.
- The tool is a bare executable with no resources, so it takes the Slovenian document
  strings and the skill from the app around it: the `.app` above its own executable,
  resolved through the symlink; or `INVOICES_APP`; or, for a build-tree binary run on
  its own, whichever build Launch Services finds. Rendering a PDF or a spreadsheet
  refuses to run without one rather than print a legal document in English; everything
  else works either way.

Every command prints JSON. Records carry an `id` (a UUID stored on the invoice and the
client, given to older rows at launch) so a draft can be named before it has a number;
issued invoices are named by number. Errors are `{"error": "…"}` on stderr with exit
status 1, worded so that an agent knows what to do next. `skills/invoices/SKILL.md` is
the agent-facing manual, written the way [herdr](https://github.com/herdrdev/herdr)
writes its skill: check the binary exists, learn the syntax from `--help`, read state
from the JSON, and confirm with the user before the irreversible steps — issuing,
cancelling, deleting.

The running app does not watch the store for changes made by another process; if it is
open while the tool writes, relaunch it to see them.
