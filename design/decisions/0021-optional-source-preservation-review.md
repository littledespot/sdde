# ADR 0021: Optional source-preservation review and shared repair model slot

Status: Accepted by the user's configuration and repair-slot request, 3 October 2026.

Amends the draft-first sequencing in [§17.3](../contracts/17-specify.md) and the
closed configuration contract in [§9](../contracts/09-configuration.md).

The optional `.sddtoolkit.json` setting
`validation.sourcePreservationCheck` is a boolean, disabled when omitted.
When enabled, complete, generation-ready references undergo a focused semantic
review before specification generation. When disabled, the extra review and its
repairs are skipped. Mandatory review of blocked references and of the generated
specification remains unchanged; this setting cannot relax publication authority.

The original captured corpus supplies one preservation obligation per source,
including sources with no extracted claims. Review compares original meaning
with extraction and reconciliation. It does not assess specification fields that
do not yet exist or resolve uncertainty already present in the source. Its closed
findings are `supported`, `candidate_omission` and `inconclusive`; model-assisted
review remains candidate evidence, not deterministic proof.

The immutable configuration service remains the only configuration authority.
A narrow action returns the configured branch outcome; YAML owns sequencing.
Source obligations join the existing required-authority ledger, evidence
admission and gate. Identified loss uses the existing producer localization,
revision-bound repair authorization, merging, dependent rebuilding and bounded
retry path. Source identities survive rebuilding and establish whether the
repaired obligation was re-reviewed. Inconclusive or unlocalized findings cannot
invent user decisions, bypass failure or authorize an unbounded repair.

All authorized candidate repairs in the supplied Spec definition use the distinct
`models.slots.repair` entry through the existing model-request subgraph.
Generation, review and loss localization use `spec_generation`. Protocol retries
retain their original request/model binding under ADR 0019. Both slots may select
the same provider/model or different registered models; each selection must join
the captured provider catalogue. There is no fallback between slots. Whole-graph
binding requires both referenced slots even when the optional check is disabled.

The setting and model-slot name are workflow-neutral. Any validated workflow can
select the registered policy action and the repair slot in its definition. Each
workflow supplies its own typed review subjects and repair validators; the engine
does not infer applicability or provide a default repair path. The supplied Spec
definition is the initial consumer.

Unit tests cover config decoding, preservation scope and evidence admission.
Offline workflow tests cover enable/disable branching, repair routing and
revalidation. Live quality assessment remains separately approved E2E work.
