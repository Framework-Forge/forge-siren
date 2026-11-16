<script>
  let {
    label, subtitle = '', hint = '', active = false, color = 'amber', shape = '',
    disabled = false, hold = false, onclick = () => {}, onpress = () => {}, onrelease = () => {},
  } = $props();
  let pressed = $state(false);
  function start(event) {
    if (!hold || disabled || pressed) return;
    pressed = true;
    if (event.pointerId !== undefined) event.currentTarget.setPointerCapture(event.pointerId);
    onpress();
  }
  function end() {
    if (!pressed) return;
    pressed = false;
    onrelease();
  }
  $effect(() => { if (disabled) end(); });
</script>

<button
  type="button" class="control {shape} {color}" class:active class:pressed
  aria-label={subtitle ? `${label} — ${subtitle}` : label} aria-pressed={active}
  title={`${subtitle || label}${hint ? ` · ${hint}` : ''}${hold ? ' · segure' : ''}`}
  {disabled}
  onpointerdown={start} onpointerup={end} onpointercancel={end} onlostpointercapture={end}
  onclick={() => { if (!hold) onclick(); }}
  onkeydown={(event) => { if (!event.defaultPrevented && hold && [' ', 'Enter'].includes(event.key)) { event.preventDefault(); start(event); } }}
  onkeyup={(event) => { if (!event.defaultPrevented && [' ', 'Enter'].includes(event.key)) end(); }} onblur={end}
>
  <span class="control-led" aria-hidden="true"></span>
  <span class="control-label">{label}</span>
  {#if subtitle}<span class="control-subtitle">{subtitle}</span>{/if}
  {#if hint}<kbd>{hint}</kbd>{/if}
</button>
