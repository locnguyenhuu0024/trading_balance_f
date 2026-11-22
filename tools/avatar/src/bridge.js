import {parse} from './protocol.js';

export function send(msg) {
  if (window.AvatarChannel) {
    window.AvatarChannel.postMessage(JSON.stringify(msg));
  } else {
    window.parent.postMessage(msg, location.origin);
  }
}

export function connect(receive) {
  function dispatch(raw) {
    const result = parse(raw);
    if (result.ok) {
      receive(result.msg);
    } else {
      send({v: 1, type: 'error', code: 'protocol', message: result.error});
    }
  }

  window.avatar = {receive: dispatch};
  window.addEventListener('message', (event) => {
    if (window.parent !== window && event.origin === location.origin && event.source === window.parent) {
      dispatch(event.data);
    }
  });
}
