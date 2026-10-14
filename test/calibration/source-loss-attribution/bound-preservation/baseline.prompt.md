Locate the omission in fixed_review; do not reassess that finding. Compare the
missing meaning with loss_sources, producers[].output and the resolved subject.
Only a producer with a non-null location can be selected for upstream loss;
other producer outputs are supporting evidence only.
Return candidate when the evidence shows the meaning survived through the upstream
outputs and is missing only from the candidate. Return localized only for an
established upstream defect: copy that producer's location, cite its source lines,
and explain what its output lost in
comparison.producer_loss. A defect in the candidate is not evidence of loss at
an upstream producer. Eligible locations and matching IDs do not prove loss.
Return unlocalized when the supplied evidence cannot establish the owner.
