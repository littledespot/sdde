# ADR 0029: Bedrock model families

- **Status:** Accepted amendment
- **Date:** 2026-10-22
- **Decision authority:** The user's instructions on 22 October 2026:
  - "for the e2e tests make use of haiku 5.5 on bedrock with low reasoning effort";
  - "the bedrock connector should allow for all model avaiable on bedrock to be used";
  - "Yes, name a family": each `.sddproviders.json` Bedrock model names a compiled
    family, so the engine knows how to send effort and temperature;
  - "Keep explicit list": billed live tests stay limited to named models;
  - "test must be generic in nature and not hardcoded".
- **Amends:**
  - [F0006](../features/F0006-LLMProviderInterface.md): a Bedrock catalogue entry may
    name any model, and its capabilities come from the compiled contract of the family
    it names, not from a compiled contract for that exact model;
  - [F0007](../features/F0007-AWSBedrockProvider.md): the registered model table, the
    two-Region set and the request-profile bullet;
  - [ADR 0028](0028-anthropic-messages-provider.md) "Not decided here", for Claude
    through Bedrock and live use of Claude Haiku 5.5 through Bedrock;
  - the request description (`model-request-debug`), whose Bedrock provider
    configuration gains the family.

  The overall design remains **Proposed design**.
- **Amended by:** [ADR 0030](0030-engine-owned-model-request.md) (23 October 2026;
  implemented 24 October 2026): a Bedrock `config` also requires a positive
  `requestTimeoutMs`, deadlines are per catalogue entry, and provider token counting is
  removed. The text below includes these.
- **Amended by:** [ADR 0039](0039-configured-temperatures-and-runaway-resend.md) (26
  October 2026): the `gpt-oss` family sends the configuration's `temperature`, and
  `temperatureRunawayRetry` on a runaway re-send, instead of `0.1`. The other families
  still omit temperature on every attempt.
- **Clarified (24 October 2026, user decision):** the E2E catalogue and the live-test
  allowlist keep the AU cross-Region inference profile `au.anthropic.claude-haiku-5-5`,
  called from `ap-southeast-2`. Bedrock routes each request to `ap-southeast-2` or
  `ap-southeast-4`. The user accepts both, superseding the same day's Sydney-only
  requirement ("it must be on ap-southeast-2"), because the
  [Claude Haiku 5.5 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-haiku-5-5.html)
  (checked 2026-10-24) lists no in-Region inference in `ap-southeast-2`, only the AU geo
  and global profiles.
- **Amended (24 October 2026, user decision: "switch to openai.gpt-oss-20b"):** the
  shipped E2E slots select GPT-OSS-20B, with low effort for `spec_generation` and
  `repair`. This supersedes "for the e2e tests make use of haiku 5.5 on bedrock with low
  reasoning effort" for the slots only: Claude Haiku 5.5 stays in the E2E catalogue and
  the live-test allowlist for generation.
- **Amended (9 November 2026, user decision):** the live-test cost policy also names
  `anthropic` / `claude-haiku-5-5` for generation only, recording the 22 October 2026
  direction ("update the providers to connect to claude") that
  `test/harness/model_cost_policy.zig` already implements. This amends ADR 0028 "Not
  decided here".

## Context

Each Bedrock model had to be compiled into the engine before a project could select
it. The catalogue could only pick from that list, and a test rejected any catalogue
attempt to choose a request encoding. Bedrock offers many models through one Converse
API. They differ in only a few request facts, and the engine owns each of those.

## Decision

### Compiled families, configured models

The engine compiles a closed set of Bedrock **families**. A family fixes everything
the engine sends beyond common Converse input:

| Family | Effort | Temperature | Request fields |
| --- | --- | --- | --- |
| `converse` | None | Omitted (provider default) | None |
| `gpt-oss` | `low`, `medium`, `high` | Configured (ADR 0039) | `additionalModelRequestFields.reasoning_effort` |
| `luna` | None | Omitted | `additionalModelRequestFields.text.format.strict` in native mode |
| `claude` | `low` to `max` | Omitted | `additionalModelRequestFields.output_config.effort`; no `thinking` field |

Every family supports both response modes, and the catalogue's `json` flag selects
one.

A Bedrock catalogue entry names its model, Region, family, documented maximum output
and deadline:

```json
{
  "model": "au.anthropic.claude-haiku-5-5",
  "json": true,
  "config": {
    "region": "ap-southeast-2",
    "family": "claude",
    "maxOutputTokens": 128000,
    "requestTimeoutMs": 180000
  }
}
```

- **Model:** any Bedrock model or inference-profile ID. The engine never interprets
  it: no prefix or substring selects a family, a capability or an encoding.
- **Region:** a closed, compiled list of the Bedrock runtime source Regions that AWS
  documented on 22 October 2026. The endpoint host is still built only from a
  compiled Region name.
- **Family:** one compiled family. The catalogue selects it; it never supplies an
  encoding.
- **Exactly these four `config` fields** are accepted. `requestTimeoutMs` is the
  provider-operation deadline
  ([ADR 0030](0030-engine-owned-model-request.md#request-deadline)).

The registry joins a Bedrock entry to its family's compiled contract. Anthropic
Messages API contracts still join by exact model ([ADR 0028](0028-anthropic-messages-provider.md)).

A wrong model, Region or family is the project's explicit choice. Bedrock rejects the
request and the engine reports a typed provider failure. It never retries with
another family or model.

### Retired registration

The Claude 3.5 Haiku registration in `us-west-2`, the only Bedrock model with
CountTokens and fixed temperature, is removed. Its model can still be configured as a
`converse` entry, without temperature.

### Captures and harness

- The request description (`model-request-debug`) records the family in the Bedrock
  provider configuration, so replay re-encodes with the captured family.
- The frozen calibration protocol records the family it binds.
- The standalone evaluator selects its family explicitly with
  `TEST_EVALUATION_FAMILY`.

### Live-test cost policy

The engine accepts any configured Bedrock model. Billed live tests still allow only
named tuples, each for named uses:

| Provider / model | Uses |
| --- | --- |
| `aws-bedrock` / `openai.gpt-oss-20b-1:0` | Generation and rubric judging |
| `aws-bedrock` / `au.anthropic.claude-haiku-5-5` | Generation only |
| `anthropic` / `claude-haiku-5-5` | Generation only (amended 9 November 2026) |

Rubric judging stays on GPT-OSS-20B ([acceptance.md](../harness/acceptance.md)). The
shipped E2E cases select GPT-OSS-20B (amended 24 October 2026), with the frozen
calibration protocol's slot controls, so the provider-compatibility probe, which is
bound to that protocol, accepts them.

### Tests

Tests iterate the compiled families, the compiled Regions and the permitted cost
tuples. They take expected models and controls from the configured binding, not from
named models.

## Not decided here

- Bedrock's Messages API endpoint, streaming, and application inference profile ARNs
  as a tested configuration.

## Consequences

- Adding a Bedrock model, or using it in another Region, is a catalogue change.
- A new request shape is a new family, which is a code change.
