# Puddlefile agents

A Puddlefile packages an agent's behavior into one portable `.puddle` file. It can contain the agent's instructions, reusable skills, static assets, and metadata describing the runtime, model, operating-system, binary, and tool permissions it needs.

The current implementation supports creating, inspecting, verifying, and running local directories and `.puddle` archives. It can also run an agent directory directly from a public GitHub repository without keeping a clone. Registry distribution, installation, signatures, bundled executable extensions, network permissions, and environment permissions are not implemented yet.

## Quick start

Create a directory for the agent:

```text
reviewer/
├── manifest.json
├── AGENT.md
└── skills/
    └── code-review/SKILL.md
```

Add a minimal `manifest.json`:

```json
{
  "puddlefile": 1,
  "name": "code-reviewer",
  "version": "0.1.0",
  "description": "Reviews a repository and reports actionable findings.",
  "runtime": {
    "min_puddle": "0.2.76"
  },
  "model": {
    "requires": ["tools"],
    "min_context": 64000
  },
  "permissions": {
    "fs": {
      "read": ["${workspace}"],
      "write": []
    },
    "bash": {
      "mode": "none"
    }
  },
  "requirements": {
    "os": ["darwin", "linux", "windows"]
  },
  "entry": {
    "greeting": "What should I review?",
    "default_prompt": null
  }
}
```

Add the agent's standing instructions to `AGENT.md`:

```markdown
# Code reviewer

Review the current repository without modifying it.

Prioritize correctness, security, regressions, and missing tests. Report findings
in severity order with file and line references. Do not praise the code or
summarize files that have no findings.
```

Test the directory directly during development:

```bash
puddle inspect ./reviewer
puddle run ./reviewer
puddle run ./reviewer "Review the authentication package"
```

Package it when ready:

```bash
puddle pack ./reviewer
# wrote code-reviewer.puddle
# digest sha256:...

puddle verify ./code-reviewer.puddle
puddle run ./code-reviewer.puddle
```

The first run displays the declared permissions and asks for consent before the agent starts.

## Directory layout

```text
my-agent/
├── manifest.json          # identity, requirements, and permissions, required
├── AGENT.md               # persona and standing instructions, required
├── skills/                # SKILL.md directories, optional
│   └── my-skill/SKILL.md
├── assets/                # static files, optional
└── README.md              # human-facing documentation, optional
```

Only `manifest.json` and a regular `AGENT.md` file are required. Other ordinary files and directories are included in the archive, but the runtime gives no special behavior to `assets/` or `README.md` yet. Files in `assets/` are not automatically added to the model context or granted filesystem access.

Do not include executable extensions in `extensions/`. The local runtime rejects any bundled extension directory containing `extension.json` because extension subprocesses cannot yet be confined to the manifest permissions. This is a deliberate fail-closed restriction.

Symlinks are not supported and cause `puddle pack` to fail.

## `AGENT.md`

By default, `AGENT.md` is appended to puddle's system prompt. It should describe the agent's role, workflow, constraints, output format, and when to load bundled skills.

Keep capability and security declarations out of this file. Permissions come only from `manifest.json` and are enforced independently of agent-authored prose.

Set `replace_system_prompt` to `true` in the manifest to use `AGENT.md` as the replacement system prompt:

```json
{
  "replace_system_prompt": true
}
```

Replacement is intended for fully specialized agents. The default layering behavior is usually preferable because it retains puddle's normal identity and tool-use guidance.

## Bundled skills

Place skills under `skills/<name>/SKILL.md` using the normal puddle skill format:

```text
skills/
└── investigate-failure/
    └── SKILL.md
```

```markdown
---
name: investigate-failure
description: Diagnose a failing command from its output and relevant source files.
---

# Investigate failure

1. Reproduce the failure if permissions allow it.
2. Identify the first meaningful error rather than downstream noise.
3. Read the implementation and nearest tests.
4. Propose the smallest correction and validation plan.
```

Bundled skills are added to normal skill discovery while the Puddlefile is running. The model sees their name and description in the skill manifest and can load the full body through the `skill` tool. See [skills.md](skills.md) for the complete skill format.

## Manifest reference

The current manifest shape is:

```json
{
  "puddlefile": 1,
  "name": "code-reviewer",
  "version": "0.1.0",
  "description": "Reviews a repository and reports actionable findings.",
  "license": "MIT",
  "runtime": {
    "min_puddle": "0.2.76"
  },
  "model": {
    "requires": ["tools", "reasoning"],
    "min_context": 64000,
    "preferred": ["claude-opus-4-5", "gpt-5.5"],
    "min_tier": ""
  },
  "permissions": {
    "fs": {
      "read": ["${workspace}", "${agent_data}"],
      "write": ["${agent_data}"]
    },
    "bash": {
      "mode": "allowlist",
      "allow": ["git", "go"]
    },
    "net": {
      "allow": []
    },
    "env": {
      "read": []
    }
  },
  "requirements": {
    "bin": ["git", "go"],
    "os": ["darwin", "linux"]
  },
  "entry": {
    "greeting": "What should I review?",
    "default_prompt": null
  },
  "replace_system_prompt": false
}
```

### Top-level fields

| Field | Required | Current behavior |
|---|---:|---|
| `puddlefile` | yes | Format version. Must be `1`. |
| `name` | yes | Local agent identity and session/data namespace. See naming rules below. |
| `version` | no | Displayed in consent and inspection output. Semver is recommended but not currently validated. |
| `description` | no | Displayed by `puddle inspect`. |
| `license` | no | Package metadata. Not otherwise interpreted by the local runtime. |
| `runtime.min_puddle` | no | Minimum puddle version. Older binaries refuse to run the agent. Unversioned development builds cannot satisfy a non-empty minimum. |
| `model` | no | Model capabilities, minimum context, and preferences. |
| `permissions` | no | Filesystem and bash permission ceiling. Omitted scopes deny access. |
| `requirements` | no | Required operating systems and executables. |
| `entry` | no | Initial presentation and prompt metadata. |
| `replace_system_prompt` | no | Replaces rather than appends to the normal system prompt when `true`. Defaults to `false`. |

### Name rules

The local runtime currently accepts a flat lowercase name containing only:

- `a` to `z`
- `0` to `9`
- `.`, `-`, and `_`

Examples:

```text
code-reviewer
repo_onboarder
acme.audit
```

Names containing `/`, uppercase letters, spaces, or path-like values such as `..` are rejected. Registry-style `namespace/agent` names are reserved for the future distribution runtime and are not accepted locally yet.

### Model requirements

`model.requires` currently recognizes:

| Capability | Behavior |
|---|---|
| `tools` | Accepted. Every model in the current catalog is treated as tool-capable. |
| `reasoning` | Requires a catalog model marked as supporting reasoning. |
| `vision` | Recognized, but currently fails closed because vision support is not represented in the model catalog. No model qualifies. |

Unknown capabilities are rejected. Use `tools`, not the draft spelling `tool_calling`.

`model.min_context` requires a catalog model with at least that many context tokens.

`model.preferred` is an ordered list of model IDs. It is a preference, not a provider requirement. Selection proceeds as follows:

1. An explicitly selected model, if present, must satisfy the requirements.
2. The user's configured default is retained if it satisfies them.
3. The first compatible model in `preferred` is selected.
4. Otherwise, puddle chooses a compatible active catalog model.
5. If none qualifies, execution stops with an error.

`model.min_tier` is present in the format shape but is not supported by the local runtime. Leave it empty or omit it. A non-empty value is rejected.

### Runtime and host requirements

Use `requirements.os` to restrict the agent to Go operating-system names:

```json
{
  "requirements": {
    "os": ["darwin", "linux", "windows"]
  }
}
```

Use `requirements.bin` for commands that must already be on `PATH`:

```json
{
  "requirements": {
    "bin": ["git", "python3"]
  }
}
```

Puddle checks these requirements before requesting consent. Puddlefiles do not have install or postinstall hooks, so authors must document how users can obtain missing programs.

### Entry fields

`entry.default_prompt` is used when the user runs the agent without a prompt. It may be a string or `null`:

```json
{
  "entry": {
    "default_prompt": "Review the current repository"
  }
}
```

A prompt supplied on the command line takes precedence.

`entry.greeting` is part of the manifest, but the current local runtime does not render it yet.

## Filesystem permissions

Filesystem permissions are enforced by the built-in `read`, `write`, and `edit` tools. Empty or omitted scopes deny the operation.

Two variables are available in filesystem scopes:

| Variable | Resolves to |
|---|---|
| `${workspace}` | The current working directory used for the run. |
| `${agent_data}` | The agent's persistent private data directory under `$PUDDLE_HOME/agents/<name>/data/`. |

Relative paths are resolved beneath `${workspace}`. For example:

```json
{
  "permissions": {
    "fs": {
      "read": ["src", "go.mod"],
      "write": ["${agent_data}"]
    }
  }
}
```

This allows reads under `<workspace>/src` and at `<workspace>/go.mod`, plus writes under the private agent data directory. It does not grant general workspace writes.

Common permission profiles follow.

Read-only repository agent:

```json
{
  "permissions": {
    "fs": {
      "read": ["${workspace}"],
      "write": []
    },
    "bash": { "mode": "none" }
  }
}
```

Repository editor with private persistent state:

```json
{
  "permissions": {
    "fs": {
      "read": ["${workspace}", "${agent_data}"],
      "write": ["${workspace}", "${agent_data}"]
    },
    "bash": { "mode": "none" }
  }
}
```

Data-only agent:

```json
{
  "permissions": {
    "fs": {
      "read": ["${agent_data}"],
      "write": ["${agent_data}"]
    },
    "bash": { "mode": "none" }
  }
}
```

Filesystem checks canonicalize existing paths, or the nearest existing parent for a new path, so symlinks cannot be used to escape a declared scope.

If the working directory changes during a run, `${workspace}` permissions are expanded again for the new directory.

## Bash permissions

`permissions.bash.mode` supports three values.

### `none`

```json
{
  "bash": { "mode": "none" }
}
```

All bash tool calls are denied. This is also the default when `mode` is omitted.

### `ask`

```json
{
  "bash": { "mode": "ask" }
}
```

Bash is available after the user approves the agent at launch. Consent for an agent using `ask` is requested on every launch and is not cached.

In the current local runtime, `ask` is launch-time capability consent. It does not open a separate confirmation dialog for every individual bash invocation.

### `allowlist`

```json
{
  "bash": {
    "mode": "allowlist",
    "allow": ["git", "go", "grep"]
  }
}
```

Every command in a shell expression must be listed. Puddle checks commands separated by `;`, `&&`, `||`, and pipes. Paths are reduced to their base command name, so `/usr/bin/git` is checked as `git`. A leading environment assignment is skipped when identifying the command.

The allowlist rejects shell substitution, newlines, redirection, backticks, `$()`, `<`, and `>`. This intentionally supports simple command pipelines rather than arbitrary shell programs.

An `allowlist` mode with an empty `allow` array is invalid.

Only declare commands the agent genuinely needs. `requirements.bin` checks that a command exists, while `permissions.bash.allow` controls whether the agent may invoke it. Agents that execute a required command normally need it in both places.

## Network and environment permissions

The manifest shape includes `permissions.net.allow` and `permissions.env.read`, but the local runtime does not enforce them yet. To avoid presenting unenforced declarations as security controls, it rejects manifests containing any network host or environment variable.

Use empty arrays or omit these sections:

```json
{
  "permissions": {
    "net": { "allow": [] },
    "env": { "read": [] }
  }
}
```

Bundled executable extensions are rejected for the same reason. Network filtering, scrubbed extension environments, and extension confinement belong to a later runtime milestone.

## Consent and persistent data

Before the first run, puddle prints the agent identity and expanded filesystem and bash permissions, then asks:

```text
Agent code-reviewer@0.1.0 wants to run.

  fs read: /path/to/workspace
  fs write: none
  bash: none

Allow? [y/N]
```

For modes other than `bash: ask`, approval is cached for the exact artifact digest under:

```text
$PUDDLE_HOME/agents/<name>/consents/<digest>.json
```

Any change to the packaged artifact produces a different digest and requires consent again. `bash: ask` always requires fresh launch consent.

Non-interactive runs refuse to bypass consent by default. For controlled automation, set:

```bash
PUDDLE_AGENT_CONSENT=1 puddle run ./code-reviewer.puddle --print "Review this repository"
```

This environment variable skips the consent prompt. Only use it after independently inspecting and trusting the exact artifact being run.

Persistent agent data lives under:

```text
$PUDDLE_HOME/agents/<name>/data/
```

The directory is created for every run, but the agent can access it only when `${agent_data}` appears in the relevant filesystem permission scope.

## Agent-scoped sessions

Puddlefile sessions are isolated from ordinary puddle sessions and from other agents:

```text
$PUDDLE_HOME/sessions/agents/<name>/
```

Normal session flags still apply, including `--continue`, `--resume`, `--session`, and `--no-session`, but their default storage root is scoped to the active agent.

## Commands

### `puddle run`

Run an unpackaged directory during development:

```bash
puddle run ./my-agent
puddle run ./my-agent "Do the task"
```

Run a packed artifact:

```bash
puddle run ./my-agent.puddle
puddle run ./my-agent.puddle --print "Do the task"
puddle run ./my-agent.puddle --json "Do the task"
```

Arguments after the reference use puddle's normal CLI parser, so model, provider, reasoning, cwd, session, tool, and output-mode flags remain available. The manifest still imposes its permission and compatibility ceiling.

Local filesystem directories, local archive paths, and public GitHub agent-directory URLs are accepted. For GitHub, puddle downloads the repository archive into a temporary directory, selects the requested agent subdirectory, validates it, runs it, and removes the downloaded files when the command exits:

```bash
puddle run https://github.com/erdium/agents/puddle-maintenance --cwd /path/to/puddle
```

Both the short subdirectory form above and a standard GitHub tree URL are supported:

```bash
puddle run https://github.com/erdium/agents/tree/main/puddle-maintenance
```

The short form reads the repository's default branch through GitHub's `HEAD` archive. A tree URL uses the branch or tag in the URL. Private repositories and GitHub references containing `/` are not currently supported. The downloaded source is temporary, but normal agent data, consent receipts, and session transcripts remain under `$PUDDLE_HOME`.

Installed names, arbitrary URLs, registry references, and OCI references are not resolved yet.

### `puddle pack`

```bash
puddle pack [directory] [output]
```

Examples:

```bash
puddle pack
puddle pack ./my-agent
puddle pack ./my-agent ./dist/reviewer.puddle
```

The default directory is the current directory. When output is omitted, puddle uses `<manifest-name>.puddle`. If the output has no `.puddle` suffix, puddle adds one.

Packing validates the manifest and directory, then creates a zstd-compressed tar archive. Entries are sorted and tar metadata is normalized with fixed timestamps and numeric ownership. The output archive itself is excluded when it is located inside the source directory. Puddle prints the SHA-256 digest of the resulting compressed artifact.

### `puddle inspect`

```bash
puddle inspect ./my-agent
puddle inspect ./my-agent.puddle
puddle inspect https://github.com/erdium/agents/puddle-maintenance
```

Inspection validates and prints the agent's name, version, description, digest, declared permissions, and complete file list. It does not execute the agent.

For a directory, the digest is computed from its canonical uncompressed tar representation. For a `.puddle` archive, the digest is computed from the archive bytes. Therefore a source-directory digest and its packed-archive digest are not expected to match.

### `puddle verify`

```bash
puddle verify ./my-agent.puddle
```

The local `verify` command validates that the archive can be safely loaded, validates the manifest and required layout, and prints its SHA-256 digest.

Despite the command name, it does **not** verify a publisher signature in the current runtime. Signature and namespace verification are planned for registry distribution.

## Packaging and extraction limits

The archive loader applies these limits:

| Limit | Value |
|---|---:|
| Compressed `.puddle` file | 100 MiB |
| One extracted entry | 64 MiB |
| Total extracted content | 256 MiB |

Archive extraction rejects absolute paths and parent traversal. Unsupported tar entry types are ignored. New packages use zstd; gzip-compressed tar archives are accepted only as a compatibility fallback for earlier experiments.

## Authoring guidance

1. Start with the narrowest permissions possible. A reviewer usually needs repository reads, not writes or bash.
2. Keep `AGENT.md` focused on stable behavior. Put task-specific procedures in skills so the model loads them only when relevant.
3. Declare every external command in both `requirements.bin` and the bash allowlist when the agent must execute it.
4. Test from a directory first with `puddle inspect` and `puddle run`.
5. Test denied behavior as well as allowed behavior. Ask the agent to attempt an out-of-scope read, write, and command.
6. Pack the same source twice and compare behavior and output digests before distributing it.
7. Inspect and verify the final archive, not only its source directory.
8. Do not claim that network, environment, signatures, extensions, installation, or registry delivery are secured or supported by the local runtime.

## Current scope

Implemented now:

- local directories and `.puddle` archives
- temporary execution of agent directories from public GitHub repositories
- `puddle pack`, `puddle inspect`, `puddle verify`, and `puddle run`
- canonical tar creation with zstd compression
- archive digest reporting and safe extraction limits
- `AGENT.md` append or replacement behavior
- bundled skills
- runtime, OS, and binary requirements
- model context and reasoning requirements
- filesystem scope enforcement
- bash `none`, `ask`, and `allowlist` modes
- digest-scoped consent receipts
- private agent data directories
- agent-scoped sessions

Not implemented yet:

- `puddle install`, `puddle agents`, `puddle use`, `puddle update`, or `puddle publish`
- installed-name, arbitrary URL, OCI, or puddle.sh index resolution
- network allowlist enforcement
- environment-variable filtering
- safely confined bundled executable extensions
- automatic artifact theme loading
- agent dependency composition
- per-agent Telegram, bot, or RPC selection
- `--no-sandbox`, `--trust-bash`, or registry trust override flags

Treat the unsupported fields and commands in the broader Puddlefile proposal as forward-looking design, not as current runtime behavior.
