"""
Copyright (c) 2019-present NAVER Corp.
MIT License
"""

# -*- coding: utf-8 -*-
import sys
import os
import time
import argparse

import torch
import torch.backends.cudnn as cudnn
from torch.autograd import Variable

import cv2
import numpy as np

import craft_utils
import imgproc
import file_utils

from craft import CRAFT
from infer import ocr_word   

from collections import OrderedDict


# ======================================================
# Utils
# ======================================================
def copyStateDict(state_dict):
    if list(state_dict.keys())[0].startswith("module"):
        start_idx = 1
    else:
        start_idx = 0

    new_state_dict = OrderedDict()
    for k, v in state_dict.items():
        name = ".".join(k.split(".")[start_idx:])
        new_state_dict[name] = v
    return new_state_dict


def str2bool(v):
    return v.lower() in ("yes", "y", "true", "t", "1")


# ======================================================
# Args
# ======================================================
parser = argparse.ArgumentParser(description='CRAFT + TrOCR OCR')
parser.add_argument('--trained_model', default='weights/craft_mlt_25k.pth', type=str)
parser.add_argument('--text_threshold', default=0.7, type=float)
parser.add_argument('--low_text', default=0.4, type=float)
parser.add_argument('--link_threshold', default=0.4, type=float)
parser.add_argument('--cuda', default=True, type=str2bool)
parser.add_argument('--canvas_size', default=1280, type=int)
parser.add_argument('--mag_ratio', default=1.5, type=float)
parser.add_argument('--poly', default=False, action='store_true')
parser.add_argument('--show_time', default=False, action='store_true')
parser.add_argument('--test_folder', default='images/', type=str)
parser.add_argument('--refine', default=False, action='store_true')
parser.add_argument('--refiner_model', default='weights/craft_refiner_CTW1500.pth', type=str)

args = parser.parse_args()


# ======================================================
# Load images
# ======================================================
image_list, _, _ = file_utils.get_files(args.test_folder)

result_folder = './result/'
os.makedirs(result_folder, exist_ok=True)


# ======================================================
# CRAFT forward
# ======================================================
def test_net(net, image, text_threshold, link_threshold, low_text, cuda, poly, refine_net=None):

    # Resize
    img_resized, target_ratio, _ = imgproc.resize_aspect_ratio(
        image,
        args.canvas_size,
        interpolation=cv2.INTER_LINEAR,
        mag_ratio=args.mag_ratio
    )
    ratio_h = ratio_w = 1 / target_ratio

    # Preprocess
    x = imgproc.normalizeMeanVariance(img_resized)
    x = torch.from_numpy(x).permute(2, 0, 1)
    x = Variable(x.unsqueeze(0))
    if cuda:
        x = x.cuda()

    # Forward
    with torch.no_grad():
        y, feature = net(x)

    score_text = y[0, :, :, 0].cpu().numpy()
    score_link = y[0, :, :, 1].cpu().numpy()

    if refine_net is not None:
        with torch.no_grad():
            y_refiner = refine_net(y, feature)
        score_link = y_refiner[0, :, :, 0].cpu().numpy()

    # Post-process
    boxes, polys = craft_utils.getDetBoxes(
        score_text, score_link,
        text_threshold, link_threshold, low_text, poly
    )

    boxes = craft_utils.adjustResultCoordinates(boxes, ratio_w, ratio_h)
    polys = craft_utils.adjustResultCoordinates(polys, ratio_w, ratio_h)

    for i in range(len(polys)):
        if polys[i] is None:
            polys[i] = boxes[i]

    return boxes, polys


# ======================================================
# MAIN
# ======================================================
if __name__ == '__main__':

    # Load CRAFT
    net = CRAFT()
    print(f"Loading CRAFT weights from {args.trained_model}")

    if args.cuda:
        net.load_state_dict(copyStateDict(torch.load(args.trained_model)))
        net = net.cuda()
        net = torch.nn.DataParallel(net)
        cudnn.benchmark = False
    else:
        net.load_state_dict(copyStateDict(torch.load(args.trained_model, map_location='cpu')))

    net.eval()

    refine_net = None
    if args.refine:
        from refinenet import RefineNet
        refine_net = RefineNet()
        refine_net.load_state_dict(copyStateDict(torch.load(args.refiner_model)))
        refine_net = refine_net.cuda()
        refine_net = torch.nn.DataParallel(refine_net)
        refine_net.eval()
        args.poly = True

    start = time.time()

    # ==================================================
    # Process images
    # ==================================================
    for idx, image_path in enumerate(image_list):
        print(f"[{idx+1}/{len(image_list)}] Processing {image_path}")

        image = imgproc.loadImage(image_path)
        h, w = image.shape[:2]

        boxes, polys = test_net(
            net, image,
            args.text_threshold,
            args.link_threshold,
            args.low_text,
            args.cuda,
            args.poly,
            refine_net
        )

        # Sort boxes left-to-right
        boxes = sorted(boxes, key=lambda b: np.min(b[:, 0]))

        ocr_results = []

        for box in boxes:
            box = box.astype(int)

            x_min = max(0, np.min(box[:, 0]))
            y_min = max(0, np.min(box[:, 1]))
            x_max = min(w, np.max(box[:, 0]))
            y_max = min(h, np.max(box[:, 1]))

            crop = image[y_min:y_max, x_min:x_max]

            if crop.size == 0:
                continue

            text = ocr_word(crop)
            ocr_results.append((box, text))

            print("   OCR:", text)

        # Draw results
        vis = image.copy()
        for box, text in ocr_results:
            cv2.polylines(vis, [box], True, (0, 255, 0), 2)
            cv2.putText(
                vis, text,
                (box[0][0], box[0][1] - 5),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6, (255, 0, 0), 2
            )

        name = os.path.basename(image_path)
        out_path = os.path.join(result_folder, f"ocr_{name}")
        cv2.imwrite(out_path, vis)

    print(f"\n✅ Done. Total time: {time.time() - start:.2f}s")
