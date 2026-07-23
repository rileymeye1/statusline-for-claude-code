# Contributing

Thanks for your interest in improving this project! It's a small, focused tool, so a little process keeps it healthy and the scope tight.

## Before you open an issue

- **Search first.** Check the [existing issues](../../issues?q=is%3Aissue) and [Discussions](../../discussions) — your topic may already be there. Add to the existing thread rather than opening a duplicate.
- Use the **Bug Report** or **Feature Request** form so we capture the details needed to act.
- For questions and open-ended ideas, prefer **[Discussions](../../discussions)** over an issue.

## Before you open a pull request

**Please open an issue first and wait for it to be accepted.** This is a maintainer-curated project; pull requests that aren't tied to an approved issue may be closed without review to keep the scope focused. Once an issue is triaged and accepted, you're clear to start work.

Exception: trivial, obvious fixes (a typo, a broken link) are fine to PR directly.

## Pull request expectations

- **Link the approved issue** in the PR description (`Closes #123`).
- **Conventional Commits** for the PR title and commits — e.g. `feat: …`, `fix: …`, `docs: …`. See [conventionalcommits.org](https://www.conventionalcommits.org/).
- **Keep bash and PowerShell in parity.** A behavior change in `bash/statusline-command.sh` should have the matching change in `powershell/statusline-command.ps1` (and vice-versa), plus the shared `statusline.conf.example` if you add a config key.
- **Test it.** Run the relevant checks in [`TESTING.md`](TESTING.md) and note in the PR which OS/shell(s) you tested on. Cross-platform changes should ideally be tested on both a Unix shell and Windows PowerShell.
- **No new required dependencies.** bash uses `jq` + `git`; PowerShell uses only built-ins. Don't add others without discussing it first.
- **Update the docs** (`README.md` / `TESTING.md`) when behavior or config changes.

## Scope

This tool aims to stay small and dependency-light. Features that add heavy dependencies, very niche modules, or broad scope creep may be declined even if well-built — please float them in an issue first so we can align before you invest time.

By contributing, you agree that your contributions are licensed under the repository's [MIT License](LICENSE).
