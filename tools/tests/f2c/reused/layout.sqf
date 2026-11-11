// Pure checks plus one bounded static-object lookup, only before flight.
// [schema,world,size,review,start,dir,cover,dir,exposure,dir,B,dir,[model,ASL,dir]]
params ["_recipe",["_requireReview",true]];
if !(_recipe isEqualType [] && {count _recipe == 13}) exitWith {[false,"RECIPE_SCHEMA"]};
if (_recipe # 0 != 1 || {_recipe # 1 != worldName} || {_recipe # 2 != worldSize}
    || {worldName != "vt7"} || {_requireReview && {_recipe # 3 == "UNREVIEWED"}}) exitWith {[false,"RECIPE_WORLD_OR_REVIEW"]};
// The selected start anchors this bounded layout; the old open field is not a world-wide anchor.
private _start = _recipe # 4;
if (!(_start isEqualType []) || {count _start != 3}
    || {(_start findIf {!(_x isEqualType 0) || {!finite _x}}) >= 0}
    || {_start # 0 < 0} || {_start # 1 < 0}
    || {_start # 0 > worldSize} || {_start # 1 > worldSize}) exitWith {[false,"RECIPE_START"]};
private _positions = [4,10]; if (_requireReview) then {_positions append [6,8];};
private _bad = _positions findIf {
    private _p = _recipe # _x;
    !(_p isEqualType []) || {count _p != 3} || {(_p findIf {!(_x isEqualType 0) || {!finite _x}}) >= 0}
        || {_p # 0 < 0} || {_p # 1 < 0} || {_p # 0 > worldSize} || {_p # 1 > worldSize}
        || {_p distance2D _start > 100} || {abs (_p # 2) > 0.5} || {surfaceIsWater _p}
};
if (_bad >= 0 || {([5,7,9,11] findIf {!((_recipe # _x) isEqualType 0) || {!finite (_recipe # _x)} || {abs (_recipe # _x) > 360}}) >= 0}) exitWith {[false,"RECIPE_POSITION_OR_DIRECTION"]};
if ((_recipe # 4) distance2D (_recipe # 10) < 20) exitWith {[false,"RECIPE_B_SEPARATION"]};
if (_requireReview) then {
    private _meta = _recipe # 12;
    if (!(_meta isEqualType []) || {count _meta != 3}) exitWith {_bad = 1;};
    if (!((_meta # 0) isEqualType "") || {_meta # 0 == ""}
        || {!((_meta # 1) isEqualType [])} || {count (_meta # 1) != 3}
        || {((_meta # 1) findIf {!(_x isEqualType 0) || {!finite _x}}) >= 0}
        || {!((_meta # 2) isEqualType 0)} || {!finite (_meta # 2)}
        || {(_recipe # 4) distance2D (_recipe # 6) > 60}
        || {(_recipe # 6) distance2D (_recipe # 8) > 80}
        || {(_recipe # 6) distance2D (ASLToATL (_meta # 1)) > 25}) exitWith {_bad = 1;};
    private _objects = nearestTerrainObjects [ASLToATL (_meta # 1),[],3];
    _objects append (nearestObjects [ASLToATL (_meta # 1),["House","Wall"],3]);
    if ((_objects findIf {(getModelInfo _x) # 1 == _meta # 0 && {getPosASL _x distance (_meta # 1) < 0.75}
        && {abs (getDir _x - (_meta # 2)) < 2}}) < 0) then {_bad = 1;};
};
[_bad < 0,if (_bad < 0) then {"VALID"} else {"STALE_COVER_METADATA"}]
