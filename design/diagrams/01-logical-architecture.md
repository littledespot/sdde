```mermaid
flowchart TB
    ENTRY[CLI / API adapter] --> RUNNER[PipelineRunner<br/>sole node invocation, contract checks,<br/>child binding and immutable delta application]
    RUNNER --> ENGINE[WorkflowEngineOrchestrator<br/>coordinate exact selection and registered invocation parsing;<br/>follow compiled transitions only]

    COMMON[Common PipelineNode interface<br/>contract + execute envelope/runtime to Outcome]
    COMMON --> ACTION[Action<br/>one responsibility, no children]
    COMMON --> ORCH[Orchestrator<br/>coordination only, no operation ports]
    COMMON --> ENGINE

    ORCH --> BIND[Runner-owned ChildNodeBinding]
    ENGINE --> BIND
    BIND --> RUNNER
    RUNNER --> ACTION
    RUNNER --> ORCH

    subgraph STAGES[Initial SDD workflow graphs; each selected independently]
        SO[SpecifyOrchestrator<br/>no SDD predecessor]
        PO[PlanOrchestrator<br/>requires current specified authority]
        TO[TasksOrchestrator<br/>requires approved current plan authority]
        IO[ImplementOrchestrator<br/>requires approved current task authority]
        VG[ValidatedGenerationOrchestrator]
        AC[AuthorityReconciliationOrchestrator]
        CL[ClarificationLifecycleOrchestrator]
        AR[AtomicRepairOrchestrator]
        TE[ImplementTaskOrchestrator]
    end

    CROOT[Composition root<br/>adapters, registered node bindings,<br/>fixed nonselectable startup graph] --> BO
    CROOT --> BIND
    RUNNER -. first bound child .-> BO[EngineStartupGraph / BootstrapOrchestrator<br/>not present in project workflow registry]
    BO -. runner-bound workflow authority actions .-> WLOAD[Workflow loader<br/>inventory/path accounting and definition schema contracts;<br/>capture, parse and schema validation]
    WLOAD --> WCOMP[Workflow compiler<br/>compiler contracts and compiled graph types;<br/>registered nodes, typed transitions, gates and capability ceiling]
    WCOMP --> WREG[Workflow registry<br/>global validation, immutable ownership and exact lookup only;<br/>arbitrary bounded definitions with unique WorkflowId and shortcode]
    WREG --> WSELECT[Parse selector, validate WorkflowId,<br/>then exact registry resolution<br/>through separate runner-bound actions]
    WSELECT -. immutable selected graph .-> ENGINE
    RUNNER -. selected registered invocation-contract node binding .-> INVOKE[Typed run context<br/>before graph entry]
    INVOKE -. typed context; runner invokes selected entry .-> SO
    INVOKE -. typed context; runner invokes selected entry .-> PO
    INVOKE -. typed context; runner invokes selected entry .-> TO
    INVOKE -. typed context; runner invokes selected entry .-> IO
    SO -. nested orchestrator binding .-> VG
    PO -. nested orchestrator binding .-> VG
    TO -. nested orchestrator binding .-> VG
    VG -. nested orchestrator binding .-> CL
    VG -. nested orchestrator binding .-> AR
    SO -. pre-generation and pre-commit binding .-> AC
    PO -. pre-generation and pre-commit binding .-> AC
    TO -. pre-generation and pre-commit binding .-> AC
    IO -. gate and pre-commit binding .-> AC
    AC -. same-stage gap binding .-> CL
    IO -. nested orchestrator binding .-> TE
    TE -. nested orchestrator binding .-> AR

    ACTION --> PORTS[Typed capability ports]
    PORTS --> FS[Contained filesystem and WAL adapter]
    PORTS --> MODEL[Versioned model-route adapter]
    PORTS --> PARSER[Markdown, data, AST and source-map parsers]
    PORTS --> COMMAND[Restricted command / implementation-overlay adapter]
    PORTS --> AUTHN[Authentication and trusted-clock adapters]

    subgraph AUTHORITIES[Separate validated authorities]
        WDEFS[WorkflowDefinitionRegistry<br/>any bounded number from paths.workflows;<br/>compiled registered-node graphs only]
        REF[Reference registry<br/>feature and business authority]
        PRINCIPLES[PrincipleRegistryState<br/>free-text Markdown from paths.principles;<br/>exact toolchain.yaml is excluded]
        PRESETS[ToolchainPresetRegistryState<br/>sole runtime root paths.toolchainPreset<br/>paths, file kinds, commands and tools]
        TLAYER[ProjectToolchainLayer<br/>exact paths.principles/toolchain.yaml;<br/>closed typed data inheriting from presets]
        STATE[Canonical workflow, actor, review, control-event,<br/>clarification and execution state]
        APOLICY[Compiler-locked requiredness, ownership<br/>and reconciliation-policy registries]
    end

    PORTS --> WDEFS
    PORTS --> REF
    PORTS --> PRINCIPLES
    PORTS --> PRESETS
    PORTS --> TLAYER
    PORTS --> STATE
    WDEFS -. exact selected graph .-> WSELECT
    REF -. typed authority and evidence .-> AC
    PRINCIPLES -. plan tasks implement authority only; never specification input .-> AC
    PRESETS -. typed authority and evidence .-> AC
    PRESETS -. validated inheritance base .-> TLAYER
    TLAYER -. typed project policy and evidence .-> AC
    STATE -. current authority and approvals .-> AC
    APOLICY -. exhaustive required slots and earliest owners .-> AC
    PRINCIPLES --> SELECT[SelectApplicablePrinciplesAction]
    SELECT --> PGUIDE[Complete bounded raw-span guidance in PipelineEnvelope]
    PGUIDE -. consumed by stage actions through typed data keys .-> PO
    PGUIDE -. consumed by stage actions through typed data keys .-> TO
    PGUIDE -. consumed by stage actions through typed data keys .-> IO

    TEMPLATES[paths.templates/*.template.md<br/>inert throughout v1] -. reserved future copy contract .-> FUTUREINIT[Future sdd init template-to-principles boundary<br/>not a current v1 action or transaction; no model authority]
    FUTUREINIT -. future materialized Markdown only .-> PRINCIPLES

    COMMON --> VALIDATE[Deterministic validation actions<br/>specialized action instances]
    RUNNER --> VALIDATE
    VALIDATE --> RUNNER

    RUNNER --> OBS[PipelineTelemetryObserver<br/>trusted lifecycle and applied facts only]
    OBS --> LOGROOT[Runner-owned instrumentation root binding]
    LOGROOT --> LOG[FeatureLoggingOrchestrator]
    LOG --> LOGBIND[Runner-owned logging ChildNodeBinding]
    LOGBIND --> RUNNER
    RUNNER --> LOGA[Logging actions using the same PipelineNode interface]
    LOGA --> LOGPORT[FeatureLogPort]
    LOGA -. instrumentation IDs excluded from self-observation .-> OBS
```
