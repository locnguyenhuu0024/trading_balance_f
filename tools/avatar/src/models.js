export const MODELS = Object.freeze({
  'pixiv-sample': 'pixiv-sample.vrm',
  'donut-chan': 'donut-chan.vrm',
});
export const DEFAULT_MODEL = 'pixiv-sample';

export function resolveModel(search) {
  const id = new URLSearchParams(search).get('model');
  if (id && /^[a-z0-9-]{1,32}$/.test(id) && Object.hasOwn(MODELS, id)) {
    return MODELS[id];
  }
  return MODELS[DEFAULT_MODEL];
}
