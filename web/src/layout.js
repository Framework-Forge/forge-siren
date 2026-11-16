const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
export const PANEL_WIDTH = 596;
export const MIN_SCALE = 0.4;
export const MAX_SCALE = 1.3;

export function panelPlacement(layout, requestedScale, width, height, panelHeight, extraHeight = 0) {
  const margin = 16;
  const scale = Math.max(0.05, Math.min(
    clamp(Number.isFinite(requestedScale) ? requestedScale : 1, MIN_SCALE, MAX_SCALE),
    (width - 2 * margin) / PANEL_WIDTH,
    (height - 2 * margin) / (panelHeight + extraHeight),
  ));
  const x = Number.isFinite(layout.x) ? layout.x * width : width - (layout.right ?? 24);
  const y = Number.isFinite(layout.y) ? layout.y * height : height - (layout.bottom ?? 32);
  return {
    x: clamp(x, margin + PANEL_WIDTH * scale, width - margin),
    y: clamp(y, margin + (panelHeight + extraHeight) * scale, height - margin),
    scale,
  };
}

export function movePanel(placement, dx, dy, width, height, panelHeight) {
  const next = panelPlacement({ x: (placement.x + dx) / width, y: (placement.y + dy) / height },
    placement.scale, width, height, panelHeight);
  return { x: next.x / width, y: next.y / height };
}
