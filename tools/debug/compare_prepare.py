"""Prints the gist files that prepare_route.py makes for a GPX, as JSON (see compare_prepare.js)."""
import contextlib
import io
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import prepare_route as pr  # noqa: E402


class Options:
    width = 300
    points = 0
    reverse = False
    flip_start = False


with contextlib.redirect_stdout(io.StringIO()):
    r = pr.prepare_one(sys.argv[1], "x", Options)
binary = pr.route_binary(r["route"])
print(json.dumps(pr.route_files(binary, pr.tile_chunks(r["tiles"]), "x")))
