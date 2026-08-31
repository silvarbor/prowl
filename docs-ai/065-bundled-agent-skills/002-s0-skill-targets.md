# 065 S0 — Skill install target verification

| | |
| --- | --- |
| **Status** | Complete |
| **Verified** | 2026-08-27 |
| **Scope** | `claude`, `codex`, and `agents` install targets only; no production skill directories were modified |

## Outcome

The V1 target table is viable with one symlink per skill directory. Claude Code and Codex
both follow a skill-directory symlink into an external canonical directory. The shared
`.agents/skills` target is read by most Agent Profile runtimes installed on the verification
host. Every locally exercised reader followed the directory-symlink shape. Cursor remains a
location-only result because its CLI stops before discovery without account authentication;
that residual gap is not evidence of refusal, so copy mode does **not** move into K2.

The three target ids describe install locations, not mutually exclusive runtimes:

- `claude` is Claude Code's native user/project location.
- `codex` is Codex's native/legacy-compatible user/project location.
- `agents` is the cross-runtime location. Codex also reads it, as do multiple other
  installed runtimes.

Installing the same bundled skill into both `codex` and `agents` is therefore expected. The
links resolve to the same canonical bundle directory; target status and removal remain
independent at skill × target granularity.

## Safety and method

All probes used temporary roots created by `mktemp`:

- a temporary `HOME` for shared user paths;
- a temporary `CLAUDE_CONFIG_DIR`;
- a temporary `CODEX_HOME`;
- initialized throwaway Git repositories for project discovery; and
- canonical marker skills outside the runtime discovery roots, linked into each target.

Each discovery root contained one valid absolute directory symlink and one dangling absolute
directory symlink. The live `~/.claude/skills`, `~/.codex/skills`, and `~/.agents/skills`
paths were neither read as test inputs nor modified. Runtime credentials were not copied into
the temporary homes.

Evidence is labelled below as:

- **black-box** — the installed runtime's own list/inspect/debug surface returned the marker;
- **installed source** — the exact installed version's loader was invoked or inspected
  without a model request; or
- **documented** — the installed CLI could not complete isolated discovery without
  authentication/model configuration, so its official runtime documentation confirms the
  location only. These cases are not reported as directory-symlink or authenticated
  end-to-end verification unless installed source supplied that additional evidence.

## Target results

### `claude`

| Field | Verified value |
| --- | --- |
| User directory | `~/.claude/skills` (`$CLAUDE_CONFIG_DIR/skills` under an override) |
| Project directory | `.claude/skills` |
| Runtime | Claude Code 2.1.246 |
| Directory symlink | Followed at user and project scope |
| Dangling symlink | Omitted from discovery; other skills continue loading |
| Evidence | Black-box startup/debug log under a temporary `CLAUDE_CONFIG_DIR` |

The probe started headless Claude Code without credentials. It exited with `Not logged in`
after local initialization, but its debug log reported the temporary user and project roots
and `Loaded 2 unique skills (… user: 1, project: 1 …)`: exactly the two valid linked marker
skills. The two dangling links were not counted. No model call or live credential was needed.

### `codex`

| Field | Verified value |
| --- | --- |
| User directory | `~/.codex/skills` (`$CODEX_HOME/skills` under an override) |
| Project directory | `.codex/skills` |
| Additional compatible directories | `~/.agents/skills`, `.agents/skills` |
| Runtime | Codex CLI 0.149.1 |
| Directory symlink | Followed in all four roots |
| Dangling symlink | Omitted; `skills/list` returned an empty `errors` array |
| Evidence | Black-box App Server `skills/list` under temporary `HOME` and `CODEX_HOME` |

The App Server handshake (`initialize` → `initialized` → `skills/list`) returned one marker
from each root. In particular, `.codex/skills` was returned with `scope: repo`, resolving the
plan's project-directory question. Returned paths pointed to each symlink's canonical target.

### `agents`

| Field | Verified value |
| --- | --- |
| User directory | `~/.agents/skills` |
| Project directory | `.agents/skills` |
| Directory symlink | Supported by the locally exercised readers below; documented/source-only readers are marked |
| Dangling symlink | Ignored by locally exercised readers; Droid additionally logs a warning |

Installed-runtime matrix:

| Runtime/version | User | Project | Evidence | Dangling-link behavior |
| --- | --- | --- | --- | --- |
| Codex CLI 0.149.1 | Yes | Yes | Black-box `skills/list` | Silently omitted |
| Gemini CLI 0.46.0 | Yes | Yes | Black-box `gemini skills list` | Omitted |
| Cursor Agent 2026.05.09 | Yes | Yes | Documented location; isolated CLI stopped at authentication | Not black-box verified in S0 |
| OpenCode 1.18.23 | Yes | Yes | Black-box `opencode debug skill` | Silently omitted |
| GitHub Copilot CLI 1.0.80 | Yes | Yes | Black-box `copilot skill list --json` | Silently omitted |
| Kimi CLI 1.41.0 | Yes | Yes | Installed loader via `resolve_skills_roots` | Silently omitted |
| Droid 0.204.0 | Yes | Yes | Installed discovery during `droid exec --list-tools`; official location docs | Skipped with `Skipping unresolvable path during discovery` warning |
| Amp 0.0.1783746383 | Yes | Yes | Black-box `amp skill list --json` with a non-secret placeholder key | Silently omitted; returned `errors: []` |
| Qoder CLI 1.1.31 | Yes | Yes | Black-box `qodercli skills list` | Silently omitted |
| Pi 0.84.3 | Yes | Yes | Installed `loadSkills` implementation | Silently omitted |
| Oh My Pi 18.0.6 | Yes | Yes | Black-box RPC `get_available_commands` with a non-secret placeholder key | Silently omitted; stderr remained empty |
| Grok Build 0.2.118 | Yes | Yes | Black-box `grok inspect --json` | Silently omitted |
| Claude Code 2.1.246 | No | No | Native directories verified separately above | N/A for this target |
| Cline CLI 3.0.56 | No by default | No by default | Official paths are `~/.cline/skills` / `.cline/skills` | N/A for this target |
| Qwen Code 0.21.3 | No by default | No by default | Official paths are `~/.qwen/skills` / `.qwen/skills`; custom directories are configurable | N/A for this target |

The V1 `agents` target should list only these established readers. A later runtime may join
when its installed behavior or authoritative documentation confirms both location and
symlink handling; Prowl should not infer support from `AgentProfileRuntime` membership alone.

## Cursor and Amp custom-model feasibility

Cursor Agent CLI cannot use a custom provider to close its remaining black-box gap. In the
installed 2026.05.09 CLI, `--api-key` is Cursor account authentication and `--model` selects
from that account's model catalog. There is no provider/base-URL option. Cursor IDE's BYOK
and OpenAI base-URL override do not carry over to Agent CLI. Without a valid Cursor account
credential, S0 can record only the official `.agents/skills` location support; it does not
claim an authenticated directory-symlink run.

Amp 0.0.1783746383 does expose a real custom-provider surface:

```text
amp config model-providers add-router openai-compatible
  --base-url <https-url>
  --api-key-env <variable>
  --model-mapping <patterns>
  --personal|--workspace
```

This can route inference away from Amp credits, but creating the personal/workspace router
still requires Amp account authentication and mutates account configuration. It was neither
needed nor used for S0: `amp skill list --json` completed locally with a non-secret
placeholder key, returned both linked marker skills, omitted both dangling links, and
reported `errors: []` without a model request.

## Plan impact

1. Keep all three target ids and their existing detection rule: the target is detected when
   its parent directory exists; explicit `--target` may create it.
2. Set Codex project scope to `.codex/skills`.
3. Describe `agents` as the shared target read by the verified runtime set above, not as a
   fourth runtime.
4. Keep direct absolute bundle links. No compatibility copy is required in K2.
5. Keep `broken` as an installer status even though runtimes omit dangling links: Prowl must
   surface and repair a moved/removed bundle instead of inheriting each runtime's mostly
   silent behavior.
6. Keep authenticated K2 manual verification focused on Claude Code and Codex as planned.
   Cursor remains a location-only result and does not become a claim of authenticated
   end-to-end testing.

## K1 implementation boundary

K1 remains foundation-only: it bundles and locates skills but does not install them. The
planned shared surface in `ProwlCLIShared` is:

```swift
public enum ProwlSkillAudience: String, Sendable {
  case user
  case workflow
}

public struct BundledSkill: Equatable, Sendable {
  public let id: String
  public let name: String
  public let description: String
  public let audience: ProwlSkillAudience
  public let directoryURL: URL
}

public enum ProwlSkills {
  public static func bundled(resourcesURL: URL) throws -> [BundledSkill]
  public static func skill(id: String, resourcesURL: URL) throws -> BundledSkill?
  public static func bundledForCLI(
    executableURL: URL,
    environment: [String: String]
  ) throws -> [BundledSkill]
}
```

The semantic contract is fixed even if red tests motivate a smaller helper split:

- `bundled(resourcesURL:)` enumerates `<resourcesURL>/skills/*/SKILL.md` in stable id order.
- `skill(id:resourcesURL:)` is the 063 runner lookup and never searches third-party roots.
- `bundledForCLI` uses `PROWL_SKILLS_DIR` first; otherwise it resolves the executable symlink
  and finds `../skills` beside the bundled `prowl-cli` directory.
- A missing override/bundle maps to `BUNDLE_NOT_FOUND` for the future K2 command surface.
- The parser accepts only `name`, plain or folded `description`, and
  `metadata.prowl-install`; absent audience defaults to `user`.

K1 tests should be red first for plain/folded descriptions, audience default/override,
stable enumeration, id lookup, executable-symlink resolution, override precedence, and the
missing-bundle error.

## References

- [Claude Code skills](https://code.claude.com/docs/en/slash-commands)
- [Codex App Server `skills/list`](https://developers.openai.com/codex/app-server/)
- [Gemini CLI skills](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/using-agent-skills.md)
- [GitHub Copilot agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
- [Kimi CLI skills](https://github.com/MoonshotAI/kimi-cli/blob/main/docs/en/customization/skills.md)
- [Factory Droid skills](https://docs.factory.ai/harness/skills)
- [Amp skills](https://ampcode.com/docs/customize/skills)
- [Amp modes and model routing](https://ampcode.com/docs/models-and-subagents)
- [Cursor Agent CLI authentication](https://docs.cursor.com/en/cli/reference/authentication)
- [OpenCode skills](https://opencode.ai/docs/skills)
- [Pi skills](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md)
- [Oh My Pi skills](https://github.com/can1357/oh-my-pi/blob/main/docs/skills.md)
- [Agent Skills specification](https://agentskills.io/specification)
