# F0008 — LLMProviderConfigService

**Status:** Accepted feature design

**Decision authority:** Explicit user direction on 2026-09-02

**Implementation:** Complete for the bounded read-only file-service increment.
F0006 remains responsible for conditionally invoking this component and
decoding its untrusted bytes.

**Compatibility:** None. `paths.providers` is required in the single current
configuration contract. There is no legacy fixed-location reader, alias,
default, search, cache, or fallback.

**Classification:** Core, read-only LLM-provider document source

**Scope:** SDDE engine development. This feature authorizes no provider
request, credential access, provider-registry construction, or target-project
mutation.

**Governing authority:** [Engine design](../design.md), especially Sections 3,
5-6, 9, 13.1, 15, and 25-31; [F0001 —
SDDToolKitConfigService](F0001-SDDToolKitConfigService.md); [F0004 —
BootstrapRootRegistryService](F0004-BootstrapRootRegistryService.md); [F0006 —
LLMProviderInterface](F0006-LLMProviderInterface.md); and the [path
contract](../paths.md).

---

## 1. Responsibility

`LLMProviderConfigService` owns one complete bounded byte capture of the
configured `.sddproviders.json` catalogue document and exposes those bytes
immutably. Catalogue membership describes an available configured model
instance; it does not add that model to the repository's allowed
`.sddtoolkit.json` `models.slots` set.

The service does not decode JSON, validate provider definitions, construct a
provider registry, validate the slot-to-catalogue subset relationship, select a
route, obtain credentials, or invoke a provider. Those remain F0006/F0007
responsibilities.

## 2. Path authority

The sole path authority is the required `paths.providers` member of the exact
project-root `.sddtoolkit.json`:

```json
{
  "paths": {
    "providers": ".sddproviders.json"
  }
}
```

The value must be a normalized portable project-relative file path whose
basename is exactly `.sddproviders.json`. F0004 validates and reserves it as a
distinct engine-read-only file role. It must not equal or nest within a
configured directory root, collide with `.sddtoolkit.json`, or escape the
project root. F0008 rejects linked components and physical identity aliasing
when the file is opened.

F0008 consumes only F0004's opaque provider-document capability. It never
reads `config.paths.providers` directly and never resolves the path again.

## 3. Minimal design

| Owner | Sole responsibility |
| --- | --- |
| `LocateLLMProviderConfigAction` | Ask the narrow source port to open the one F0004-authorized no-follow regular file and return an exact open-file capability. |
| `ReadLLMProviderConfigAction` | Capture that already opened file completely under the fixed byte limit and return owned untrusted bytes. |
| Filesystem adapter | Consume the opaque F0004 capability, walk beneath the bound project root without following links, open read-only, and verify file identity/type/size before and after capture. |
| `LLMProviderConfigOrchestrator` | Coordinate only the runner-owned locate and read child bindings and preserve failed/cancelled outcomes. |
| Pipeline runner | Invoke the two actions, validate/apply their declared deltas, own intermediates, and construct the service only after a successful complete read. |
| `LLMProviderConfigService` | Own the captured bytes and expose one borrowed immutable `bytes()` view. |
| Composition root | Construct the filesystem adapter, actions, runner, and orchestrator entry point without invoking it during ordinary bootstrap. |

No action invokes another action. The orchestrator receives only child
bindings. The service performs no I/O and has no reload or mutation method.

## 4. Read and ownership contract

The compiler-owned limit is:

```text
maxLLMProviderConfigBytes = 1,048,576
```

The adapter rejects a missing file, wrong kind, linked component, linked leaf,
project-root escape, identity replacement, short read, growth, shrink, or byte
limit violation. It reads no parent, sibling, repository example, packaged
asset, environment-selected path, or default location.

The service API is:

```zig
pub fn bytes(self: *const LLMProviderConfigService) []const u8
pub fn deinit(self: *LLMProviderConfigService) void
```

Repeated `bytes()` calls return the same borrowed slice without allocation,
I/O, parsing, or mutation. The service owns and releases the capture exactly
once.

The bytes remain untrusted. Only F0006's decoder may interpret them.

## 5. Failure and orchestration boundary

F0008 returns the closed outcomes `ready`, `failed`, or `cancelled`. Every
locate or capture rejection returns `failed`; the future F0006 model-provider
bootstrap boundary maps it to `LLM_PROVIDER_CONFIG_READ_ERROR`. No partial
service is published.

F0008 does not decide whether a selected workflow needs model capability.
F0006's capability-free model-provider bootstrap orchestrator remains the
owner of that branch. A capability-free workflow must not probe or read the
provider document merely because `paths.providers` is reserved during root
validation.

## 6. Acceptance criteria

1. `paths.providers` is required by the closed `.sddtoolkit.json` contract.
2. F0004 validates and reserves its exact project-relative
`.sddproviders.json` path without reading the file; F0008 performs its
no-follow physical checks when the file is requested.
3. F0008 consumes only the opaque F0004 capability; raw config path strings do
   not cross into the reader.
4. Locate and read are separate single-responsibility actions.
5. The adapter opens read-only beneath the project root without following
   links and verifies a stable regular-file identity and length.
6. Exactly 1,048,576 bytes are accepted; one byte more is rejected.
7. `LLMProviderConfigService` exposes immutable bytes only and performs no I/O,
   parsing, registry work, or provider work.
8. Missing, malformed, or unsafe provider content is never replaced by a
   source example, packaged asset, fixed root filename, or cached value.
9. All handles and owned bytes are released once on every terminal branch.
10. Provider-document loading remains unreachable for a selected compiled
    workflow without model-provider capability; ordinary bootstrap only
    reserves the path and never invokes the F0008 entry point.

## 7. Verification

Tests cover configured-path normalization and exact basename; collision with
the engine config and every configured root; nested configured locations;
missing, wrong-kind, symlinked, replaced, short, growing, shrinking, exact-size,
and over-size files; orchestrator order and terminal propagation; runner delta
application and cleanup; immutable repeated queries; absence of parsing in the
service; ordinary-bootstrap non-probing; and no fixed-location or
source-example fallback.

## 8. Traceability

| Concern | Authority |
| --- | --- |
| Closed configuration field | F0001 and `sddtoolkit-config.schema.json` |
| Path validation and opaque capability | F0004 and `design/paths.md` |
| Provider-document decoding and registry | F0006 Sections 3-5 |
| Filesystem and secret safety | Design Sections 25-26 |
| Testing and packaging | Design Sections 28, 30-31 |
