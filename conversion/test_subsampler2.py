from transformers import LasrForCTC

m = LasrForCTC.from_pretrained("google/medasr")
print(m.encoder.subsampler)
