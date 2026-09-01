#!/usr/bin/env python3
"""
Convert google/medasr (LASR Conformer + CTC) to FP16 Core ML.

Strategy:
  - Rebuild the attention module without the dynamic int-cast op that
    coremltools cannot lower. The cast comes from hidden_shape = (*input_shape, -1, head_dim)
    where -1 is resolved at trace time via an aten::Int node.
  - We replace all 17 attention modules with a clean StaticAttention that
    avoids the problematic reshape by computing num_heads explicitly.
  - cos/sin RoPE tables are pre-computed and passed as model inputs (avoids
    torch.arange inside the graph entirely).

Output:
  MedASR.mlpackage   — FP16 Core ML program (iOS 17+, Neural Engine)
  medasr_vocab.json  — {token_id: piece} for on-device greedy CTC decode

Usage:
  source .venv312/bin/activate
  python convert_medasr.py
  xcrun coremlcompiler compile MedASR.mlpackage MedASR.mlmodelc
  cp -R MedASR.mlmodelc ../RadiologySuite/Resources/
  cp medasr_vocab.json  ../RadiologySuite/Resources/
"""

import json
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import coremltools as ct
from transformers import AutoProcessor, LasrForCTC

HF_TOKEN   = os.environ.get("HF_TOKEN", "")  # set HF_TOKEN env var before running
MODEL_ID   = "google/medasr"
OUT_MODEL  = "MedASR.mlpackage"
OUT_VOCAB  = "medasr_vocab.json"
MAX_T      = 10001   # max subsampled frames ≈ 400 s of audio

# ──────────────────────────────────────────────────────────────────────
# 1.  Patched attention — avoids aten::Int on dynamic shape dimension
# ──────────────────────────────────────────────────────────────────────

_HALF_DIM = 32  # head_dim // 2 = 64 // 2 = 32  — constant, avoids aten::Int in trace


def rotate_half(x: torch.Tensor) -> torch.Tensor:
    # Use literal constant slices — no dynamic x.shape[-1] // 2
    x1, x2 = x[..., :_HALF_DIM], x[..., _HALF_DIM:]
    return torch.cat((-x2, x1), dim=-1)


class StaticAttention(nn.Module):
    """
    Drop-in replacement for LasrEncoderAttention that uses explicit
    reshapes (no -1 in view) so the graph is fully static-friendly.
    """
    def __init__(self, orig_attn):
        super().__init__()
        self.q_proj   = orig_attn.q_proj
        self.k_proj   = orig_attn.k_proj
        self.v_proj   = orig_attn.v_proj
        self.o_proj   = orig_attn.o_proj
        self.scaling  = orig_attn.scaling
        # Infer heads from weight shape: q_proj [hidden, hidden]
        hidden        = orig_attn.q_proj.weight.shape[0]
        # head_dim from rotary embeddings: cos shape was [1, T, head_dim]
        # LasrEncoderConfig defaults: num_attention_heads=8, head_dim=hidden/8
        self.num_heads = 8
        self.head_dim  = hidden // self.num_heads

    def forward(
        self,
        hidden_states: torch.Tensor,
        position_embeddings=None,
        attention_mask=None,
        **kwargs,
    ):
        B, T, _ = hidden_states.shape
        H, D   = self.num_heads, self.head_dim

        q = self.q_proj(hidden_states).view(B, T, H, D).transpose(1, 2)  # [B,H,T,D]
        k = self.k_proj(hidden_states).view(B, T, H, D).transpose(1, 2)
        v = self.v_proj(hidden_states).view(B, T, H, D).transpose(1, 2)

        if position_embeddings is not None:
            cos, sin = position_embeddings
            cos = cos.unsqueeze(1)   # [B,1,T,D]
            sin = sin.unsqueeze(1)
            q = q * cos + rotate_half(q) * sin
            k = k * cos + rotate_half(k) * sin

        # Scaled dot-product attention (no mask — bidirectional encoder)
        attn = torch.matmul(q, k.transpose(-2, -1)) * self.scaling  # [B,H,T,T]
        attn = F.softmax(attn, dim=-1, dtype=torch.float32).to(q.dtype)
        out  = torch.matmul(attn, v)                                 # [B,H,T,D]
        out  = out.transpose(1, 2).reshape(B, T, H * D)             # [B,T,hidden]
        return self.o_proj(out), attn


# ──────────────────────────────────────────────────────────────────────
# 2.  Wrapper model
# ──────────────────────────────────────────────────────────────────────

class MedASRWrapper(nn.Module):
    """
    Inputs:
      input_features : [1, T_frames, 128]  log-mel spectrogram
      cos            : [1, T_sub,    64]   pre-computed RoPE cosines
      sin            : [1, T_sub,    64]   pre-computed RoPE sines
    Output:
      log_probs      : [1, T_sub,    512]  CTC log-probabilities
    """
    def __init__(self, m: LasrForCTC):
        super().__init__()
        self.subsampler = m.encoder.subsampler
        self.out_norm   = m.encoder.out_norm
        self.ctc_head   = m.ctc_head

        # Replace each attention module with the patched version
        self.layers = nn.ModuleList()
        for layer in m.encoder.layers:
            layer.self_attn = StaticAttention(layer.self_attn)
            self.layers.append(layer)

    def forward(
        self,
        input_features: torch.Tensor,
        cos: torch.Tensor,
        sin: torch.Tensor,
    ) -> torch.Tensor:
        hidden = self.subsampler(input_features)
        for layer in self.layers:
            hidden = layer(
                hidden,
                attention_mask=None,
                position_embeddings=(cos, sin),
            )
        hidden = self.out_norm(hidden)
        logits = self.ctc_head(hidden.transpose(1, 2)).transpose(1, 2)
        return F.log_softmax(logits, dim=-1)


# ──────────────────────────────────────────────────────────────────────
# 3.  Main conversion
# ──────────────────────────────────────────────────────────────────────

def main():
    # 1. Load
    print("[1/6] Loading model …")
    processor = AutoProcessor.from_pretrained(MODEL_ID, token=HF_TOKEN)
    model     = LasrForCTC.from_pretrained(
        MODEL_ID, torch_dtype=torch.float32, token=HF_TOKEN
    )
    model.eval()
    print(f"      {sum(p.numel() for p in model.parameters())/1e6:.1f}M params")

    # 2. Vocab
    print("[2/6] Exporting vocab …")
    vocab = processor.tokenizer.get_vocab()
    with open(OUT_VOCAB, "w", encoding="utf-8") as f:
        json.dump({str(v): k for k, v in vocab.items()}, f,
                  ensure_ascii=False, indent=2)
    print(f"      {len(vocab)} tokens → {OUT_VOCAB}")

    # 3. Pre-compute RoPE tables
    print("[3/6] Pre-computing RoPE table …")
    with torch.no_grad():
        cos_full, sin_full = model.encoder.rotary_emb(
            torch.zeros(1, MAX_T, 512),
            torch.arange(MAX_T).unsqueeze(0),
        )
    print(f"      cos/sin: {list(cos_full.shape)}")

    # 4. Build wrapper + dummy inputs
    print("[4/6] Building wrapper and trace inputs …")
    wrapper = MedASRWrapper(model)
    wrapper.eval()

    dummy_audio  = np.zeros(16_000 * 20, dtype=np.float32)
    feat         = processor(
        dummy_audio, sampling_rate=16_000,
        return_tensors="pt", padding=False,
    )
    dummy_feats  = feat["input_features"]

    with torch.no_grad():
        T_sub = wrapper.subsampler(dummy_feats).shape[1]

    cos_trace = cos_full[:, :T_sub].clone()
    sin_trace = sin_full[:, :T_sub].clone()
    print(f"      feats {list(dummy_feats.shape)}, T_sub={T_sub}")

    # Sanity-check
    with torch.no_grad():
        sanity = wrapper(dummy_feats, cos_trace, sin_trace)
    print(f"      sanity output: {list(sanity.shape)}")

    # 5. Trace
    print("[5/6] Tracing …")
    with torch.no_grad():
        traced = torch.jit.trace(
            wrapper, (dummy_feats, cos_trace, sin_trace), strict=False
        )

    # Verify no aten::Int nodes remain
    int_ops = [n for n in traced.graph.nodes() if n.kind() == "aten::Int"]
    if int_ops:
        raise RuntimeError(f"Still {len(int_ops)} aten::Int ops — patch incomplete")
    print("      trace OK, 0 aten::Int ops")

    # 6. Convert
    print("[6/6] Converting to Core ML FP16 …")
    T_feat_range = ct.RangeDim(lower_bound=42,  upper_bound=159_998, default=1998)
    T_sub_range  = ct.RangeDim(lower_bound=10,  upper_bound=39_997,  default=T_sub)
    head_dim     = cos_trace.shape[-1]  # 64

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_features",
                          shape=(1, T_feat_range, 128), dtype=np.float32),
            ct.TensorType(name="cos",
                          shape=(1, T_sub_range, head_dim), dtype=np.float32),
            ct.TensorType(name="sin",
                          shape=(1, T_sub_range, head_dim), dtype=np.float32),
        ],
        outputs=[ct.TensorType(name="log_probs", dtype=np.float32)],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
        convert_to="mlprogram",
    )
    mlmodel.short_description = "MedASR – Google Health AI LASR Conformer CTC FP16"
    mlmodel.input_description["input_features"] = (
        "Log-mel spectrogram [1, T, 128] · 16 kHz, hop=160"
    )
    mlmodel.input_description["cos"] = "RoPE cosines [1, T/4, 64]"
    mlmodel.input_description["sin"] = "RoPE sines   [1, T/4, 64]"
    mlmodel.output_description["log_probs"] = (
        "CTC log-probs [1, T/4, 512] · greedy argmax → token IDs"
    )
    mlmodel.save(OUT_MODEL)

    print()
    print("✓ Saved → MedASR.mlpackage")
    print("✓ Vocab → medasr_vocab.json")
    print()
    print("Next steps:")
    print(f"  xcrun coremlcompiler compile {OUT_MODEL} MedASR.mlmodelc")
    print( "  cp -R MedASR.mlmodelc ../RadiologySuite/Resources/")
    print( "  cp medasr_vocab.json  ../RadiologySuite/Resources/")
    print()
    print("NOTE: MedASREngine.swift now expects 3 inputs (features, cos, sin).")
    print("      Update ingest() to compute RoPE slices before calling the model.")


if __name__ == "__main__":
    main()
