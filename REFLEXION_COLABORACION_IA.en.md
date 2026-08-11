# Reflection: collaborating with AI on a long-haul technical project

*[Leer esto en español](REFLEXION_COLABORACION_IA.md)*

*Rafael Eduardo Martín Candial (raemca@hotmail.com), with Claude (Anthropic) as assistant*

## Why this document

`METODOLOGIA.md` tells *what* was done and in what order. This
document is different: it's a reflection on *what it was like* to work
this way — a person with a real technical profile (software
development, Z80 assembly, MSX architecture) and an AI assistant
with no memory of its own between sessions, relying on a text file
(`FINDINGS.md`) as a bridge. It's not a piece of marketing about how
well AI works, nor a complaint about its limits — it's an honest
attempt to describe the real dynamic, with its successes and its
friction, using this specific project as a case study.

That technical profile matters from the start: nothing that follows
— reading Z80 assembly, designing the architecture of a
reconstruction project, evaluating whether a technical hypothesis
holds up — is reachable without real software development
experience and knowledge of the MSX's architecture.

## The underlying pattern: verify, don't trust

The first thing to say is that this collaboration has **not rested on
blind trust from either side**. Not "the AI said so, it must be
true" nor "the user remembers the game, it must be true". It has
rested on a third, neutral element: **the real bytes of the
original binary**, against which every claim was verified before
being accepted.

This changes the nature of the collaboration in an important way.
When the final arbiter is "recompile and compare", disagreements
between person and AI stop being a contest of authority and become
a solvable technical problem. A clear example, from this very
session: the user edited directly on GitHub the name of the
musician credited in the game's credits, believing he was fixing a
typo (`"COMILONAS"` → `"GOMILONAS"`). When merging that branch,
instead of simply accepting the user's change (it's his project, his
edit, made in good faith) or simply dismissing it (he might be right
— he actually played the game), the check was mechanical:
look up the literal byte in the already-verified source code
(`DB "COMILONAS"`, extracted directly from the ROM). The data won,
not the person nor the AI. That was explained to the user with the
evidence right there, and the user himself accepted it with no
friction — because it wasn't one opinion against another, it was a
verifiable fact.

## Who brings what

Throughout the project there's a fairly clear division of roles,
and it's worth naming it precisely because it isn't "the AI does the
hard work and the person supervises", nor the other way around:

**What the person brings — knowledge that no byte analysis can
reconstruct on its own:**

- Identifying the 64 character sprites at a glance on a
  raw render, with no naming hints at all — recognizing "this is
  Pac-Man with his mouth half-open", "this is the vulnerable
  ghost" is visual recognition trained by actually having played the
  game, not something deducible from the structure of the
  data.
- Explaining game mechanics that aren't obvious from the code
  (the L-shaped trapdoor that flips over, the real order of
  Pac-Man's death animation sequence — "58→59→60→61→40→41→42→43→44",
  which is NOT the order of the indices in the table and which
  nobody would have guessed by looking only at bytes).
- The initial hunch that triggered this session's most important
  correction (§below): "this has odd stripes, could this be data
  from two patterns mixed together, like in the Spectrum version?" — an
  intuition based on knowing *another* version of the same game, something
  completely outside the scope of analyzing a single MSX binary.

And underneath these three points there's a fourth thing, distinct
from "game knowledge": background technical judgment — understanding
Z80 assembly, the MSX's real architecture (VDP, PSG, memory map),
and the craft of software development itself well enough to judge
whether an AI proposal makes sense, or to decide the architecture of
the reconstruction project itself.

**What the AI brings — capacity for systematic processing at scale:**

- Comparing binaries byte for byte, over and over, with no
  fatigue or shortcuts — the verification discipline described in
  `METODOLOGIA.md` is only sustainable at this volume if the
  marginal cost of "check again" is practically zero.
- Sustaining hundreds of rounds of consistent renaming/cleanup
  without losing track of already-established conventions (names in
  Spanish, decimal where it helps reading, dot-prefixed local
  labels for internal jump marks).
- Testing alternative hypotheses fast when needed — in the
  sprite-format correction, generating and comparing three different
  readings of the same bytes within minutes, instead of reasoning
  in the abstract about which one "sounds more plausible".

Neither role replaces the other. The user's suspicion
about the sprites would have gone nowhere without the immediate
empirical check; and the empirical check would never have
started without the suspicion, because the "official" render had
already been taken as settled for a while.

## The direction of the investigation: navigating, not just validating

There's a part of the user's work that the two sections
above leave out, and which in volume is as large as any
other: **deciding where to go next**. It wasn't always the AI that
proposed the next step with a plan already in hand — often it was a
short, direct instruction: "let's look at these variables now to see
what they do", "let's jump to that table, it might be related to this
function", "try relating this data block to such-and-such
structure". It's a navigation role, distinct from bringing
game knowledge (§above) and distinct from verifying an
already-obtained result (§below): it's deciding *where to look
next* while the map is still incomplete.

That role shows up with particular clarity in the stretches where
`FINDINGS.md` itself documents a thread that gets opened, left
parked unresolved, and picked back up sessions later. The
reused zone at `$DC00` is a real example: it was identified as a
static table inside a still-undeciphered gap, it was **explicitly
flagged as pending** for a while, and it was only fully resolved in
a later session once it was connected to the actor clipping-mask
mechanism — the entry for the resolved "big gap" itself
flags it as "resolves the 0xDC00 zone that had been left
undeciphered in an earlier session's finding". The same
thing happened with `RM_TABLE_CFA4`: first labeled as a candidate
"sound envelope/percussion table" just because it was near the
real sound tables —a weak hypothesis, deliberately left that
way instead of forcing a conclusion— and corrected sessions
later, once the sound driver had been fully disassembled and it
became clear no sound routine read it, and that it was actually
the head of level 13's body.

That pattern of **deliberately parking a lead and coming back to
it once there's more context**, instead of forcing an answer with
what's known at that moment, is a research decision, not a
technical finding — and it's a decision the user has taken above
all, marking which threads were worth chasing right away and
which were better left to mature.

## Human perception and data, in a loop: ears, eyes, and narrowing down bytes

There's a third work pattern, distinct from "the person validates at
the end" and from "the person directs where to look": the person and
the AI **narrowing down the same range of bytes at the same time**,
alternating between rendering/generating and perceiving. It isn't a
single-pass process (decode → listen/look → approve), it's a short
loop that repeats several times over the same stretch of data
until it fits.

The most documented case is the sound driver. Once the
renderer (`mmsnd_render.py`) was built, `FINDINGS.md` itself logs
**successive rounds of real listening** by the user, each one
finding something that sounded wrong and narrowing down which command
or which instrument field was responsible — leading, for example, to
finding that `SET_MIXER`'s polarity was inverted, or that
a specific script's loop-end detection was broken and that's why a
`.wav` "didn't sound complete". The user's ear wasn't just
confirming an already-closed result — it was **narrowing the
search**: "this doesn't sound right in the second bar" pointed
directly to which bytes to check next, in a way no purely
structural analysis of the bytecode could have suggested on its
own. One specific case is even confirmed by name in the sound
catalog itself: the effect tied to index 4 was identified by ear,
live, as "shot (plane mode)" — a fact that lived nowhere in the
code, only in the user's memory while listening to the rendered
sound.

The same loop repeats with images, with the eye instead of the
ear. The HUD candy frame is the clearest example: a
768-byte block was tried rendered one way, nothing recognizable
came out, and it was filed away as "background texture/shading" —
a reasonable conclusion at the time, but wrong. Sessions
later, going back to look at it with a different format hypothesis
(color, not pattern) and comparing the resulting render against a
real VRAM dump, exactly what was expected appeared: red-and-white
stripes, rounded corners, the highlight motif. The process itself
of "generate a candidate image, look at it, decide whether it looks
right or another interpretation needs testing" is just as mechanical
as the sound-listening loop, just with visual instead of
auditory perception — and it's the same loop that,
months later, uncovered the sprite-format error (covered in
detail in the next section).

## The full case: when the AI gets it wrong and the user notices

It's worth reconstructing this case in full because it sums up the
dynamic well. In an earlier session, the 64 character sprites were
located and decoded as 144 bytes per entry, regrouped
into 48 rows of 24 pixels wide — a format that produced
**recognizable** sprites, which the user himself had confirmed
by identifying each one at a glance. With that validation in
hand, the format was taken as "visually confirmed" and used as-is,
with no further review, on several pages of the project (the
sprite catalog, the visual poster/dossier) for quite a while.

The problem is that "recognizable" is not the same as "correct".
The user, looking at the already-published catalog, noticed
something that didn't fit: a background with horizontal
black-and-white stripes, and an "elongated" proportion that didn't
match what he remembered of the original game — and he connected it
to an outside piece of knowledge, that in the ZX Spectrum version of
the same game the sprites are 24×24 with two patterns, not
24×48 with a single one.

Instead of defending the already-"confirmed" format (which also
carried a prior validation from the user himself), the response was
to genuinely put it to the test: generating the three possible
readings of the same 144 bytes separately — 48 rows in a row
(the old reading), two 24-row blocks stacked, and rows interleaved
even/odd — and looking at them. Only the third had no stripes. It
also fit with something that was already documented without being
connected: the actor-drawing algorithm uses an AND mask followed by
an OR pattern, a classic blitting technique that needs exactly two
planes of the same size — the missing piece had been sitting
described in another document (`manual_subsistema_grafico.md`) for
weeks with nobody having connected the two threads.

The lesson isn't "the AI got it wrong" nor "the user was right" — it's
that **a passed visual validation ("the character is recognizable")
doesn't prove the data model is correct**, only that it's
close enough for the human eye. It took two things
to find the error: someone with the right context (having
played the Spectrum version) noticing that something didn't quite
fit, and a cheap mechanism to actually check it instead
of arguing about it in the abstract.

## Decisions with no answer in the bytes: naming and commenting

Not everything in this project was resolved by comparing binaries.
There's a whole category of decisions —what name best fits a
function, what comment truly explains why a table exists,
what deserves its own label and what stays internal— where
**there is no byte that can arbitrate who is right**, because it isn't a
question about the binary, it's a question about how the
result reads best. There the dynamic shifts: sometimes the
user's judgment carried more weight (how he prefers something to be
called, what home-grown Spanish terminology to use instead of a
literal translation from English), and sometimes an AI conclusion
backed by real code-usage data carried more weight — not an
aesthetic preference, but "this name no longer describes what it
does, and here's why".

The clearest example of the latter is a renaming that corrected
itself: a variable was first called
`SELECTOR_DIRECCION_SCROLL_FINO`, a reasonable name given where
it lived and how it was used on a first reading. Analyzing in more
detail the code that consumes it, it became clear that value doesn't
control any scroll offset at all — it's Pac-Man's **real
animation frame** (mouth open/closed, orientation).
`FINDINGS.md` itself logs it as an "important correction" and
renames it to `SELECTOR_SPRITE_COMECOCOS`. Nobody "was right" about
the original name — it was the best hypothesis available with what
was known at the time, and it was corrected as soon as analysis of
the real code contradicted it, exactly the way a data-format error
would be corrected.

There's also a visible pattern of **proposing before applying**: for
large batches of renaming (for example, the entire family of
internal labels in the actor engine, or the ones in the item
movement engine) the usual process wasn't to rename
directly, but to first leave a "study, not applied" with the
full proposal of Spanish names, and only turn it into
real changes in a later round. That intermediate step is,
literally, the space for the user to agree or ask for
a different name before the change spreads across dozens of places
in the code — a deliberate editorial decision, not a
technical verification.

## Real friction, not just successes

It would be dishonest to describe only what went well. Some things
didn't:

- **Repeated confusion with the Git commit workflow.** Twice in
  the same session the user got stuck thinking "the commit isn't
  working", when actually `git commit` with no message
  had opened an editor waiting for text — not a technical failure, but
  an interface (VS Code's more than git's own) that didn't
  communicate well what was happening. Diagnosing it was quick,
  but that it happened twice suggests the first explanation
  didn't leave a clear mental model of why it happens, it only
  fixed the immediate symptom.
- **Configuration polluted by loose sessions.** Over time,
  the tool's own permission files (`.claude/settings.json`
  and `settings.local.json`) had accumulated dozens of rules
  pointing at temp folders from already-closed sessions — literally
  useless even on the same machine, because every new session
  generates a different folder. Nobody had been actively cleaning
  them up; they piled up as residue until an explicit
  pass was needed to "make the configuration portable" and
  realize most of those rules had never been
  reusable, not even locally.
- **The real limit of "doing it all in one session".** The request to
  translate the whole project into English included `FINDINGS.md`, a
  ~17,700-line diary. Chunking and translating it with the same
  care as the rest would have taken several dozen rounds of
  reading/writing just for that file — technically possible,
  but not realistic in a single session without degrading
  attention. The right call there wasn't "push through at all
  costs" nor "lower the quality to go faster", but stopping
  mid-task, being explicit about the real pace, and letting the
  user decide how to continue instead of assuming it.

## The real pace: hundreds of small steps, not big leaps

Something that's easily lost when only looking at the final result is
how unspectacular most of the work is, step by step.
Of the roughly 370 milestones and rounds logged in `FINDINGS.md`, the
vast majority are not discoveries — they're things like "replace a
loose `CALL $86BB` with its real label", "rename 8 words of
the user's own terminology in the code labels", "convert
a field from hex to decimal because it reads better". None of
these steps is interesting on its own. What makes them valuable is
the sustained consistency across hundreds of rounds with no
error slipping through — and that is, again, the kind of work where a
systematic process (check, apply, recompile, check again)
pays off far more than the occasional flash of inspiration.

## Final reflection

If there's an underlying conclusion, it's that this project hasn't
worked just because of having "a very powerful AI" nor just because
of having "a user with technical judgment" — both were needed, but
neither one was enough on its own. It has worked because of also
having a method that didn't depend on either side always being
right. Byte-for-byte
verification isn't just technical rigor: it's what allowed a
disagreement (is this a hidden level or a normal one? is it "COMILONAS" or
"GOMILONAS"? are there 48 rows or 24 interleaved ones?) to always be
resolved by looking at the data, not by arguing over who had
more authority to decide. In a reverse-engineering project that's
almost mandatory, because there's an objective answer waiting to
be found.

But reducing it all to "verify against the bytes" would leave out
half the real work. Before anything can be verified, someone has to
decide *what* to look at —the user's role of direction and
intuition, parking and picking threads back up—; often the
verification itself is a shared perception loop, not a
one-shot verdict —the ear narrowing down which sound bytes to check,
the eye narrowing down which image bytes to try a different way—;
and there's a whole category of decisions, naming and commenting,
where no byte can arbitrate and the shared judgment call —sometimes
the user's, sometimes the AI's backed by data on how the code is
actually used— is all there is. The reflection worth taking away
isn't just "always have an external arbiter to appeal to when
one is available", but that such an arbiter doesn't replace the
need to decide together where to look, what to call what's
found, and when to leave a lead half-followed to pick it back up
later with more context — that last part isn't settled by any
data, it's shared judgment, built session by session.
