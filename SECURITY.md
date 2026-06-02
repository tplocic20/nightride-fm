# Security policy

This is a small client app that streams public internet radio. It has no
accounts, no servers of its own, and collects no user data — so the attack
surface is small. Still, if you find something, I'd genuinely like to know.

## Reporting a vulnerability

**Please don't open a public issue for security problems.** Instead, report
privately via one of:

- **GitHub private vulnerability reporting** — the "Report a vulnerability"
  button under the repository's **Security** tab (preferred).
- **Email** — hello@plocic.dev, subject line starting with `[security]`.

Please include:

- what the issue is and where (file / platform),
- steps to reproduce or a proof of concept,
- the impact you think it has.

## What to expect

This is a hobby project maintained in spare time, so I can't promise enterprise
SLAs — but I'll aim to:

- acknowledge your report within about a week,
- keep you posted on the fix,
- credit you when the fix ships, if you'd like.

## Scope

In scope: the client code in this repo (macOS / iOS / Android) and the build /
release scripts.

Out of scope: the Nightride FM service itself (`nightride.fm`,
`stream.nightride.fm`) — that's operated by the station, not this project.
Report those to Nightride FM directly. Likewise Spotify / Apple Music / YouTube
and Discord are third parties; report issues in those to their vendors.
