<script>
  let { data, onsave, onreload } = $props();
  const copy = (value) => ({ ...value });
  // Deliberate initial snapshot: a remote update must never overwrite unsaved edits.
  function initialSnapshot() { return { ...data, settings: copy(data.settings) }; }
  const initial = initialSnapshot();
  let draft = $state(initial.settings);
  let baseRevision = $state(initial.revision);
  let baseEpoch = $state(initial.epoch);
  let busy = $state(false);
  let error = $state('');
  let success = $state('');
  const dirty = $derived(JSON.stringify(draft) !== JSON.stringify(data.settings));
  const stale = $derived(baseEpoch !== data.epoch || baseRevision !== data.revision);
  function adopt(next) {
    draft = copy(next.settings); baseRevision = next.revision; baseEpoch = next.epoch;
  }
  function change(key, value) {
    draft = { ...draft, [key]: value };
    if (key === 'listenerVolume') draft.farVolume = Math.min(draft.farVolume, value);
    error = ''; success = '';
  }
  async function save(event) {
    event.preventDefault();
    if (busy || stale) return;
    busy = true; error = ''; success = '';
    try {
      const result = await onsave({ settings: copy(draft), revision: baseRevision, epoch: baseEpoch });
      if (result?.ok && result.allowed) { adopt(result); success = 'Configuração global aplicada e salva.'; }
      else error = result?.error || 'Não foi possível salvar. Confira sua permissão.';
    } finally { busy = false; }
  }
  async function reload() {
    if (busy) return;
    busy = true; error = ''; success = '';
    try {
      const result = await onreload();
      if (result?.ok && result.allowed) adopt(result);
      else error = result?.error || 'Não foi possível recarregar.';
    } finally { busy = false; }
  }
</script>

<form class="admin-megaphone" onsubmit={save} aria-label="Configuração global do megafone">
  <p class="admin-description">Para toda a cidade · megafone veicular e portátil · salvo no servidor.</p>
  <div class="admin-switches">
    {#each [{ key: 'enabled', label: 'Megafone habilitado' }, { key: 'monitorEnabled', label: 'Retorno da própria voz' }, { key: 'effectEnabled', label: 'Efeito rádio / megafone' }] as option}
      <label><input type="checkbox" checked={draft[option.key]} disabled={busy} onchange={(event) => change(option.key, event.currentTarget.checked)} /><span>{option.label}</span></label>
    {/each}
  </div>
  <div class="admin-volume-fields">
    {#each [{ key: 'monitorVolume', label: 'Volume máximo de retorno', hint: 'Som que o próprio jogador escuta.' }, { key: 'listenerVolume', label: 'Volume máximo para jogadores próximos', hint: 'Volume de referência perto do megafone.' }, { key: 'farVolume', label: 'Volume no limite do alcance', hint: 'Diminui gradualmente com a distância; fora do alcance fica mudo.' }] as field}
      <div class="admin-volume-field">
        <label for={`admin-${field.key}`}>{field.label}<output>{draft[field.key]}%</output></label>
        <input id={`admin-${field.key}`} type="range" min="0" max={field.key === 'farVolume' ? draft.listenerVolume : 100} step="1" value={draft[field.key]} disabled={busy} oninput={(event) => change(field.key, Number(event.currentTarget.value))} />
        <p>{field.hint}</p>
      </div>
    {/each}
  </div>
  <div class="admin-range-field"><label for="admin-range">Alcance máximo</label><div><input id="admin-range" type="number" min="1" max={data.maxRange} step="1" value={draft.range} disabled={busy} required onchange={(event) => change('range', Number(event.currentTarget.value))} /><span>metros</span></div></div>
  <p class="settings-note">Limite técnico do PMA: {data.maxRange} m · volumes relativos ao áudio do jogador, não ao volume físico do dispositivo.</p>
  {#if stale}<p class="admin-warning" role="status">Outro administrador atualizou os valores. Recarregue antes de salvar.</p>{/if}
  {#if error}<p class="admin-warning" role="alert">{error}</p>{/if}
  {#if success}<p class="admin-success" role="status">{success}</p>{/if}
  <div class="admin-actions"><button class="small-button" type="button" disabled={busy} onclick={reload}>RECARREGAR</button><button class="small-button recall" type="submit" disabled={busy || stale || !dirty}>{busy ? 'AGUARDE...' : 'SALVAR GLOBAL'}</button></div>
</form>
