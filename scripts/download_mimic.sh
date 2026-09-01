#!/usr/bin/env bash
# Downloads MIMIC-CXR (text only) + MIMIC-IV-Note radiology reports.
# Requires an APPROVED PhysioNet account with DUA signed for both datasets.
set -euo pipefail

BASE="$(cd "$(dirname "$0")/.." && pwd)"
RAW="$BASE/data/raw"
mkdir -p "$RAW"

read -rp "PhysioNet username: " PN_USER
read -rsp "PhysioNet password: " PN_PASS
echo

fetch () {
  local url="$1" out="$2"
  echo ">> $url"
  wget -c --user "$PN_USER" --password "$PN_PASS" -O "$out" "$url"
}

# --- MIMIC-CXR v2.0.0 : report text only (~30 MB, skip the 500 GB of images) ---
fetch "https://physionet.org/files/mimic-cxr/2.0.0/reports.zip"        "$RAW/mimic_cxr_reports.zip"
# Optional but useful: structured labels + metadata for frequency weighting
fetch "https://physionet.org/files/mimic-cxr/2.0.0/mimic-cxr-2.0.0-metadata.csv.gz" "$RAW/mimic_cxr_metadata.csv.gz"

# --- MIMIC-IV-Note v2.2 : radiology module (ALL modalities: CT/MR/US/XR) ---
fetch "https://physionet.org/files/mimic-iv-note/2.2/radiology.csv.gz" "$RAW/mimic_iv_note_radiology.csv.gz"
fetch "https://physionet.org/files/mimic-iv-note/2.2/discharge.csv.gz" "$RAW/mimic_iv_note_discharge.csv.gz"

echo "Done. Files in $RAW"
echo "Next: python3 scripts/mine_reports.py"
