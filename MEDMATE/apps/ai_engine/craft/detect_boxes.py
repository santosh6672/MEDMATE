import os
import torch
import cv2
import numpy as np

from . import craft_utils
from . import imgproc
from .craft import CRAFT


# ── helper ─────────────────────────────────────────────

def _copy_state_dict(state_dict: dict) -> dict:
    start = 1 if list(state_dict.keys())[0].startswith("module") else 0
    return {".".join(k.split(".")[start:]): v for k, v in state_dict.items()}


# ── detector ───────────────────────────────────────────

class CraftDetector:

    def __init__(self, cuda: bool = True):
        self.cuda = cuda and torch.cuda.is_available()

        weights_path = os.path.join(
            os.path.dirname(__file__), "weights", "craft_mlt_25k.pth"
        )

        self.net = CRAFT()

        if self.cuda:
            state = torch.load(weights_path)
            self.net.load_state_dict(_copy_state_dict(state))
            self.net = self.net.cuda()

            if torch.cuda.device_count() > 1:
                self.net = torch.nn.DataParallel(self.net)
                print(f"✅ CRAFT loaded on {torch.cuda.device_count()} GPUs")
            else:
                print("✅ CRAFT loaded on single GPU")
        else:
            state = torch.load(weights_path, map_location="cpu")
            self.net.load_state_dict(_copy_state_dict(state))
            print("⚠️ CRAFT running on CPU")

        self.net.eval()

    def detect(
        self,
        image_path: str,
        text_threshold: float = 0.6,
        link_threshold: float = 0.4,
        low_text: float = 0.4,
        mag_ratio: float = 1.5,
        min_size: int = 15,   # 🔥 filter noise
    ) -> list:

        image = imgproc.loadImage(image_path)
        h_orig, w_orig = image.shape[:2]

        # Adaptive canvas
        canvas_size = min(max(h_orig, w_orig), 2560)

        img_resized, target_ratio, _ = imgproc.resize_aspect_ratio(
            image,
            canvas_size,
            interpolation=cv2.INTER_LINEAR,
            mag_ratio=mag_ratio
        )

        ratio_h = ratio_w = 1 / target_ratio

        x = imgproc.normalizeMeanVariance(img_resized)
        x = torch.from_numpy(x).permute(2, 0, 1).unsqueeze(0)

        if self.cuda:
            x = x.cuda()

        # ── forward pass ─────────────────────────────
        with torch.no_grad():
            y, _ = self.net(x)

        score_text = y[0, :, :, 0].cpu().numpy()
        score_link = y[0, :, :, 1].cpu().numpy()

        # 🔥 polygon=True → tighter boxes
        boxes, _ = craft_utils.getDetBoxes(
            score_text,
            score_link,
            text_threshold,
            link_threshold,
            low_text,
            True   # IMPORTANT
        )

        # adjust to original image
        boxes = craft_utils.adjustResultCoordinates(boxes, ratio_w, ratio_h)

        # sort boxes (top → bottom, left → right)
        boxes = sorted(boxes, key=lambda b: (np.min(b[:, 1]), np.min(b[:, 0])))
        boxes = [box.astype(int).tolist() for box in boxes]

        print(f"✅ Raw boxes: {len(boxes)}")

        # ── filter small / noise boxes ─────────────────
        filtered_boxes = []

        for box in boxes:
            pts = np.array(box)

            w = np.max(pts[:, 0]) - np.min(pts[:, 0])
            h = np.max(pts[:, 1]) - np.min(pts[:, 1])

            # remove tiny noise
            if w < min_size or h < min_size:
                continue

            filtered_boxes.append(box)

        print(f"✅ After filtering: {len(filtered_boxes)}")

        return filtered_boxes