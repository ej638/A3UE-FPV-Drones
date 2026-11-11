params [["_path", [], [[]]], ["_allowEmpty", false, [true]]];
count _path <= 256 && {_allowEmpty || {count _path > 0}} && {
    _path findIf {
        !(_x isEqualType []) || {count _x != 3} || {_x findIf {!(_x isEqualType 0) || {!finite _x} || {abs _x > 1000000}} >= 0}
    } < 0
}
