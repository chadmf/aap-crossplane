# Architecture Decision Records (ADRs)

This directory contains Architecture Decision Records for the AAP Crossplane Provider.

## What is an ADR?

An ADR captures an important architectural decision made along with its context and consequences. It helps teams understand:
- **What** decision was made
- **Why** it was made (context and forces)
- **What** becomes easier or harder (consequences)
- **When** it should be reviewed

## ADR Index

| ID | Status | Decision | Date |
|----|--------|----------|------|
| [ADR-001](ADR-001-upjet-vs-native.md) | Accepted | Use Upjet (Terraform wrapper) over native Go provider | 2026-03-31 |
| [ADR-002](ADR-002-job-crd-semantics.md) | Accepted | Job CRD as action trigger with Orphan deletion policy | 2026-03-31 |

## ADR Lifecycle

- **Proposed**: Under discussion, not yet implemented
- **Accepted**: Implemented and in use
- **Deprecated**: No longer recommended, but not yet replaced
- **Superseded**: Replaced by a newer ADR

## Creating a New ADR

Use this template:

```markdown
# ADR-XXX: [Decision Title]

## Status
Proposed | Accepted | Deprecated | Superseded by ADR-YYY

## Context
What is the issue that we're seeing that is motivating this decision?

## Decision
What is the change that we're proposing and/or doing?

## Consequences
What becomes easier or harder because of this change?

## Trade-offs
| Approach | Gained | Given Up |
|----------|--------|----------|
| ...      | ...    | ...      |

## Review Criteria
When should this decision be revisited?
```

## Review Schedule

- **ADR-001**: Review 2026-09-30 (or when upstream Terraform provider stalls)
- **ADR-002**: Review 2026-09-30 (or when job_template resource becomes available)
