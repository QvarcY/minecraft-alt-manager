# Minecraft ALT Manager

**A Windows manager for Minecraft Java Edition ALT accounts, automated login flows, server switching, AFK workflows and reconnect handling.**

Created by **QvarcY**<br>
**IT solutions by QvarcY**<br>
https://kas.id.lv

---

## Overview

Minecraft ALT Manager is a Windows application designed to keep Minecraft Java Edition ALT accounts connected without running a full Minecraft game client.

Instead of hard-coding one specific server flow, the application uses configurable profiles and simple automation workflows.

A profile can describe things such as:

```text
WHEN the ALT joins
→ WAIT 3 seconds
→ DO /login {password}

WHEN the server confirms login
→ WAIT 3 seconds
→ DO /server-survival

WHEN the target server is ready
→ WAIT 3 seconds
→ DO /tp land-home

WHEN the destination world has loaded
→ MARK AS AFK
```
---

## Highlights

- Minecraft **Java Edition** support
- Windows x64
- Portable and installed modes
- Local browser-based management interface
- Multiple configurable server profiles
- Guided profile templates
- Exploration mode for unknown servers
- `WHEN → WAIT → DO` workflow editor
- Automatic `/login` workflows
- Proxy / hub server switching
- Automatic teleport and home commands
- Automatic AFK workflow handling
- Automatic reconnect with progressive backoff
- Reconnect circuit breaker
- Velocity `CONFIGURATION` transition handling
- Modern Minecraft `CLIENT_TICK_END` compatibility
- Manual command console
- Clickable server log messages for workflow configuration
- Profile validation
- Profile JSON import/export
- Windows DPAPI protected password storage
- Bundled Node.js runtime in Windows releases
- Clean-PC self-test
- Release integrity verification

---

## Download

The recommended way to use Minecraft ALT Manager is through the latest GitHub Release.

Current stable version:

**Minecraft ALT Manager v3.2.0**

Release package:

```text
MinecraftAltManager_By_QvarcY-v3.2.0-Windows-x64.zip
```

Platform:

```text
Windows x64
Minecraft Java Edition
```

Release size:

```text
ZIP:       44.4 MB
Extracted: 195.4 MB
```

SHA256:

```text
8931b3d24ab9686c4fc13b67321f184b789cae9fe94bf5b8d905a71067e6f769
```

The Windows release includes the required Node.js runtime and dependencies.

You do **not** need to install Node.js separately when using the packaged release.

---

## Portable or Installed?

Minecraft ALT Manager can be used in two different ways.

### Portable mode

Run:

```text
RUN-PORTABLE.cmd
```

The application runs directly from the extracted release folder or from a USB drive.

Portable mode is useful when you want to:

- keep the application self-contained;
- move it between compatible Windows computers;
- avoid installing the application permanently;
- keep profiles together with the portable copy.

Passwords are **not stored directly inside profile JSON files**.

Minecraft ALT Manager protects saved passwords using Windows DPAPI, so the encrypted credential data remains tied to the Windows user environment where it was saved.

### Installed mode

Run:

```text
INSTALL.cmd
```

Minecraft ALT Manager will install itself under the current Windows user's local application data directory.

The packaged installer already contains the required runtime, so a separate Node.js installation is not required.

To remove the installed application, use:

```text
UNINSTALL-FROM-PC.cmd
```

The uninstall process removes the installed application while preserving portable identity data where appropriate.

---

## First Run

After starting Minecraft ALT Manager, open the local management interface:

```text
http://127.0.0.1:3077
```

From the interface you can:

1. create or select a server profile;
2. configure the Minecraft server address and port;
3. enter the ALT username and authentication type;
4. save the account password securely;
5. configure the connection workflow;
6. start the ALT;
7. follow connection status and server messages in real time.

---

## Creating a Profile

Minecraft servers do not all use the same login and navigation flow.

One server may connect directly to the target world, while another may require:

```text
Login
→ Hub
→ Server selection
→ Teleport / Home
→ AFK
```

Minecraft ALT Manager therefore provides several starting templates:

- **Exploration mode**
- **Direct AFK**
- **Login + AFK**
- **Hub / Proxy + Home**

If you do not yet know how a server behaves, start with **Exploration mode**.

You can connect the ALT, watch the server log and use the manual command console to determine which commands and server messages are required.

The workflow system follows a simple model:

```text
WHEN something happens
↓
WAIT for a defined delay
↓
DO an action
```

For example:

```text
WHEN the ALT spawns
→ WAIT 3 seconds
→ DO /login {password}

WHEN login succeeds
→ WAIT 3 seconds
→ DO /server-survival

WHEN the destination server responds
→ WAIT 3 seconds
→ DO /tp land-home
```

Available workflow variables include:

```text
{password}
{username}
{host}
{port}
```

The real password is resolved at runtime and does not need to be written directly into the profile JSON.

---

## Example: KNT Survival

A sanitized real-world profile example is included in:

```text
examples/knt-survival.example.json
```

This workflow was developed and tested against:

```text
mc.knt.lv
```

using Minecraft Java Edition `1.21.11`.

The example demonstrates a complete multi-step connection flow:

```text
Connect to mc.knt.lv
↓
Wait for spawn
↓
/login {password}
↓
Wait for successful login message
↓
/server-survival
↓
Wait for the Survival server
↓
/tp land-home
↓
Wait for the server/world transition
↓
Mark the ALT as AFK
```

The example profile also demonstrates handling of a Velocity-based server transition and automatic reconnect behavior.

For public distribution, the included profile uses:

```text
Example_ALT
```

instead of a real Minecraft account username.

No real password is included. The `{password}` value is resolved by Minecraft ALT Manager at runtime from the locally protected credential store.

### About KNT

KNT is the server environment where this workflow was developed and tested.

Server address:

```text
mc.knt.lv
```

Minecraft ALT Manager is an independent project and is **not an official KNT product**. No affiliation, endorsement or official support relationship is implied.

The KNT profile is included as a practical example of how Minecraft ALT Manager can automate a real server workflow.

---

## Password Security

Minecraft ALT Manager does not store profile passwords directly inside profile JSON files.

On Windows, saved passwords are protected using **DPAPI** and are tied to the Windows user environment where they were stored.

Profiles can therefore contain:

```text
/login {password}
```

without containing the real password itself.

The `{password}` placeholder is resolved only when the workflow is executed.

Sensitive runtime data must never be committed to Git or shared publicly.

Examples include:

```text
data/secrets/
data/microsoft-auth/
PortableData/
manager.token
*.dat
```

Minecraft ALT Manager release packages are built with checks that help prevent locally stored passwords and Microsoft authentication caches from being accidentally included.

When reporting bugs or sharing screenshots, always remove passwords, tokens and other authentication data.

See [SECURITY.md](SECURITY.md) for the project's security reporting policy.

---

## Reconnect Protection

Minecraft ALT Manager can automatically reconnect an ALT after an unexpected disconnect.

Reconnect attempts use increasing delays instead of retrying continuously at full speed.

The reconnect system also includes a circuit breaker.

If repeated connection failures continue beyond the configured limit, automatic reconnect stops instead of creating an endless reconnect loop.

When the ALT successfully reaches its AFK state, the reconnect failure counter is reset.

A manual start begins a new reconnect cycle.

This helps distinguish between:

```text
Temporary disconnect
→ reconnect
→ continue workflow
```

and:

```text
Repeated failure
→ stop automatic retries
→ wait for manual intervention
```

This behavior is especially useful on servers using proxies, server switching or temporary world transitions.

---

## Velocity and Modern Minecraft Compatibility

Modern Minecraft Java protocol versions can transition between different connection states when moving between proxy servers, game servers or worlds.

One important transition is:

```text
PLAY
→ CONFIGURATION
→ PLAY
```

This can happen on Velocity-based networks when the ALT is moved from a hub to another server.

Minecraft ALT Manager includes compatibility handling for these transitions.

During the `CONFIGURATION` state, the application temporarily prevents PLAY-only `tick_end` packets from being sent and disables physics processing that would otherwise continue under the wrong protocol state.

When the connection returns to `PLAY`, normal processing is restored.

The project also uses a Mineflayer build containing support for modern:

```text
CLIENT_TICK_END
```

packet handling required by newer Minecraft Java protocol versions.

Without this handling, some newer servers can disconnect automated clients during normal gameplay or server transitions.

Minecraft ALT Manager was tested with Minecraft Java Edition:

```text
1.21.11
```

including:

```text
Velocity proxy transition
→ target server connection
→ workflow continuation
→ AFK state
→ reconnect handling
```

The compatibility layer is intentionally kept separate from the configurable workflow system, so server-specific automation can be changed without modifying the underlying protocol handling.

---

## Java Edition Release Optimization

Minecraft ALT Manager targets Minecraft **Java Edition**, so the Windows release package is optimized around Java / PC protocol data.

During release generation:

- all required Java / PC Minecraft protocol data is retained;
- large Bedrock Edition version-data sets are removed;
- small Bedrock common metadata required by the upstream loader is retained;
- unnecessary development and cache files are removed from packaged dependencies.

This reduced the development package from approximately:

```text
536.8 MB
```

to approximately:

```text
195.4 MB
```

before ZIP compression.

The final v3.2.0 Windows x64 distributable ZIP is approximately:

```text
44.4 MB
```

The optimization process is designed to reduce release size without removing Java Edition compatibility data.

---

## Clean-PC Self Test

The Windows release includes:

```text
SELF-TEST.cmd
```

This performs a local preflight test of the packaged application before normal use.

The self-test verifies, among other things:

- required release files are present;
- the bundled Node.js runtime can start;
- JavaScript source files pass syntax checks;
- required runtime dependencies can be loaded;
- Java Edition Minecraft data is available;
- locally stored passwords are not packaged;
- Microsoft authentication caches are not packaged;
- the Manager can start and stop in an isolated test environment.

The self-test does **not** connect to a real Minecraft server.

A successful self-test helps confirm that the release package is structurally complete before the ALT Manager is used on a live server.

---

## Building from Source

Minecraft ALT Manager can also be run directly from the source repository.

### Requirements

- Windows
- Node.js
- npm
- Internet access while installing dependencies

Clone or download the repository and open a terminal in the project directory.

Install the locked dependency set with:

```powershell
npm ci
```

Check the main application entry point for JavaScript syntax errors:

```powershell
npm run check
```

Start Minecraft ALT Manager from source:

```powershell
npm start
```

This runs:

```text
node manager.js
```

The local management interface can then be accessed at:

```text
http://127.0.0.1:3077
```

### Mineflayer dependency

Minecraft ALT Manager currently uses a Mineflayer build containing the `CLIENT_TICK_END` compatibility work required by the application:

```text
https://github.com/iiroak/mineflayer
branch: fix/client-tick-end
```

This dependency is defined in `package.json` and installed automatically by npm.

### Building the Windows release

To generate the packaged Windows release, run:

```text
BUILD-USB.cmd
```

The command launches:

```text
BUILD-USB.ps1
```

which performs the release packaging and verification process.

Generated release files are written under:

```text
PORTABLE-BUILD/
```

This directory is intentionally excluded from Git because compiled/generated release packages are distributed through GitHub Releases instead of being committed to the source repository.

---

## Repository Structure

```text
minecraft-alt-manager/
├── core/                 Application core and workflow logic
├── dev-tools/            Development and diagnostic helpers
├── docs/                 User and release documentation
├── examples/             Sanitized example profiles
├── usb-tools/            Portable, installer and release helpers
├── web/                  Local web management interface
│
├── manager.js            Main application entry point
├── package.json          Project metadata and dependencies
├── package-lock.json     Locked npm dependency information
│
├── BUILD-USB.cmd         Windows release builder launcher
├── BUILD-USB.ps1         Release packaging and verification
├── SET-VERSION.cmd       Version management helper
│
├── README.md             Project documentation
├── CHANGELOG.md          Version history
├── SECURITY.md           Security policy
├── LICENSE               GNU GPL v3 license
└── .gitignore            Local/generated file exclusions
```

Runtime credentials, authentication caches, local profiles and generated release packages are intentionally not part of the public source repository.

---

## Important Notes

Minecraft ALT Manager is intended for use on Minecraft servers where ALT accounts, automated clients and AFK accounts are permitted.

Server rules differ.

**Always follow the rules of the server you connect to.**

Some servers may use:

- CAPTCHA or anti-bot systems;
- custom authentication plugins;
- unusual proxy configurations;
- custom server-switching commands;
- additional verification steps;
- plugins that are not compatible with Mineflayer-based clients.

A workflow that works on one server may therefore require changes before it works on another.

The included KNT configuration is an example of one tested server workflow, not a guarantee of compatibility with every Minecraft server.

---

## Documentation

The packaged Windows release includes bilingual documentation:

```text
README-FIRST.txt
LIETOSANAS-PAMACIBA-LV.txt
USER-GUIDE-EN.txt
CHANGELOG.txt
```

Minecraft ALT Manager also includes an integrated guide inside the local management interface.

For security-related information, see:

[SECURITY.md](SECURITY.md)

For version history, see:

[CHANGELOG.md](CHANGELOG.md)

---

## License

Minecraft ALT Manager is released under the **GNU General Public License v3.0 only**.

You are free to use, study, modify and redistribute the software under the terms of the GPL-3.0 license.

See the complete license text:

[LICENSE](LICENSE)

---

## Project

**Minecraft ALT Manager**

Created by **QvarcY**<br>
**IT solutions by QvarcY**

https://kas.id.lv

---

## Disclaimer

Minecraft ALT Manager is an independent community project.

Minecraft is a trademark of Microsoft Corporation and Mojang Studios.

This project is **not affiliated with, endorsed by, sponsored by or officially supported by Microsoft or Mojang Studios**.

References to third-party Minecraft servers are provided only to document tested configurations and real-world usage examples.