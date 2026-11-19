// Loaded AU source, cached locally; this returns code and never executes an attack.
// 1.0.9 (SW-2): also the five commander-menu functions our SCRT wrappers replace (AU's scrt addon).
params ["_name"];

private _category = switch (_name) do {
    case "singleAttack";
    case "wavedAttack";
    case "attackHQ";
    case "invaderPunish": {"CREATE"};
    case "showInterceptedSetupCall";
    case "showInterceptedSupportCall": {"Supports"};
    case "ui_updateSupportMenu";
    case "ui_setSupportCostText";
    case "ui_manageSupportTabEventHandler";
    case "ui_launchSupport";
    case "ui_clearSupport": {"SCRT_UI"};
    default {""};
};
if (_category isEqualTo "") exitWith {{}};

private _cacheKey = "A3UE_FPV_stockAU_" + _name;
private _stock = localNamespace getVariable _cacheKey;
if (isNil "_stock") then {
    private _path = if (_category isEqualTo "SCRT_UI") then {
        format ["\x\A3A\addons\scrt\UI\fn_%1.sqf", _name]
    } else {
        format ["\x\A3A\addons\core\functions\%1\fn_%2.sqf", _category, _name]
    };
    _stock = compileScript [_path, true];
    localNamespace setVariable [_cacheKey, _stock];
};
_stock
