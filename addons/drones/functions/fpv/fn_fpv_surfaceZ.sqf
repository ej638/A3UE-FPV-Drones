// ASL height of the surface a low-flying drone must clear at [x, y] (EN-02 design section 4.2, section 7.5):
// the terrain, or over the sea its surface (waves and tide included) plus a 0.5 m wave margin.
// Pure read, no state. Callers on hot paths read getTerrainHeightASL first and only ask here near
// sea level.
// [x, y] -> z ASL
params [["_x0", 0], ["_y0", 0]];
private _z = getTerrainHeightASL [_x0, _y0];
if (surfaceIsWater [_x0, _y0]) then {_z = _z max (((AGLToASL [_x0, _y0, 0]) # 2) + 0.5);};
_z
