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
  - `model-request-debug/v9`, which becomes `v10`.

  The overall design remains **Proposed design**.
- **Amended by:** [ADR 0030](0030-engine-owned-model-request.md) (23 October 2026;
  implemented 24 October 2026). A Bedrock `config` also requires a positive
  `requestTimeoutMs`, so it accepts four fields, not three, and `model-request-debug`
  advanced to v11, whose provider configuration records the deadline. Deadlines are per
  catalogue entry, which settles "Per-family request deadlines". Provider token counting
  is removed, so "A family that registers CountTokens" would first need counting itself
  to return by its own decision.
- **Amended by:** [ADR 0039](0039-configured-temperatures-and-runaway-resend.md) (26
  October 2026): the `gpt-oss` family sends the configuration's `temperature`, and
  `temperatureRunawayRetry` on a runaway re-send, instead of `0.1`. The other families
  still omit temperature on every attempt.
- **Clarified (24 October 2026, user decision):** the E2E catalogue and the live-test
  allowlist keep the AU cross-Region inference profile `au.anthropic.claude-haiku-5-5`,
  called from `ap-southeast-2`. Bedrock routes each request to `ap-southeast-2` or
  `ap-southeast-4`. The user accepts both, superseding the same day's Sydney-only
  requirement ("it must be on ap-southeast-2"), because the current
  [Claude Haiku 5.5 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-haiku-5-5.html)
  (checked 2026-10-24) lists no in-Region inference in `ap-southeast-2`, only the AU geo
  and global profiles. A pin to the in-Region ID `anthropic.claude-haiku-5-5`, made for
  that requirement, is reverted. Its Bedrock 403 ("not available for this account")
  later came through the AU profile too, so it reflects the account's access to the
  model, not the Region.
- **Amended (24 October 2026, user decision: "switch to openai.gpt-oss-20b"):** the
  shipped E2E slots select GPT-OSS-20B again, with low effort for `spec_generation` and
  `repair`, as before 23 October. This supersedes "for the e2e tests make use of haiku 5.5
  on bedrock with low reasoning effort" for the slots only: Claude Haiku 5.5 stays in the
  E2E catalogue and the live-test allowlist for generation. All eleven Haiku attempts
  ended `authorization_denied` because the account lacks access to the model.

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
one. No family registers CountTokens.

A Bedrock catalogue entry names its model, Region, family and documented maximum
output:

```json
{
  "model": "au.anthropic.claude-haiku-5-5",
  "json": true,
  "config": { "region": "ap-southeast-2", "family": "claude", "maxOutputTokens": 128000 }
}
```

- **Model:** any Bedrock model or inference-profile ID. The engine never interprets
  it: no prefix or substring selects a family, a capability or an encoding.
- **Region:** a closed, compiled list of the Bedrock runtime source Regions that AWS
  documented on 22 October 2026. The endpoint host is still built only from a
  compiled Region name.
- **Family:** one compiled family. The catalogue selects it; it never supplies an
  encoding.
- **Exactly these three `config` fields** are accepted.

The registry joins a Bedrock entry to its family's compiled contract. Anthropic
Messages API contracts still join by exact model ([ADR 0028](0028-anthropic-messages-provider.md)).

A wrong model, Region or family is the project's explicit choice. Bedrock rejects the
request and the engine reports a typed provider failure. It never retries with
another family or model.

### Retired registration

The Claude 3.5 Haiku registration in `us-west-2` was the only Bedrock model with
CountTokens and fixed temperature. It is removed. Its model can still be configured
as a `converse` entry, without token counting or temperature. No shipped workflow
counts tokens. A counting-capable family needs its own decision.

### Captures and harness

- `model-request-debug/v10` adds the family to the Bedrock provider configuration,
  so replay re-encodes with the captured family. A `v9` description is rejected.
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

Rubric judging stays on GPT-OSS-20B ([acceptance.md](../harness/acceptance.md)). The
shipped E2E cases select GPT-OSS-20B again (amended 24 October 2026), with the frozen
calibration protocol's slot controls, so the provider-compatibility probe, which is
bound to that protocol, accepts them. From 23 to 24 October they selected Claude Haiku
5.5 with low effort in every slot, which the probe rejects.

### Tests

Tests iterate the compiled families, the compiled Regions and the permitted cost
tuples. They take expected models and controls from the configured binding, not from
named models.

## Not decided here

- A family that registers CountTokens.
- Per-family request deadlines.
- Bedrock's Messages API endpoint, streaming, and application inference profile ARNs
  as a tested configuration.

## Consequences

- Adding a Bedrock model, or using it in another Region, is a catalogue change.
- A new request shape is a new family, which is a code change.
- Retained `v9` captures can no longer be replayed.
