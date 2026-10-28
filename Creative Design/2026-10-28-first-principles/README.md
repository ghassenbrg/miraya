# Miraya — first-principles design review

> **PROPOSAL ONLY — NOT APPROVED — DO NOT SHIP OR APPLY.**

Created 2026-10-28 for personal design review. Everything in this folder is isolated from shipping code, icons, resources, version metadata and workflows. Sidefolk is outside this work and is not modified.

Open `index.html` locally for the interactive review. It covers principal Mac sender and Android/Google TV receiver states, three creative directions, identity, platform icons, product semantics and review notes.

## Selected direction: Reflection Seam

Two mirrored folded facets form a central reflection seam. The mark avoids generic monitor, Wi‑Fi, cast, antenna and play symbols. The seam also becomes a state grammar: unavailable, pairing, trusted, live, paused and stopped.

The Mac sender is a single source → seam → destination connection plane, not a conventional left sidebar plus settings cards. The TV receiver prioritizes across-room readability, D-pad focus, safe edges and explicit Back/Stop behavior.

## Product-truth note

This proposal follows the review brief: six-digit comparison pairing and product label `0.1.0`. The inspected repo snapshot currently contains a 16-character pairing-code UI and Android `versionName = "1.0.0"`. Those shipping details are deliberately **not changed here**.

Netflix handoff and the iOS icon direction are labeled proposal/future surfaces; they do not claim current shipping functionality.