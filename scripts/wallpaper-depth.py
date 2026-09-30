#!/usr/bin/env python3
"""
scripts/wallpaper-depth.py — Wallpaper Depth estimation and mask generator for xeon-shell.

Uses Depth Anything V2 Small (ONNX) to generate foreground alpha depth masks
for desktop wallpapers, allowing desktop widgets to appear behind foreground scenery.
"""

import argparse
import ctypes
import fcntl
import glob
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time

# Processing metadata
MODEL_REVISION = "4472b7362082ad9968fee890ca0f1e5aca36b93d"
PROCESSING_VERSION = "v1"
MODEL_FILENAME = "depth-anything-v2-small.onnx"
MODEL_URL = f"https://huggingface.co/onnx-community/depth-anything-v2-small/resolve/{MODEL_REVISION}/onnx/model.onnx"
MODEL_EXPECTED_SIZE = 99060839

# Standard directories (isolated from shell themes/lockscreen/greeter)
XDG_DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
XDG_CACHE_HOME = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")

DATA_DIR = os.path.join(XDG_DATA_HOME, "xeon-shell", "wallpaper-depth")
CACHE_DIR = os.path.join(XDG_CACHE_HOME, "xeon-shell", "wallpaper-depth")
MODEL_DIR = os.path.join(DATA_DIR, "models")
MODEL_PATH = os.path.join(MODEL_DIR, MODEL_FILENAME)
VENV_DIR = os.path.join(DATA_DIR, "venv")
VENV_PYTHON = os.path.join(VENV_DIR, "bin", "python")
VENV_PIP = os.path.join(VENV_DIR, "bin", "pip")

# Max cache size: 500 MB
MAX_CACHE_BYTES = 500 * 1024 * 1024
TARGET_CACHE_BYTES = 400 * 1024 * 1024


def setup_pdeathsig():
    """Ensure child process terminates automatically when parent process dies."""
    try:
        PR_SET_PDEATHSIG = 1
        libc = ctypes.CDLL("libc.so.6")
        libc.prctl(PR_SET_PDEATHSIG, 15)  # SIGTERM = 15
    except Exception:
        pass


def emit_json(data):
    """Emit a single-line JSON event to stdout and flush."""
    sys.stdout.write(json.dumps(data) + "\n")
    sys.stdout.flush()


def emit_error(msg):
    """Emit an error event to stdout and flush."""
    emit_json({"status": "error", "message": str(msg)})


def ensure_dirs():
    os.makedirs(DATA_DIR, exist_ok=True)
    os.makedirs(MODEL_DIR, exist_ok=True)
    os.makedirs(CACHE_DIR, exist_ok=True)


def get_cache_size():
    """Calculate total size in bytes of cache directory."""
    if not os.path.isdir(CACHE_DIR):
        return 0
    total = 0
    for dirpath, _, filenames in os.walk(CACHE_DIR):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if not os.path.islink(fp):
                try:
                    total += os.path.getsize(fp)
                except OSError:
                    pass
    return total


def format_bytes(size):
    for unit in ["B", "KB", "MB", "GB"]:
        if size < 1024.0:
            return f"{size:.1f} {unit}"
        size /= 1024.0
    return f"{size:.1f} TB"


def is_nvidia_available():
    """Check if an NVIDIA GPU is detected via nvidia-smi."""
    try:
        res = subprocess.run(["nvidia-smi"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return res.returncode == 0
    except FileNotFoundError:
        return False


def get_installed_status():
    """Check whether venv, packages, and model are installed."""
    if not os.path.isfile(MODEL_PATH) or os.path.getsize(MODEL_PATH) < 1000000:
        return {"installed": False, "gpuInstalled": False, "provider": "none"}
    if not os.path.isfile(VENV_PYTHON):
        return {"installed": False, "gpuInstalled": False, "provider": "none"}

    check_code = """
import sys
try:
    import numpy, PIL
except ImportError:
    sys.exit(2)
try:
    import onnxruntime as ort
    providers = ort.get_available_providers()
    is_gpu = "CUDAExecutionProvider" in providers
    sys.exit(0 if is_gpu else 1)
except ImportError:
    sys.exit(3)
"""
    try:
        res = subprocess.run([VENV_PYTHON, "-c", check_code], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if res.returncode == 0:
            return {"installed": True, "gpuInstalled": True, "provider": "CUDA"}
        elif res.returncode == 1:
            return {"installed": True, "gpuInstalled": False, "provider": "CPU"}
        else:
            return {"installed": False, "gpuInstalled": False, "provider": "none"}
    except Exception:
        return {"installed": False, "gpuInstalled": False, "provider": "none"}


def run_status():
    """Output JSON status."""
    stat = get_installed_status()
    has_nvidia = is_nvidia_available()
    cache_bytes = get_cache_size()

    emit_json({
        "status": "status",
        "installed": stat["installed"],
        "gpuInstalled": stat["gpuInstalled"],
        "hasNvidiaGpu": has_nvidia,
        "defaultProvider": stat["provider"],
        "cacheSizeBytes": cache_bytes,
        "cacheSizeFormatted": format_bytes(cache_bytes),
        "modelRevision": MODEL_REVISION,
        "processingVersion": PROCESSING_VERSION
    })


def preload_nvidia_libs(venv_path):
    """Preload nvidia shared libraries from pip packages so onnxruntime-gpu finds CUDA."""
    site_packages = glob.glob(os.path.join(venv_path, "lib", "python*", "site-packages"))
    if not site_packages:
        return
    sp = site_packages[0]
    nvidia_dirs = glob.glob(os.path.join(sp, "nvidia", "*", "lib"))
    if not nvidia_dirs:
        return

    # Add to LD_LIBRARY_PATH in os.environ
    cur_ld = os.environ.get("LD_LIBRARY_PATH", "")
    os.environ["LD_LIBRARY_PATH"] = ":".join(nvidia_dirs) + (":" + cur_ld if cur_ld else "")

    # Also explicitly load shared libraries with ctypes RTLD_GLOBAL
    for d in nvidia_dirs:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if ".so" in f:
                fp = os.path.join(d, f)
                try:
                    ctypes.CDLL(fp, mode=ctypes.RTLD_GLOBAL)
                except Exception:
                    pass


def download_model(report_install=False):
    """Download the ONNX model from Hugging Face with integrity checking."""
    ensure_dirs()
    if os.path.isfile(MODEL_PATH) and os.path.getsize(MODEL_PATH) == MODEL_EXPECTED_SIZE:
        return True

    tmp_path = MODEL_PATH + ".part"
    if report_install:
        emit_json({"status": "installing", "step": "Downloading model (~99 MB)...", "percent": 70})

    try:
        import urllib.request
        with urllib.request.urlopen(MODEL_URL) as response, open(tmp_path, "wb") as out_file:
            total_size = int(response.info().get("Content-Length", MODEL_EXPECTED_SIZE))
            downloaded = 0
            block_size = 1024 * 1024
            while True:
                buffer = response.read(block_size)
                if not buffer:
                    break
                downloaded += len(buffer)
                out_file.write(buffer)
                if report_install and total_size > 0:
                    pct = 70 + int((downloaded / total_size) * 25)
                    emit_json({"status": "installing", "step": f"Downloading model ({downloaded // (1024*1024)} / {total_size // (1024*1024)} MB)...", "percent": pct})

        actual_size = os.path.getsize(tmp_path)
        if actual_size < 90000000:
            raise RuntimeError(f"Downloaded model size {actual_size} too small (expected {MODEL_EXPECTED_SIZE})")

        os.replace(tmp_path, MODEL_PATH)
        return True
    except Exception as e:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass
        raise e


def run_install(gpu=False):
    """Install Python venv and dependencies."""
    ensure_dirs()
    emit_json({"status": "installing", "step": "Initializing isolated environment...", "percent": 5})

    # Step 1: Create venv if needed
    if not os.path.isfile(VENV_PYTHON):
        emit_json({"status": "installing", "step": "Creating virtual environment...", "percent": 15})
        res = subprocess.run([sys.executable, "-m", "venv", VENV_DIR], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if res.returncode != 0:
            emit_error(f"Failed to create venv: {res.stderr}")
            return False

    # Step 2: Install dependencies
    emit_json({"status": "installing", "step": "Installing Python dependencies...", "percent": 30})
    if gpu:
        # Uninstall CPU onnxruntime if present
        subprocess.run([VENV_PIP, "uninstall", "-y", "onnxruntime"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        pkgs = [
            "numpy", "Pillow",
            "onnxruntime-gpu==1.24.4",
            "nvidia-cuda-runtime-cu12", "nvidia-cublas-cu12",
            "nvidia-cudnn-cu12", "nvidia-cufft-cu12", "nvidia-curand-cu12"
        ]
    else:
        # Uninstall onnxruntime-gpu if present
        subprocess.run([VENV_PIP, "uninstall", "-y", "onnxruntime-gpu"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        pkgs = ["numpy", "Pillow", "onnxruntime"]

    proc = subprocess.Popen([VENV_PIP, "install"] + pkgs, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    while True:
        line = proc.stdout.readline()
        if not line and proc.poll() is not None:
            break
        if "Downloading" in line:
            emit_json({"status": "installing", "step": line.strip()[:60] + "...", "percent": 50})

    if proc.returncode != 0:
        emit_error(f"pip install exited with code {proc.returncode}")
        return False

    # Step 3: Download model
    try:
        download_model(report_install=True)
    except Exception as e:
        emit_error(f"Model download failed: {e}")
        return False

    emit_json({"status": "installing", "step": "Verifying installation...", "percent": 95})
    stat = get_installed_status()
    emit_json({
        "status": "ready",
        "installed": stat["installed"],
        "gpuInstalled": stat["gpuInstalled"],
        "activeProvider": stat["provider"],
        "message": "Installation successful"
    })
    return True


def prune_cache(wallpaper_dir=None):
    """Enforce total cache size cap, keeping wallpapers that still exist in wallpaper_dir."""
    current_size = get_cache_size()
    if current_size <= MAX_CACHE_BYTES:
        return

    # Collect existing wallpaper hashes if wallpaper_dir is provided
    keep_hashes = set()
    if wallpaper_dir and os.path.isdir(wallpaper_dir):
        try:
            for fname in os.listdir(wallpaper_dir):
                fpath = os.path.join(wallpaper_dir, fname)
                if os.path.isfile(fpath):
                    # compute first 64KB hash or full hash
                    try:
                        with open(fpath, "rb") as f:
                            h = hashlib.sha256(f.read()).hexdigest()[:16]
                            keep_hashes.add(h)
                    except Exception:
                        pass
        except Exception:
            pass

    # Find all cache entries
    entries = []
    for f in os.listdir(CACHE_DIR):
        if (f.startswith("depth_") and f.endswith(".npy")) or (f.startswith("mask_") and f.endswith(".png")):
            fp = os.path.join(CACHE_DIR, f)
            try:
                st = os.stat(fp)
                parts = f.split("_")
                img_hash = parts[1] if len(parts) > 1 else ""
                is_keep = img_hash in keep_hashes
                entries.append((st.st_atime, st.st_size, fp, is_keep))
            except OSError:
                pass

    # Sort least-recently used first, non-keep files first
    entries.sort(key=lambda x: (x[3], x[0]))

    for _, size, fp, is_keep in entries:
        if current_size <= TARGET_CACHE_BYTES:
            break
        if is_keep and current_size <= MAX_CACHE_BYTES:
            # Try not to evict active wallpapers unless strictly needed
            continue
        try:
            os.remove(fp)
            current_size -= size
        except OSError:
            pass


def run_clear_cache():
    """Clear all depth maps and masks from the cache directory."""
    if os.path.isdir(CACHE_DIR):
        for f in os.listdir(CACHE_DIR):
            if (f.startswith("depth_") and f.endswith(".npy")) or (f.startswith("mask_") and f.endswith(".png")):
                try:
                    os.remove(os.path.join(CACHE_DIR, f))
                except OSError:
                    pass
    emit_json({"status": "cleared", "cacheSizeBytes": 0, "cacheSizeFormatted": "0 B"})


def smoothstep_mask(depth, threshold, feather, target_w, target_h):
    """
    Compute foreground alpha coverage from normalized depth map using smoothstep.
    depth: 2D numpy float32 array in 0..1 (higher = nearer)
    threshold: 0..100 (default 30) -> t in 0..1
    feather: 0..50 (default 8) -> f in 0..0.25 (feather / 50 * 0.25)
    Returns: PIL Image (RGBA) with white RGB and alpha = foreground coverage.
    """
    import numpy as np
    from PIL import Image

    t = float(threshold) / 100.0
    f = (float(feather) / 50.0) * 0.25

    e0 = t - f
    e1 = t + f

    # Upsample depth map to target resolution capped to max display long edge
    depth_img = Image.fromarray(depth, mode="F")
    depth_resized = depth_img.resize((target_w, target_h), Image.Resampling.BICUBIC)
    depth_up = np.array(depth_resized, dtype=np.float32)

    if e1 > e0:
        x = np.clip((depth_up - e0) / (e1 - e0), 0.0, 1.0)
        alpha = x * x * (3.0 - 2.0 * x)
    else:
        alpha = (depth_up >= t).astype(np.float32)

    # Output RGBA mask: white RGB (255, 255, 255), alpha = foreground coverage (0..255)
    rgba = np.zeros((target_h, target_w, 4), dtype=np.uint8)
    rgba[..., 0:3] = 255
    rgba[..., 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)

    return Image.fromarray(rgba, mode="RGBA")


def run_generate(wallpaper_path, threshold=30, feather=8, device="cpu", wallpaper_dir=None):
    """
    Generate depth map and alpha mask for a single wallpaper.
    Runs inside the venv or re-executes inside venv if running with system python.
    """
    if not os.path.isfile(wallpaper_path):
        emit_error(f"Wallpaper file not found: {wallpaper_path}")
        return False

    # Check file size & readability
    try:
        with open(wallpaper_path, "rb") as f:
            content = f.read()
            wallpaper_hash = hashlib.sha256(content).hexdigest()[:16]
    except Exception as e:
        emit_error(f"Cannot read wallpaper file {wallpaper_path}: {e}")
        return False

    ensure_dirs()

    depth_cache_file = os.path.join(CACHE_DIR, f"depth_{wallpaper_hash}_{MODEL_REVISION[:8]}_{PROCESSING_VERSION}.npy")
    mask_cache_file = os.path.join(CACHE_DIR, f"mask_{wallpaper_hash}_{MODEL_REVISION[:8]}_{PROCESSING_VERSION}_t{threshold}_f{feather}.png")

    # 1. Cache HIT on Mask:
    if os.path.isfile(mask_cache_file) and os.path.getsize(mask_cache_file) > 0:
        try:
            # Update access time for LRU
            os.utime(mask_cache_file, None)
        except OSError:
            pass
        emit_json({
            "status": "ready",
            "wallpaper": wallpaper_path,
            "mask": mask_cache_file,
            "cacheHit": True,
            "activeProvider": "cached"
        })
        return True

    # Need venv libraries
    try:
        import numpy as np
        from PIL import Image, ImageOps
        import onnxruntime as ort
    except ImportError:
        emit_error("Required libraries (numpy, PIL, onnxruntime) not found. Please install first.")
        return False

    # Open image
    try:
        raw_img = Image.open(wallpaper_path)
        raw_img = ImageOps.exif_transpose(raw_img).convert("RGB")
        orig_w, orig_h = raw_img.size
    except Exception as e:
        emit_error(f"Unreadable or unsupported image format {wallpaper_path}: {e}")
        return False

    # Resolution cap: max output long edge = 2560 px
    max_edge = min(max(orig_w, orig_h), 2560)
    cap_scale = max_edge / max(orig_w, orig_h)
    target_w = max(16, int(round(orig_w * cap_scale)))
    target_h = max(16, int(round(orig_h * cap_scale)))

    active_provider = "CPU"

    # 2. Check depth map cache
    if os.path.isfile(depth_cache_file):
        try:
            depth = np.load(depth_cache_file)
            cache_hit_type = "depth"
            active_provider = "cached_depth"
        except Exception:
            depth = None
            cache_hit_type = False
    else:
        depth = None
        cache_hit_type = False

    # 3. Model Inference (if depth map not cached)
    if depth is None:
        if not os.path.isfile(MODEL_PATH):
            emit_error("Depth Anything V2 ONNX model not found. Please click Install in Settings.")
            return False

        # Input preprocessing: resize aspect-preserving to multiple of 14, max 518
        max_model_size = 518
        scale = max_model_size / max(orig_w, orig_h)
        new_w = max(14, int(round(orig_w * scale / 14.0)) * 14)
        new_h = max(14, int(round(orig_h * scale / 14.0)) * 14)
        resized = raw_img.resize((new_w, new_h), Image.Resampling.BILINEAR)

        img_np = np.array(resized, dtype=np.float32) / 255.0
        mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
        std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
        norm_img = (img_np - mean) / std
        input_tensor = np.transpose(norm_img, (2, 0, 1))[np.newaxis, ...]

        # Provider selection
        providers = []
        if device == "gpu":
            providers = ["CUDAExecutionProvider"]
        elif device == "auto":
            providers = ["CUDAExecutionProvider", "CPUExecutionProvider"]
        else:
            providers = ["CPUExecutionProvider"]

        try:
            session = ort.InferenceSession(MODEL_PATH, providers=providers)
            actual_providers = session.get_providers()
            active_provider = actual_providers[0] if actual_providers else "CPU"
            if device == "gpu" and "CUDAExecutionProvider" not in actual_providers:
                emit_error("CUDA Execution Provider requested but unavailable.")
                return False
        except Exception as e:
            if device == "auto":
                # Fallback to CPU
                session = ort.InferenceSession(MODEL_PATH, providers=["CPUExecutionProvider"])
                active_provider = "CPUExecutionProvider (CUDA fallback: " + str(e) + ")"
            else:
                emit_error(f"Failed to initialize ONNX session with {device}: {e}")
                return False

        # Run inference
        try:
            outputs = session.run(["predicted_depth"], {"pixel_values": input_tensor})
            raw_depth = outputs[0][0]  # shape (H, W)
            # Normalize to 0..1 (higher = nearer)
            d_min = float(raw_depth.min())
            d_max = float(raw_depth.max())
            depth = ((raw_depth - d_min) / (d_max - d_min + 1e-8)).astype(np.float32)

            # Save depth map cache atomically
            tmp_depth = depth_cache_file + ".tmp.npy"
            np.save(tmp_depth, depth)
            os.replace(tmp_depth, depth_cache_file)
        except Exception as e:
            emit_error(f"Inference failed: {e}")
            return False

    # 4. Generate and save alpha mask PNG
    try:
        mask_img = smoothstep_mask(depth, threshold, feather, target_w, target_h)
        tmp_mask = mask_cache_file + ".tmp.png"
        mask_img.save(tmp_mask, "PNG", compress_level=1)
        os.replace(tmp_mask, mask_cache_file)
    except Exception as e:
        emit_error(f"Failed to save mask: {e}")
        return False

    prune_cache(wallpaper_dir)

    emit_json({
        "status": "ready",
        "wallpaper": wallpaper_path,
        "mask": mask_cache_file,
        "cacheHit": cache_hit_type,
        "activeProvider": active_provider
    })
    return True


def run_pregenerate(wallpaper_dir, threshold=30, feather=8, device="cpu"):
    """Pre-generate masks for all still images in wallpaper_dir at low priority."""
    if not os.path.isdir(wallpaper_dir):
        emit_error(f"Wallpaper directory not found: {wallpaper_dir}")
        return False

    extensions = (".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tiff", ".avif", ".heic", ".heif")
    candidates = []
    try:
        for f in sorted(os.listdir(wallpaper_dir)):
            fp = os.path.join(wallpaper_dir, f)
            if os.path.isfile(fp) and f.lower().endswith(extensions):
                candidates.append(fp)
    except Exception as e:
        emit_error(f"Failed to scan wallpaper directory: {e}")
        return False

    total = len(candidates)
    if total == 0:
        emit_json({"status": "pregenerate_done", "total": 0, "processed": 0})
        return True

    emit_json({"status": "pregenerate_start", "total": total})

    processed = 0
    for idx, fpath in enumerate(candidates, 1):
        emit_json({
            "status": "progress",
            "current": idx,
            "total": total,
            "file": os.path.basename(fpath)
        })
        try:
            success = run_generate(fpath, threshold=threshold, feather=feather, device=device, wallpaper_dir=wallpaper_dir)
            if success:
                processed += 1
        except Exception:
            pass

    emit_json({"status": "pregenerate_done", "total": total, "processed": processed})
    return True


def main():
    setup_pdeathsig()

    parser = argparse.ArgumentParser(description="Wallpaper Depth processor for xeon-shell")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("status")

    install_parser = subparsers.add_parser("install")
    install_parser.add_argument("--gpu", action="store_true", help="Install GPU CUDA support")

    subparsers.add_parser("clear-cache")

    gen_parser = subparsers.add_parser("generate")
    gen_parser.add_argument("wallpaper", help="Path to original wallpaper file")
    gen_parser.add_argument("--threshold", type=int, default=30, help="Depth threshold (0-100, default 30)")
    gen_parser.add_argument("--feather", type=int, default=8, help="Edge feather (0-50, default 8)")
    gen_parser.add_argument("--device", choices=["cpu", "auto", "gpu"], default="cpu", help="Compute device")
    gen_parser.add_argument("--wallpaper-dir", default=None, help="Wallpaper folder to protect during cache pruning")

    pregen_parser = subparsers.add_parser("pregenerate")
    pregen_parser.add_argument("wallpaper_dir", help="Wallpaper directory")
    pregen_parser.add_argument("--threshold", type=int, default=30)
    pregen_parser.add_argument("--feather", type=int, default=8)
    pregen_parser.add_argument("--device", choices=["cpu", "auto", "gpu"], default="cpu")

    args = parser.parse_args()

    if not args.command or args.command == "status":
        run_status()
        return

    if args.command == "install":
        run_install(gpu=args.gpu)
        return

    if args.command == "clear-cache":
        run_clear_cache()
        return

    # For generate and pregenerate: ensure we run inside the venv if venv exists
    is_inside_venv = sys.prefix == VENV_DIR
    if not is_inside_venv and os.path.isfile(VENV_PYTHON):
        # Re-execute under venv python with same arguments
        preload_nvidia_libs(VENV_DIR)
        cmd = [VENV_PYTHON, __file__] + sys.argv[1:]
        proc = subprocess.Popen(cmd, stdout=sys.stdout, stderr=sys.stderr)
        try:
            sys.exit(proc.wait())
        except KeyboardInterrupt:
            proc.terminate()
            sys.exit(130)

    # Inside venv: preload nvidia libs
    preload_nvidia_libs(VENV_DIR)

    if args.command == "generate":
        # Acquire lock to ensure single generation at a time
        lock_file_path = os.path.join(CACHE_DIR, "generate.lock")
        ensure_dirs()
        with open(lock_file_path, "w") as lock_file:
            try:
                fcntl.flock(lock_file, fcntl.LOCK_EX)
                run_generate(args.wallpaper, threshold=args.threshold, feather=args.feather, device=args.device, wallpaper_dir=args.wallpaper_dir)
            finally:
                fcntl.flock(lock_file, fcntl.LOCK_UN)

    elif args.command == "pregenerate":
        wallpaper_dir = os.path.expanduser(args.wallpaper_dir)
        run_pregenerate(wallpaper_dir, threshold=args.threshold, feather=args.feather, device=args.device)


if __name__ == "__main__":
    main()
