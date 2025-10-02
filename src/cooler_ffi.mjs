export function addKeyListener(callback) {
  window.addEventListener("keydown", (event) => {
    if (event.key === " ") {
      event.preventDefault(); // Prevent page scrolling
      callback();
    }
  });
}

export function copyToClipboard(text) {
  navigator.clipboard.writeText(text).catch((err) => {
    console.error("Failed to copy:", err);
  });
}

export function updateUrlHash(hash) {
  window.history.replaceState(null, "", `#${hash}`);
}

export function getUrlHash() {
  return window.location.hash.slice(1);
}

export function onHashChange(callback) {
  window.addEventListener("hashchange", () => {
    callback(getUrlHash());
  });
}
