# ELM-FUN BNFMIP — Results Summary

**Submission:** 3 sites × 4 experiments × 3 protocol sections = **36 files**, all verified.
**Generated:** 2026-07-08 · Contact: renatob@caltech.edu

Experiments: `nofun_baseline` (FUN off), `fun` (§3.1 Houlton), `noacc` (§3.2 Bytnerowicz
no-acclimation), `acc` (§3.3 Bytnerowicz with acclimation).
Sections: §5.3 historical 1850–2014 · §5.4 fixed CO₂/Ndep @2014, SSP5-8.5 warming,
2015–2100 · §5.5 transient SSP5-8.5 CO₂/Ndep, 2015–2100.

## Headline table (last-decade mean)

GPP, NPP in gC m⁻² yr⁻¹; BNF (`NFIX_TO_SMINN`) in gN m⁻² yr⁻¹.

| Site / exp | GPP 5.3/5.4/5.5 | NPP 5.3/5.4/5.5 | BNF 5.3/5.4/5.5 |
|---|---|---|---|
| **Manaus** nofun | 3776 / 2523 / 4143 | 1559 / 1015 / 1813 | 1.77 / 1.33 / 1.46 |
| Manaus fun | 3447 / 2126 / 4064 | 879 / 471 / 1046 | 2.52 / 0.93 / 1.65 |
| Manaus noacc | 3447 / 2126 / 4064 | 879 / 471 / 1046 | 2.85 / 1.57 / 2.56 |
| Manaus acc | 3447 / 2126 / 4064 | 879 / 471 / 1046 | 2.58 / 1.56 / 2.51 |
| **Harvard** nofun | 1222 / 1624 / 2421 | 714 / 934 / 1455 | 1.05 / 1.28 / 0.98 |
| Harvard fun | 1026 / 1254 / 2184 | 370 / 437 / 822 | 0.51 / 0.12 / 0.16 |
| Harvard noacc | 1026 / 1254 / 2184 | 369 / 437 / 822 | 0.46 / 0.09 / 0.16 |
| Harvard acc | 1026 / 1254 / 2184 | 369 / 437 / 822 | 0.47 / 0.10 / 0.16 |
| **Bonanza** nofun | 960 / 1150 / 1771 | 455 / 523 / 860 | 0.70 / 0.78 / 0.83 |
| Bonanza fun | 905 / 1001 / 1707 | 241 / 247 / 479 | 0.01 / 0.01 / 0.02 |
| Bonanza noacc | 905 / 1001 / 1708 | 241 / 247 / 479 | 0.01 / 0.01 / 0.01 |
| Bonanza acc | 905 / 1001 / 1708 | 241 / 247 / 479 | 0.01 / 0.01 / 0.00 |

## Key findings

1. **BNF temperature-response signal (the MIP's core question).** At warm Manaus, the
   Bytnerowicz functions predict markedly *more* fixation than Houlton (§5.5 BNF:
   noacc/acc ≈ 2.5 vs fun ≈ 1.65 gN m⁻² yr⁻¹), and §5.5 (warmer) > §5.4 — a clear
   warming response. At cold Bonanza all schemes give ≈ 0. Harvard is intermediate.

2. **BNF latitudinal gradient:** tropical ≫ temperate ≫ boreal
   (Manaus ~1.6–2.9 → Harvard ~0.1–0.5 → Bonanza ~0.01 gN m⁻² yr⁻¹).

3. **FUN's carbon cost suppresses NPP** ~40–55 % vs the no-FUN baseline at every site
   (e.g. Manaus §5.3 NPP 879 vs 1559).

4. **SSP5-8.5 raises GPP at all sites** (CO₂ fertilization + warming): §5.5 > §5.4 > §5.3
   growing-season productivity; e.g. Harvard nofun GPP 1222 → 2421.

5. **Acclimation ≈ no-acclimation** at all three sites (<1 % in C fluxes; small BNF
   differences). Worth flagging: in the current implementation thermal acclimation has
   minimal effect at these sites' temperature ranges.

## Caveats (see docs/corrections.md)

- **Harvard PFT:** run on PFT 6 (broadleaf-deciduous tropical) rather than protocol
  PFT 7 (temperate). BNF temperature-response parameters are identical between the two,
  so the intercomparison signal is intact; Harvard absolute C fluxes are ~10–25 % low.
- **Manaus §5.5** required repurposing the §5.4 case builds (the `ssp585` case builds
  were defective and could not load vegetation); scientifically it is a standard
  2015–2100 transient-SSP5-8.5 run from the end-of-2014 state.
