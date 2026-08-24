# ADR 0002: SonarQube quality automation

**Status:** Accepted for the bootstrap by the explicit user request to add SonarQube and a pre-commit hook. This decision does not accept or amend `design/design.md`, which remains proposed.

## Decision

The repository uses TypeScript 6.0.3, `@sonar/scan` 5.0.0, c8 12.0.0, and Husky 9.1.7 as pinned development tools. SonarQube analyzes the TypeScript sources and build scripts through `sonar-project.properties`; its project key is derived from the package name rather than a server-specific value committed to the repository.

`docker-compose.sonarqube.yml` defines one local SonarQube Community Build 26.8 container using its embedded H2 database. Its health check succeeds only when the server reports `UP`. SonarQube binds only to `127.0.0.1:9000`; its named volumes preserve local state across normal stops. Embedded H2 is appropriate for this local development bootstrap, not a production server. The analysis token is neither committed nor logged.

`sonar-project.properties` defaults the scanner to the local endpoint. `npm run sonar` is the single validation command. It loads an optional ignored `.env` file, validates that `SONAR_TOKEN` is nonempty, regenerates source-mapped LCOV evidence at `coverage/lcov.info`, starts the local container if necessary, waits up to five minutes for it to become healthy, runs the scanner, and waits up to five minutes for the quality gate. `SONAR_HOST_URL` may explicitly override the local endpoint for a separately configured server.

The configured SonarQube platform must be Community Build 26.7 or newer, or SonarQube Server 2026.4 or newer, because those analyzer generations support TypeScript 6. The pre-commit hook deliberately runs only `npm run verify:changed`, the deterministic local build and SEA test gate. It never starts a networked SonarQube scan or requires a token.

The local `sdde` project uses the server-side `sdde TypeScript` profile, which inherits Sonar way. It activates `typescript:S104` with `maximum=399`; the parameter is inclusive, so this enforces fewer than 400 lines per TypeScript file. The active quality gate fails on any new violation, so a new oversized-file issue fails `npm run sonar`.

## Consequences

- Developers install the hook through npm's `prepare` lifecycle and can invoke its underlying check with `npm run precommit`.
- A developer performs the initial local sign-in, password change, and analysis-token creation; `npm run sonar` then uses that token from the environment. A failing quality gate fails the command.
- This bootstrap does not configure CI or choose server-side quality-profile thresholds. Running `npm run sonar` explicitly starts the local stack and sends the repository analysis to it.
- Moving from the former PostgreSQL-backed local instance to embedded H2 resets SonarQube account, token, and analysis metadata. The detached PostgreSQL Docker volume remains untouched for recovery and is not referenced by this configuration.
