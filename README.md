# Radiology ASR — Data & Training Pipeline

Builds radiology phrase corpora → Apple `SFCustomLanguageModelData`.

## Get MIMIC access (one-time, ~2–5 days)

1. CITI Human Subjects training: https://www.citiprogram.org (complete "Data or Specimens Only Research" course, ~2–4 hrs, free)
2. PhysioNet account: https://physionet.org — submit credentialing request with CITI certificate
3. After approval, sign the DUA for each dataset:
   - MIMIC-CXR v2.0.0:  https://physionet.org/content/mimic-cxr/
   - MIMIC-IV-Note v2.2: https://physionet.org/content/mimic-iv-note/
4. Run: `bash scripts/download_mimic.sh` (prompts for username/password)

⚠️ MIMIC text may NOT be redistributed or shipped in the app.
We ship only derived frequency counts / vocabulary lists.

## Pipeline

```
data/raw/            ← downloads land here
scripts/mine_reports.py   MIMIC text → cleaned sections → n-gram frequencies
output/phrases_*.json     weighted phrases per modality
output/Phrases.swift      generated Swift source for SFCustomLanguageModelData
```

## Free-now alternatives (no credentialing)

- RadLex term list (free registration): https://www.rsna.org/radlex
- IU Open-i chest reports (~4k reports, fully public)
- PubMed Central Open Access subset (radiology full text)

## Rules

- Never commit raw MIMIC data anywhere
- Version phrase files (`v1`, `v2`…) — app recompiles custom LM per version
