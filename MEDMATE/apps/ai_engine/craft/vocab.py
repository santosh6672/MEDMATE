# vocab.py
import string

PAD = "<PAD>"
SOS = "<SOS>"
EOS = "<EOS>"

chars = list(string.ascii_lowercase + string.digits)
vocab = [PAD, SOS, EOS] + chars

char2idx = {c: i for i, c in enumerate(vocab)}
idx2char = {i: c for c, i in char2idx.items()}
