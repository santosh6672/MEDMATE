"""
paddle_ocr.py
─────────────
Fix: "string index out of range"

Root cause:
    PaddleOCR's .ocr() method expects either:
      a) A file path string  → works reliably
      b) A numpy array       → works ONLY if the array is a valid 3-channel
                               BGR image of sufficient size

    The crash was happening because some CRAFT crops after preprocessing
    (Otsu threshold → grayscale → back to BGR) were producing arrays that
    PaddleOCR's internal C++ pipeline couldn't index correctly.

    Specifically: very small crops (thin lines, punctuation boxes) were
    producing 1D or near-empty arrays after Otsu thresholding.

Fix:
    Save each preprocessed crop to a named temp file and pass the
    FILE PATH to .ocr() instead of the numpy array directly.
    PaddleOCR handles file paths through its own image loading pipeline
    which is more robust than direct array input.

    Temp files are cleaned up immediately after each crop is processed.
"""

import os
import cv2
import tempfile
import numpy as np
from paddleocr import PaddleOCR


class PaddleRecognizer:

    def __init__(self):
        self.ocr = PaddleOCR(
            use_angle_cls=True,
            lang="en",
            show_log=False,
            use_gpu=True,
        )
        print("✅ PaddleOCR ready")

    def recognize(
        self,
        image_path: str,
        boxes: list,
        padding:  int   = 8,
        min_conf: float = 0.3,
    ) -> tuple:
        """
        Recognise text inside CRAFT-detected boxes.

        Args:
            image_path: Path to preprocessed image
            boxes:      CRAFT boxes [[[x,y],[x,y],[x,y],[x,y]], ...]
            padding:    Extra pixels around each crop
            min_conf:   Minimum OCR confidence to keep

        Returns:
            full_text (str):  All recognised text joined by newlines
            results   (list): Per-word dicts {box, text, confidence}
        """
        image = cv2.imread(image_path)
        if image is None:
            raise ValueError(f"Image not found: {image_path}")

        if not boxes:
            print("⚠️  No boxes to recognise")
            return "", []

        h, w = image.shape[:2]

        full_text_lines = []
        results         = []

        for i, box in enumerate(boxes):
            temp_path = None
            try:
                # ── Extract crop ───────────────────────────────────────────
                pts   = np.array(box).astype(int)
                x_min = max(0, np.min(pts[:, 0]) - padding)
                y_min = max(0, np.min(pts[:, 1]) - padding)
                x_max = min(w, np.max(pts[:, 0]) + padding)
                y_max = min(h, np.max(pts[:, 1]) + padding)

                crop = image[y_min:y_max, x_min:x_max]

                # Skip empty or too-small crops
                if crop.size == 0 or crop.shape[0] < 8 or crop.shape[1] < 8:
                    continue

                # ── Preprocess crop ────────────────────────────────────────
                crop = self._preprocess_crop(crop)

                # ── Save to temp file and pass PATH to PaddleOCR ──────────
                # Passing file path is more reliable than numpy array input
                fd, temp_path = tempfile.mkstemp(suffix=".jpg")
                os.close(fd)
                cv2.imwrite(temp_path, crop)

                # ── Run OCR ────────────────────────────────────────────────
                crop_result = self.ocr.ocr(temp_path, cls=True)

                if not crop_result:
                    continue

                for page in crop_result:
                    if page is None:
                        continue
                    for word in page:
                        if word is None or len(word) < 2:
                            continue

                        text       = word[1][0]
                        confidence = float(word[1][1])

                        if confidence >= min_conf and text.strip():
                            full_text_lines.append(text)
                            results.append({
                                "box":        box,
                                "text":       text,
                                "confidence": confidence,
                            })

            except Exception as e:
                print(f"⚠️  Crop {i} failed: {e}")
                continue

            finally:
                # Always clean up temp file
                if temp_path and os.path.exists(temp_path):
                    os.remove(temp_path)

        full_text = "\n".join(full_text_lines)
        print(f"✅ PaddleOCR: {len(results)} words from {len(boxes)} boxes")
        return full_text, results

    @staticmethod
    def _preprocess_crop(crop: np.ndarray) -> np.ndarray:
        """
        Prepare a CRAFT crop for PaddleOCR.
        Otsu threshold separates ink from paper.
        Dilation connects broken handwriting strokes.
        Returns 3-channel BGR (PaddleOCR requirement).
        """
        gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)

        # Otsu threshold
        _, binary = cv2.threshold(
            gray, 0, 255, cv2.THRESH_BINARY | cv2.THRESH_OTSU
        )

        # Dilate to connect broken strokes
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2))
        binary = cv2.dilate(binary, kernel, iterations=1)

        # Back to 3-channel BGR
        return cv2.cvtColor(binary, cv2.COLOR_GRAY2BGR)