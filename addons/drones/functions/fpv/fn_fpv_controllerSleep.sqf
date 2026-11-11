// Only pass active subsystem deadlines. Due work retains the 20 ms floor.
params ["_now", "_tickTimes"];
if (_tickTimes isEqualTo []) exitWith {0.02};
(((selectMin _tickTimes) - _now) max 0.02) min 0.25
