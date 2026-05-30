# Item 4: N Uptake Analysis — Why Is NUPTAKE So High?

## Observed Values (noacc_transient, ~2010 mean, scale=1e3 gN m⁻² yr⁻¹)
| Site           | NUPTAKE model | Literature range |
|----------------|---------------|------------------|
| Manaus         | TBD           | 3.0–8.0          |
| Harvard Forest | ~5.1          | 2.0–5.0 (Aber+93)|
| Bonanza Creek  | ~4.7          | 0.5–2.0 (Chapin+95) |

## Key Findings
1. **NUPTAKE at Bonanza is 2–9× above literature**: The value of ~4.7 gN m⁻² yr⁻¹
   vs. expected 0.5–2.0 gN m⁻² yr⁻¹ is anomalously high.

2. **SNFIX and FFIX are tiny**: SNFIX ≈ 0.007–0.009, FFIX ≈ 0.027 gN m⁻² yr⁻¹.
   So NUPTAKE is dominated by mineral N uptake from soil (~4.67 gN m⁻² yr⁻¹).

3. **NPP_NACTIVE, NPP_NFIX are also tiny** (order 0.001–0.016 gC m⁻² yr⁻¹ after ×1e3).
   These are C allocated TO the pathway — they do NOT represent gN acquired.

4. **COST_NFIX, COST_NACTIVE are DIMENSIONLESS** (gC gN⁻¹ ratios).
   Do NOT multiply by 86400×365 — they are NOT per-area fluxes.

## Hypotheses for High NUPTAKE
A. **NUPTAKE includes N retranslocation**: In ELM, NUPTAKE may account for BOTH
   new N from soil (sminn_to_plant) AND internally recycled N (retransn_to_npool).
   If retranslocation provides ~3–4 gN m⁻² yr⁻¹, that would inflate NUPTAKE
   while the actual new mineral N uptake from soil remains realistic.

B. **N cycle overcycling**: SOM decomposition in ELM may be too fast at Bonanza,
   generating more N mineralization than observed → SMINN_TO_PLANT too high.
   This is a known issue in CLM/ELM in cold biomes.

C. **Double P-limitation effect on N cycle**: With P artificially suppressed (fpg_p bug),
   C/N allocation is imbalanced → demand-driven N cycle is inflated.
   Fixing fpg_p should partially correct this.

## Recommended Next Steps
1. Check if `SMINN_TO_PLANT` is available in h0 output — compare to NUPTAKE
   to determine if retranslocation is included in NUPTAKE
2. Run with the fpg_p fix and compare NUPTAKE before/after
3. Look at `RETRANSN_TO_NPOOL` or similar diagnostic if available
4. Consider checking `NET_NMIN` — if this is also high at Bonanza, the N cycle
   is genuinely overcycling (hypothesis B)

## Notebook Addition
Added N uptake pathway breakdown cell after the N-fluxes cell:
- NPP_NACTIVE, NPP_NFIX, NPP_NRETRANS, NPP_NNONMYC (gC m⁻² yr⁻¹ each)
- COST_NFIX, COST_NACTIVE (dimensionless gC/gN — plotted with flux=False)
- Approximate gN per pathway derived as NPP_N* / COST_* (where > 0)
