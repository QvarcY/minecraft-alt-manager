# Minecraft ALT Manager Changelog

This file documents the public release history of Minecraft ALT Manager.

Internal development builds existed before the first public release, but they were never distributed publicly and are therefore documented separately as pre-release development milestones rather than public releases.

---

## 3.2.0 — 2026-08-24

**Initial Public Release**

**Status:** Stable<br>
**Platform:** Windows x64<br>
**Edition:** Minecraft Java Edition

Minecraft ALT Manager v3.2.0 is the first version of the application released publicly.

### Added

- Multi-server and multi-profile system.
- Guided profile templates:
  - Exploration mode
  - Direct AFK
  - Login + AFK
  - Hub / Proxy + Home
- `WHEN → WAIT → DO` workflow editor.
- `afterStep` conditions for linear workflow chains.
- Server-message triggers that can depend on completion of a previous step.
- Manual command console.
- Workflow variables:
  - `{password}`
  - `{username}`
  - `{host}`
  - `{port}`
- Clickable server log messages for easier workflow configuration.
- Profile validation.
- Profile import and export.
- Integrated application guide.
- Full Latvian and English user documentation.

### Reliability

- Progressive automatic reconnect delays.
- Reconnect circuit breaker.
- Per-profile reconnect safety configuration.
- Reconnect failure counter reset after successful AFK state.
- Fresh reconnect cycle after manual Start / Restart.
- Velocity proxy transition handling.
- Minecraft `CONFIGURATION` state handling.
- PLAY-only `tick_end` protection outside the `PLAY` state.
- Physics processing protection during protocol-state transitions.

### Security

- Windows DPAPI protected password storage.
- Passwords are not stored directly in profile JSON files.
- `{password}` values are resolved only when required by a workflow action.
- Release packaging checks exclude locally stored secrets.
- Microsoft authentication caches are excluded from release packages.
- Sensitive runtime data is excluded from the public source repository.

### Portable and Installed Modes

- Portable Windows mode.
- Installed Windows mode.
- Stable Portable ID between release versions.
- Bundled Node.js runtime.
- Installation without requiring a system Node.js installation.
- Installed-mode application marker.
- Safe uninstall process.
- Uninstaller executes from the Windows temporary directory during cleanup.
- Installed uninstall preserves `PortableData` where appropriate.

### Release Engineering

- Automated Windows release builder.
- Versioned release directory generation.
- Bilingual release documentation generation.
- Release integrity manifest.
- Package metadata generation.
- Final distributable ZIP generation.
- SHA256 checksum generation.
- Builder validation against obsolete or unsafe installer architecture.
- Runtime dependency probing.
- Isolated clean-PC startup simulation.

### Release Optimization

The packaged Java Edition release was optimized from approximately:

```text
536.8 MB
```

to approximately:

```text
195.4 MB
```

before ZIP compression.

The final Windows x64 distributable ZIP is approximately:

```text
44.4 MB
```

The optimization removes unnecessary Bedrock Edition version-data sets while retaining:

- all required Java / PC `minecraft-data`;
- Bedrock common metadata required by the upstream loader;
- all runtime dependencies required by Minecraft ALT Manager.

### Verified

The first public stable release was tested successfully for:

- Portable mode — **PASS**
- Installed mode — **PASS**
- Automatic reconnect — **PASS**
- Reconnect circuit breaker — **PASS**
- Installed uninstall — **PASS**
- `PortableData` preservation — **PASS**
- Clean-PC isolated startup without system-installed Node.js — **PASS**
- Velocity proxy transition handling — **PASS**
- Workflow continuation after server transition — **PASS**

A complete real-world workflow was also tested on:

```text
mc.knt.lv
```

using Minecraft Java Edition:

```text
1.21.11
```

Tested workflow:

```text
Connect
→ Login
→ Survival server
→ land-home
→ AFK
→ reconnect handling
```

Minecraft ALT Manager is not an official KNT product and no affiliation or endorsement is implied.

---

## Pre-release Development

Before v3.2.0 became the first public release, Minecraft ALT Manager went through multiple internal development iterations.

These builds were used only during development and testing and were never publicly released.

The milestones below are grouped by development area rather than by invented release dates.

### Core ALT Management

The original application evolved from a server-specific ALT connection tool into a reusable profile-based manager.

Development included:

- Mineflayer connection management;
- configurable Minecraft server address and port;
- configurable username and authentication mode;
- automatic login commands;
- AFK-state tracking;
- server log monitoring;
- manual start and stop controls.

### Workflow System

Server-specific command sequences were progressively separated from the application core.

This resulted in:

- configurable workflow steps;
- message-based triggers;
- spawn-based triggers;
- configurable delays;
- workflow actions;
- `afterStep` dependencies;
- reusable workflow variables;
- guided profile templates;
- profile validation;
- profile import and export.

This allowed different Minecraft servers to use different login, proxy, teleport and AFK sequences without modifying the core application.

### Reconnect and Failure Handling

Connection recovery was developed into a dedicated resilience system.

Internal development introduced:

- automatic reconnect;
- progressive reconnect backoff;
- retry counters;
- reconnect circuit breaker;
- stable-connection detection;
- AFK-based reconnect reset;
- manual reconnect-cycle reset.

### Modern Minecraft Protocol Compatibility

Newer Minecraft Java versions required additional protocol compatibility work.

Development included:

- modern `CLIENT_TICK_END` support;
- Mineflayer `tick_end` compatibility patch;
- protection against PLAY-only packets outside the `PLAY` state;
- Velocity `CONFIGURATION` transition handling;
- temporary physics suspension during configuration transitions;
- restoration of normal processing after returning to `PLAY`.

### Credential Handling

Password handling evolved from simple runtime configuration into Windows-protected credential storage.

Development included:

- DPAPI encryption;
- separate secret storage;
- `{password}` workflow substitution;
- delayed password decryption;
- protection against including secrets in release packages;
- separation of Portable and Installed credential contexts.

### Portable and Installed Architecture

The application was developed to support both portable and installed use.

This required:

- portable identity handling;
- stable Portable ID;
- portable runtime data;
- user-local installation;
- install markers;
- safe uninstall logic;
- temporary-directory uninstall bootstrap;
- preservation of selected portable data;
- registry cleanup.

### Release Builder and Verification

The development project was converted into a reproducible Windows release system.

The builder gained:

- bundled Node.js runtime;
- dependency packaging;
- generated launchers;
- generated installers and uninstallers;
- bilingual documentation;
- integrity metadata;
- package metadata;
- clean-PC simulation;
- dependency validation;
- secret/auth-cache checks;
- final ZIP verification;
- SHA256 checksum generation.

### Package Optimization

The initial packaged development tree was considerably larger than necessary.

Release optimization reduced the package by:

- cleaning unnecessary dependency files;
- removing unused Bedrock version data;
- retaining complete Java / PC protocol data;
- retaining loader-required common metadata;
- validating runtime dependencies after cleanup.

### User Interface and Documentation

The local web interface evolved alongside the application core.

Development included:

- profile management;
- guided profile creation;
- workflow editing;
- clickable server logs;
- manual command console;
- status and reconnect information;
- built-in help;
- Latvian documentation;
- English documentation.

---

## Release History Policy

Only versions that are actually made available publicly are listed as dated releases in this changelog.

Internal development versions, experiments and test builds are not presented as public releases.

Future public releases will be listed here with their actual release dates.

---

Minecraft ALT Manager<br>
Created by **QvarcY**<br>
**IT solutions by QvarcY**<br>
https://kas.id.lv