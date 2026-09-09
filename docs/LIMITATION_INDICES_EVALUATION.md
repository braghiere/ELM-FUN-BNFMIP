# N/P limitation indices in ELM-FUN — calculation & evaluation

Tom's ask: separate N/P limitation proxies from FUN C-costs, plus comparison to leaf N:P /
C:N and other indices, to understand how warming affects N fixation across models. Computed
from CORRECTED runs (3 sites x 3 FUN schemes, annual 1850-2100). Benchmarks: Braghiere 2022
(JAMES), Menge 2026 (GBC).

Figures: notebooks/figs/limitation_indices_A.png (indices), _B.png (leaf stoich vs retrans),
bnf_benchmark_C.png (BNF C-investment vs literature). Scripts in /home/braghiere/BNF_tom/.

## FUN variable meanings (verified CNFUNMod.F90:2315-2364)
- NPP_NUPTAKE = C cost of N acquisition = active(myc AM/ECM+nonmyc)+SYMBIOTIC FIXATION+retrans+burn.
- NPP_PUPTAKE = C cost of P acquisition (no fixation).
- NPP_NACTIVE = mycorrhizal-only N cost (fixation-free). NPP_NFIX = symbiotic fixation C cost only.
- Free-living fixation (FFIX_TO_SMINN): input to soil mineral N, NO plant C cost (not in NPP_NUPTAKE).
- Model NUPTAKE_NPP_FRACTION = npp_Nuptake/availc  (NOT /(NPP+costs)) => not identical to Tom's proxy.

## Present-day (2005-2014) indices, FUN(Houlton)
site     Nlim    Plim   Cuse%  N:Pcost  C/N   C/P   fix%Nupt  NFIXcostShare
Manaus   0.0048  0.0280  3.28   0.172   0.19  17.6   15.0%      7.5%
Harvard  0.0054  0.0490  5.44   0.111   0.27  41.6   20.8%      8.4%
Bonanza  0.0001  0.0134  1.35   0.006   0.00   9.0    4.6%      3.7%

## BNF C-investment benchmark, FUN(Houlton)
site     symBNF%NPP  Ccost/Nfixed(gC/gN)  symFIX  freeFIX  sym/tot  mycorr%NPP
Manaus     0.037%        0.12             2.64    0.75     0.78      0.08%
Harvard    0.048%        0.13             1.77    0.39     0.82      0.07%
Bonanza    0.0003%       1.54             0.00    0.21     0.00      0.01%
Benchmarks: Menge2026 natural symbiotic BNF=0.29%NPP (0.30% trop evergreen broadleaf);
Braghiere2022 ELM-FUN global symbiotic=0.002%NPP. Ccost/Nfixed: Menge 5(4-6), FUN nominal 7.5-12.5.
Mycorrhizal C-use: Braghiere2022 global 5.9%.

## Warming response (fixation share of N uptake, 2000s->2090s)
site     Houlton      noACC        ACC          dTsoil12cm
Manaus   15.0->9.0%   16.5->12.4%  15.3->12.2%  31.0->35.7C
Harvard  20.8->21.1%  18.1->19.4%  18.4->19.7%  11.6->15.2C
Bonanza   4.6->3.4%    4.6->3.4%    4.6->3.4%    1.6->6.5C

## Leaf stoichiometry (prescribed/fixed)
leaf N:P mass = 14.1/15.0/10.0, C:N = 24/25/40 -> FLAT to <0.1% over 1850-2100
(Braghiere2022 sec2.1: "Flexible plant tissue stoichiometry is not considered").
Retranslocation N:P is DYNAMIC (Man 15.4->16.4, Har 17.6->19.3, Bon 11.7->13.3) = where the
N/P-limitation signal actually lives (2022 sec3.4 used leaf-N:P relative to retrans-N:P).

## EVALUATION — do they make sense? YES as relative/dynamic indices; 2 caveats on absolute magnitude.
1. Tom's N/P split valid + internally consistent. P-acquisition dominates N at all sites
   (P-lim >> N-lim). Forest C-use 1.3-5.4% < 2022 global ~13% (forests cheaper than grassland/crop). OK.
2. Fixation confound real & non-trivial: NPP_NFIX is 7-8% of NPP_NUPTAKE at Manaus/Harvard
   (vs ~0.03% global) because these are N-fixing forest sites. Use NPP_NACTIVE for fixation-free N.
3. CAVEAT A: C PRICE of N/fixation realized very low. Cross-checked (NPP_NFIX/NFIX=0.12;
   1/COST_NFIX=0.27 gC/gN) => ~0.1-0.3 gC/gN, ~40x below Menge obs(5), ~60-100x below FUN nominal.
   Mycorrhizal C-use 0.07-0.08%NPP vs 5.9% global. BNF FLUXES realistic (sym 2.64, free 0.75 gN/m2/yr)
   but C INVESTMENT tiny (s_fix down-tuning). => cost-based limitation meaningful RELATIVELY, not as
   absolute intensity; ELM-FUN BNF C-investment ~8x below obs band. FLAG FOR TOM.
4. CAVEAT B: leaf C:N/N:P cannot be a warming-response index (fixed by PFT => flat). Fine as static
   cross-site descriptor; null warming response by construction. Dynamic analog = retranslocation N:P.
5. Warming x fixation behaves as protocol predicts: hot Manaus Houlton suppresses most (15->9%),
   Bytnerowicz sustains (->12%); temperate rises; boreal low+scheme-insensitive. Matches April table.
6. Model NUPTAKE_NPP_FRACTION != Tom's proxy (denominator availc, per-timestep avg); ~5x lower; not
   interchangeable. Tom's explicit formula is the more transparent choice.

## Recommended indices for Tom
- N vs P balance: NPP_NUPTAKE/NPP_PUPTAKE (dimensionless; dynamic cousin of leaf N:P).
- Fixation-independent N index: NPP_NACTIVE/(NPP_NUPTAKE+NPP_PUPTAKE+NPP).
- Warming x fixation: fixation share + BNF C-investment (NPP_NFIX/NPP) w/ Caveat A vs Menge2026.
- Portable cross-model: leaf N:P, but state ELM-FUN's is fixed (Caveat B) => null warming response.
- Cost per unit nutrient: NPP_NUPTAKE/NUP, NPP_PUPTAKE/PUP (P >> N here).
NPP_NACTIVE/NPP_NFIX/NUPTAKE_NPP_FRACTION/PUPTAKE_NPP_FRACTION/COST_* are in raw h0, not yet in
data_csv_corrected/ (VMAP edit + repackage to add).
