// Complete Functions Library representations; never installs or executes a binding.
// Reviewed against installed Arma 2.22 initFunctions SQF/SQFC, preserved with Packet A.
params ["_functionName", "_path", "_declaration", "_sources"];
private _refused = ["UNAVAILABLE", [], []];
if (!(_functionName isEqualType "") || {!(_path isEqualType "")}
    || {!(_declaration isEqualType configNull)} || {!isClass _declaration}
    || {!(_sources isEqualType [])} || {_sources isEqualTo []}
    || {!(_sources isEqualTypeAll "")}) exitWith {_refused};
private _meta = _functionName call BIS_fnc_functionMeta;
if (isNil "_meta" || {!(_meta isEqualType [])} || {count _meta != 9}) exitWith {_refused};
if !((_meta select [0, 2]) isEqualTypeAll "" && {(_meta # 2) isEqualType 0}
    && {(_meta select [3, 3]) isEqualTypeAll true} && {(_meta select [6, 3]) isEqualTypeAll ""}) exitWith {_refused};
private _tag = _meta # 6;
private _category = _meta # 7;
private _leaf = _meta # 8;
private _tagConfig = configFile >> "CfgFunctions" >> _tag;
private _categoryConfig = _tagConfig >> _category;
private _expectedDeclaration = _categoryConfig >> _leaf;
private _exportTag = getText (_tagConfig >> "tag");
if (_exportTag == "") then {_exportTag = _tag;};
if (_declaration isNotEqualTo _expectedDeclaration || {!isClass _expectedDeclaration}
    || {_functionName != _exportTag + "_fnc_" + _leaf}) exitWith {["DECLARATION", [], []]};
// Shared tag contributors are context, not owners of every sibling function.
// Keep target/category ownership; inherited attributes below check their actual node.
private _provenance = [_declaration, _categoryConfig, _tagConfig] apply {configSourceAddonList _x};
if (((_provenance select [0, 2]) findIf {(_x findIf {!(toLower _x in _sources)}) >= 0}) >= 0)
    exitWith {["PROVIDER", [], []]};
// Locate the class actually declaring a property, including class inheritance.
// Containment fallback for file is resolved separately, as in the library.
private _attributeOwner = {
    params ["_node", "_attribute"];
    private _owner = configNull;
    for "_depth" from 0 to 15 do {
        if (isNull _node) exitWith {};
        if ((configProperties [_node, "true", false] findIf {configName _x == _attribute}) >= 0)
            exitWith {_owner = _node;};
        _node = inheritsFrom _node;
    };
    _owner
};
private _attributes = [];
private _attributeRefused = false;
{
    _x params ["_node", "_attribute"];
    private _entry = _node >> _attribute;
    if (isText _entry || {isNumber _entry} || {isArray _entry} || {isClass _entry}) then {
        private _owner = [_node, _attribute] call _attributeOwner;
        private _providers = configSourceAddonList _owner;
        _attributes pushBack [str _node, _attribute, str _owner, _providers];
        if (isNull _owner || {_providers isEqualTo []}
            || {(_providers findIf {!(toLower _x in _sources)}) >= 0}) then {_attributeRefused = true;};
    };
} forEach ([[_tagConfig, "tag"]] + (["ext", "headerType", "preInit", "postInit", "recompile", "preStart", "cheatsEnabled"] apply {[_declaration, _x]}));
if (_attributeRefused) exitWith {["ATTRIBUTE_PROVIDER", [], []]};
private _declarations = [];
{
    {
        private _candidate = _x >> _leaf;
        if (isClass _candidate) then {_declarations pushBack str _candidate;};
    } forEach ("true" configClasses (_x >> "CfgFunctions" >> _tag));
} forEach [configFile, missionConfigFile, campaignConfigFile];
if (count _declarations != 1) exitWith {["DECLARATION_COUNT", [], []]};
private _extension = getText (_declaration >> "ext");
if (_extension == "") then {_extension = ".sqf";};
private _headerType = getNumber (_declaration >> "headerType");
private _declaredPath = getText (_declaration >> "file");
private _pathProviderIndex = 0;
if (_declaredPath == "") then {
    private _folder = getText (_categoryConfig >> "file");
    _pathProviderIndex = 1;
    if (_folder == "") then {_folder = getText (_tagConfig >> "file"); _pathProviderIndex = 2;};
    if (_folder != "") then {_declaredPath = _folder + "\fn_" + _leaf + _extension;};
};
// Empty structural leaves are not provider evidence. Review the node actually
// supplying file, even when the selected category/tag inherits that property.
private _pathNode = [_declaration, _categoryConfig, _tagConfig] # _pathProviderIndex;
private _pathOwner = [_pathNode, "file"] call _attributeOwner;
private _pathSources = configSourceAddonList _pathOwner;
if (isNull _pathOwner || {_pathSources isEqualTo []}) exitWith {["PROVIDER_UNAVAILABLE", [], []]};
if ((_pathSources findIf {!(toLower _x in _sources)}) >= 0) exitWith {["FILE_PROVIDER", [], []]};
_attributes pushBack [str _pathNode, "file", str _pathOwner, _pathSources];
if (_extension != ".sqf" || {(_meta # 1) != _extension} || {!(_headerType in [-1, 0, 1])}
    || {(_meta # 2) != _headerType}
    || {(_meta select [3, 3]) isNotEqualTo (["preInit", "postInit", "recompile"] apply {getNumber (_declaration >> _x) > 0})}
    || {toLower _declaredPath != toLower _path} || {toLower (_meta # 0) != toLower _path}
    || {getNumber (_declaration >> "preStart") != 0} || {getNumber (_declaration >> "cheatsEnabled") != 0}
    || {!fileExists _path}) exitWith {["CONTEXT", [], []]};
// UNAVAILABLE stays unavailable. We enumerate reviewed forms, not an inferred setting.
private _debugSetting = uiNamespace getVariable ["bis_fnc_initFunctions_debugMode", "UNAVAILABLE"];
private _patching = isFilePatchingEnabled;
private _context = ["LIBRARY_222_MISSION_COPY_V2", _functionName, _path, +_meta, str _declaration,
    +_sources, _provenance, _pathProviderIndex, _declarations, _debugSetting, _patching, _attributes];
private _key = "A3UE_FPV_bindingRepresentations_" + _functionName;
private _cached = localNamespace getVariable [_key, []];
if (!_patching && {count _cached == 2} && {(_cached # 0) isEqualTo _context}) exitWith {
    ["REVIEWED", _cached # 1, _context]
};
// Installed initFunctions.sqfc constants use LF in literal headers (confirmed by
// decoded constants AND engine character probe). Only generated line context is CRLF.
private _crlf = toString [13, 10];
private _lf = toString [10];
private _tab = toString [9];
private _noDebug = _lf + _tab + "private _fnc_scriptNameParent = if (isNil '_fnc_scriptName') then {'%1'} else {_fnc_scriptName};"
    + _lf + _tab + "private _fnc_scriptName = '%1';" + _lf + _tab + "scriptName _fnc_scriptName;" + _lf;
private _saveMap = _lf + _tab + "private _fnc_scriptMap = if (isNil '_fnc_scriptMap') then {[_fnc_scriptName]} else {_fnc_scriptMap + [_fnc_scriptName]};" + _lf;
private _logMap = _lf + _tab + "textLogFormat ['%1 : %2', _fnc_scriptMap joinString ' >> ', _this];" + _lf;
private _system = _lf + _tab + "private _fnc_scriptNameParent = if (isNil '_fnc_scriptName') then {'%1'} else {_fnc_scriptName};"
    + _lf + _tab + "scriptName '%1';" + _lf;
private _headers = switch (_headerType) do {
    case -1: {[""]};
    case 1: {[_system]};
    default {[_noDebug, _noDebug + _saveMap, _noDebug + _saveMap + _logMap]};
};
private _lineContext = format ["%4%1line 1 ""%2 [%3]""%4", "#", _meta # 0, _functionName, _crlf];
private _expected = [];
private _complete = true;
{
    private _compiled = compileScript [_meta # 0, false, format [_x, _functionName, "Log: [Functions]%1 | %2"] + _lineContext];
    private _direct = str _compiled;
    // initFunctions copies mutable mission functions with this exact operation.
    // The call evaluates only the outer Code literal; the function body is never run.
    if (count _direct <= 16 || {count _direct > 262144}) then {
        _complete = false;
    } else {
        private _copy = call compile _direct;
        private _missionCopy = if (!isNil "_copy" && {_copy isEqualType {}}) then {str _copy} else {""};
        if (count _missionCopy <= 16 || {count _missionCopy > 262144}) then {_complete = false;} else {
            _expected pushBackUnique _direct;
            _expected pushBackUnique _missionCopy;
        };
    };
} forEach _headers;
if (!_complete || {_expected isEqualTo []}) exitWith {_refused};
// File patching can change source/includes/SQFC without changing metadata. Never cache it.
localNamespace setVariable [_key, if (_patching) then {nil} else {[_context, _expected]}];
["REVIEWED", _expected, _context]
