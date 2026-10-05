"""build_sw.py - create the Vitis platform + application for one bitstream.

Run with the Vitis Python interpreter:
    vitis -s build_sw.py drhe        (or lpc)
Produces ../build/vitis_<algo>/radar_app/build/radar_app.elf and copies it to
../out/radar_app_<algo>.elf
"""
import os, sys, shutil, glob
import vitis

algo = sys.argv[1] if len(sys.argv) > 1 else "drhe"
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.normpath(os.path.join(here, ".."))
xsa = os.path.join(root, "out", f"kcu116_{algo}.xsa")
ws = os.path.join(root, "build", f"vitis_{algo}")
src = os.path.join(here, "src")
if not os.path.exists(xsa):
    sys.exit(f"missing {xsa} - run vivado/build.bat {algo} first")
if os.path.exists(ws):
    shutil.rmtree(ws)
os.makedirs(ws)

client = vitis.create_client()
client.set_workspace(path=ws)

plat = client.create_platform_component(name="kcu116_plat", hw_design=xsa,
                                        os="standalone", cpu="microblaze_0",
                                        domain_name="standalone_microblaze_0")
plat.build()
xpfm = os.path.join(ws, "kcu116_plat", "export", "kcu116_plat", "kcu116_plat.xpfm")

app = client.create_app_component(name="radar_app", platform=xpfm,
                                  domain="standalone_microblaze_0",
                                  template="empty_application")
files = ["main.c", "board_map.h"]
try:
    app.import_files(from_loc=src, files=files, dest_dir_in_cmp="src")
except Exception as e:  # older/newer API: fall back to copying into src/
    print("import_files failed (%s); copying sources directly" % e)
    dst = os.path.join(ws, "radar_app", "src")
    os.makedirs(dst, exist_ok=True)
    for f in files:
        shutil.copy(os.path.join(src, f), dst)
app.build()

elfs = glob.glob(os.path.join(ws, "radar_app", "build", "*.elf"))
if not elfs:
    sys.exit("no ELF produced - see the build output above")
os.makedirs(os.path.join(root, "out"), exist_ok=True)
shutil.copy(elfs[0], os.path.join(root, "out", f"radar_app_{algo}.elf"))
print("ELF:", os.path.join(root, "out", f"radar_app_{algo}.elf"))
client.close()
