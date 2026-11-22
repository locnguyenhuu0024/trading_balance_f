import {Vector3} from 'three';

export function createHitTest(camera, canvas) {
  const headPoint = new Vector3();
  const chestPoint = new Vector3();
  const hipsPoint = new Vector3();
  const radiusPoint = new Vector3();
  const cameraRight = new Vector3();

  function toScreen(point) {
    point.project(camera);
    point.x = (point.x + 1) * canvas.clientWidth / 2;
    point.y = (1 - point.y) * canvas.clientHeight / 2;
  }

  function projectRadius(point, meters) {
    cameraRight.setFromMatrixColumn(camera.matrixWorld, 0).normalize();
    radiusPoint.copy(point).addScaledVector(cameraRight, meters);
    toScreen(radiusPoint);
    toScreen(point);
    return Math.abs(radiusPoint.x - point.x);
  }

  return (x, y, bones) => {
    if (!bones) return 'outside';

    bones.head.getWorldPosition(headPoint);
    const headRadius = projectRadius(headPoint, 0.11);
    if (Math.hypot(x - headPoint.x, y - headPoint.y) <= headRadius) return 'head';

    bones.chest.getWorldPosition(chestPoint);
    bones.hips.getWorldPosition(hipsPoint);
    const bodyRadius = projectRadius(chestPoint, 0.16);
    toScreen(hipsPoint);
    const dx = hipsPoint.x - chestPoint.x;
    const dy = hipsPoint.y - chestPoint.y;
    const lengthSquared = dx * dx + dy * dy;
    const fraction = lengthSquared ? ((x - chestPoint.x) * dx + (y - chestPoint.y) * dy) / lengthSquared : 0;
    const along = Math.max(0, Math.min(1, fraction));
    return Math.hypot(x - chestPoint.x - along * dx, y - chestPoint.y - along * dy) <= bodyRadius
      ? 'body'
      : 'outside';
  };
}
