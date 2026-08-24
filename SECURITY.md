# Security Policy

## Supported Versions

Minecraft ALT Manager currently receives security fixes for the latest stable release.

| Version | Supported |
| ------- | --------- |
| 3.2.x   | Yes       |
| < 3.2   | No        |

## Reporting a Security Vulnerability

Please do not publicly disclose security vulnerabilities before they have been reviewed.

If GitHub Private Vulnerability Reporting is enabled for this repository, please use it for security-sensitive reports.

Otherwise, contact the project author through:

https://kas.id.lv

Please include:

- the affected Minecraft ALT Manager version;
- a clear description of the issue;
- steps required to reproduce it;
- the potential security impact;
- relevant logs or screenshots, with passwords, tokens and other credentials removed.

## Sensitive Information

Never include any of the following in a public issue, discussion, log or screenshot:

- Minecraft account passwords;
- Microsoft authentication data;
- DPAPI secret files;
- access tokens;
- API keys;
- `manager.token`;
- files from `data/secrets/`;
- files from `data/microsoft-auth/`;
- files from `PortableData/`.

Minecraft ALT Manager is designed so that packaged releases do not include locally stored DPAPI secrets or Microsoft authentication caches.

## Scope

Security reports related to the Minecraft ALT Manager application, installer, portable mode, local web interface, credential handling and release tooling are welcome.

Issues originating solely from third-party Minecraft servers, server plugins, proxies, Minecraft itself, Node.js or upstream dependencies should normally be reported to the relevant upstream project unless Minecraft ALT Manager introduces or exposes the vulnerability.

## Responsible Disclosure

Please allow reasonable time for investigation and remediation before publishing details of a vulnerability.

---

Minecraft ALT Manager

Created by QvarcY<br>
IT solutions by QvarcY<br>
https://kas.id.lv
