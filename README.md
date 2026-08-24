# sdde

Minimal TypeScript bootstrap for a host-platform Node single executable application (SEA).

Requirements: Node 24.x and npm (built and tested with Node 24.2.0).

```sh
npm install
npm run build:sea
./dist/sdde
npm test
```

On Windows, run `dist\\sdde.exe`. `npm test` rebuilds the executable and runs it
from an empty temporary directory.

The scoped technical decision is documented in
[ADR 0001](docs/adr/0001-typescript-node-sea-bootstrap.md).

## Code quality

Run the deterministic local quality gate with `npm run verify`. It is also run
by the Husky pre-commit hook after `npm install`.

Open <http://127.0.0.1:9000>, sign in with `admin` / `admin`, change the
administrator password, and create an analysis token. Store it in your shell,
then run the analysis:

Put the token in the repository-root `.env` file:

```dotenv
SONAR_TOKEN=replace-with-your-token
```

Then run:

```sh
npm run sonar
```

The command loads that ignored file; do not commit the token.

This single command runs coverage, starts the local server if needed, waits for
it to be healthy, submits the analysis, waits for the quality gate, and exits
nonzero on failure. The server remains running between validations. The scan
targets `http://127.0.0.1:9000` by default; set `SONAR_HOST_URL` only when
deliberately overriding that local endpoint.

The local server uses SonarQube Community Build 26.8 with its embedded H2
database; it is for local development only. See
[ADR 0002](docs/adr/0002-code-quality-automation.md) for the scoped policy.

The local `sdde TypeScript` quality profile inherits Sonar way and requires
every TypeScript file to remain below 400 lines.
