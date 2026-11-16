<script>
  import { onMount } from 'svelte';
  import ControllerButton from './ControllerButton.svelte';
  import Lcd from './Lcd.svelte';
  import AdminMegaphone from './AdminMegaphone.svelte';
  import { initialState, receiveState, keyMatches, previewState } from './model.js';
  import { panelPlacement, movePanel, PANEL_WIDTH, MIN_SCALE, MAX_SCALE } from './layout.js';

  const preview = typeof window.GetParentResourceName !== 'function' && new URLSearchParams(location.search).has('preview');
  const clone = (value) => JSON.parse(JSON.stringify(value));
  let state = $state(preview ? previewState({ admin: new URLSearchParams(location.search).has('admin') }) : clone(initialState));
  let viewportWidth = $state(innerWidth);
  let viewportHeight = $state(innerHeight);
  let controllerHeight = $state(320);
  let settingsHeight = $state(500);
  let settings = $state(false);
  let adminTab = $state(false);
  let names = $state(['', '', '']);
  let heldKey = '';
  let draft = $state(null);
  let gesture;
  let demoTimer;
  const demoPresets = [];
  const modeLabel = $derived(state.modes.find((mode) => mode.id === (state.mode || state.selectedMode))?.label || 'WAIL');
  const display = $derived(state.megaphone ? 'MEGAFONE / TX' : state.notice || (!state.ready ? 'SINCRONIZANDO' : state.horn ? 'AIR HORN' : state.manual ? 'MANUAL' : state.mode ? modeLabel : state.lights ? 'LUZES / SILENCIO' : 'STANDBY'));
  const disabled = $derived(!state.focused || !state.ready || state.editing);
  const placement = $derived(panelPlacement(draft || state.layout, draft?.scale ?? state.preferences.scale,
    viewportWidth, viewportHeight, controllerHeight, settings ? settingsHeight + 20 : 0));

  function initializeDraft(next = state) {
    const position = panelPlacement(next.layout, next.preferences.scale, viewportWidth, viewportHeight, controllerHeight);
    draft = { x: position.x / viewportWidth, y: position.y / viewportHeight, scale: next.preferences.scale };
  }
  async function beginLayout() {
    release();
    settings = false;
    await send('layoutEdit', { enabled: true });
  }
  function cancelLayout() {
    gesture = null;
    send('layoutEdit', { enabled: false });
  }
  function resetLayout() {
    const position = panelPlacement({ right: state.layout.right, bottom: state.layout.bottom }, 1,
      viewportWidth, viewportHeight, controllerHeight);
    draft = { x: position.x / viewportWidth, y: position.y / viewportHeight, scale: 1 };
  }
  function saveLayout() {
    gesture = null;
    send('layout', { x: placement.x / viewportWidth, y: placement.y / viewportHeight, scale: draft.scale });
  }
  function beginGesture(event, kind) {
    if (!state.editing || !draft || event.button !== 0) return;
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    gesture = { kind, id: event.pointerId, x: event.clientX, y: event.clientY,
      placement: { ...placement }, scale: draft.scale };
  }
  function moveGesture(event) {
    if (!gesture || !draft || event.pointerId !== gesture.id) return;
    const dx = event.clientX - gesture.x, dy = event.clientY - gesture.y;
    if (gesture.kind === 'move') {
      draft = { ...draft, ...movePanel(gesture.placement, dx, dy, viewportWidth, viewportHeight, controllerHeight) };
    } else {
      const delta = (dx * PANEL_WIDTH + dy * controllerHeight) / (PANEL_WIDTH ** 2 + controllerHeight ** 2);
      draft = { ...draft, scale: Math.max(MIN_SCALE, Math.min(MAX_SCALE, gesture.scale - delta)) };
    }
  }
  function endGesture() { gesture = null; }

  function demoNotice(text) {
    state.notice = text;
    clearTimeout(demoTimer);
    demoTimer = setTimeout(() => { state.notice = ''; }, 2400);
  }
  async function send(endpoint, data = {}) {
    if (preview) return demo(endpoint, data) || { ok: true };
    try {
      const response = await fetch(`https://${window.GetParentResourceName()}/${endpoint}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data),
      });
      const result = await response.json();
      if (['adminGet', 'adminSave'].includes(endpoint) && result?.ok) state.admin = result;
      return result;
    } catch (error) {
      console.warn('[Forge Siren] Painel indisponível:', error.message);
      return { ok: false };
    }
  }
  function demo(endpoint, data) {
    if (endpoint === 'adminGet') return { ok: true, ...clone($state.snapshot(state.admin)) };
    if (endpoint === 'adminSave' && state.admin.allowed) {
      state.admin = { ...state.admin, settings: clone(data.settings), revision: state.admin.revision + 1 };
      return { ok: true, ...clone($state.snapshot(state.admin)) };
    }
    if (endpoint === 'close') { state.focused = false; state.editing = false; draft = null; settings = false; }
    if (endpoint === 'layoutEdit') {
      state.editing = data.enabled;
      if (data.enabled) initializeDraft(); else draft = null;
    }
    if (endpoint === 'layout') {
      state.layout = { ...state.layout, x: data.x, y: data.y };
      state.preferences.scale = data.scale;
      state.editing = false;
      draft = null;
      demoNotice('PAINEL AJUSTADO');
    }
    if (endpoint === 'release') { state.horn = false; state.megaphone = false; if (state.manual) state.mode = 0; state.manual = false; }
    if (endpoint === 'preference') { state.preferences[data.key] = data.value; demoNotice('PREFERENCIA SALVA'); }
    if (endpoint === 'preset') {
      if (data.operation === 'save') {
        demoPresets[data.slot - 1] = clone($state.snapshot(state.preferences));
        state.presets[data.slot - 1] = { name: data.name || `PRESET 0${data.slot}`, saved: true };
      } else if (demoPresets[data.slot - 1]) state.preferences = clone(demoPresets[data.slot - 1]);
      demoNotice(`PRESET 0${data.slot} ${data.operation === 'save' ? 'SALVO' : 'ATIVO'}`);
    }
    if (endpoint !== 'action') return;
    const name = data.name;
    if (name === 'megaphoneStart' || name === 'megaphoneEnd') state.megaphone = name === 'megaphoneStart';
    if (name === 'lights') { state.lights = !state.lights; if (!state.lights) state.mode = 0; demoNotice(state.lights ? 'LUZES LIGADAS' : 'LUZES DESLIGADAS'); }
    if (name === 'sound') { state.mode = state.mode ? 0 : state.selectedMode; if (state.mode) state.lights = true; }
    if (name === 'off') { state.lights = false; state.mode = 0; state.horn = false; state.manual = false; demoNotice('SISTEMA DESLIGADO'); }
    if (['cycle', 'previous', 'next', 'tone'].includes(name)) {
      state.selectedMode = name === 'tone' ? data.value : ((state.selectedMode - 1 + (name === 'previous' ? -1 : 1) + state.modes.length) % state.modes.length) + 1;
      if (state.mode) state.mode = state.selectedMode;
      demoNotice(state.modes.find((mode) => mode.id === state.selectedMode).label);
    }
    if (name === 'hornStart' || name === 'hornEnd') state.horn = name === 'hornStart';
    if (name === 'manualStart' && !state.mode) { state.mode = state.selectedMode; state.manual = true; }
    if (name === 'manualEnd' && state.manual) { state.mode = 0; state.manual = false; }
    if (name === 'keepLights' || name === 'keepSound') {
      state.preferences[name] = !state.preferences[name];
      demoNotice(`${name === 'keepLights' ? 'LUZ' : 'SOM'} AO SAIR ${state.preferences[name] ? 'MANTER' : 'DESLIGAR'}`);
    }
    if (name === 'primary') { state.preferences.primaryMode = (state.preferences.primaryMode % state.modes.length) + 1; demoNotice('PRINCIPAL ' + state.modes[state.preferences.primaryMode - 1].label); }
  }
  const act = (name, value) => send('action', { name, value });
  function openSettings() {
    names = state.presets.map((preset) => preset.name);
    adminTab = false;
    settings = !settings;
  }
  function release() {
    heldKey = '';
    gesture = null;
    send('release');
  }
  function keydown(event) {
    if (event.defaultPrevented) return;
    if (preview && keyMatches(event, state.keys.panel)) { event.preventDefault(); state.focused = !state.focused; return; }
    if (!state.visible || !state.focused) return;
    if (state.editing) {
      if (event.key === 'Escape') { event.preventDefault(); cancelLayout(); return; }
      if (event.target instanceof HTMLInputElement) return;
      const step = event.shiftKey ? 10 : 1;
      const arrows = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
      if (arrows[event.key] && draft) {
        event.preventDefault();
        draft = { ...draft, ...movePanel(placement, ...arrows[event.key], viewportWidth, viewportHeight, controllerHeight) };
      }
      return;
    }
    if (event.key === 'Escape') {
      event.preventDefault();
      if (settings) settings = false; else send('close');
      release(); return;
    }
    if (event.target instanceof HTMLInputElement || event.repeat) return;
    // Keep-input sends the cursor key to the native mapping too. Only Lua toggles the
    // real panel; handling it here as well would close and reopen it.
    if (keyMatches(event, state.keys.panel)) { event.preventDefault(); return; }
    if (disabled) return;
    if (keyMatches(event, state.keys.lights)) { event.preventDefault(); act('lights'); }
    else if (keyMatches(event, state.keys.sound)) { event.preventDefault(); act('sound'); }
    else if (keyMatches(event, state.keys.horn)) { event.preventDefault(); heldKey = event.code; act('hornStart'); }
    else if (keyMatches(event, state.keys.cycle)) { event.preventDefault(); heldKey = event.code; act(state.mode ? 'cycle' : 'manualStart'); }
  }
  function keyup(event) {
    if (event.code === heldKey) release();
  }
  function reserveDrivingKeys(event) {
    // Space is the vehicle handbrake, not activation of the last clicked
    // button. Cancel the browser default before child button handlers run.
    if (state.visible && state.focused && event.key === ' '
        && !(event.target instanceof HTMLInputElement) && !event.target?.isContentEditable) {
      event.preventDefault();
    }
  }
  onMount(() => {
    function receive(event) {
      const next = receiveState(event.data);
      if (!next) return;
      if ((!next.visible || !next.focused) && (state.horn || state.manual || heldKey || state.focused && state.megaphone)) release();
      if (!next.visible || !next.focused) settings = false;
      if (next.editing && next.visible && next.focused) {
        settings = false;
        if (!draft) initializeDraft(next);
      } else { draft = null; gesture = null; }
      state = next;
      if (!next.admin.allowed) adminTab = false;
    }
    window.addEventListener('message', receive);
    window.addEventListener('keydown', reserveDrivingKeys, true);
    window.addEventListener('keyup', reserveDrivingKeys, true);
    send('ready');
    return () => {
      window.removeEventListener('message', receive);
      window.removeEventListener('keydown', reserveDrivingKeys, true);
      window.removeEventListener('keyup', reserveDrivingKeys, true);
      clearTimeout(demoTimer);
    };
  });
</script>

<svelte:window bind:innerWidth={viewportWidth} bind:innerHeight={viewportHeight} onkeydown={keydown} onkeyup={keyup} onblur={release} onpointermove={moveGesture} onpointerup={endGesture} onpointercancel={endGesture} />

{#if state.visible}
  {#if state.editing && draft}
    <section class="layout-toolbar hardware" aria-label="Ajustar posição e tamanho">
      <div><strong>AJUSTAR PAINEL</strong><p>Arraste o painel · canto para tamanho · setas para ajuste fino</p></div>
      <label for="layout-scale">Tamanho <output>{Math.round(draft.scale * 100)}%</output></label>
      <input id="layout-scale" aria-label="Tamanho do painel no editor" type="range" min={MIN_SCALE} max={MAX_SCALE} step="0.01" value={draft.scale} oninput={(event) => draft = { ...draft, scale: Number(event.currentTarget.value) }} />
      <div class="layout-actions"><button class="small-button" onclick={resetLayout}>RESTAURAR</button><button class="small-button" onclick={cancelLayout}>CANCELAR</button><button class="small-button recall" onclick={saveLayout}>SALVAR POSIÇÃO</button></div>
    </section>
  {/if}
  <div class="controller-anchor" style:right={`${viewportWidth - placement.x}px`} style:bottom={`${viewportHeight - placement.y}px`} style:--scale={placement.scale}>
    {#if preview}<div class="preview-tag">PRÉVIA INTERATIVA · CTRL PARA CURSOR</div>{/if}
    {#if settings && state.focused}
      <section class="settings hardware" aria-label="Configurações e presets" bind:clientHeight={settingsHeight}>
        <div class="settings-heading"><div><span class="eyebrow">{adminTab ? 'FORGE / GLOBAL CONTROL' : 'FORGE / PERSONAL MEMORY'}</span><h1>{adminTab ? 'Megafone da cidade.' : 'Seu jeito de responder.'}</h1></div><button class="small-button" onclick={() => settings = false} aria-label="Fechar configurações">×</button></div>
        {#if state.admin.allowed && state.admin.settings}
          <div class="settings-tabs" aria-label="Área de configurações"><button class:selected={!adminTab} onclick={() => adminTab = false}>PESSOAL</button><button class:selected={adminTab} onclick={() => adminTab = true}>ADMIN</button></div>
        {/if}
        {#if adminTab && state.admin.allowed && state.admin.settings}
          <AdminMegaphone data={state.admin} onsave={(data) => send('adminSave', data)} onreload={() => send('adminGet')} />
        {:else}
        <div class="setting-row"><div><strong>Luzes ao sair</strong><p>Aplicado quando o último ocupante da frente sai.</p></div><button class="switch" class:on={state.preferences.keepLights} role="switch" aria-checked={state.preferences.keepLights} aria-label="Manter luzes ao sair" onclick={() => act('keepLights')}><span></span></button></div>
        <div class="setting-row"><div><strong>Som ao sair</strong><p>Aplicado quando o último ocupante da frente sai.</p></div><button class="switch" class:on={state.preferences.keepSound} role="switch" aria-checked={state.preferences.keepSound} aria-label="Manter som ao sair" onclick={() => act('keepSound')}><span></span></button></div>
        <div class="setting-row"><div><strong>Tom principal</strong><p>Tom inicial ao ligar. Não dispara a sirene.</p></div><div class="segments">{#each state.modes as mode}<button class:selected={state.preferences.primaryMode === mode.id} onclick={() => send('preference', { key: 'primaryMode', value: mode.id })}>{mode.label}</button>{/each}</div></div>
        <div class="memories-label"><span>SUAS MEMÓRIAS</span><span>01 — 03</span></div>
        <div class="preset-list">{#each state.presets as preset, index}<div class="preset"><span class="preset-number">0{index + 1}</span><input aria-label={`Nome do preset ${index + 1}`} maxlength="24" bind:value={names[index]} placeholder="Nome da memória" /><button class="small-button" onclick={() => send('preset', { slot: index + 1, name: names[index], operation: 'save' })}>SALVAR</button><button class="small-button recall" disabled={!preset.saved} onclick={() => send('preset', { slot: index + 1, operation: 'load' })}>USAR</button></div>{/each}</div>
        <div class="settings-footer"><label for="scale">Tamanho do painel</label><input id="scale" type="range" min="0.4" max="1.3" step="0.05" value={state.preferences.scale} oninput={(event) => send('preference', { key: 'scale', value: Number(event.currentTarget.value) })} /><span>{Math.round(state.preferences.scale * 100)}%</span></div>
        <button class="small-button layout-launch" onclick={beginLayout}>REPOSICIONAR / REDIMENSIONAR PAINEL</button>
        <p class="settings-note">Salvo neste computador · presets guardam preferências, não ligam luzes ou som.</p>
        {/if}
      </section>
    {/if}
    <section class="console hardware" class:interactive={state.focused} class:editing={state.editing} aria-label="Controlador de sirene Forge" bind:clientHeight={controllerHeight}>
      {#if state.editing}
        <button class="layout-drag" aria-label="Arrastar painel" onpointerdown={(event) => beginGesture(event, 'move')}><span>↔ ARRASTE PARA MOVER</span></button>
        <button class="layout-resize" aria-label="Redimensionar painel" onpointerdown={(event) => beginGesture(event, 'resize')}>⤡</button>
      {/if}
      <span class="screw top-left" aria-hidden="true"></span><span class="screw top-right" aria-hidden="true"></span><span class="screw bottom-left" aria-hidden="true"></span><span class="screw bottom-right" aria-hidden="true"></span>
      <div class="faceplate">
        <header class="console-header"><div class="brand"><span class="brand-mark">F</span>FORGE<span class="brand-series">SIREN SYSTEMS</span></div><span class="model">FS—200 <span class="online" class:ready={state.ready}></span> SYNC</span></header>
        <Lcd text={display} lights={state.lights} sound={state.mode > 0 || state.horn} memory={settings} />
        <div class="main-controls">
          <ControllerButton label="SIREN" subtitle="SOM" hint={state.keys.sound} active={state.mode > 0} color="red" shape="siren-button" {disabled} onclick={() => act('sound')} />
          <div class="stack"><ControllerButton label="MAN" hint={state.keys.cycle} active={state.manual} color="blue" hold {disabled} onpress={() => act('manualStart')} onrelease={() => act('manualEnd')} /><ControllerButton label="HORN" hint={state.keys.horn} active={state.horn} color="red" hold {disabled} onpress={() => act('hornStart')} onrelease={() => act('hornEnd')} /></div>
          <ControllerButton label="FLASH" subtitle="ILUMINAÇÃO" hint={state.keys.lights} active={state.lights} color="blue" shape="flash-button" {disabled} onclick={() => act('lights')} />
          <div class="stack">{#each state.modes.slice(0, 2) as mode}<ControllerButton label={`A${mode.id}`} subtitle={mode.label} active={state.selectedMode === mode.id} color={mode.id === 1 ? 'blue' : 'red'} {disabled} onclick={() => act('tone', mode.id)} />{/each}</div>
          <ControllerButton label="OFF" subtitle="TUDO" active={!state.lights && state.mode === 0 && !state.horn} color="red" shape="off-button" {disabled} onclick={() => act('off')} />
        </div>
        <div class="function-controls">
          <ControllerButton label="◀" subtitle="TOM" color="blue" {disabled} onclick={() => act('previous')} />
          <ControllerButton label="F1" subtitle="LUZ AO SAIR" active={state.preferences.keepLights} color="blue" {disabled} onclick={() => act('keepLights')} />
          <ControllerButton label="F2" subtitle="SOM AO SAIR" active={state.preferences.keepSound} color="red" {disabled} onclick={() => act('keepSound')} />
          <ControllerButton label="B1" subtitle="PRINCIPAL" color="blue" {disabled} onclick={() => act('primary')} />
          <ControllerButton label="B2" subtitle="MEMÓRIAS" active={settings} color="red" {disabled} onclick={openSettings} />
          <ControllerButton label="▶" subtitle="TOM" color="red" {disabled} onclick={() => act('next')} />
        </div>
        <div class="megaphone-control"><ControllerButton label="MEGAFONE" subtitle="SEGURE PARA FALAR" hint={state.keys.megaphone} active={state.megaphone} color="blue" hold {disabled} onpress={() => act('megaphoneStart')} onrelease={() => act('megaphoneEnd')} /></div>
        <footer class="console-footer"><span><i class:active={state.lights}></i>{state.vehicle || 'EMERGENCY'}<span class="divider">/</span>{modeLabel}</span><span>{state.focused ? 'ESC  ·  VOLTAR AO JOGO' : `${state.keys.panel}  ·  ATIVAR CURSOR`}</span></footer>
      </div>
    </section>
  </div>
{/if}
