import test from 'node:test';
import assert from 'node:assert/strict';
import {
  snapTemperature,
  tempToAngleDeg,
  pointerOffsetToTemp,
  computeBoilerTelemetry,
  parseVoiceCommand,
  computeFlowState,
  TAB_XS,
} from './thermostat';

test('snapTemperature clamps and snaps to 0.5°C increments', () => {
  assert.equal(snapTemperature(22.4), 22.5);
  assert.equal(snapTemperature(22.1), 22.0);
  assert.equal(snapTemperature(5.0), 10.0);
  assert.equal(snapTemperature(35.0), 30.0);
});

test('tempToAngleDeg maps 10..30°C to -135..+135 degrees', () => {
  assert.equal(tempToAngleDeg(10.0), -135);
  assert.equal(tempToAngleDeg(20.0), 0);
  assert.equal(tempToAngleDeg(30.0), 135);
  assert.equal(tempToAngleDeg(22.5), 33.75);
});

test('pointerOffsetToTemp maps top center to 20.0°C and right to ~26.5°C', () => {
  assert.equal(pointerOffsetToTemp(0, -100), 20.0);
  assert.equal(pointerOffsetToTemp(100, 0), 26.5);
  assert.equal(pointerOffsetToTemp(-100, 0), 13.5);
});

test('computeBoilerTelemetry activates modulation when target exceeds room temp', () => {
  const standby = computeBoilerTelemetry(21.8, 21.5);
  assert.equal(standby.isHeating, false);
  assert.equal(standby.flamePercent, 0);

  const konfor = computeBoilerTelemetry(21.8, 22.5);
  assert.equal(konfor.isHeating, true);
  assert.ok(konfor.flamePercent >= 20 && konfor.flamePercent <= 60);
  assert.equal(konfor.modulationActive, true);

  const boost = computeBoilerTelemetry(21.8, 26.0);
  assert.equal(boost.isHeating, true);
  assert.equal(boost.flamePercent, 100);
  assert.equal(boost.modulationActive, false);
});

test('parseVoiceCommand handles Turkish temperature, preset, and navigation commands', () => {
  const tempRes = parseVoiceCommand('Sıcaklığı 24 derece yap');
  assert.equal(tempRes.handled, true);
  assert.equal(tempRes.newTargetTemp, 24.0);
  assert.equal(tempRes.navigateTab, 'termo');

  const ecoRes = parseVoiceCommand('Eko moda geç');
  assert.equal(ecoRes.handled, true);
  assert.equal(ecoRes.newPreset, 'eko');
  assert.equal(ecoRes.newTargetTemp, 20.0);

  const navRes = parseVoiceCommand('Hava durumunu aç');
  assert.equal(navRes.handled, true);
  assert.equal(navRes.navigateTab, 'hava');
});

test('computeFlowState smoothly interpolates bead position and rise across 4 tabs', () => {
  const start = computeFlowState(
    0.0,
    [{ ts: 0, a: 0, b: 2, d: 0.8, fromAcc: [1, 0.48, 0.14], toAcc: [0.55, 0.4, 1] }],
    0,
    [1, 0.48, 0.14]
  );
  assert.equal(start.x, TAB_XS[0]);
  assert.equal(start.rise, 1);

  const mid = computeFlowState(
    0.4,
    [{ ts: 0, a: 0, b: 2, d: 0.8, fromAcc: [1, 0.48, 0.14], toAcc: [0.55, 0.4, 1] }],
    2,
    [0.55, 0.4, 1]
  );
  assert.ok(mid.x > TAB_XS[0] && mid.x < TAB_XS[2]);
  assert.ok(mid.rise < 0.3, 'bead should sink into the glass bar mid-transition');
  assert.ok(mid.sx > 1.2, 'bead should stretch horizontally mid-transition');

  const end = computeFlowState(
    1.5,
    [{ ts: 0, a: 0, b: 2, d: 0.8, fromAcc: [1, 0.48, 0.14], toAcc: [0.55, 0.4, 1] }],
    2,
    [0.55, 0.4, 1]
  );
  assert.equal(end.x, TAB_XS[2]);
  assert.ok(Math.abs(end.rise - 1) < 0.02);
});
