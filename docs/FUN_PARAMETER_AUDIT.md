# FUN parameter audit — two inherited N-cost defects (2026-09)

Read-only audit of ELM-FUN as used for the BNFMIP delivery. Verified on CADES against the
compiled SourceMods, the three paramfiles, and the delivered output. **Both defects are
nitrogen-only; the phosphorus pathway is correctly oriented.**

## Defect A — kc_nonmyc/kn_nonmyc transposed (the CLM5 #2120 swap) — CONFIRMED, N-only
- Paramfiles (all 3, BNF_tom/clm_params_fun3_sfix01*.nc): kc_nonmyc max 7.2 (root-C, gC/m3),
  kn_nonmyc max 0.12 (soil-N, gC/m2) — element-identical to the documented CLM5 SWAPPED arrays.
- The compiled code ALSO hardcodes the swap: CNFUNMod.F90 overwrites kc_nonmyc(ivt)/kn_nonmyc(ivt)
  at runtime; else-tier (PFTs 4/7/2) = kc=0.72, kn=0.012 (L1980-81). Fixing the paramfile alone
  would NOT fix it — the code re-swaps.
- Cost fn (L3320): fun_cost_nonmyc = kn_nonmyc/sminn + kc_nonmyc/rootc. Swapped => soil-N term
  coefficient is 0.012 not 0.72 (~60x too small) => non-mycorrhizal uptake stays cheap under N
  limitation. Live at all 3 sites.

## Defect B — ivt(p).eq.7 should be .eq.17 — CONFIRMED, N-only, universal
- AM N-cost high tier, L1452: `else if(ivt(p).eq.14 .or. ivt(p).eq.7 .or. ivt(p).eq.18)` <- typo.
- EcM N-cost (L1410), funp EcM (L1430), funp AM (L1472), nonmyc (L1966) all correctly use .eq.17.
- Active-cost paramfile reads are commented out (L1400/1443) => hardcoded block is LIVE.
- Present in all 38 CNFUNMod.F90 (every delivered case + all 6 repo source_mods variants), byte-identical.
- PFT indexing verified: 7 = broadleaf_deciduous_temperate_tree, 17 = corn, 14 = c4_grass, 18 = irr_corn.
  => PFT 7 gets AM cost akc=0.6/akn=1.2 instead of 0.06/0.12 (10x too high); corn (17) gets it 10x too low.

## Phosphorus — CLEAN (checked because runs use FUN-P)
- Defect B: all P branches use .eq.17 (N vs P AM branches disagree by exactly this char -> proves N typo).
- Defect A: P non-myc soil-P constant (kp=0.08 code / 0.8 paramfile) > root-C constant (kcp=0.03 / 0.3)
  = correct orientation, opposite to N. P active follows intended root>soil. scalex=100 scales P costs (tuning).

## Materiality (site PFTs: Manaus=4 100%AM, Harvard=7 50%AM/50%EcM, Bonanza=2 100%EcM)
- Defect A affects Manaus & Harvard (AM fraction>0). Bonanza insulated (100% EcM -> nonmyc structurally off).
- Defect B additionally hits Harvard (PFT 7): its AM N-cost is 10x too high. Manaus/Bonanza not hit.
- NoFUN runs: FUN cost code inactive -> unaffected.

## Output signature (present-day N-uptake partitioning; verified NACTIVE=NAM+NECM, excludes NNONMYC;
## exact closure NUPTAKE = NACTIVE + NNONMYC + NFIX_TO_SMINN + NRETRANS)
| site    | mycorrhizal | non-myc | fixation | retrans |
|---------|------------:|--------:|---------:|--------:|
| Manaus  | 3.5%        | 68.4%   | 11.7%    | 16.4%   |
| Harvard | 3.2%        | 65.5%   | 17.0%    | 14.2%   |
| Bonanza | 87.2%       | 0.3%    | 0.0%     | 12.5%   |
Manaus & Harvard show the ecologically-backwards ~3% mycorrhizal / ~66-68% non-myc signature
(worse than the known-buggy CLM5 9%/78%). Bonanza is insulated.

## Consequence for the delivered runs (data_csv_corrected/ on GitHub, used by Tom)
- N-side pathway partitioning is materially wrong at Manaus & Harvard.
- P cost params are clean, but FUN allocates one shared C budget, so P uptake, the N-vs-P limitation
  balance, and the fixation share (BNFMIP headline) are indirectly distorted. The "more P- than
  N-limited" and low-N-cost findings are partly artifacts of Defect A making N cheap.
- Fix = 2 changes in CNFUNMod.F90: (1) L1452 .eq.7 -> .eq.17; (2) exchange the hardcoded nonmyc
  kc/kn tiers (and the paramfile arrays) to the corrected orientation. Then rebuild + re-run all
  FUN/noACC/ACC configs at Manaus & Harvard (Bonanza/NoFUN for uniformity), re-package, re-deliver.
