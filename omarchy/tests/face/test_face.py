"""Tests the decision logic of xps-face with a fake camera and fake model (no camera or models needed)."""
import importlib.machinery, importlib.util, json, os, sys, tempfile, time, types

home = tempfile.mkdtemp()
os.environ["HOME"] = home
loader = importlib.machinery.SourceFileLoader("xf", sys.argv[1])
spec = importlib.util.spec_from_loader("xf", loader)
xf = importlib.util.module_from_spec(spec)
loader.exec_module(xf)
import numpy as np

fails = 0
def check(name, cond):
    global fails
    print(("PASS: " if cond else "FAIL: ") + name)
    fails |= (not cond)

class FakeCam:
    def __init__(self, frames): self.frames = list(frames); self.released = False
    def read(self):
        return (True, self.frames.pop(0)) if self.frames else (True, None)
    def release(self): self.released = True

class FakeEngine:
    cv = types.SimpleNamespace()
    def feature(self, frame):
        return None if frame is None else np.array([frame], dtype="float32")   # a "frame" is just the vector
    def score(self, a, b):
        a, b = a.ravel(), b.ravel()
        return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))

me = [1.0, 0.0, 0.0, 0.0]
other = [0.0, 1.0, 0.0, 0.0]
xf.VERIFY_SECONDS = 0.5

# nothing enrolled -> "not ready" (2), never a pass
check("no saved face -> 2", xf.verify(FakeEngine(), FakeCam([me] * 5)) == 2)

os.makedirs(xf.DATA, exist_ok=True)
json.dump([me], open(xf.FEATURES, "w"))
check("same face -> 0", xf.verify(FakeEngine(), FakeCam([me] * 10)) == 0)
check("other face -> 1", xf.verify(FakeEngine(), FakeCam([other] * 10)) == 1)
check("no face in view -> 1", xf.verify(FakeEngine(), FakeCam([None] * 10)) == 1)
check("only 2 good frames is not enough -> 1", xf.verify(FakeEngine(), FakeCam([me, me] + [other] * 8)) == 1)
cam = FakeCam([me] * 10); xf.verify(FakeEngine(), cam)
check("camera is released", cam.released)
# no camera at all -> 2 (the lock falls back to the recovery code)
xf.open_camera = lambda cv2: None
check("no camera -> 2", xf.verify(FakeEngine()) == 2)
check("status works without models", xf.main(["xps-face", "status"]) == 0)
check("remove deletes data", xf.main(["xps-face", "remove"]) == 0 and not os.path.exists(xf.FEATURES))
sys.exit(fails)
