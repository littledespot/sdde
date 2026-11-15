# F0008 — LLMProviderConfigService

**Status:** Accepted feature design

**Decision authority:** Explicit user direction on 2026-09-02

**Implementation:** Complete. F0006's conditional provider-bootstrap routine, invoked after
exact workflow selection, runs this feature's locate and read steps exactly once when required
and decodes the untrusted bytes. The earlier `LLMProviderConfigService` type was removed when the
sequence became that routine (ADR 0032); the file keeps its name for the links that cite it.

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
LLMProviderInterface](F0006-LLMProviderInterface.md); and the [configuration
paths](../contracts/09-configuration.md#91-required-configuration-shape).

---

## 1. Responsibility

The provider-bootstrap routine's locate and read steps own one complete bounded byte capture of the
configured `.sddproviders.json` catalogue document and hand those bytes, still untrusted,
to the decode step; no service type holds them. Catalogue membership describes an available configured model
instance; it does not add that model to the repository's allowed
`.sddtoolkit.json` `models.slots` set.

The capture does not decode JSON, validate provider definitions, construct a
provider registry, validate the slot-to-catalogue subset relationship, select a
workflow operation or model slot, obtain credentials, or invoke a provider. Those remain
responsibilities of F0006 and each peer provider's adapter, such as F0007 for Bedrock
([ADR 0028](../decisions/0028-anthropic-messages-provider.md)).

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

- The value must be a normalized portable project-relative file path whose basename is
  exactly `.sddproviders.json`.
- F0004 validates and reserves it as a distinct engine-read-only file role.
- It must not equal or nest within a configured directory root, collide with
  `.sddtoolkit.json`, or escape the project root.
- F0008 rejects linked components and physical identity aliasing when the file is
  opened.

F0008 consumes only F0004's opaque provider-document capability. It never
reads `config.paths.providers` directly and never resolves the path again.

## 3. Minimal design

| Owner | Sole responsibility |
| --- | --- |
| `locate_config` step | Ask the narrow source port to open the one F0004-authorized no-follow regular file and return an exact open-file capability. |
| `read_config` step | Capture that already opened file completely under the fixed byte limit and return owned untrusted bytes. |
| Filesystem adapter | Consume the opaque F0004 capability, walk beneath the bound project root without following links, open read-only, and verify file identity/type/size before and after capture. |
| Provider-bootstrap routine | Under ADR 0032, run the locate and read steps as part of the provider-bootstrap engine routine, preserve failed/cancelled outcomes, own intermediates, and keep the capture only after a successful complete read. Locate and read stay separate typed steps (AC 4), with fake-port tests. |
| Composition root | Construct the filesystem adapter and the routine's port without invoking the routine during ordinary bootstrap. |

No step invokes another step. The capture has no reload or mutation method: the routine holds the
bytes in the read step's return value, decodes them once and releases them when the routine ends.

## 4. Read and ownership contract

The compiler-owned limit is 1,048,576 bytes (`llm_provider_config.max_bytes`).

The adapter rejects a missing file, wrong kind, linked component, linked leaf,
project-root escape, identity replacement, short read, growth, shrink, or byte
limit violation. It reads no parent, sibling, repository example, packaged
asset, environment-selected path, or default location.

The read step returns the owned raw bytes (`llm_provider_config.Raw`), and the routine releases
them exactly once on every path, after the decode step has copied what it needs.

The bytes remain untrusted. Only F0006's decoder may interpret them.

## 5. Failure and orchestration boundary

The routine returns the closed outcomes `ready`, `failed`, or `cancelled`. Every
locate or capture rejection returns `failed`; F0006's conditional
provider-bootstrap routine maps it to the already accepted
`LLM_PROVIDER_CONFIG_READ_ERROR`. No partial service is published.

- F0008 does not decide whether a selected workflow needs model binding or provider
  calls.
- F0006's accepted model-provider bootstrap routine owns that
  branch.
- A workflow whose derived requirement is `not_required` must not probe or read the
  provider document merely because `paths.providers` is reserved during root validation.

## 6. Acceptance criteria

1. `paths.providers` is required by the closed `.sddtoolkit.json` contract.
2. F0004 validates and reserves its exact project-relative
   `.sddproviders.json` path without reading the file; F0008 performs its
   no-follow physical checks when the file is requested.
3. F0008 consumes only the opaque F0004 capability; raw config path strings do
   not cross into the reader.
4. Locate and read are separate single-responsibility steps.
5. The adapter opens read-only beneath the project root without following
   links and verifies a stable regular-file identity and length.
6. Exactly 1,048,576 bytes are accepted; one byte more is rejected.
7. The locate and read steps return untrusted bytes only and perform no parsing, registry work,
   or provider work; no service type holds the capture.
8. Missing, malformed, or unsafe provider content is never replaced by a
   source example, packaged asset, fixed root filename, or cached value.
9. All handles and owned bytes are released once on every terminal branch.
10. Provider-document loading remains unreachable for a selected compiled
    workflow without model-binding requirements or provider-call capability;
    ordinary bootstrap only reserves the path and never invokes the F0008 entry point. A required
    provider-bootstrap branch invokes it once and never refreshes that capture.

## 7. Verification

Tests cover:

- configured-path normalization and exact basename
- collision with the engine config and every configured root
- nested configured locations
- missing, wrong-kind, symlinked, replaced, short, growing, shrinking, exact-size, and
  over-size files
- routine step order and terminal propagation
- cleanup on every path
- absence of parsing in the locate and read steps
- conditional single capture (zero port calls on `not_required`)
- ordinary-bootstrap non-probing
- no fixed-location or source-example fallback.
