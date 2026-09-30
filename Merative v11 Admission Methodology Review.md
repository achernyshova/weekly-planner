# Merative v11 Admission Methodology Review

## Admission ID and calculation differences from Advantage Suite v5.4

**New / target:** Merative v11 — *Truven Flexible Analytics Inpatient Admission Grouper Methodology Guide v11.2.0*  
**Legacy / baseline:** Merative Advantage Suite v5.4 — *Data Manager’s Guide*, Chapter 9  
**Prepared:** September 29, 2026

## Purpose and summary

This document summarizes the main differences and similarities between the legacy Merative Advantage Suite v5.4 admission methodology and the new Merative v11 methodology.

The two versions follow the same general purpose—grouping related claims into inpatient admissions—but they are **not expected to produce exactly the same results**. Important rules changed around Admission IDs, claim eligibility, admission windows, LOS, clinical calculations, and admission removal. Because of these differences, some claims may move between admissions, admissions may split or merge, and calculated values may change.

`NEW` below means the v11 45-page document. `LEGACY` means the Advantage Suite v5.4 document, printed pages 9-1 through 9-23.

## Admission ID

Merative changed the Admission ID methodology and introduced letters into the new ID format. Therefore, a legacy Admission ID should not be expected to match a v11 Admission ID one-to-one.

| Legacy v5.4 | New v11 | Meaning for comparison | References |
|---|---|---|---|
| Admission ID is described as Patient Key + Admit Start Period Key + a two-digit sequence | The v11 guide includes a different construction description, and the 9/10 discussion confirms that production IDs now contain letters | Admission IDs should be treated as different identifiers. A mismatch by itself does not mean that the underlying admission changed. | LEGACY 9-9; NEW 36; 9/10 discussion |

To determine whether the same admission exists in both versions, compare:

- the patient;
- the source claims assigned to the admission;
- admission and discharge dates; and
- whether one admission was split into several admissions or several admissions were merged.

The new v11 Admission ID should be stored as a string so that letters, leading zeros, and the complete value are preserved. The exact v11 ID length, allowed characters, uniqueness, and rerun behavior should be confirmed with Merative.

## What changed

| Area | Legacy v5.4 | New v11 | Possible result | References |
|---|---|---|---|---|
| **Claims considered for grouping** | Requires a valid first-service date and medical coverage; uses place and ER/Observation criteria; can use `inpt_ind` | Uses medical facility/professional claims with `claim_type_cd=1`; explicitly addresses telehealth and optional LTC exclusion | Different claims may enter the admission-building process | LEGACY 9-1–9-4; NEW 32–34 |
| **Room-and-board identification** | Uses a Room and Board Flag Code whose derivation is not provided in the chapter | Derives an `rb_indicator` from revenue-code groups and a value matrix | Different claims may become the anchors for an admission | LEGACY 9-5–9-6, 9-17; NEW 27–28 |
| **Begin Date** | Uses the later of Date of First Service and claim-level Admission Date Original | Uses the claim begin/date of first service for window construction | A v11 admission may begin earlier | LEGACY 9-5–9-6; NEW 28–29 |
| **Window boundary** | A record fits when last service is before discharge; equality goes to the extension branch | A record fits when the end date is on or before discharge; extension requires an end date after discharge | A claim ending exactly on discharge may follow a different branch | LEGACY 9-6–9-8; NEW 29–30 |
| **Earlier or late-arriving claims** | Documents left extension and reconstruction of affected admissions | No equivalent separate left-extension/reconstruction process is documented | Updated admissions and identifiers may behave differently | LEGACY 9-6, 9-8; NEW 28–34 |
| **Multiple possible admissions** | Uses a hold array, provider hierarchy, place group, shorter admission, and first-admission tie-break | Uses facility/provider matching, place group/earliest logic, and shortest duration | A claim eligible for two admissions may be assigned differently | LEGACY 9-13–9-14; NEW 32–33 |
| **Length of stay** | Uses claim Days with overlap adjustments and a final calendar-day cap | Uses discharge date minus admission date; same-day LOS is set to 1 | LOS and every metric that depends on LOS may change | LEGACY 9-9–9-12; NEW 40 |
| **Admit source and admit type** | Uses the first room-and-board record that formed the window | Uses the latest nonmissing inpatient room-and-board record | The same claim group can receive different admit-source or admit-type values | LEGACY 9-20; NEW 36 |
| **Age and sex selection** | Uses ranked person/demographic records and includes mother/baby precedence | Uses the latest nonmissing inpatient room-and-board record | Clinical grouping inputs may differ | LEGACY 9-6, 9-15, 9-17; NEW 36, 40 |
| **Clinical population** | DRG, MDC, and Disease Staging are documented for acute admissions only | No equivalent acute-only restriction is stated in the reviewed v11 pages | v11 may assign clinical results to a broader population | LEGACY 9-18, 9-21; NEW 17, 34–42 |
| **Diagnosis and POA processing** | Uses a matrix, can rotate an invalid principal diagnosis, and includes special overrides; missing-POA default is not shown | Uses explicit record ordering; missing POA defaults to `W` | Diagnosis order, principal diagnosis, DRG, and staging results may differ | LEGACY 9-3, 9-18–9-20; NEW 41–42 |
| **ICD and DRG selection** | ICD selector is based on diagnosis-matrix composition | Coding system is taken from the earliest room-and-board record, with explicit DRG version/date rules | A different grouper path or DRG version may be selected | LEGACY 9-18–9-20; NEW 31, 34, 37–39 |
| **Missing discharge status** | Defaults missing status to home/alive (`1`) for grouping | Uses the latest nonmissing room-and-board status; the same default is not documented | DRG or staging may change when status is missing | LEGACY 9-19; NEW 39 |
| **Removing admissions** | By default, can remove admissions with total allowed amount at or below zero, with configurable protections | Capitation can prevent removal, but the same default zero-dollar threshold is not documented | Some admissions may exist in v11 but not legacy | LEGACY 9-17–9-18; NEW 38 |
| **Previous/next admission gaps** | Uses zero at the edges and when the gap is over 365 days; transfer pairs are excluded | Uses blank at the edges; no equivalent 365-day limit is stated; LTC/non-acute admissions are excluded | Readmission-gap values and null/zero handling may differ | LEGACY 9-21–9-22; NEW 38–39 |
| **Newborn days** | Copies legacy LOS when Newborn Days Indicator is `Y` | Uses room-and-board indicator combinations to identify newborn stays | The newborn population and calculated days may differ | LEGACY 9-22; NEW 41 |
| **LOS trim** | Uses legacy LOS and applies to acute admissions | Uses v11 LOS and MarketScan DRG thresholds | The trim value must be recalculated and may change | LEGACY 9-23; NEW 40 |
| **Per-diem trim** | Includes a per-diem trim based on Allowed Amount Total divided by LOS | No corresponding metric is documented | The legacy metric may be retired or supplied elsewhere | LEGACY 9-23; NEW — |
| **Output structure** | Describes fact, dimension, and associative tables | Describes admission, admission-medical link, ungrouped, episode-link, and optional statistics outputs | Output mapping and downstream links may need to change | LEGACY 9-3–9-4, 9-15–9-17; NEW 44–45 |

## What remains the same or generally aligned

The following areas are either documented the same way or retain the same basic intent. “Generally aligned” means the overall rule is similar even if the supporting fields or implementation details are not identical.

| Area | Alignment | What remains aligned | References |
|---|---|---|---|
| **Overall purpose** | Generally aligned | Both methodologies group related facility and professional claims into inpatient admissions built around inpatient/room-and-board activity | LEGACY 9-1–9-14; NEW 24–34 |
| **One-day adjacency** | Aligned | Both evaluate records that begin one day after the current discharge as possible transfer/continuation cases | LEGACY 9-7; NEW 30 |
| **ER/Observation timing** | Aligned | Both allow qualifying ER/Observation activity during the admission window or exactly one day before admission | LEGACY 9-12–9-13; NEW 33 |
| **Rehabilitation transfer test** | Aligned | Both identify a transfer when the adjacent admission is rehabilitation and the current admission is not | LEGACY 9-7; NEW 31 |
| **Different facility IDs** | Aligned at rule level | Both identify a transfer when valid/nonmissing facility IDs are unequal | LEGACY 9-8; NEW 31 |
| **Place-group fallback** | Aligned | Both use different nonmissing place groups as a fallback transfer indicator | LEGACY 9-8; NEW 31 |
| **Other claims associated by admission dates** | Generally aligned | Both assign eligible facility/professional claims when service dates fall within an admission window | LEGACY 9-12–9-13; NEW 32 |
| **Initial versus final DRG indicator** | Aligned | Both indicate whether the final DRG differs from the initially calculated DRG | LEGACY 9-20; NEW 39 |
| **Total net payment** | Aligned | Both define total admission net payment as facility plus professional net payment | LEGACY 9-16; NEW 42 |
| **Cost-trim numeric bands** | Aligned | Both use the same seven ranges: below `1/15`, `1/15–<1/10`, `1/10–<1/5`, `1/5–5`, `>5–10`, `>10–15`, and `>15` times the benchmark | LEGACY 9-22; NEW 43–44 |
| **Core DRG concept** | Generally aligned | Both calculate an initial DRG, may produce a final DRG, assign MDC, and track whether the DRG changed | LEGACY 9-18–9-21; NEW 34–39 |
| **Provider attribution** | Generally aligned | Both assign admission-level facility and physician/provider information, although selection order and exact fields can differ | LEGACY 9-16–9-17; NEW 24–25, 41 |

## Bottom line

The two Merative methodologies are built for the same general purpose and share several transfer, payment, DRG, and trim concepts. However, the changed Admission ID format and the differences in eligibility, admission windows, LOS, clinical processing, and admission removal mean the outputs should not be expected to match exactly.

The most reliable comparison is to match admissions using the underlying patient and source claims, then review any differences in admission dates and calculated metrics using the page-referenced rules above.
