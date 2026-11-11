// Loaded AU source, cached locally; this returns code and never executes an attack.
params ["_name"];

private _category = switch (_name) do {
    case "singleAttack";
    case "wavedAttack";
    case "attackHQ";
    case "invaderPunish": {"CREATE"};
    case "showInterceptedSetupCall";
    case "showInterceptedSupportCall": {"Supports"};
    default {""};
};
if (_category isEqualTo "") exitWith {{}};

private _cacheKey = "A3UE_FPV_stockAU_" + _name;
private _stock = localNamespace getVariable _cacheKey;
if (isNil "_stock") then {
    private _path = format ["\x\A3A\addons\core\functions\%1\fn_%2.sqf", _category, _name];
    _stock = compileScript [_path, true];
    localNamespace setVariable [_cacheKey, _stock];
};
_stock
