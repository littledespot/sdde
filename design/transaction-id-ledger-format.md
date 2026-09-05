# Transaction-ID ledger stored format

This closes the byte representation used by Design Section 25.1. Workflow
definitions remain YAML; this engine-state document is UTF-8 JSON without BOM.

```json
{"schema":"transaction-id-ledger/v1","storageOwner":{"project":{"bootstrapRootContractVersion":"bootstrap-roots/v2"}},"revision":1,"nextTransactionOrdinal":2,"reservations":[{"transactionOrdinal":1,"transactionKind":"feature_activation","status":"reserved"}],"retiredTransactionOrdinals":[]}
```

The root contains exactly the six fields shown. Every field is required.
`storageOwner` contains exactly one of:

- `project`: exactly `bootstrapRootContractVersion`, equal to the current
  bootstrap-root identity's contract version.
- `feature`: exactly `featureId` and `workflowArtifactRegistryStateOrdinal`.
  The ordinal identifies the workflow-artifact-registry state for that feature;
  the namespace is fixed by this field, not supplied by the document.

Owner references are collection-relative. The codec requires the expected typed
storage owner from its caller; a project reference resolves only to that
context's bootstrap-root identity. Feature fields must match that context's
feature and artifact-registry state. The document cannot choose a project root,
collection, filename, or write target. Absolute paths and fingerprints are not
stored. These bytes alone do not authenticate their originating project: a
future reader must obtain them through the matching validated collection and
held lock. This codec creates no read, lock, or durability evidence.

Each reservation contains exactly `transactionOrdinal`, `transactionKind`, and
`status`. Kind names are the existing closed `DurableTransactionKind` names;
status is `reserved`, `committed`, or `retired`. All record and retirement
ordinals inherit the single document owner. `retiredTransactionOrdinals` is the
exact ordered projection of retired records, never independent status authority.

All numbers are unsigned base-10 integer JSON tokens within `u64`; quoted,
negative, fractional, or exponent forms are rejected. The shared ledger
validator owns positive ordinals, ordered complete history, revisions,
owner/kind restrictions, retirement equality, and optional prior-ledger
transition checks. The codec does not repeat those rules.

Parsing rejects missing, unknown, duplicate (including escaped-equivalent), or
wrong-type fields, unsupported schema versions, malformed UTF-8/JSON, and
trailing non-whitespace data. The closed nonrecursive shape bounds nesting.
The caller supplies a positive byte ceiling and the existing ledger limits;
oversized input is rejected before parsing and record limits before conversion.

Serialization accepts only a validated ledger and its matching expected owner.
It emits fields in the order shown, compact JSON, canonical enum strings and
integer tokens, and one final LF. Arrays preserve validated ordinal order. It
counts the rendered bytes before allocating the output buffer and enforces the
same caller-supplied byte ceiling, including the LF. Parse/render round trips
preserve the complete ledger in the same owner context.

The codec performs no filesystem access, ID allocation, recovery, or commit.
Registered persistence operations and their capability bindings remain separate
work. Rerun output replacement and protection of user-closed clarification files
remain governed by Design Section 23.2.
