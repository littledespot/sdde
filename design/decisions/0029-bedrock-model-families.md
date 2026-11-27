# ADR 0029: Bedrock model families

- **Status:** Accepted
- **Date:** 2026-10-22
- **Decision authority:** User decisions, 22 and 24 October 2026 and 9, 17 and 25
  November 2026
- **Amends:** [F0006](../features/F0006-LLMProviderInterface.md),
  [F0007](../features/F0007-AWSBedrockProvider.md),
  [ADR 0028](0028-anthropic-messages-provider.md) "Not decided here" and the request
  description (`model-request-debug`). The overall design remains **Proposed design**.
- **Amended by:** [ADR 0030](0030-engine-owned-model-request.md),
  [ADR 0039](0039-configured-temperatures-and-runaway-resend.md)

## Context

Bedrock offers many models through one Converse API. They differ in only a few request
facts, and the engine owns each of those. A Bedrock catalogue entry may name any model;
its capabilities come from the compiled contract of the family it names, not from a
compiled contract for that exact model.

## Decision

### Compiled families, configured models

The engine compiles a closed set of Bedrock **families**. A family fixes everything
the engine sends beyond common Converse input:

| Family | Effort | Temperature | Request fields |
| --- | --- | --- | --- |
| `converse` | None | Omitted (provider default) | None |
| `gpt-oss` | `low`, `medium`, `high` | Configured (ADR 0039) | `additionalModelRequestFields.reasoning_effort` |
| `luna` | None | Omitted | `additionalModelRequestFields.text.format.strict` |
| `claude` | `low` to `max` | Omitted | `additionalModelRequestFields.output_config.effort`; no `thinking` field |

Every family sends native JSON-schema output, the only response mode. The catalogue has
no `json` member. The `gpt-oss` family sends the configuration's `temperature`, and
`temperatureRunawayRetry` on a runaway re-send; the other families omit temperature on
every attempt.

A Bedrock catalogue entry names its model, Region, family, documented maximum output
and deadline:

```json
{
  "model": "au.anthropic.claude-haiku-5-5",
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

No Bedrock model has a compiled per-model registration, a fixed temperature or a
token-counting path.

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
| `anthropic` / `claude-haiku-5-5` | Generation only |

`test/harness/model_cost_policy.zig` holds the list. `au.anthropic.claude-haiku-5-5` is
the AU cross-Region inference profile, called from `ap-southeast-2`; Bedrock routes each
request to `ap-southeast-2` or `ap-southeast-4`, and the user accepts both.

Rubric judging stays on GPT-OSS-20B ([acceptance.md](../harness/acceptance.md)). The
shipped E2E cases select `anthropic` / `claude-haiku-5-5` in every slot. The
provider-compatibility probe stays bound to the frozen calibration protocol's GPT-OSS
slot controls, so it does not accept the shipped cases and checks only its own fixtures.

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
