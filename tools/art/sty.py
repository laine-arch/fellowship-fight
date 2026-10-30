import cv2, numpy as np
from PIL import Image
def kmeans_q(rgb, mask, K, seed=1):
    px = rgb[mask].reshape(-1,3).astype(np.float32)
    lab = cv2.cvtColor(px.reshape(-1,1,3).astype(np.uint8), cv2.COLOR_RGB2LAB).reshape(-1,3).astype(np.float32)
    cv2.setRNGSeed(seed)
    _, lbl, cen = cv2.kmeans(lab, K, None, (cv2.TERM_CRITERIA_EPS+cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5), 3, cv2.KMEANS_PP_CENTERS)
    cen_rgb = cv2.cvtColor(cen.reshape(-1,1,3).astype(np.uint8), cv2.COLOR_LAB2RGB).reshape(-1,3)
    out = rgb.copy(); out[mask] = cen_rgb[lbl.ravel()]; return out
def boost(rgb, sat=1.3, gamma=0.95, contrast=1.12):
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV).astype(np.float32)
    hsv[...,1] = np.clip(hsv[...,1]*sat, 0, 255)
    v = hsv[...,2]/255.0; v = np.clip((v-0.5)*contrast+0.5, 0, 1)**gamma; hsv[...,2] = v*255
    return cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2RGB)
def stylize(img, K=12, outline=4, edge_lo=50, edge_hi=130, bil=5, ink=(28,14,20), line_w=1, sat=1.3):
    a = np.array(img.convert('RGBA'))
    rgb = a[...,:3].copy(); al = a[...,3]
    mask = al > 100
    # fill background with nearest colours so filters don't pull in black halos
    inv = (~mask).astype(np.uint8)*255
    rgb = cv2.inpaint(rgb, inv, 3, cv2.INPAINT_TELEA) if inv.any() else rgb
    f = rgb
    for _ in range(bil): f = cv2.bilateralFilter(f, 9, 38, 7)
    f = boost(f, sat=sat)
    q = kmeans_q(f, mask, K)
    q = cv2.medianBlur(q, 3)
    g = cv2.cvtColor(cv2.GaussianBlur(f,(3,3),0), cv2.COLOR_RGB2GRAY)
    e = cv2.Canny(g, edge_lo, edge_hi)
    if line_w > 1: e = cv2.dilate(e, np.ones((line_w,line_w),np.uint8))
    er = cv2.erode(mask.astype(np.uint8), np.ones((3,3),np.uint8))>0
    e = (e>0) & er
    out = q.copy(); out[e] = (out[e]*0.25 + np.array(ink)*0.75).astype(np.uint8)
    # outer silhouette outline
    m8 = mask.astype(np.uint8)*255
    big = cv2.dilate(m8, cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(outline*2+1,outline*2+1)))
    big = cv2.GaussianBlur(big,(3,3),0)
    ring = (big>0) & ~mask
    out[ring] = ink
    alpha = np.maximum(big, np.where(mask, 255, 0)).astype(np.uint8)
    return Image.fromarray(np.dstack([out, alpha]), 'RGBA')

def stylize2(img, levels=5, ss=50, sr=0.35, passes=2, chromaK=7, outline=5, min_edge=25, line_w=2, sat=1.35, ink=(30,16,24), edge_lo=35, edge_hi=90, lmin=0.18, feat_sigma=6, feat_c=28):
    a = np.array(img.convert('RGBA')); rgb = a[...,:3].copy(); mask = a[...,3] > 100
    inv = (~mask).astype(np.uint8)*255
    if inv.any(): rgb = cv2.inpaint(rgb, inv, 5, cv2.INPAINT_TELEA)
    f = rgb
    for _ in range(passes): f = cv2.edgePreservingFilter(f, flags=1, sigma_s=ss, sigma_r=sr)
    f = boost(f, sat=sat, contrast=1.08)
    lab = cv2.cvtColor(f, cv2.COLOR_RGB2LAB).astype(np.float32)
    L = lab[...,0]; vals = L[mask]
    lo, hi = np.percentile(vals, 2), np.percentile(vals, 99)
    t = np.clip((L-lo)/(hi-lo+1e-6), 0, 1)
    band = np.floor(t*levels-1e-6); band = np.clip(band,0,levels-1)
    Lq = lo + (band+0.5)/levels*(hi-lo)
    Lq = np.maximum(Lq, lmin*255)
    Lq = cv2.medianBlur(Lq.astype(np.uint8), 5).astype(np.float32)
    ab = lab[...,1:].copy()
    px = ab[mask].astype(np.float32); cv2.setRNGSeed(2)
    _, lbl, cen = cv2.kmeans(px, chromaK, None, (cv2.TERM_CRITERIA_EPS+cv2.TERM_CRITERIA_MAX_ITER, 30, 0.5), 3, cv2.KMEANS_PP_CENTERS)
    abq = ab.copy(); abq[mask] = cen[lbl.ravel()]
    abq = np.dstack([cv2.medianBlur(abq[...,0].astype(np.uint8),5), cv2.medianBlur(abq[...,1].astype(np.uint8),5)]).astype(np.float32)
    out = cv2.cvtColor(np.dstack([Lq, abq]).astype(np.uint8), cv2.COLOR_LAB2RGB)
    fe = cv2.bilateralFilter(rgb, 7, 30, 5)
    g = cv2.cvtColor(fe, cv2.COLOR_RGB2GRAY)
    e = cv2.Canny(cv2.GaussianBlur(g,(3,3),0), edge_lo, edge_hi)
    # dark features (eyes, brows, nostrils, mouth): much darker than surroundings
    loc = cv2.GaussianBlur(g.astype(np.float32), (0,0), feat_sigma)
    dark = (g.astype(np.float32) < loc - feat_c) & (g < 110)
    e = (e > 0) | dark
    n, lab_e, stats, _ = cv2.connectedComponentsWithStats((e>0).astype(np.uint8), connectivity=8)
    keep = np.zeros(n, bool); keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= min_edge
    e = keep[lab_e]
    if line_w > 1: e = cv2.dilate(e.astype(np.uint8), np.ones((line_w,line_w),np.uint8)) > 0
    er = cv2.erode(mask.astype(np.uint8), np.ones((5,5),np.uint8)) > 0
    e &= er
    out[e] = (out[e]*0.2 + np.array(ink)*0.8).astype(np.uint8)
    m8 = mask.astype(np.uint8)*255
    big = cv2.dilate(m8, cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(outline*2+1,outline*2+1)))
    big = cv2.GaussianBlur(big,(3,3),0)
    out[(big>0)&~mask] = ink
    out[~mask & (big==0)] = 0
    return Image.fromarray(np.dstack([out, np.maximum(big, m8)]), 'RGBA')
