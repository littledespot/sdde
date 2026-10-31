Main responsibilities and relationships at the AWS Bedrock provider boundary. Bedrock is
one per-family projection of the shared provider-port implementation
([ADR 0028](../decisions/0028-anthropic-messages-provider.md)); its contract is the
compiled family the catalogue entry names
([ADR 0029](../decisions/0029-bedrock-model-families.md)).

```mermaid
classDiagram
    direction LR
    class CompositionRoot
    class LLMProviderInterface
    class ModelProvider
    class BedrockProjection
    class IdentifiedProviderNeutralModelRequest
    class CompiledModelResultSchema
    class ValidatedProviderModelBinding
    class BedrockFamilyContract
    class ProviderAuthorizationLeasePort
    class InvokedProviderOperation
    class ModelHttpExchange
    class ProviderInvocationObservation

    CompositionRoot ..> ModelProvider : binds concrete dependencies
    ModelProvider ..|> LLMProviderInterface : implements provider operations for every provider
    ModelProvider --> BedrockProjection : dispatches the Bedrock family target
    ModelProvider ..> IdentifiedProviderNeutralModelRequest : receives the retained workflow request
    IdentifiedProviderNeutralModelRequest --> CompiledModelResultSchema : retains the required response contract
    ModelProvider ..> ValidatedProviderModelBinding : receives the selected model binding
    ValidatedProviderModelBinding --> BedrockFamilyContract : supplies family request fields and Region policy
    ModelProvider --> ProviderAuthorizationLeasePort : consumes single-use authorization
    ModelProvider ..> InvokedProviderOperation : requires the authorized operation and deadline
    BedrockProjection ..> BedrockFamilyContract : builds the compiled-Region endpoint and family request fields
    ModelProvider --> ModelHttpExchange : performs one deadline-bound exchange
    ModelProvider ..> ProviderInvocationObservation : returns response and usage evidence

    note for LLMProviderInterface "Supports inference"
    note for ModelProvider "Credentials and transport capabilities stay inside authorized adapters"
    note for ProviderInvocationObservation "A provider response is candidate data; the engine owns validation and workflow outcomes"
```

[F0007](../features/F0007-AWSBedrockProvider.md) owns exact request/model/input/
deadline binding and actual token reporting. Originating-step identity and
resources follow [ADR 0012](../decisions/0012-workflow-owned-model-request.md);
workflow policy controls retries and preserves failure/cancellation.
