import Toybox.Lang;

// Version without a map: no built-in route or streets.
// This file is replaced by tools/prepare_route.py when a route is prepared.
module RoutePack {
    const HAS_MAP = false;
    const NAME = "";
    const PACK_ID = "";
    const LAT0 = 0;
    const LON0 = 0;
    const TILE = 500;
    const CHUNKS = 0;

    function routeBin() {
        return null;
    }

    function chunk(i) {
        return null;
    }
}
