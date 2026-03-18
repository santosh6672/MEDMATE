# model.py
import torch
import torch.nn as nn
import math

# ======================
# Positional Encodings
# ======================

class PositionalEncoding2D(nn.Module):
    def __init__(self, d_model, max_h=100, max_w=500):
        super().__init__()
        pe = torch.zeros(max_h, max_w, d_model)

        d_half = d_model // 2
        div = torch.exp(torch.arange(0, d_half, 2) * -(math.log(10000.0) / d_half))

        pos_h = torch.arange(0, max_h).unsqueeze(1)
        pos_w = torch.arange(0, max_w).unsqueeze(1)

        pe[:, :, 0:d_half:2] = torch.sin(pos_h * div).unsqueeze(1)
        pe[:, :, 1:d_half:2] = torch.cos(pos_h * div).unsqueeze(1)
        pe[:, :, d_half::2] = torch.sin(pos_w * div)
        pe[:, :, d_half+1::2] = torch.cos(pos_w * div)

        self.register_buffer("pe", pe)

    def forward(self, x, h, w):
        pe = self.pe[:h, :w].reshape(-1, self.pe.size(-1))
        return x + pe.unsqueeze(0)


class PositionalEncoding1D(nn.Module):
    def __init__(self, d_model, max_len=60):
        super().__init__()
        pe = torch.zeros(max_len, d_model)
        pos = torch.arange(0, max_len).unsqueeze(1)
        div = torch.exp(torch.arange(0, d_model, 2) * -(math.log(10000.0) / d_model))
        pe[:, 0::2] = torch.sin(pos * div)
        pe[:, 1::2] = torch.cos(pos * div)
        self.register_buffer("pe", pe.unsqueeze(0))

    def forward(self, x):
        return x + self.pe[:, :x.size(1)]


# ======================
# CNN Backbone
# ======================

class ResBlock(nn.Module):
    def __init__(self, in_c, out_c, stride=1, down=None):
        super().__init__()
        self.conv1 = nn.Conv2d(in_c, out_c, 3, stride, 1, bias=False)
        self.bn1 = nn.BatchNorm2d(out_c)
        self.conv2 = nn.Conv2d(out_c, out_c, 3, 1, 1, bias=False)
        self.bn2 = nn.BatchNorm2d(out_c)
        self.down = down
        self.relu = nn.ReLU(inplace=True)

    def forward(self, x):
        identity = x
        out = self.relu(self.bn1(self.conv1(x)))
        out = self.bn2(self.conv2(out))
        if self.down:
            identity = self.down(x)
        return self.relu(out + identity)


class ResNetBackbone(nn.Module):
    def __init__(self, d_model=384):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 64, 7, 2, 3, bias=False)
        self.bn1 = nn.BatchNorm2d(64)
        self.relu = nn.ReLU(inplace=True)
        self.pool = nn.MaxPool2d(3, 2, 1)

        self.layer1 = self._make(64, 64, 2, 1)
        self.layer2 = self._make(64, 128, 2, 2)
        self.layer3 = self._make(128, 256, 2, 2)
        self.layer4 = self._make(256, d_model, 2, 1)

    def _make(self, in_c, out_c, blocks, stride):
        down = None
        if stride != 1 or in_c != out_c:
            down = nn.Sequential(
                nn.Conv2d(in_c, out_c, 1, stride, bias=False),
                nn.BatchNorm2d(out_c)
            )
        layers = [ResBlock(in_c, out_c, stride, down)]
        for _ in range(1, blocks):
            layers.append(ResBlock(out_c, out_c))
        return nn.Sequential(*layers)

    def forward(self, x):
        x = self.pool(self.relu(self.bn1(self.conv1(x))))
        x = self.layer1(x)
        x = self.layer2(x)
        x = self.layer3(x)
        x = self.layer4(x)
        return x


# ======================
# Encoder-Decoder Model
# ======================

class EncoderDecoderHTR(nn.Module):
    def __init__(self, vocab_size):
        super().__init__()
        self.d_model = 384

        self.backbone = ResNetBackbone(self.d_model)
        self.pos2d = PositionalEncoding2D(self.d_model)
        self.pos1d = PositionalEncoding1D(self.d_model)

        self.embed = nn.Embedding(vocab_size, self.d_model)

        enc_layer = nn.TransformerEncoderLayer(
            self.d_model, 8, 1536, 0.2,
            activation="gelu", batch_first=True, norm_first=True
        )
        self.encoder = nn.TransformerEncoder(enc_layer, 6)

        dec_layer = nn.TransformerDecoderLayer(
            self.d_model, 8, 1536, 0.2,
            activation="gelu", batch_first=True, norm_first=True
        )
        self.decoder = nn.TransformerDecoder(dec_layer, 4)

        self.fc = nn.Linear(self.d_model, vocab_size)

    def encode(self, x):
        f = self.backbone(x)
        b, c, h, w = f.shape
        f = f.flatten(2).transpose(1, 2)
        f = self.pos2d(f, h, w)
        return self.encoder(f)

    def generate(self, images, sos, eos, max_len=50):
        self.eval()
        mem = self.encode(images)
        B = images.size(0)

        out = torch.full((B, 1), sos, device=images.device)
        finished = torch.zeros(B, dtype=torch.bool, device=images.device)

        for _ in range(max_len):
            emb = self.embed(out) * math.sqrt(self.d_model)
            emb = self.pos1d(emb)
            mask = nn.Transformer.generate_square_subsequent_mask(out.size(1)).to(out.device)
            dec = self.decoder(emb, mem, tgt_mask=mask)
            logits = self.fc(dec[:, -1])
            next_tok = logits.argmax(-1, keepdim=True)

            finished |= (next_tok.squeeze() == eos)
            next_tok[finished] = sos
            out = torch.cat([out, next_tok], 1)

            if finished.all():
                break
        return out
