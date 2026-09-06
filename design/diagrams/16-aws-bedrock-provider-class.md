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

Each call is bound to its exact request, model, input and deadline. Request
identity and resources remain associated with the originating workflow step.
The provider reports actual token usage and preserves failure or cancellation;
workflow policy controls further calls and retries.
