params [
	["_target", objNull],
	["_impactMode", "NONE"],
	["_reason", "NONE"]
];

if !(_impactMode isEqualType "") then {
	_impactMode = "NONE";
};

if !(_reason isEqualType "") then {
	_reason = "NONE";
};

createHashMapFromArray [
	["valid", false],
	["impactMode", _impactMode],
	["impactPointASL", []],
	["surfaceType", "none"],
	["surfaceObject", objNull],
	["targetNetId", if (isNull _target) then {""} else {netId _target}],
	["reason", _reason],
	["fallbackAllowed", true],
	["fallbackRadius", 0],
	["updatedAt", time]
]