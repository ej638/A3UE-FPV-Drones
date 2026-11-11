"""Focused source contracts and representation/transport models, NOT Arma execution.

PACKET_A_LIBRARY may point at the preserved installed initFunctions.sqf. Its exact
headers and mission-copy route are checked against shipped SQF and decoded
installed SQFC constants, with no whitespace normalization. Engine compilation and actual RPT transport remain separate gates.
"""
import json
import os
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
FPV = ROOT/'addons/drones/functions/fpv'
REP = (FPV/'fn_fpv_bindingRepresentations.sqf').read_text()
MATCH = (FPV/'fn_fpv_hookBindingMatches.sqf').read_text()
REPORT = (FPV/'fn_fpv_reportAUAdapter.sqf').read_text()
PROBE = (ROOT/'tools/tests/ua_dive/bindings.sqf').read_text()


def authored_headers():
    """Evaluate only the five literal concatenations in the shipped helper."""
    values = {'_crlf': '\r\n', '_lf': '\n', '_tab': '\t'}
    for name in ['_noDebug', '_saveMap', '_logMap', '_system']:
        # Semicolons can occur inside SQF strings, so tokenize string atoms first.
        tail = REP.split('private ' + name + ' = ', 1)[1]
        atoms = re.match(r'((?:"(?:[^"]|"")*"|_\w+|\s|\+)+);', tail)[1]
        tokens = re.findall(r'"((?:[^"]|"")*)"|(_\w+)', atoms)
        values[name] = ''.join(literal.replace('""', '"') if var == '' else values[var]
                              for literal, var in tokens)
    return values


def sqf_format(text, name='A3A_fnc_SUP_FPVAvailable'):
    # Simultaneous substitution, as format does not re-expand inserted % tokens.
    return re.sub(r'%([12])', lambda m: name if m[1] == '1' else 'Log: [Functions]%1 | %2', text)


def wire(value):
    if isinstance(value, str): return '"' + value.replace('"', '""') + '"'
    if isinstance(value, bool): return str(value).lower()
    if isinstance(value, list): return '[' + ','.join(map(wire, value)) + ']'
    return str(value)


def emitter_model(record):
    # The contract explicitly reads _this, never only its first parameter.
    assert 'private _text = str _this;' in REPORT
    text = wire(record).replace('\r', ' ').replace('\n', ' ')
    limit, keep = map(int, re.search(r'count _text > (\d+).*?select \[0, (\d+)\]', REPORT, re.S).groups())
    if len(text) > limit:
        text = text[:keep] + f' <TRUNCATED originalChars={len(text)}; full details in A3UE_FPV_auAdapterReport>'
    return text


class PacketABindings(unittest.TestCase):
    def test_authored_success_cache_gate_invalidates_replacements_and_context(self):
        gate = re.search(r'if \((!isFilePatchingEnabled.*?)\) then', MATCH, re.S)[1]
        for old,new in [('!isFilePatchingEnabled','not patching'),('count _checked','len(checked)'),
                        ('(_checked # 0)','checked[0]'),('(_checked # 1)','checked[1]'),
                        ('_actual','actual'),('_context','context'),('isEqualTo','=='),
                        ('&&',' and '),('{','('),('}',')')]:
            gate = gate.replace(old,new)
        def qualifies(checked,actual='complete original',context=('path','provider','meta','debug'),patching=False):
            return eval(' '.join(gate.split()),{'__builtins__':{},'len':len},locals())
        good = ['complete original',('path','provider','meta','debug')]
        self.assertTrue(qualifies(good))
        self.assertFalse(qualifies(good,actual='changed executable; same path'))
        self.assertFalse(qualifies(good,context=('path','foreign','meta','debug')))
        self.assertFalse(qualifies(good,context=('path','provider','meta','new debug')))
        self.assertFalse(qualifies(good,patching=True))
        self.assertFalse(qualifies([]))

    def test_exact_installed_headers_and_line_context(self):
        path = os.environ.get('PACKET_A_LIBRARY')
        if not path: self.skipTest('Installed library reference not supplied; run with PACKET_A_LIBRARY')
        library = Path(path).read_bytes().decode('utf-8')
        generated = authored_headers()
        for ours, theirs in [('_noDebug','_headerNoDebug'), ('_saveMap','_headerSaveScriptMap'),
                            ('_logMap','_headerLogScriptMap'), ('_system','_headerSystem')]:
            expected = re.search(r'private ' + theirs + r' = "(.*?)";', library, re.S)[1]
            # Exported source uses CRLF; actual SQFC constants below establish LF.
            self.assertEqual(generated[ours], expected.replace('\r\n', '\n'))
        context = 'format ["%4%1line 1 ""%2 [%3]""%4", "#",'
        self.assertIn(context, library)
        self.assertIn(context, REP)
        self.assertIn('compileScript [_meta # 0, false, format [_x, _functionName, "Log: [Functions]%1 | %2"] + _lineContext]', REP)
        self.assertIn('_xCode = call compile str (uinamespace getvariable _x);', library)
        self.assertIn('private _copy = call compile _direct;', REP)
        data_path = os.environ.get('PACKET_A_LIBRARY_CONSTANTS')
        if not data_path: self.fail('Decoded installed SQFC constants required with the library reference')
        literals = json.loads(Path(data_path).read_text())['library:initFunctions.sqfc']['header_literals']
        self.assertEqual([generated[k] for k in ['_noDebug','_saveMap','_logMap','_system']], literals)
        self.assertTrue(literals[0].startswith('\n\t'))
        self.assertNotIn('\r', literals[0])

    def test_complete_reviewed_forms_refuse_body_edits_and_unknown_headers(self):
        h = authored_headers()
        headers = ['', h['_system'], h['_noDebug'], h['_noDebug']+h['_saveMap'],
                   h['_noDebug']+h['_saveMap']+h['_logMap']]
        body = 'params ["_value"]; _value + 41001;'
        # Model exact complete representation equality, not the Arma compiler.
        forms = ['{' + sqf_format(x) + '\r\n#line 1 "path [name]"\r\n' + body + '}' for x in headers]
        for effective in forms:
            self.assertIn(effective, forms)
            self.assertNotIn(effective.replace('41001', '41002'), forms)
            self.assertNotIn('{private _unknown = true;' + effective[1:], forms)
            self.assertNotIn(effective + 'foreign', forms)
        self.assertIn('_expected findIf {_x isEqualTo _actual}', MATCH)
        self.assertNotIn('select [count _actual', MATCH)
        self.assertNotIn('splitString', REP)
        self.assertIn('_expectedBodies findIf {_x isEqualTo _effectiveBody}', REPORT)

    def test_provenance_context_and_unavailable_refusals_precede_cache(self):
        for text in ['count _meta != 9', '_declaration isNotEqualTo _expectedDeclaration',
                     '_functionName != _exportTag + "_fnc_" + _leaf', 'count _declarations != 1',
                     '_headerType in [-1, 0, 1]', 'toLower _declaredPath != toLower _path',
                     '_provenance select [0, 2]', '_attributes pushBack', '!fileExists _path']:
            self.assertLess(REP.index(text), REP.index('private _cached'))
        self.assertIn('"UNAVAILABLE"', REP)
        self.assertIn('_pathSources isEqualTo []',REP)
        self.assertIn('private _pathOwner = [_pathNode, "file"] call _attributeOwner;',REP)
        self.assertIn('configProperties [_node, "true", false]',REP)
        self.assertIn('_node = inheritsFrom _node;',REP)
        self.assertIn('LIBRARY_222_MISSION_COPY_V2',REP)
        self.assertIn('_pathProviderIndex = 1',REP)
        self.assertIn('_pathProviderIndex = 2',REP)
        self.assertNotIn('(_provenance # 2) isEqualTo []',REP)
        self.assertIn('isNil "_meta" || {!(_meta isEqualType [])}',REPORT)
        self.assertIn('_meta param [0, "", [""]]',REPORT)
        self.assertIn('private _patching = isFilePatchingEnabled;', REP)
        self.assertIn('if (!_patching &&', REP)
        self.assertIn('if (_patching) then {nil}', REP)
        self.assertIn('!isServer || {isRemoteExecuted}', MATCH)
        self.assertLess(MATCH.index('setVariable [_checkedKey, nil]'), MATCH.index('if !(_effective'))
        self.assertLess(MATCH.index('call A3UE_fnc_fpv_bindingRepresentations'), MATCH.index('count _checked == 2'))
        self.assertIn('(_checked # 0) isEqualTo _actual', MATCH)
        self.assertIn('(_checked # 1) isEqualTo _context', MATCH)
        self.assertEqual(MATCH.count('setVariable [_checkedKey, [_actual, _context]]'), 1)
        self.assertIn('if (_matches && {!isFilePatchingEnabled})', MATCH)

    def test_all_install_prerequisites_and_engine_negative_cases(self):
        rivals = (FPV/'fn_fpv_installRivalsHooks.sqf').read_text()
        support = (FPV/'fn_fpv_patchSupportRegistries.sqf').read_text()
        self.assertIn('[_name, _path, _cfg, ["a3a_scrt"]]', rivals)
        self.assertIn('[_name, _path, _cfg, ["fpv_ai_drones"]]', rivals)
        self.assertIn('[_name, _path, _cfg, ["fpv_ai_drones"]]', support)
        for case in ['UNTOUCHED_BASELINE', 'FOREIGN_PROVIDER_AND_DECLARATION', 'CHANGED_BODY_SAME_METADATA',
                     'UNKNOWN_HEADER_FULL_SOURCE', 'UNAVAILABLE_BINDING', 'RESTORED_ORIGINAL']:
            self.assertIn(case, PROBE)
        self.assertIn('CAPTURED_ORIGINAL (live owned wrapper; not a live predicate positive)', PROBE)
        self.assertIn('if (_owned) then {missionNamespace setVariable [_name, _original];}', PROBE)
        self.assertNotIn('call A3UE_fnc_fpv_install', PROBE)

    def test_summary_and_six_flat_row_payloads_and_transport_bounds(self):
        emit = REPORT.split('private _emit = {',1)[1].split('};',1)[0]
        self.assertIn('str _this', emit)
        self.assertNotIn('params ["_record"]', emit)
        self.assertIn('["A3UE FPV AU adapter SUMMARY", _version', REPORT)
        self.assertIn('["A3UE FPV AU adapter ROW", _forEachIndex + 1, _x get "function"', REPORT)
        pairs = re.findall(r'\["(\w+)", "(CREATE|Supports)"\]', REPORT)
        self.assertEqual(len(pairs), 6)
        payloads = [['A3UE FPV AU adapter SUMMARY','12.0.3','versionChars/max48',6,True,2,True,6,
                     'six config adapters; full details in A3UE_FPV_auAdapterReport']]
        for index,(name,_) in enumerate(pairs,1):
            path = '\\fpv_ai_drones\\functions\\fpv\\au_overrides\\fn_'+name+'.sqf'
            payloads.append(['A3UE FPV AU adapter ROW',index,'A3A_fnc_'+name,'ACTIVE',True,
                             'config/effective',path[:120],path[:120],'pathsTruncated',False,
                             'declarations/sources/foreign counts',1,2,0,
                             'paths max120; provenance details omitted; full report in memory'])
        lines = [emitter_model(x) for x in payloads]
        self.assertEqual(len(set(lines)),7)
        for i,(name,_) in enumerate(pairs,1):
            self.assertIn(f'ROW",{i},"A3A_fnc_{name}"',lines[i])
        self.assertTrue(all(len(x)<760 for x in lines))
        # Also count outer RPT string escaping and a timestamp, not just payload length.
        native_lengths = [len('20:00:00 '+wire(x)) for x in lines]
        self.assertLess(max(native_lengths), 900)
        oversized = emitter_model(['A3UE FPV AU adapter ROW',1,'name','"\n'*1000])
        self.assertIn('<TRUNCATED originalChars=',oversized)
        self.assertNotIn('\n',oversized)
        print('Packet A modeled payload chars:',list(map(len,lines)), 'modeled RPT chars:',native_lengths)

    def test_shared_tag_inventory_is_context_and_target_owners_are_enforced(self):
        # Execute the shipped target/category provider predicate as a tiny model.
        predicate = re.search(r'if \(\(\(_provenance select \[0, 2\]\) findIf \{(.*?)\}\) >= 0\)', REP, re.S)[1]
        self.assertEqual(predicate.strip(), '(_x findIf {!(toLower _x in _sources)}) >= 0')
        inventory = ['A3A_core','A3A_gui','A3A_patcom','fpv_ai_drones']
        allowed = ['a3a_core','fpv_ai_drones']
        def reviewed(leaf,category,tag=inventory):
            provenance = [leaf,category,tag]
            return not any(any(p.lower() not in allowed for p in node) for node in provenance[:2])
        self.assertTrue(reviewed(['fpv_ai_drones'],['A3A_core','fpv_ai_drones']))
        self.assertTrue(reviewed([],['fpv_ai_drones']))
        self.assertFalse(reviewed(['fpv_ai_drones','foreign'],['fpv_ai_drones']))
        self.assertFalse(reviewed([],['foreign']))
        self.assertNotIn('_tagSources',REP)
        self.assertNotIn('a3a_gui',REP.lower())
        self.assertNotIn('a3a_patcom',REP.lower())

    def test_captured_header_character_pattern(self):
        # A small immutable capture, not an engine simulation or equality proof.
        name = 'A3UE_fnc_fpv_rivalsUavFlyby'
        header = sqf_format(authored_headers()['_noDebug'],name)
        captured_actual = [123,10,9,112,114,105,118,97,116,101,32,95,102,110,99,95,115,99,114,105,112,116,78,97]
        captured_expected = [123,13,10,9,112,114,105,118,97,116,101,32,95,102,110,99,95,115,99,114,105,112,116,78]
        self.assertEqual(list(map(ord, ('{' + header)[:24])),captured_actual)
        self.assertEqual(list(map(ord, ('{' + header.replace('\n','\r\n'))[:24])),captured_expected)
        # The capture's 166-character difference exceeds its 5 CR / 2 LF gap.
        self.assertGreater(1367-1201, (6-1)+(38-36))
        self.assertIn('private _copy = call compile _direct;',REP)

    def test_inherited_attribute_owner_and_unavailable_model(self):
        def owner(node,attribute):
            for _ in range(16):
                if node is None: return None
                if attribute in node['direct']: return node
                node = node.get('parent')
            return None
        def accepted(node,attribute):
            found = owner(node,attribute)
            return bool(found and found['providers']) and all(x in ['fpv_ai_drones','a3a_core'] for x in found['providers'])
        parent = dict(direct={'file':'expected','tag':'A3A'},providers=['a3a_core'])
        child = dict(direct={},providers=['fpv_ai_drones'],parent=parent)
        self.assertTrue(accepted(child,'file'))
        self.assertTrue(accepted(child,'tag'))
        parent['providers'] = ['foreign']
        self.assertFalse(accepted(child,'file'))
        self.assertFalse(accepted(child,'tag'))
        parent['providers'] = []
        self.assertFalse(accepted(child,'file'))
        self.assertFalse(accepted(child,'unknown'))
        child['direct']['file']='expected'
        self.assertTrue(accepted(child,'file'))
        self.assertFalse(accepted(child,'tag'))
        self.assertIn('[_tagConfig, "tag"]',REP)
        self.assertIn('"ATTRIBUTE_PROVIDER"',REP)
        self.assertIn('"FILE_PROVIDER"',REP)
        self.assertIn('_patching, _attributes]',REP)

    def test_complete_payload_and_literal_characters_are_never_normalized(self):
        literal = 'A\r\nB\t#line 42 "literal"'
        direct = '{\nprivate _x = "' + literal.replace('"','""') + '"; 41001;}'
        # Only complete compiler outputs are modeled as prepared forms.
        forms = [direct, direct + ' generated-context-model']
        for mutation in [direct.replace('41001','41002'),direct.replace('\r',''),
                         direct.replace('\t',' '),direct.replace('literal','changed'),direct[10:]]:
            self.assertNotIn(mutation,forms)
        self.assertIn('_expected pushBackUnique _direct',REP)
        self.assertIn('_expected pushBackUnique _missionCopy',REP)
        self.assertIn('if (!_complete || {_expected isEqualTo []}) exitWith {_refused}',REP)
        self.assertNotIn('call _compiled',REP)
        self.assertNotIn('call _copy',REP)
        self.assertNotIn('select [', REP.split('private _expected = [];',1)[1])
        self.assertIn('"CONTEXT_CONTROL"',PROBE)
        self.assertIn('"literal preserved", _literalPreserved',PROBE)
        self.assertIn('"DIFF_CODES"',PROBE)
        self.assertIn('private _codeOffset = 0 max (_low - 4);',PROBE)
        self.assertIn('toArray (_expected select [_codeOffset, 12])',PROBE)
        self.assertIn('toArray (_actual select [_codeOffset, 12])',PROBE)

    def test_existing_ownership_and_fallback_contracts_retained(self):
        ownership = (ROOT/'tools/tests/au06_hook_ownership.sqf').read_text()
        self.assertEqual(ownership.count('] call _assert;'),15)
        self.assertLess(ownership.index('PRODUCTION BASELINE'), ownership.index('A3UE_fnc_fpv_hookBindingMatches = {_matches}'))
        self.assertIn('PRODUCTION_BINDING_RESTORATION',ownership)
        for case in ['REPEAT_KEEPS_OWNED_TUPLE','IDENTICAL_FOREIGN_TUPLE_PRESERVED',
                     'RIVALS_REPEAT_NO_SELF_CAPTURE','LATER_WRAPPER_PRESERVED_AND_NO_FIGHT']:
            self.assertIn(case,ownership)
        for name in ['rivalsSelectAndExecuteEvent','rivalsUavFlyby']:
            self.assertRegex((FPV/f'fn_fpv_{name}.sqf').read_text(), r'call _orig\w*')


if __name__ == '__main__': unittest.main()
