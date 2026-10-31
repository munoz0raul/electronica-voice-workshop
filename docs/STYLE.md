# Docs style guide

How the docs in this repository are written. It applies to `README.md`, the
files in `docs/`, commit messages and patches.

## Kinds of doc

- **Instruction docs** (SETUP, WORKSHOP, BUILDING-OS, BUILDING-ZEPHYR) give the
  steps to follow and nothing else.
- **Reference docs** (ARCHITECTURE, the MCU interface spec) describe how things
  are.

## Steps

- Group steps into numbered phases. End each phase with a **Check**: what the
  reader should see when it worked, and what to do when it didn't.
- Say which machine each command runs on: the build machine, the host PC, the
  VENTUNO Q or a UNO Q.
- Put a warning before any step that is hard to undo: flashing, deleting,
  reflashing the VENTUNO Q.
- Introduce each file and tool at the step that first uses it.
- Every placeholder (`<ventuno-q-ip>`) says where its value comes from.
- A note set apart from the steps starts on its own line with `NOTE:`.
- Mark anything specific to one OS: "For Ubuntu, install … (other Linux
  OSes will vary)."

## Wording

- **Stay technically accurate; invent no behavior.** Describe only what the
  code, a test or a measurement shows.
- Say why, briefly. The steps and the code already show how.
- **State what is, positively.** Avoid contrastive phrasing: "not X",
  "instead of", "rather than", "would otherwise", "before the fix", "as
  opposed to".
- **Capture only non-obvious context:** the intent, invariants and
  constraints a reader (or an agent) couldn't reconstruct from the code
  itself.
- **Keep the subject beside its verb.** A clause wedged between them strands two
  verbs together — *the defect this entry records recurs*. Say it in order:
  *this entry records a recurring defect*.
- Plain, short sentences. Define a term the first time it's used, or link the
  [glossary](README.md#glossary).
- One name for each thing, spelled the same way everywhere: VENTUNO Q,
  UNO Q, Bughopper, update-server (`fioserver` is its service), fiocli, and
  update for what is uploaded and rolled out; target for the entry
  aktualizr-lite installs from it.
- Name updates `<machine>-<step>-<what>`, so they sort in step order:
  `uno-q-0-start`, `uno-q-4-qli-2.1.1`.

## Voice

- Write for a peer engineer. Assume Linux, Yocto and Docker; define only this
  demo's own terms.
- Plain declaratives. One hedge where something is uncertain.
- No filler intensifiers: *simply, just, clearly, obviously, of course,
  straightforward*.
- No exclamation points and no emoji.

## Formatting

- Commands in fenced code blocks, one command per line, runnable as written
  from the repository root unless the step says otherwise.
- Steps as numbered lists; tables for comparisons and settings.
- File names, commands, services and values in backticks.
- Link other docs at the point the reader needs them.

## Commits and patches

- Subject: `area: component: change`, in the imperative or as a short noun
  phrase, under 72 characters.
- Body: why the change is made, briefly.
- One change per commit.
- Patches for other projects carry `Upstream-Status:` and live only in this
  repository.
