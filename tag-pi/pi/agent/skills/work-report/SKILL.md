---
name: work-report
description: >
  Generate a work report for a given period (day, week, month, year). Combines
  GitHub activity from `did` and pi session summaries from ClickHouse repos.
  Use when the user asks for a status report, weekly/monthly summary, or "what
  did I do last X".
---

# Work Report

Combines two data sources:

1. **`did`** -- GitHub activity (issues, PRs created/commented/merged)
2. **pi sessions** -- what was actually worked on in the ClickHouse repos

## Step 1 -- Compute date range

**ALWAYS run `date` to get the real wall-clock date and weekday. Never assume
or infer the day of week from context, the system prompt, or prior
conversation. Every time. No exceptions.**

```bash
TODAY=$(date +%F)
DOW=$(date +%u)   # 1=Mon ... 7=Sun
echo "Today is $TODAY (DOW=$DOW)"
```

Then compute ranges from that anchor:

```bash
# Start of the current week (this Monday), works for any DOW
DAYS_SINCE_MON=$(( DOW - 1 ))
THIS_MON=$(date -d "$TODAY - ${DAYS_SINCE_MON} days" +%F 2>/dev/null \
           || date -j -v-${DAYS_SINCE_MON}d +%F)

# Previous week = the Mon-Sun block before the current week
PREV_SINCE=$(date -d "$THIS_MON - 7 days" +%F 2>/dev/null \
             || date -j -f %F "$THIS_MON" -v-7d +%F)
PREV_UNTIL=$(date -d "$THIS_MON - 1 day" +%F 2>/dev/null \
             || date -j -f %F "$THIS_MON" -v-1d +%F)

# The week before the previous week
PREV2_SINCE=$(date -d "$THIS_MON - 14 days" +%F 2>/dev/null \
              || date -j -f %F "$THIS_MON" -v-14d +%F)
PREV2_UNTIL=$(date -d "$THIS_MON - 8 days" +%F 2>/dev/null \
              || date -j -f %F "$THIS_MON" -v-8d +%F)

# This week so far
THIS_SINCE=$THIS_MON
THIS_UNTIL=$TODAY

# Last month
MONTH_SINCE=$(date -d 'last month' +%Y-%m-01 2>/dev/null || date -v-1m -v1d +%F)
MONTH_UNTIL=$(date -d "$(date +%Y-%m-01) - 1 day" +%F 2>/dev/null || date -v-1d -v1m +%F)
```

| User says              | use                            |
|------------------------|--------------------------------|
| previous / last week   | `PREV_SINCE` .. `PREV_UNTIL`   |
| the week before that   | `PREV2_SINCE` .. `PREV2_UNTIL` |
| this week              | `THIS_SINCE` .. `THIS_UNTIL`   |
| last month             | `MONTH_SINCE` .. `MONTH_UNTIL` |
| last N days            | `TODAY - N` .. `TODAY`         |
| custom range           | as given                       |

> `date -d` is GNU (Linux); `date -j -f/-v` is BSD (macOS). Use the right one or try both.

## Step 2 -- Run `did` (raw, into a sidecar file)

`did` dumps **everything** the GitHub account touched -- including unrelated
side projects. Do **not** hand-edit or paraphrase it. Write the raw markdown to
a sidecar file next to the report so the user can filter it themselves:

```bash
did --since $SINCE --until $UNTIL --GitHub --format=markdown \
    > "${GIT_ROOT:-.}/pi-progress/did-${SINCE}_${UNTIL}.md"
```

`did` also accepts shorthand periods (`did last week --GitHub --format=markdown`).

**Filtering, when asked:** keep the ClickHouse org (`ClickHouse/*`) and the
user's own `Felixoid/*` repos. Drop clearly unrelated external side projects
(e.g. `wezterm`, `OrcaSlicer`, upstream forks the user only commented on).

## Step 3 -- Run pi-sessions

The script lives next to this SKILL.md:

```bash
python3 /home/felixoid/.pi/agent/skills/work-report/pi-sessions.py \
    --since $SINCE --until $UNTIL \
    > "${GIT_ROOT:-.}/pi-progress/pi-sessions-${SINCE}_${UNTIL}.md"
```

## Step 4 -- Delegate composition to `user:report-writer`

Once both raw files exist, spawn a subagent on `claude-sonnet-4-6` to do the
actual summarization -- no need to burn expensive parent tokens on it:

```
agent_team start:
  graph:
    objective: "Write a work report for <period>"
    authority:
      allowFilesystemRead: true
      allowMutationTools: true
    steps:
      - id: write-report
        agent:
          ref: user:report-writer
        task: |
          Read the raw inputs and write the report.

          Pi sessions: <path to pi-sessions output>
          Did output:  <path to did sidecar file>
          Period:      <SINCE> to <UNTIL>

          Write the final report to: <path to report file>
```

Wait for the run to finish, then show the user the report path.

## Step 5 -- (legacy) Compose the report manually

Only use this if `user:report-writer` is unavailable.

```markdown
# Work Report -- <period>

## What I worked on

<short narrative, derived ONLY from pi sessions>

---

## GitHub Activity (raw `did` output)

<tail in the raw did sidecar file verbatim>
```

This format is implemented in `user:report-writer`. Follow these rules only
when composing manually (Step 5).

**The narrative comes from the pi sessions, nothing else.** Each session/task
gets a few words to at most a couple of sentences: what it was and its state
(merged / under review / in progress / fixed). Then tail the raw `did` file in
below it, untouched.

Add a GitHub link to a narrative item **only** when that PR/issue appears in the
`did` output (or the session itself). Match by repo + topic. If there is no
matching `did`/session entry, leave it unlinked -- never guess a number.

### Hard rules -- do NOT

- **Do not invent narrative items from `did`.** If something is in `did` but the
  sessions never mention it, it does not go in the narrative. (`did` is already
  in the report verbatim -- that's enough.)
- **Do not assert authorship.** Do not say "my fix" / "I fixed" unless the
  session shows the user authored it. A PR under "reviewed" in `did` means the
  user **reviewed** it -- say "reviewed", not "fixed".
- **Do not fabricate context** for a `did` row. No backports, cleanups, or syncs
  in the narrative unless a session actually covers them.

## Notes

- If `did` returns nothing, say so and skip the GitHub section.
- If no pi sessions are found, say so briefly and move on.
- **Summarise the sessions, don't dump them.** The raw `pi-sessions.py` output is
  a noisy transcript (half-typed retries, duplicates, profanity). Condense each
  session/task into a few words to a couple of sentences -- enough that someone
  unaware of the work understands what it was and whether it's done. Never paste
  the transcript into the report.
- Group by project/task. Two sessions on the same task can be merged into one
  narrative item; keep genuinely separate tasks separate.
- Stick to what the sessions actually say. Don't extrapolate scope or outcomes.
