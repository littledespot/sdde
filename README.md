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
