"""F2 correction tooling admission/collection contracts; no engine qualification."""
import importlib.util,sys,unittest
from pathlib import Path
Q=Path(__file__).resolve().parent/'f2c'
spec=importlib.util.spec_from_file_location('f2c_monitor',Q/'monitor.py')
monitor=importlib.util.module_from_spec(spec);sys.modules[spec.name]=monitor;spec.loader.exec_module(monitor)

class F2CQA(unittest.TestCase):
    def test_actual_inventory_requires_sole_exact_candidate(self):
        manifest={'candidate_pbo':r'C:\private\addons\fpv_ai_drones.pbo'}
        def rpt(paths):return '==== Loaded addons ====\n'+''.join('12:00:00 '+p+' - hash\n' for p in paths)+'======================='
        self.assertEqual(monitor.startup_identity(rpt([manifest['candidate_pbo']]),manifest)['duplicate_fpv_count'],1)
        for paths in [[],[r'C:\old\fpv_ai_drones.pbo'],[manifest['candidate_pbo']]*2]:
            with self.assertRaises(ValueError):monitor.startup_identity(rpt(paths),manifest)

    def test_incremental_transport_and_nested_marker_are_distinct(self):
        raw='12:00:00 ["F2R_AUTO",1,"ticket-001","SESSION",10,[]]\n'.encode('utf-16')
        reader=monitor.LiveLines();lines=[]
        for i in range(0,len(raw),3):lines+=reader.feed(raw[i:i+3])
        self.assertEqual(len(lines),1)
        self.assertEqual(monitor.auto_event(lines[0])[3],'SESSION')
        self.assertIsNone(monitor.auto_event('["A3UE_FPV_QA|",["MARK",["F2R_AUTO",1,"ticket-001"]]]'))

    def test_missing_activity_never_qualifies_flight(self):
        result=monitor.score([],None,[])
        self.assertEqual(result['fixture_admission']['status'],'NOT OBSERVED')
        self.assertEqual(result['capture_integrity']['status'],'INCOMPLETE')
        self.assertEqual(result['active_attack_release']['status'],'NOT OBSERVED')
        self.assertFalse(any(v['status']=='PASS' for v in result.values()))

    def test_no_rejected_gameplay_dependency_or_automatic_matrix(self):
        runner=(Q/'runner.sqf').read_text();player=(Q/'player.sqf').read_text();arm=(Q/'arm.sqf').read_text()
        for word in ['hasObservation','trackConfidence','handoffSteering','huntBudget','recoveryProgress','failureDisposition']:
            self.assertNotIn(word,runner+player)
        self.assertIn('[2,true,true,false,true]',runner)
        self.assertIn('removeMissionEventHandler ["EachFrame",_thisEventHandler]',arm)
        self.assertIn('scripts\\f2r\\finish.sqf',runner)
        self.assertNotIn('"REVIEW"',arm)
        self.assertNotIn('"Recipe"',(Q/'monitor.py').read_text())
        for text in [runner,player,arm]:
            self.assertNotRegex(text,r'\b(hint|hintSilent|hintC)\b')
        self.assertNotIn('setVariable ["A3UE_FPV_targetNetId"',runner+player)
        self.assertNotIn('setVariable ["A3UE_FPV_reportedControl"',runner+player)

    def test_dismount_stimulus_fences_and_deferred_observation(self):
        runner=(Q/'runner.sqf').read_text()
        stimulus=runner.split('private _stimulated = false;',1)[1].split('private _until = diag_tickTime + 100',1)[0]
        for guard in ['isNil {','call _valid','_u distance _a > 150','!local _x','isPlayer _x','objectParent _x != _a','A3UE_POLICY_crewIds']:
            self.assertIn(guard,stimulus)
        self.assertIn('unassignVehicle _x; moveOut _x;',stimulus)
        self.assertIn('A3UE_POLICY_crew - [driver _a]',stimulus)
        self.assertIn('_nextSense = diag_tickTime + 0.5',runner)
        self.assertNotIn('copyToClipboard',runner)
        capture=(Q.parent/'ua_dive/capture.sqf').read_text()
        self.assertIn('60000',capture)
        self.assertNotIn('A3UE_FPV_flightPurpose',capture)

if __name__=='__main__':unittest.main()
