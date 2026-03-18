"""
qwen2.py
─────────
Qwen2-VL vision OCR — optimised for handwritten prescription images on GPU.

Changes vs original:
─────────────────────────────────────────────────────────────────────────────
1. ASPECT RATIO PRESERVED (was forced 768×768 square)
   │
   │  Original: image.resize((768, 768))
   │  Problem:  A prescription photo is ~3:4 portrait. Squishing it to a
   │            square distorts letter shapes — Qwen2-VL misreads medicine
   │            names that get horizontally compressed.
   │
   │  New: resize keeping aspect ratio, max dimension = 1024px
   │
2. CUDA WARMUP on first load
   │  First inference on a freshly loaded GPU model is slow due to CUDA
   │  kernel compilation (JIT). We run one dummy forward pass at __init__
   │  time so the FIRST real task doesn't pay this cost.
   │
3. max_new_tokens: 200 → 300
   │  Dense prescriptions with 8+ medicines and instructions can exceed 200
   │  tokens. Truncation silently cuts off the last few medicines.
   │
4. Better prompt — explicitly asks for medicine names, dosages, frequencies
   │  Original prompt: "return only the text exactly as written"
   │  Problem: Qwen2-VL sometimes returns a narrative description of the
   │           prescription rather than raw text.
   │  New prompt focuses output on the fields the LLM reasoner needs.
─────────────────────────────────────────────────────────────────────────────
"""

import torch
from transformers import (
    AutoProcessor,
    AutoModelForImageTextToText,
    BitsAndBytesConfig,
)
from PIL import Image


class QwenReasoner:

    def __init__(self):
        model_id = "JackChew/Qwen2-VL-2B-OCR"

        print("🚀 Loading Qwen2-VL OCR model...")

        self.processor = AutoProcessor.from_pretrained(model_id)

        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_compute_dtype=torch.float16,
            bnb_4bit_use_double_quant=True,
            bnb_4bit_quant_type="nf4",
        )

        self.model = AutoModelForImageTextToText.from_pretrained(
            model_id,
            device_map="auto",
            quantization_config=bnb_config,
            torch_dtype=torch.float16,
        )
        self.model.eval()

        # CUDA warmup — pay JIT compilation cost at load time, not on first task
        self._warmup()

        print(f"✅ Qwen2-VL ready (device: {next(self.model.parameters()).device})")

    # ── warmup ────────────────────────────────────────────────────────────

    def _warmup(self):
        """
        Run a tiny dummy forward pass so CUDA kernels are compiled
        before the first real image arrives.
        Without this, the first task takes an extra ~5-8s compared to
        subsequent tasks on the same worker.
        """
        try:
            dummy = Image.new("RGB", (64, 64), color=(255, 255, 255))
            self._run_inference(dummy, max_new_tokens=5)
            print("✅ Qwen2-VL CUDA warmup complete")
        except Exception as e:
            print(f"⚠️  Warmup failed (non-critical): {e}")

    # ── helpers ────────────────────────────────────────────────────────────

    @staticmethod
    def _resize_keep_aspect(image: Image.Image, max_dim: int = 1024) -> Image.Image:
        """
        Resize so the longer side = max_dim, preserving aspect ratio.
        Prescriptions are portrait — squishing to square hurts OCR accuracy.
        """
        w, h  = image.size
        scale = max_dim / max(w, h)
        if scale < 1.0:
            image = image.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
        return image

    def _run_inference(self, image: Image.Image, max_new_tokens: int = 300) -> str:
        prompt = (
            "You are an OCR engine for medical prescriptions.\n"
            "Extract ALL text from this prescription image exactly as it appears.\n"
            "Focus on: medicine names, dosages (mg/ml), frequencies (times per day), "
            "and any doctor instructions.\n"
            "Return plain text only. No explanations."
        )

        conversation = [{
            "role": "user",
            "content": [
                {"type": "image"},
                {"type": "text", "text": prompt},
            ],
        }]

        text_prompt = self.processor.apply_chat_template(
            conversation, tokenize=False, add_generation_prompt=True
        )

        inputs = self.processor(
            text=[text_prompt],
            images=[image],
            padding=True,
            return_tensors="pt",
        )
        inputs = {k: v.to(self.model.device) for k, v in inputs.items()}

        with torch.inference_mode():
            output_ids = self.model.generate(
                **inputs,
                max_new_tokens=max_new_tokens,
                do_sample=False,
            )

        generated = output_ids[:, inputs["input_ids"].shape[1]:]
        return self.processor.batch_decode(
            generated, skip_special_tokens=True
        )[0].strip()

    # ── public API ─────────────────────────────────────────────────────────

    def extract_text(self, image_path: str) -> str:
        """
        Run vision OCR on a prescription image.

        Returns:
            Raw text extracted from the image (str)
        """
        try:
            image = Image.open(image_path).convert("RGB")
        except Exception as e:
            raise ValueError(f"Could not load image: {image_path} | {e}")

        # Preserve aspect ratio — don't squish portrait prescriptions
        image = self._resize_keep_aspect(image, max_dim=1024)

        text = self._run_inference(image, max_new_tokens=300)
        print(f"✅ Qwen2-VL extracted {len(text)} chars")
        return text