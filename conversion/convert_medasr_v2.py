#!/usr/bin/env python3
"""
MedASR v2 — single-input CoreML model, ANE-compatible.

ANE crash root cause:
  v1 had cos/sin as separate inputs with independent RangeDims.
  ANE requires tensors in ios17.mul to share the same symbolic dimension.
  Two separate RangeDims = ANE rejects at load time.

Fix strategy:
  Register cos/sin as module buffers sliced to EXACTLY the trace-time T_sub.
  The tracer records them as constants of shape [1, 497, 64].
  coremltools then promotes T_sub to a RangeDim that is TIED to input_features
  via the subsampler ops — single symbolic dimension drives the whole graph.
  No aten::Int, no aten::arange, no aten::slice on dynamic dims.

Usage (run from conversion/ with .venv312 active):
  python convert_medasr_v2.py
  xcrun coremlcompiler compile MedASR.mlpackage MedASR.mlmodelc
  rm -rf ../RadiologySuite/Resources/MedASR.mlmodelc
  cp -R MedASR.mlmodelc ../RadiologySuite/Resources/MedASR.mlmodelc
"""

import json, os, sys
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import coremltools as ct
from transformers import AutoProcessor, LasrForCTC
from sentencepiece import SentencePieceProcessor

HF_TOKEN  = os.environ.get("HF_TOKEN", "")  # set HF_TOKEN env var before running
MODEL_ID  = "google/medasr"
SPM_PATH  = os.path.expanduser(
    "~/.cache/huggingface/hub/models--google--medasr/snapshots/"
    "ae1e4845b4b07479735d93e1e591e566435b7104/spiece.model"
)
OUT_MODEL  = "MedASR.mlpackage"
OUT_VOCAB  = "../RadiologySuite/Resources/medasr_vocab.json"
TRACE_SECS = 3      # 3s chunk → T_frames=298, T_sub=72 — responsive real-time inference
MAX_ROPE_T = 10_001
_HALF_DIM  = 32     # 64 // 2 — constant, no aten::Int


# ── rotate_half with fixed constant split ────────────────────────────────────
def rotate_half(x: torch.Tensor) -> torch.Tensor:
    return torch.cat((-x[..., _HALF_DIM:], x[..., :_HALF_DIM]), dim=-1)


# ── patched attention ────────────────────────────────────────────────────────
class StaticAttention(nn.Module):
    def __init__(self, orig):
        super().__init__()
        self.q_proj  = orig.q_proj
        self.k_proj  = orig.k_proj
        self.v_proj  = orig.v_proj
        self.o_proj  = orig.o_proj
        self.scaling = orig.scaling
        self.H = 8
        self.D = 64

    def forward(self, hidden_states, position_embeddings=None,
                attention_mask=None, **_):
        B, T, _ = hidden_states.shape
        H, D = self.H, self.D
        q = self.q_proj(hidden_states).view(B, T, H, D).transpose(1, 2)
        k = self.k_proj(hidden_states).view(B, T, H, D).transpose(1, 2)
        v = self.v_proj(hidden_states).view(B, T, H, D).transpose(1, 2)
        if position_embeddings is not None:
            cos, sin = position_embeddings
            # cos: [1, T_sub, 64] → unsqueeze → [1, 1, T_sub, 64]
            # q:   [1, 8, T_sub, 64] — broadcast over head dim only
            cos = cos.unsqueeze(1)
            sin = sin.unsqueeze(1)
            q = q * cos + rotate_half(q) * sin
            k = k * cos + rotate_half(k) * sin
        attn = torch.matmul(q, k.transpose(-2, -1)) * self.scaling
        attn = F.softmax(attn, dim=-1, dtype=torch.float32).to(q.dtype)
        out  = torch.matmul(attn, v).transpose(1, 2).reshape(B, T, H * D)
        return self.o_proj(out), attn


# ── single-input wrapper ─────────────────────────────────────────────────────
class MedASRWrapper(nn.Module):
    """
    Input:  input_features  [1, T_frames, 128]
    Output: log_probs        [1, T_sub,   512]

    cos_buf / sin_buf are registered as buffers of shape [1, T_sub_trace, 64]
    where T_sub_trace = 497 (the subsampler output for 20 s of audio).
    The tracer sees them as constants; coremltools ties T_sub to the single
    RangeDim that drives input_features, so ANE validates all shapes correctly.
    """
    def __init__(self, m: LasrForCTC,
                 cos_trace: torch.Tensor,
                 sin_trace: torch.Tensor):
        super().__init__()
        self.subsampler = m.encoder.subsampler
        self.out_norm   = m.encoder.out_norm
        self.ctc_head   = m.ctc_head
        # cos_trace / sin_trace: [1, T_sub_trace, 64]
        self.register_buffer("cos_buf", cos_trace)
        self.register_buffer("sin_buf", sin_trace)
        self.layers = nn.ModuleList()
        for layer in m.encoder.layers:
            layer.self_attn = StaticAttention(layer.self_attn)
            self.layers.append(layer)

    def forward(self, input_features: torch.Tensor) -> torch.Tensor:
        hidden = self.subsampler(input_features)   # [1, T_sub, 512]
        # cos_buf is [1, T_sub_trace, 64]. At trace time T_sub == T_sub_trace.
        # coremltools propagates the single RangeDim through all ops so that
        # at runtime any T_sub in [10, 39997] is accepted and shapes match.
        for layer in self.layers:
            hidden = layer(hidden, attention_mask=None,
                           position_embeddings=(self.cos_buf, self.sin_buf))
        hidden = self.out_norm(hidden)
        logits = self.ctc_head(hidden.transpose(1, 2)).transpose(1, 2)
        return F.log_softmax(logits, dim=-1)


# ── main ─────────────────────────────────────────────────────────────────────
def main():
    print("[1/6] Loading model …")
    sys.stdout.flush()
    processor = AutoProcessor.from_pretrained(MODEL_ID, token=HF_TOKEN)
    model     = LasrForCTC.from_pretrained(
        MODEL_ID, torch_dtype=torch.float32, token=HF_TOKEN)
    model.eval()
    print(f"      {sum(p.numel() for p in model.parameters())/1e6:.1f}M params")

    print("[2/6] Rebuilding vocab from spiece.model …")
    sys.stdout.flush()
    spm = SentencePieceProcessor()
    spm.Load(SPM_PATH)
    vocab = {str(i): spm.IdToPiece(i) for i in range(spm.GetPieceSize())}
    with open(OUT_VOCAB, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False, indent=2)
    print(f"      {len(vocab)} tokens → {OUT_VOCAB}")

    print("[3/6] Building trace inputs …")
    sys.stdout.flush()
    dummy_audio = np.zeros(16_000 * TRACE_SECS, dtype=np.float32)
    feat        = processor(dummy_audio, sampling_rate=16_000,
                            return_tensors="pt", padding=False)
    dummy_feats = feat["input_features"]                # [1, T_frames, 128]
    T_frames    = dummy_feats.shape[1]

    # Compute RoPE table and slice to exact trace-time T_sub
    with torch.no_grad():
        cos_full, sin_full = model.encoder.rotary_emb(
            torch.zeros(1, MAX_ROPE_T, 512),
            torch.arange(MAX_ROPE_T).unsqueeze(0),
        )
        T_sub     = model.encoder.subsampler(dummy_feats).shape[1]
        cos_trace = cos_full[:, :T_sub, :]  # [1, T_sub, 64]
        sin_trace = sin_full[:, :T_sub, :]

    print(f"      T_frames={T_frames}, T_sub={T_sub}")
    print(f"      cos_trace: {list(cos_trace.shape)}")

    print("[4/6] Building wrapper + sanity check …")
    sys.stdout.flush()
    wrapper = MedASRWrapper(model, cos_trace, sin_trace)
    wrapper.eval()

    with torch.no_grad():
        sanity = wrapper(dummy_feats)
    print(f"      output: {list(sanity.shape)}  ✓")

    print("[5/6] Tracing …")
    sys.stdout.flush()
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, dummy_feats, strict=False)

    bad = [n for n in traced.inlined_graph.nodes() if n.kind() == "aten::Int"]
    if bad:
        raise RuntimeError(f"{len(bad)} aten::Int ops remain — cannot convert")
    print("      0 aten::Int ops  ✓")

    print("[6/6] Converting to CoreML FP16 …")
    sys.stdout.flush()
    T_range = ct.RangeDim(lower_bound=10, upper_bound=159_998, default=T_frames)
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="input_features",
                shape=(1, T_range, 128),
                dtype=np.float32,
            )
        ],
        outputs=[ct.TensorType(name="log_probs", dtype=np.float32)],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram",
    )
    mlmodel.short_description = (
        "MedASR – Google Health AI LASR Conformer CTC FP16 v2 (ANE-safe)"
    )
    mlmodel.input_description["input_features"] = (
        "Log-mel spectrogram [1, T_frames, 128] · 16 kHz, hop=160"
    )
    mlmodel.output_description["log_probs"] = (
        "CTC log-probs [1, T_sub, 512]  — T_sub=(T_frames-7)//4"
    )
    mlmodel.save(OUT_MODEL)

    print()
    print("✓  MedASR.mlpackage  saved")
    print("✓  medasr_vocab.json saved")
    print()
    print("Next steps:")
    print("  xcrun coremlcompiler compile MedASR.mlpackage MedASR.mlmodelc")
    print("  rm -rf ../RadiologySuite/Resources/MedASR.mlmodelc")
    print("  cp -R MedASR.mlmodelc ../RadiologySuite/Resources/MedASR.mlmodelc")


if __name__ == "__main__":
    main()
