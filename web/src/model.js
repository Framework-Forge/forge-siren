export const initialState = {
  visible: false, focused: false, ready: false, editing: false, lights: false, mode: 0,
  horn: false, manual: false, megaphone: false, selectedMode: 1, seat: -1, notice: '', vehicle: '',
  modes: [], presets: [],
  preferences: { keepLights: true, keepSound: false, primaryMode: 1, scale: 1 },
  keys: { lights: 'Q', sound: 'ALT', cycle: 'R', horn: 'E', panel: 'LCONTROL', megaphone: 'F7' },
  admin: { allowed: false, settings: null, revision: 0, epoch: '', maxRange: 50 },
  layout: { right: 24, bottom: 32, x: null, y: null },
};

export function receiveState(message) {
  if (!message || message.type !== 'forge-siren:state') return null;
  return {
    ...initialState, ...message,
    preferences: { ...initialState.preferences, ...message.preferences },
    keys: { ...initialState.keys, ...message.keys },
    layout: { ...initialState.layout, ...message.layout },
    admin: { ...initialState.admin, ...message.admin, allowed: message.admin?.allowed === true },
    modes: Array.isArray(message.modes) ? message.modes : [],
    presets: Array.isArray(message.presets) ? message.presets : [],
  };
}

export function keyMatches(event, label) {
  const aliases = { LMENU: 'ALT', RMENU: 'ALT', LSHIFT: 'SHIFT', RSHIFT: 'SHIFT', LCONTROL: 'CONTROL', RCONTROL: 'CONTROL' };
  const normalized = String(label || '').toUpperCase();
  return (aliases[normalized] || normalized) === event.key.toUpperCase();
}

// Only used with ?preview=1 outside FiveM. No fake state in the game.
export function previewState({ admin = false } = {}) {
  return receiveState({
    type: 'forge-siren:state', visible: true, focused: true, ready: true,
    vehicle: 'POLICE', lights: true, mode: 1,
    modes: [{ id: 1, label: 'WAIL' }, { id: 2, label: 'YELP' }, { id: 3, label: 'PRIORITY' }],
    presets: [1, 2, 3].map((slot) => ({ name: `PRESET 0${slot}`, saved: false })),
    admin: admin ? { allowed: true, revision: 1, epoch: 'preview', maxRange: 50,
      settings: { enabled: true, monitorEnabled: true, effectEnabled: true,
        monitorVolume: 30, listenerVolume: 100, farVolume: 25, range: 35 } } : initialState.admin,
  });
}
