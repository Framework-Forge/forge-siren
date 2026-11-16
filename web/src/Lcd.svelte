<script>
  import { matrix } from './lcd.js';
  let { text = 'STANDBY', lights = false, sound = false, memory = false } = $props();
  const dots = $derived(matrix(text));
</script>

<div class="lcd" role="status" aria-live="polite" aria-label={text}>
  <div class="lcd-flags" aria-hidden="true">
    <span class:on={lights}>LIGHT</span><span class:on={sound}>SIREN</span><span class:on={memory}>MEMORY</span>
    <span class="lcd-stereo">STEREO / SYNC</span>
  </div>
  <svg viewBox="0 0 286 14" class="matrix" aria-hidden="true">
    {#each dots as dot}
      <rect x={dot.x} y={dot.y} width="1.35" height="1.35" rx="0.25" class:lit={dot.on} />
    {/each}
  </svg>
</div>
