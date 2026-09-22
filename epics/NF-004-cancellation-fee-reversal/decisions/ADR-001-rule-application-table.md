# ADR-001 — Record which rules produced each charge

**Epic:** NF-004 — cancellation fee/commission reversal · **Status:** proposed, 2026-09-22

When an agency books a ticket we charge a service fee and pay a commission, both
worked out by business rules, and when that ticket is later cancelled those
amounts have to be reversed — but not simply given back in full, because a
partly-flown journey only reverses its unflown portion, which means re-running
the rules that applied at the time of sale rather than whatever the rules say
today. We don't reliably record which rule versions those were, and the two
obvious ways to recover it both fail: the price-adjustment records that reference
the rule evaluation get rewritten whenever anything about the order changes
(including automatically on the first retrieval after ticketing), they don't
cover commission at all, and one ticket maps to several of them so there is no
single record to read; while the rules service's own audit log sits in a separate
service with its own clean-up policy, which an operational step running months
later should not depend on. Rather than keep reconstructing something we already
knew at the time, we propose writing it down when it happens — one small new
table holding a row per fee or discount type per charge, recording the rule
version used, the amount it produced and an audit pointer, written once and never
updated, with the sale and the cancellation each getting their own set of rows so
that each explains itself. We chose a table over adding columns to the existing
ticket/seller record because what needs storing per fee type is about six pieces
of information rather than one, which across the six fee and discount types would
mean roughly forty new fields on a record that already has forty and would grow
again with every new fee type; a table also answers "which charges used this rule
version?" in a single query, which is exactly the question asked when a rule turns
out to have been published with a mistake. Real data backs the shape — every
ticket we examined used a separate rule per fee and discount type rather than one
shared rule, with one document carrying eighteen across three levels of the agency
chain — and the cost is one table and one migration, written at the moment we
already snapshot other charge details. Before building, though, we need one check
against production: in the local development database this reversal appears never
to have run, because the configuration that enables it has no rows at all, so the
code exits immediately every time, there are no fee or commission ledger entries
anywhere, and no automated test covers it — so if production looks the same we
should say plainly that this is not a working feature being migrated, and if it
doesn't, we can capture real behaviour from production to test against.

## Table detail

*To be added.*
