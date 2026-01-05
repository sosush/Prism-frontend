# 🔮 PRISM Engine v2.0 - Technical Documentation

> **For:** @Swarnim, @Jai, @Sohini, @Srijan, @Sumit  
> **Status:** Production Ready (Hackathon Version)  
> **Updated:** Jan 6, 2026

---

## 🚀 Overview

The **PRISM Engine** (`app/main.py`) is the physics-based liveness detection core. Unlike AI detection models that look for "artifacts," this engine looks for **biological signals** that purely generative AI cannot simulate.

It analyzes a video stream (frames) to verify:
1.  **Biology**: Is there a pulse? Is the heart rate chaotic (HRV, Alive)?
2.  **Physics**: Does light scatter through skin (SSS)?
3.  **Signal Theory**: Is the video purely static (Photo)? Is it a screen replay (Moiré)?

---

## 🛠️ The Detection Layers

We run **7 parallel checks** on every frame. A "Human" result requires passing a multi-modal fusion score.

### 1. Enhanced rPPG (Heart Rate)
*   **What it attempts:** Extract blood volume pulse from green light absorption.
*   **The Tech:** Uses **Welch's Method** (Power Spectral Density) instead of raw FFT for noise robustness.
*   **Metric:** `BPM` (45-190) and `Signal Quality (Q)` (SNR > 0.25).

### 2. HRV (Heart Rate Variability) - *Critical for Liveness*
*   **The Concept:** A real beating heart is **chaotic**, not metronomic. Deepfakes often have perfect, looping, or non-existent pulses.
*   **The Tech:** Extracts R-R intervals and computes **Shannon Entropy**.
*   **Pass Condition:** Entropy > 0.25 (Indicates biological complexity).

### 3. Subsurface Scattering (SSS)
*   **The Concept:** Light penetrates real skin (red blurring), but reflects off screens/paper (sharp).
*   **The Tech:** Compares Laplacian variance of Red vs. Blue channels.
*   **Metric:** `SSS Ratio` (Blue Sharpness / Red Sharpness).
*   **Pass Condition:** Ratio > 0.88 (Adjusted for glasses/webcams).

### 4. Moiré Pattern Detection (Anti-Screen)
*   **The Concept:** Filming a screen creates interference patterns (grid lines) invisible to the naked eye but visible in Frequency Domain.
*   **The Tech:** 2D FFT looking for periodic peaks.
*   **Defense:** Triple penalty (-15 score) if detected.

### 5. Static Image Detection (**The "Photo Killer"**) 🛡️
*   **The Vulnerability:** High-definition photos passed SSS and sometimes rPPG (due to noise).
*   **The Defense:** We measure **Temporal Signal Variance** in the green channel over 3 seconds.
*   **Logic:**
    *   **Real Face:** Variance > 0.5% (Blood flow causes micro-flushing).
    *   **Photo:** Variance < 0.1% (Sensor noise only).
*   **Action:** If `is_static = True`, we **FORCE FAIL** (`is_human = False`) regardless of other scores.

### 6. BPM Stability Check
*   **The Vulnerability:** Random noise can sometimes look like a 120 BPM heart rate to a basic FFT.
*   **The Defense:** We track standard deviation of raw BPM readings.
*   **Pass Condition:** `StdDev < 15.0`. Real hearts don't jump 60->120->50 in seconds.

---

## 🔌 Integration Guide

### Interface (For Sohini & Jai)

The main entry point is `PrismEngine.process_frame`.

```python
from app.main import PrismEngine, LivenessResult

engine = PrismEngine()

# Call this for every video frame (approx 30 FPS)
result: LivenessResult = engine.process_frame(
    forehead_roi=cropped_numpy_array,  # From Jai's Face Mesh
    face_img=full_face_numpy_array,    # From Jai's Camera
    screen_color="RED"                 # From Srijan's React Frontend
)
```

### Output Object (`LivenessResult`)

```python
{
    "is_human": bool,        # MAIN DECISION: Pass this to Smart Contract
    "confidence": float,     # 0-100 Score
    "bpm": int,             # 72
    "signal_quality": float, # 0.85 (High reliability)
    "hrv_score": float,      # 1.45 (Good biological chaos)
    "details": {
        "bpm_stability_std": 2.1,      # Low = Good
        "signal_variance": 0.85,       # > 0.5 is Alive
        "static_image_penalty": 0,     # -50 if Photo
        "forced_false_reason": None    # "static_image_detected" if Photo
    }
}
```

---

## 🧪 How to Test (For the Team)

We have a built-in visual debugger.

**Command:**
```bash
uv run app/test_main.py
```
*(Press `q` to quit)*

### Understanding the HUD

![HUD Explanation](https://placehold.co/600x400?text=HUD+Layout)

1.  **BPM (Q: 0.XX)**
    *   **Green Text**: Good signal.
    *   **Q < 0.25**: Bad lighting or moving too much.
2.  **HRV Entropy**
    *   **> 1.0**: Excellent. You are definitely human.
    *   **< 0.5**: Suspicious.
3.  **Human: True/False (XX%)**
    *   This is the fused score. 50% is the pass threshold.
4.  **SSS | Var** (Bottom Line)
    *   `SSS`: Surface scattering. Needs to be > 0.88.
    *   `Var`: **Signal Variance**.
        *   **Real Face**: `0.50` to `3.00`
        *   **Photo**: `0.00` to `0.10` ❌ **(INSTANT FAIL)**

### Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| **Human: False** (Score ~30%) | Bad lighting | Turn on a lamp. Face the light. |
| **BPM Jumping** | Motion artifacts | Sit still. Camera shake kills rPPG. |
| **SSS (0.8 - 0.9)** | Glasses | Remove glasses if consistent failure. |
| **Var: 0.00** | Python Loop Speed | Ensure `test_main.py` is running at 30+ FPS. |

---

## 🚨 Anti-Spoofing Performance

| Attack Vector | Defeated By | Confidence Penalty |
|---------------|-------------|-------------------|
| **HD Photo (Print/Phone)** | Static Image Check | **-50 (Forced Fail)** |
| **Screen Replay (Video)** | Moiré Detection | **-45 (Triple Penalty)** |
| **Deepfake (Live)** | Temporal Latency (TODO) | N/A (Client/Server Check) |
| **Random Noise** | BPM Stability | **-30** |

---

**CC:** @Srijan (Frontend needs to send screen colors), @Sumit (Only mint NFT if `is_human=True`)
