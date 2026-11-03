# Voice to Action — Presentation Master Doc

> **Base material for building the slide deck.** This file organizes the
> narrative, the slide-by-slide outline with speaker notes, the live-demo
> runbook, and a technical appendix of verified facts. It is the source another
> agent (or you) draws from to produce the actual PPT. Everything in the
> "Verified facts" sections traces to this repo (`docs/ARCHITECTURE.md`,
> `docs/REPRODUCE.md`, `PRODUCT.md`, the app `docker-compose.yml` files) or to
> the live-demo work done on the boards. Items I'm adding as suggestions are
> marked **[idea]**.

---

## 0. Talk metadata

| | |
| --- | --- |
| **Title** | Voice to Action: Building Portable Edge AI Applications with Linux and Containers |
| **Event** | Electronica 2026, Munich |
| **Presenters** | Raul Muñoz (Software Engineer / Marketing Manager, Foundries.io) + Edge Impulse co-presenter |
| **Format** | Interactive live session; audience participates with smartphones only |
| **Hardware on stage** | Arduino UNO Q, Arduino VENTUNO Q, Qualcomm Dragonwing IQ8 EVK, Qualcomm Dragonwing IQ9 EVK |
| **The one-sentence promise** | "By the end, the device will recognize a command that did not exist when the talk started." |
| **The loop we demonstrate** | collect data → train → package → deploy → run on real hardware → improve |

**Partner logos to carry throughout:** Arduino, Edge Impulse, Foundries.io,
Qualcomm Dragonwing. (These four are the exact logos the app itself serves —
`apps/webapp-led-mcu-voice/assets/{arduino,edgeimpulse,foundries,qualcomm}.png`.)

**Brand world (if slides match the on-screen app):** Qualcomm Dragonwing —
primary Dragonwing Purple `#31017D`; accents Violet `#5B0CD9` / Amber `#FF8300`
/ Orange `#FF5F00`; neutrals white → `#2F363D`. (From `PRODUCT.md` / `DESIGN.md`.)

---

## 1. The thesis (what the audience should remember)

One demo, told as one argument:

> **A voice command the device had never heard becomes a working feature, live,
> in front of you — because the application is containerized, the model ships
> *inside* the application, and the whole software stack is updatable over the
> air on hardware you control.**

Four supporting pillars, each a section of the talk:

1. **Prototyping is easy now** — Arduino UNO Q + Edge Impulse + containers get
   you a working voice-AI device in an afternoon. This is where everyone starts.
2. **Production is a different problem** — consistency, security, fleet
   visibility, maintainability. The prototype doesn't survive contact with a
   real product unless you own the OS and have an update mechanism.
3. **Portability has a boundary** — what lives *inside* the container travels
   across boards; what touches hardware (drivers, accelerators, LED/MCU, audio
   routing) stays board-specific. Knowing where that line is *is* the
   engineering.
4. **The loop never closes** — collect → train → package → deploy → run →
   improve, forever. The update path is as much a part of the AI product as the
   model.

**Running sub-theme (weave through, don't isolate):** AI and Linux are far more
approachable today with AI coding agents — but *knowing what you're doing lets
you direct them and move faster*. The agent is an amplifier, not a substitute
for understanding the stack. (This demo's own tooling and OTA plumbing were
built and operated alongside an AI agent — a concrete, honest example.)

---

## 2. Narrative arc (acts)

The abstract's structure maps to a cold-open + 6 acts. Start the audience
data-collection **early** so training runs in the background while you teach the
architecture — that overlap is the whole pacing trick.

- **Cold open** — the device works, but deliberately can't do blue/red yet.
- **Act 1 — The prototype.** UNO Q, Edge Impulse, containers. Why these choices.
- **Act 2 — Audience becomes the dataset.** QR codes, phones, collect blue & red.
  *Kick off training here.*
- **Act 3 — While it trains: the architecture.** Yocto/Linux, containers,
  runtimes, hardware access, drivers, acceleration; portable vs board-specific;
  the four platforms.
- **Act 4 — From prototype to production.** Own your OS, OTA, CI/CD, security,
  Targets/TUF, device management at scale, app/OS separation.
- **Act 5 — The payoff.** Export the new `.eim`, push to GitHub, OTA rolls out,
  all boards now recognize blue & red. Live.
- **Act 6 — AI agents + close.** Fundamentals make you faster with agents; call
  to action.

---

## 3. Slide-by-slide outline

Each entry: **slide intent** → bullets to show → *speaker notes*. Trim to your
time budget; the ★ slides are the spine you can't cut.

### COLD OPEN

**Slide 1 — Title ★**
- Voice to Action: Building Portable Edge AI Applications with Linux and Containers
- Four board photos in a row (UNO Q → VENTUNO Q → IQ8 → IQ9), presenter + partner logos
- *Notes: "Everything you'll see runs on real hardware on this table. You only need your phone."*

**Slide 2 — Live cold open (no slide, or one holding slide) ★**
- Say "select … green", "select … yellow" → LEDs + on-screen dashboard react
- Then: "select … blue" → **nothing.** "select … red" → **nothing.**
- *Notes: "This device does not know blue or red. It never has. By the end of
  this talk, it will — and you are going to teach it. Remember this moment."*

### ACT 1 — THE PROTOTYPE

**Slide 3 — Where edge AI starts: the prototype**
- A new "intelligent" approach: traditional programming (rules+data→outcomes)
  vs ML (data+outcomes→rules). *(carried over from the old deck — still a
  clean framing)*
- ML isn't magic; it's a different engineering approach to the same problem
- *Notes: keep this to 90 seconds; the audience is here for edge, not an ML 101.*

**Slide 4 — Arduino UNO Q: the ideal prototyping board**
- "Dual brain": Linux compute + real-time MCU on one board
- Runs full Linux → runs Docker → runs your containerized AI app
- Classic UNO form factor, Wi-Fi/BT, AI-ready
- *Notes: the UNO Q is the gateway drug — accessible, but it runs the **same**
  app architecture you'll later ship on professional hardware. That's the whole
  point of the four-board lineup.*

**Slide 5 — Edge Impulse: the AI development loop ★**
- Collect → Design → Test → Deploy → (back to Collect). The edge device is not
  the end of the loop.
- End-to-end platform; integrates with existing tools; no lock-in (TensorFlow/
  PyTorch/numpy under the hood)
- For keyword spotting you need the keyword **and** background/unknown speech
- *Notes: foreshadow — "Deploy gives us a single file, a `.eim`. Hold that
  thought; that file is the hero of the second half."*

**Slide 6 — Containers for embedded, in one slide ★**
- A container = code + runtime + libraries + settings, as one package
- Isolation + portability + easy updates, via Linux namespaces & cgroups
- The Edge Impulse model runs *inside* a container → the app is self-contained
- *Notes: this is the hinge between "AI" and "Linux". The container is what makes
  the model shippable and the whole thing portable — up to a boundary we'll draw
  in Act 3.*

**Slide 7 — Our app, concretely**
- `webapp-led-mcu-voice` — mic → Edge Impulse keyword spotting → LEDs + 8×13
  matrix + web UI on `:8000`
- `webapp-led-mcu-voice-assets` — carries the model, drops it where the app reads
  it
- Vocabulary: wake word **"select"** + colors **blue green purple red yellow**
- *Notes: two containers on purpose — one is the app, one is the model. We'll see
  in Act 5 why that split is the trick that makes retraining an app update.*

### ACT 2 — THE AUDIENCE BECOMES THE DATASET

**Slide 8 — "You are the data" ★**
- Big QR code #1 → **say "blue", pause, "blue", pause… for a few seconds**
- Then QR code #2 → **say "red" the same way**
- Phone-only; a shared link opens Edge Impulse's mobile collection page
- *Notes: this is the crowd-data moment. Collect genuinely — accents and room
  noise are a feature, not a bug; that's exactly the "background & unknown"
  robustness from Slide 5. Technique ref: Edge Impulse "power of the crowd"
  mobile collection.*

**Slide 9 — Look at what we just built**
- Show the Data Acquisition view filling up with everyone's blue/red samples
- "This dataset did not exist 3 minutes ago."
- **→ Start the training run now.** State out loud: "while this trains, let's
  open the box."
- *Notes: training is your hidden timer for Act 3/4. Have a backup pre-recorded
  dataset/model ready in case connectivity or the crowd under-delivers (see §6).*

### ACT 3 — WHILE IT TRAINS: THE ARCHITECTURE

**Slide 10 — Choosing the right OS for AI ★**
- Upstream or long-term-support Linux; must support Docker; strong open-source
  community + reproducibility
- *Notes: "A prototype runs on whatever boots. A product runs on an OS you chose
  on purpose and can rebuild byte-for-byte."*

**Slide 11 — The stack, bottom to top ★**
- Silicon + accelerators (CPU / GPU / NPU-Hexagon) → drivers & firmware →
  Linux (Yocto-built) → container runtime → your app container → the model
- *Notes: name each layer and who owns it. The audience's mental model should be
  "the model is the top brick on a tall, deliberate stack."*

**Slide 12 — Yocto & embedded Linux in one slide**
- Yocto = you build your *own* Linux distribution, reproducibly, for your board
- Pick packages, kernel, drivers; bake in exactly what the product needs
- This is how `snd-usb-audio` for the USB mic gets into the image on purpose
- *Notes: contrast with "flash a vendor image and hope" — Yocto is control.*

**Slide 13 — Hardware access, drivers, acceleration ★**
- How a container touches hardware: device nodes, privileged mode, host network,
  group membership (audio), sysfs
- Acceleration lives *below* the container: an NPU (Hexagon) would be reached via
  vendor userspace libraries the OS provides, not something the container carries
- Our voice keyword model runs on the **CPU** via the Edge Impulse runtime — no
  accelerator dependency, which is exactly why it's trivially portable. The
  moment a model needs the NPU, you've crossed into board-specific territory
- *Notes: the "why Linux still matters under the container" slide. The container
  is portable; the *path to the accelerator* is the OS's job. Our model happens
  to need no accelerator — that's a portability win, and it previews the boundary
  on the next slide.*

**Slide 14 — Portable vs hardware-specific: the boundary ★★**
- **Portable (inside the container):** Python app, the Edge Impulse `.eim` model,
  CPU inference, web UI, the color→action mapping
- **Hardware-specific (crosses the boundary):** audio device index
  (`PA_ALSA_DEVICE`), the MCU/LED-matrix UART, host RGB-LED sysfs nodes, kernel
  modules baked by Yocto — and, for heavier models, the accelerator path from
  Slide 13
- The app **degrades gracefully**: on a board with no MCU/LEDs (the IQ9), those
  calls fail silently and the web UI + voice keep working
- *Notes: THE money slide of Act 3. Same container image, very different boards.
  What survived the trip is the AI and the logic; what didn't is everything that
  touches a wire. Designing that boundary deliberately is what separates a demo
  from a product.*

**Slide 15 — Four boards, one architecture ★**
- Table: UNO Q (prototyping) · VENTUNO Q (prototyping + our local server) ·
  IQ8 EVK · IQ9 EVK (professional edge AI)
- Same two containers (voice app + its model), same OTA client, same loop —
  scaling from accessible dev boards to professional systems
- *Notes: this is the abstract's headline claim, shown not told. "The thing that
  scales is the architecture, not the code rewrite."*

### ACT 4 — FROM PROTOTYPE TO PRODUCTION

**Slide 16 — Prototype → product: the challenges ★**
- Consistency · security · maintainability · fleet visibility
- "It works on my board" is not a product
- *Notes: the pivot of the whole talk. Everything before was "easy"; here's why
  easy isn't enough.*

**Slide 17 — Own your OS, own your updates ★★**
- You must be able to update the **entire** software stack: app **and** OS, on
  the field, securely
- App/OS separation: a model retrain should be an **app** update (fast, no
  reboot); a kernel/driver fix is an **OS** update (atomic, reboots)
- *Notes: the single most important engineering message. Set up Act 5's payoff:
  "watch a retrain land as an app-only update, no reboot."*

**Slide 18 — Security built into every layer**
- Secure boot (hardware root of trust) · read-only root filesystem · signed/
  encrypted OTA · automated CVE scanning in CI/CD
- *Notes: carried from the old deck; still the right four. "Security isn't a
  feature you add; it's a property of how you build and ship."*

**Slide 19 — CI/CD for devices ★**
- Branch/tag flow → build reproducible artifacts → test → sign → publish
- A `git push` is the trigger; the pipeline produces the deployable Target
- *Notes: "Your device fleet deserves the same CI/CD discipline as your cloud
  backend." In our demo, a push to GitHub is literally what ships the new model.*

**Slide 20 — What is a Target? (The Update Framework) ★**
- A **Target** describes exactly the software a device should run: the OS
  (OSTree) commit + the set of container apps, each pinned by content hash,
  plus which hardware IDs and tags it's for
- Show the JSON shape (hashes, `docker_compose_apps`, `hardwareIds`, `tags`)
- *Notes: this is how "what should this device run" becomes a signed, verifiable
  fact. TUF = The Update Framework; it's what makes the rollback-proofing real.*

**Slide 21 — Device management at scale**
- One dashboard: every device, its group, its current Target + version, last
  check-in
- Rollouts target **groups**; devices pull only the Target matching their
  hardware ID and tag
- *Notes: "Three boards or three thousand — same model." Show the fleet view.*

**Slide 22 — Our setup, drawn ★**
- VENTUNO Q = the local server (plays the role a hosted factory would): builds on
  push, stages per-board Targets, rolls them out
- UNO Q + IQ9 = end devices: check in, pull only changed blobs (a model swap is
  ~14 MB), install app-only, no reboot
- *Notes: use the ASCII diagram from `docs/ARCHITECTURE.md` as the basis for a
  clean graphic. Emphasize: no hosted cloud dependency — you can own all of this.*

### ACT 5 — THE PAYOFF

**Slide 23 — Training's done ★**
- Edge Impulse: show accuracy / confusion matrix for the new blue+red model
- Deploy → Linux (AARCH64) → build → **one file: `deployment.eim`**
- *Notes: "Remember this file from Slide 5? Here it is. This is the whole AI
  product, in one artifact."*

**Slide 24 — Ship it: one push ★★**
- Drop the new `.eim` into the assets app → `git commit` → `git push`
- That's the entire operator action. No reboot, no re-flash, no manual deploy.
- *Notes: do this live. Then switch to the fleet view / device logs while it
  rolls out (~2 min to build + stage, ~5 s device check-in).*

**Slide 25 — It lands ★★**
- Fleet view: version ticks up on all boards
- Live: "select … blue" → **it lights up.** "select … red" → **it lights up.**
- On all four boards at once
- *Notes: THE moment. Let it breathe. "A command that did not exist when we
  started. You collected the data. The loop is closed — and it never really
  closes; that's the point."*

### ACT 6 — AI AGENTS + CLOSE

**Slide 26 — AI + Linux is easier now — if you know the stack ★**
- AI coding agents make Yocto, containers, and OTA plumbing far more approachable
- But: the agent is an amplifier. Knowing *what* you're asking for — the stack,
  the boundary, the update model — is what lets you direct it and go faster
- Honest note: parts of this very demo's tooling/OTA automation were built with
  an AI agent — *and* it took knowing the fundamentals to get it right
- *Notes: this is your personal POV. Deliver it as earned advice, not hype. "The
  fundamentals didn't become less important; they became the thing that makes the
  agent useful."*

**Slide 27 — The loop, one more time ★**
- collect → train → package → deploy → run → improve
- Data: get the *right* data (crowd, synthetic, open datasets); reuse existing
  models; update/upgrade in the field
- Devices: own your OS; CI/CD for test + deploy; secure the whole stack
- *Notes: tie the AI lessons and the device lessons back into one loop.*

**Slide 28 — What you learned (mirror the abstract's bullets)**
- Collaborative smartphone data collection · Edge Impulse for dataset/train/
  deploy · model into a containerized Linux app · how Yocto+containers+runtimes+
  drivers+acceleration fit · portable vs hardware-specific · one architecture
  from Arduino-class to professional edge · why app/OS separation matters
- *Notes: this doubles as the "takeaways" slide reviewers expect.*

**Slide 29 — Call to action / resources ★**
- The repo (public): the whole thing is reproducible
- Partners: Arduino (boards), Edge Impulse (the AI loop), Foundries.io (OTA/
  fleet), Qualcomm Dragonwing (the silicon + accelerators)
- Giveaway / booth / "come try it" — carry over the DigiKey giveaway idea if it
  applies
- *Notes: end on "go build your own loop."*

---

## 4. Live-demo runbook (condensed — full detail in `docs/REPRODUCE.md`)

The talk's two live beats and exactly what happens underneath.

### Beat A — cold open (device knows colors, not blue/red)
- Boards already flashed, registered, in group `demo`, running the **old** model
  (one trained *without* blue/red).
- Say "select" + a known color → LEDs/matrix + the `:8000` dashboard react.
- Say "select blue"/"select red" → no match (model has no such label). This is
  the setup, not a bug.

### Beat B — the retrain → OTA loop (the payoff)
1. **Collect** (Act 2): audience scans QR → Edge Impulse mobile collection →
   "blue" and "red" samples land in Data Acquisition.
2. **Train** (background during Act 3/4): retrain in Edge Impulse. Keep labels
   `select` + `blue green purple red yellow` or the LED mapping breaks.
3. **Export:** Deployment → Linux (**AARCH64** — not x86) → build → `deployment.eim`.
4. **Package:** `cp <model>.eim apps/webapp-led-mcu-voice-assets/deployment.eim`.
5. **Deploy:** `git add apps/ && git commit -m "retrain" && git push`. **That's
   the only operator action.**
6. **The server does the rest** (VENTUNO Q `poll-and-build`, ~2 min): rebuilds
   the changed app image on-board, stages a per-board Target (each with that
   board's OS `ostree_repo` + the apps), uploads to the local update-server,
   rolls out to group `demo`.
7. **Devices pull** at next ~5 s check-in: only the changed OCI blobs (~14 MB),
   installed **app-only, no reboot** (same OS commit).
8. **Confirm:** fleet view version ticks up; say "select blue"/"select red" →
   now recognized on all boards.

### Why the two-container split matters (say this out loud)
The model ships in `webapp-led-mcu-voice-assets`, which writes `deployment.eim`
to a shared volume and restarts the voice app when the file changes. So **a
retrain is just a new build of the assets app** — a new image, a new OTA update
— **not** a change to the OS and **not** a push to a device that polls a repo
for a model. No token, no device-side network fetch. That separation is the
cleanest possible illustration of Slide 17.

---

## 5. Technical appendix — verified facts to build diagrams/slides from

All of the following are from this repo and the running demo. Use them to make
the architecture slides accurate (Slides 11, 13, 14, 20, 22).

**Roles**
- **VENTUNO Q** = the local update-server (the self-hosted stand-in for a hosted
  FoundriesFactory) **and** an end device running the app. Also hosts the demo
  Wi-Fi access point, chrony time source, mDNS (`demo-server.local`), and the
  `poll-and-build` timer (polls the repo every 2 min).
- **UNO Q** = end device. Has the STM32-class MCU driving the 8×13 LED matrix
  (Zephyr firmware, loaded by `zephyr-loader`) + host RGB LEDs.
- **IQ9 EVK** = end device. **No MCU, no physical LEDs** — web UI + voice only;
  LED/matrix calls fail silently by design.

**The OTA flow (4 steps)**
1. Each board registers once (`fio-device-register`), then checks in every ~5 s.
2. Build apps → stage a **Target** (an OS `ostree_repo` + the staged compose
   apps) → `fiocli updates upload`. Each upload is one Target, tagged `main`,
   versioned higher than the last.
3. `fiocli updates create-rollout` points a Target at a device **group**;
   enrolled devices whose tag matches pull it at next check-in.
4. Same OS hash → **app-only** update (fast, no reboot). Changed OS hash → OS
   update (reboots).

**Portability boundary — concrete values (for Slide 14)**
- Inside the container (portable): the Python app, `deployment.eim`, inference,
  the Flask web UI on `:8000`, the color→action logic.
- Crosses to hardware (board-specific), from the real compose files:
  - `PA_ALSA_DEVICE=3` — the USB-mic ALSA "default" PCM (index 0 = raw `hw:0,0`
    is locked at 44.1 kHz and rejects the model's 16 kHz; index 3 resamples).
  - `privileged: true`, `network_mode: host`, `group_add: audio` — to reach the
    MCU UART, host LED sysfs, and audio.
  - `/var/local/assets` shared volume — the model hand-off between the two apps.
  - `snd-usb-audio` kernel module — baked into the OS image by Yocto, not in the
    container.
- Graceful degradation: on the IQ9, no MCU port and no `unoq:*` LED sysfs nodes
  → those calls raise and are swallowed → app keeps running.

**Accelerator path (for Slide 13) — note this demo does NOT use it**
- The voice keyword model runs on the **CPU** via the Edge Impulse Linux runtime.
  It needs no accelerator, which is precisely why the container is trivially
  portable across all four boards.
- Worth stating as the contrast: *if* a model needed the NPU, it would be reached
  through vendor FastRPC userspace libs the OS provides plus Hexagon context
  binaries that are HTP-version-specific (different per board). That is where
  portability stops being free — the exact boundary Slide 14 draws. Keep this
  conceptual; don't claim the voice demo touches the NPU, because it doesn't.

**Numbers worth citing**
- Device check-in: ~5 s. · `poll-and-build` poll: every 2 min.
- A model-swap app-only update pulls ~14 MB of changed blobs.
- End-to-end server pipeline (git push → Target rolled out), measured clean:
  about **9 minutes** including structural upload overhead; the model rebuild
  itself is the small part. *(Use as "minutes, not a re-flash" — don't over-
  promise a specific number live; network varies.)*

**The two apps (exact names)**
- `webapp-led-mcu-voice` — voice → LED/matrix + web UI (`:8000`).
- `webapp-led-mcu-voice-assets` — carries + delivers `deployment.eim`.

---

## 6. Live-demo risk & backup plan (read before stage) [idea]

The payoff depends on a live train + OTA. De-risk every link:

- **Crowd under-delivers / bad samples.** Have a pre-collected blue+red dataset
  already in the Edge Impulse project; you can train on the merged set so a thin
  crowd contribution still yields a good model.
- **Training is slow / network flaky.** Have a **pre-built `deployment.eim`** for
  blue+red on your laptop. If the live train stalls, `cp` that file and push —
  the OTA half of the demo (the real Foundries story) still lands exactly the
  same way.
- **OTA doesn't land on a board.** Known failure modes and fixes are in
  `docs/REPRODUCE.md §7` (group-rollout last-wins → per-UUID rollout; TUF
  rollback after deleting Targets → clear cached meta rows). Rehearse the
  per-UUID rollout command; keep an SSH session open to the server.
- **Audio/mic issues on a board.** Confirm `arecord -l` shows the USB card before
  you start; the app captures via `PA_ALSA_DEVICE=3`.
- **Keep one board as the "hero".** Even if one board misbehaves, land the update
  convincingly on at least the UNO Q + VENTUNO Q.
- **Pre-stage the OS commits.** Each board's `ostree_repo` must match its flashed
  OS exactly, or the first app update looks like an OS change and reboots. Verify
  before the session.

---

## 7. My added ideas for the deck [idea]

Things beyond your outline that I think strengthen the talk:

1. **A "stack ownership" spectrum slide.** A horizontal bar from "flash a vendor
   image" → "own the app" → "own the OS" → "own the update pipeline + fleet".
   Plot where a prototype sits vs where a product must sit. Makes Slide 17
   visual.
2. **A single recurring diagram you return to 3×.** Draw the full stack once
   (Slide 11), then re-show it dimmed with just one layer lit in Slides 13
   (drivers/accel), 14 (the container boundary), and 22 (OTA across the fleet).
   Repetition of one diagram beats four unrelated ones.
3. **"What the agent did vs what you must know" two-column slide** for Act 6. Left:
   things an AI agent accelerates (scaffolding Yocto recipes, writing compose
   files, scripting rollouts). Right: judgment the agent can't own (where the
   portability boundary is, what to put in the OS vs the app, security posture).
4. **A before/after of the device's vocabulary.** Slide showing the label set
   *without* blue/red, then the same set *with* them — a tiny, literal picture of
   "the product changed in the field."
5. **Close with the loop as a circle, not a line.** The abstract lists the loop
   linearly; render it as a cycle with "improve" arcing back to "collect" — the
   last visual should say "this never stops."
6. **A QR code on the final slide** to the public repo, so attendees can
   reproduce the entire thing. Reinforces "you can own all of this."
7. **Timing budget overlay (for your own notes, not a slide):** cold open 2 min ·
   Act 1 ~6 · Act 2 ~4 (start training) · Act 3 ~10 · Act 4 ~10 · Act 5 ~5 ·
   Act 6 ~3. Adjust to your slot; the training timer sets the floor on Act 3+4.

---

## 8. Open items to decide before the deck is final

- **IQ8 EVK in the demo.** The abstract and board lineup include the IQ8, but the
  repo's OTA automation is wired for UNO Q + VENTUNO Q + IQ9 (`poll-and-build`
  stages those three). Decide whether the IQ8 is (a) live in the OTA loop too, or
  (b) shown as "same architecture, additional platform" without being in the live
  rollout. The slides should match whichever is true on stage.
- **Deck visual system.** Match the Dragonwing brand world (§0) for a unified look
  with the on-screen app, or use a neutral conference template? Recommend
  Dragonwing purple as the through-line so slides and the projected app agree.
- **How much ML detail.** The old deck had several ML-history slides (perceptron,
  "60 years", synthetic data). Recommend cutting to the single Slide 3 framing —
  this audience wants edge + Linux, and Edge Impulse owns the ML depth.
- **Giveaway / CTA specifics.** Carry over the DigiKey giveaway from the old deck
  if it applies to this event; otherwise replace Slide 29's CTA.
- **Stale docs note (not a slide):** `docs/ARCHITECTURE.md` and `docs/REPRODUCE.md`
  still describe a third app (`dorbell`) on all three boards. This demo runs only
  the voice app (`webapp-led-mcu-voice` + `-assets`); dorbell has been removed
  from the shipped app set. If you demo straight from the docs, update them first
  so they match what's actually running.
```
