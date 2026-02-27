# ray_sphere
# ==========
# Casts rays through a pixel grid against a scene of spheres using
# integer distance checks. Accumulates per-pixel shading into a
# checksum. Stresses nested loops, arithmetic, and list traversal.

# Types
# -----

type Sphere() {
  sphere{U32, U32, U32}
}

type Scene() {
  snil{}
  scons{Sphere, Scene}
}

# Utils
# -----

# Returns the absolute difference of two U32 values (branchless)
def abs_diff(a: U32, b: U32) -> U32:
  ge = a >= b
  ge * (a - b) + (1 - ge) * (b - a)

# Scene
# -----

# Builds a scene with 5 spheres at fixed positions
def build_scene() -> Scene:
  scons{sphere{128, 128, 80},
  scons{sphere{300, 200, 60},
  scons{sphere{200, 350, 70},
  scons{sphere{400, 100, 50},
  scons{sphere{350, 400, 90},
  snil{}}}}}}

# Shading
# -------

# Computes shade contribution from one sphere at pixel (x, y).
# Returns r^2 - d^2 if hit, 0 if miss.
def sphere_shade(x: U32, y: U32, s: Sphere) -> U32:
  match s:
    case sphere{cx, cy, r}:
      dx  = abs_diff(x, cx)
      dy  = abs_diff(y, cy)
      d2  = dx * dx + dy * dy
      r2  = r * r
      hit = d2 <= r2
      hit * (r2 - d2)

# Sums shade contributions from all spheres in the scene
def pixel_shade(x: U32, y: U32, scene: Scene, acc: U32) -> U32:
  match scene:
    case snil{}:
      acc
    case scons{s, rest}:
      val = sphere_shade(x, y, s)
      pixel_shade(x, y, rest, acc + val)

# Image Loop
# ----------

# Iterates over one row of pixels (y from h down to 1)
def row(x: U32, y: U32, scene: Scene, acc: U32) -> U32:
  match y:
    case 0:
      acc
    case j:
      val = pixel_shade(x, j, scene, 0)
      acc = (acc ^ val) * 16777619 + 2166136261
      row(x, j - 1, scene, acc)

# Iterates over columns (x from w down to 1)
def image(x: U32, h: U32, scene: Scene, acc: U32) -> U32:
  match x:
    case 0:
      acc
    case i:
      acc = row(i, h, scene, acc)
      image(i - 1, h, scene, acc)

# Main
# ----

# Entry point
def main() -> U32:
  scene = build_scene()
  image(3780, 3780, scene, 0)
