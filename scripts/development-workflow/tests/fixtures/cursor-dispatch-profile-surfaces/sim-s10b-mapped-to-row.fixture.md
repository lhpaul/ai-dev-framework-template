## Decision gate

| Row | Stop |
| --- | --- |
| R1 | PROCEED |
| R2 | PROCEED |
| R3 | PROCEED |
| R4 | PROCEED |
| R5 | PROCEED |
| R6 | PROCEED |
| R7 | PROCEED |
| R8 | PROCEED |
| R9 | PROCEED |
| R10 | missing_required_secret_or_permission |
| R11 | PROCEED |
| R12 | dispatch_handoff_unavailable |
| R13 | dispatch_profile_declaration_missing |
| R14 | dispatch_profile_declaration_missing |
| R15 | dispatch_profile_declaration_missing |
| R16 | dispatch_profile_declaration_missing |
| R17 | dispatch_profile_declaration_missing |
| R18 | dispatch_profile_declaration_missing |

- S1 -> R1
- S2 -> R2
- S3 -> R3
- S4 -> R4
- S5 -> R5
- S6 -> R6
- S7 -> R7
- S8 -> R8
- S9 -> R9
- S10 -> R10
- S10b -> R10
- S11 -> R11
- S12 -> R12
- S13 -> R13
- S14 -> R14
- S15 -> R15
- S16 -> R16
- S17a -> R17
- S17b -> R17
- S18 -> R18
- S19 -> R18

S7 is a recovery scenario (mid-run native to parent orchestrated); its re-declaration is validated against its own action-specific fact and is not treated as a coarse-fact mismatch (E4c exemption).
