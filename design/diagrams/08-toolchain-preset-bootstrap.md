Generic startup and YAML-declared target preparation. Startup is fixed engine
machinery; workflow behavior remains in the selected compiled YAML.

```mermaid
flowchart TD
    CLI[Invocation working directory] --> CONFIG[Read exact .sddtoolkit.json<br/>validate closed config and configured roots]
    CONFIG --> INVENTORY[Discover workflow definitions and explicitly declared resources]
    INVENTORY --> COMPILE[Validate and compile through one immutable generic operation registry]
    COMPILE --> SELECT[Resolve exact selected workflow]
    SELECT --> REQUIRE{Selected graph needs model binding or provider calls}
    REQUIRE -- No --> START[New atomic workflow execution at compiled start]
    REQUIRE -- Yes --> PROVIDERS[Capture configured .sddproviders.json once<br/>validate catalogue repository allowlist and immutable bindings]
    PROVIDERS -- Ready --> START
    PROVIDERS -- Failure or cancellation --> STOP[Return exact failure or cancellation; execute no workflow node]
    START --> INVOKE[Run YAML-named invocation contract]
    INVOKE --> SETUP[Run only YAML-declared preparation operations]
    SETUP --> CONTEXT[Resolve any selected feature directory relative to configured paths.specs;<br/>validate target preset and project toolchain;<br/>capture relevant principles and repository facts]
    CONTEXT --> RUN[Follow compiled YAML transitions through runner-owned bindings]
    RUN --> END{Terminal outcome}
    END -- Success --> OUTPUT[Publish complete validated workflow output]
    END -- Non-success --> ABANDON[Abandon candidate; preserve clarifications]
```

For SDD feature selection, `.sddtoolkit.json`'s `paths.specs` supplies the root;
`--feature` supplies only its relative directory, with no ownership registry.
Provider calls do not require a feature-owned journal. No project/feature
transaction recovery, ledger scan or checkpoint precedes execution. Templates
remain inert; no source-tree fallback or hidden model route is introduced.
[ADR 0009](../decisions/0009-atomic-workflow-execution.md) governs fresh reruns.
