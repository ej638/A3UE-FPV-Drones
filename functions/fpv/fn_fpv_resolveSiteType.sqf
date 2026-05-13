params [["_markerX", ""], ["_locationType", ""]];

if (!isNil "airportsX" && {_markerX in airportsX}) exitWith {"Airport"};
if (!isNil "milbases" && {_markerX in milbases}) exitWith {"Milbase"};
if (!isNil "seaports" && {_markerX in seaports}) exitWith {"Seaport"};
if (!isNil "outposts" && {_markerX in outposts}) exitWith {"Outpost"};
if (!isNil "factories" && {_markerX in factories}) exitWith {"Factory"};
if (!isNil "resourcesX" && {_markerX in resourcesX}) exitWith {"Resource"};

if (_locationType in ["Airport", "Milbase", "Seaport", "Outpost", "Factory", "Resource"]) exitWith {
	_locationType
};

""