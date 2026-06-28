# Security Policy

## Supported versions

This image is rolling: only the latest published tags receive fixes. There is one
tag per supported .NET version (`dotnet7`, `dotnet8`, `dotnet10` / `latest`). Older
digests are not patched — pull the current tag to get fixes.

## Reporting a vulnerability

Please report security issues privately, not in public issues.

Use GitHub's **"Report a vulnerability"** button under the repository's **Security**
tab (Security advisories). This opens a private channel with the maintainer.

When reporting, please include:

- the affected image tag and, if possible, the digest;
- a description of the issue and its impact;
- steps to reproduce or a proof of concept.

This is a small, best-effort project, so please allow some time for a response
before any public disclosure.

## Scope

In scope:

- the image build (`Dockerfile`) and the startup scripts in `scripts/`;
- the GitHub Actions workflows in this repository.

Out of scope:

- **Vintage Story itself** — report game issues to
  [Anego Studios](https://www.vintagestory.at/).
- **Third-party mods** downloaded at runtime — report those to their authors.
- Vulnerabilities only exploitable through a misconfigured deployment (e.g. exposing
  the server without a password on an untrusted network).
