import torch
from transformers import LasrForCTC

m = LasrForCTC.from_pretrained("google/medasr")
sub = m.encoder.subsampler
x = torch.randn(1, 1158, 128)
y = sub(x)
print(f"tFrames={x.shape[1]} -> tSub={y.shape[1]}")
