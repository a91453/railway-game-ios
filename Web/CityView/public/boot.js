// Along the Line (decision 163): the scripts index.html had inline, in a file of their own, so that the page runs
// under the website's Content-Security-Policy, which forbids inline scripts. Loaded right after the loading screen,
// before the modules.

// The city's name goes on the loading screen before anything else runs, so it never changes under the eye.
(function () {
  var id = new URLSearchParams(location.search).get('area') || 'tokyo', name = null;
  try { name = localStorage.getItem('procedural-tokyo:name:' + id); } catch (e) {}
  // Along the Line: the app's areas by their names, before the page has stored them
  name = name || { kaohsiung: '高雄車站', taichung: '臺中車站' }[id];
  document.querySelector('#loader .city').textContent = name || id.charAt(0).toUpperCase() + id.slice(1);
})();

// Along the Line: the website link in the page's language (in the app, the web view's is the app's); none in the
// game (?app=1), whose settings have their own
document.addEventListener('DOMContentLoaded', function () {
  var link = document.getElementById('website');
  if (new URLSearchParams(location.search).get('app') === '1') link.remove();
  else if (/^zh/i.test(navigator.language)) link.querySelector('span').textContent = '官網';
});

// The atmosphere works out its tables (the sky's colours, the light on the clouds) in the browser's idle
// time, of which a busy page — the whole city loaded, clouds on — has none: the sky would stay dull and the
// clouds dark for as long as it is busy. Idle work is given a deadline, so that it is done all the same.
// (Here, before the modules: the library takes hold of the function when it is loaded.)
if (window.requestIdleCallback) {
  const idle = window.requestIdleCallback.bind(window);
  window.requestIdleCallback = (callback, options) => idle(callback, { timeout: 30, ...options });
}
