# Contributing

1. Pick or open an issue. The issue is the spec (what, why, acceptance criteria).
2. Branch from `main`: `<type>/<short-topic>` (e.g. `fix/clutter-hash`).
3. Make the change; follow `AGENTS.md` and `DESIGN.md`. Run `./test.sh` and `./build.sh`.
4. Commit small, imperative messages ("Add Gradle cache to developer leftovers").
5. Open a PR with `Closes #N`, what and why, and how to test (screenshots for visual changes).

Never commit: signing identities, notarytool profiles, Sparkle keys, `.env*`, `build/`, `.build/`, renders, `node_modules/`.
If you learned something the next person needs, add it to `AGENTS.md` or `DESIGN.md` in the same PR.
