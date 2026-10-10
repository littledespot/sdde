For each comparisons[].members collection, does it preserve
fixed_finding.missing_obligation? This supplied source obligation is the single
comparison target. Each comparison is a complete upstream claims collection.
supporting_evidence provides diagnostic detail, final-field purpose and producer
context; do not infer a different obligation from them or assess them as another
collection. Its deficient_subject has already been judged deficient. Upstream
claims need not be written as the final field or describe its defect.

Return one assessment per comparison: preserved when its complete collection
expresses the supplied obligation; lost when that obligation is absent
or weakened; uncertain when the evidence cannot establish either. Judge expressed
meaning, allowing equivalent wording and joint support, regardless of how it is
divided or categorized: a value already expressed in a requirement needs no
separate member. A value alone does not express its required
behavior. Preserve conditions, negation and obligation strength. Cite source
spans and assessed members, and briefly explain the result. For lost, identify the
part of the supplied obligation missing from the complete assigned collection.
Empty collections have no members to cite and cannot be preserved. Do not select
a culprit or repair operation.

comparison_id selects comparisons[].id; members selects IDs only from that
comparison's members. Source spans select sources[].chunk_id and inclusive
first/last IDs from its lines. Supporting evidence supplies no selectable IDs.
