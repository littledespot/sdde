Main responsibilities and relationships at the AWS Bedrock provider boundary.

```mermaid
classDiagram
    direction LR
    class CompositionRoot
    class LLMProviderInterface
    class AWSBedrockProvider
    class IdentifiedProviderNeutralModelRequest
    class CompiledModelResultSchema
    class ValidatedProviderModelBinding
    class AWSBedrockModelContract
    class ProviderAuthorizationLeasePort
    class InvokedProviderOperation
    class TrustedEndpointResolver
    class AWSBedrockRuntimePort
    class ProviderInvocationObservation

    CompositionRoot ..> AWSBedrockProvider : binds concrete dependencies
    AWSBedrockProvider ..|> LLMProviderInterface : implements provider operations
    AWSBedrockProvider ..> IdentifiedProviderNeutralModelRequest : receives the retained workflow request
    IdentifiedProviderNeutralModelRequest --> CompiledModelResultSchema : retains the required response contract
    AWSBedrockProvider ..> ValidatedProviderModelBinding : receives the selected model binding
    ValidatedProviderModelBinding --> AWSBedrockModelContract : supplies registered model and routing policy
    AWSBedrockProvider --> ProviderAuthorizationLeasePort : consumes single-use authorization
    AWSBedrockProvider ..> InvokedProviderOperation : requires the authorized operation and deadline
    AWSBedrockProvider --> TrustedEndpointResolver : resolves an allowed endpoint
    AWSBedrockProvider --> AWSBedrockRuntimePort : performs one deadline-bound exchange
    AWSBedrockProvider ..> ProviderInvocationObservation : returns response and usage evidence

    note for LLMProviderInterface "Supports inference and explicitly requested input-token counting"
    note for AWSBedrockProvider "Credentials and transport capabilities stay inside authorized adapters"
    note for ProviderInvocationObservation "A provider response is candidate data; the engine owns validation and workflow outcomes"
```

[F0007](../features/F0007-AWSBedrockProvider.md) owns exact request/model/input/
deadline binding and actual token reporting. Originating-step identity and
resources follow [ADR 0012](../decisions/0012-workflow-owned-model-request.md);
workflow policy controls retries and preserves failure/cancellation.
