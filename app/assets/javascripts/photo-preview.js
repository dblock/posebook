(() => {
  const dialog = document.querySelector("[data-photo-dialog]");
  if (!dialog || typeof dialog.showModal !== "function") return;
  const image = dialog.querySelector("[data-photo-image]");
  const error = dialog.querySelector("[data-photo-error]");
  dialog.querySelector("[data-photo-close]").addEventListener("click", () => dialog.close());

  document.addEventListener("click", event => {
    const link = event.target.closest?.("[data-photo-preview]");
    if (!link || event.defaultPrevented || event.button !== 0 ||
        event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    event.preventDefault();
    image.hidden = false;
    error.hidden = true;
    image.alt = link.querySelector("img").alt;
    image.src = link.href;
    dialog.showModal();
  });

  image.addEventListener("error", () => {
    image.hidden = true;
    error.hidden = false;
  });

  dialog.addEventListener("click", event => {
    if (event.target !== dialog) return;
    const bounds = dialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right ||
        event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
  });

  dialog.addEventListener("close", () => {
    image.hidden = true;
    image.removeAttribute("src");
    image.alt = "";
    error.hidden = true;
  });
  window.addEventListener("pagehide", () => dialog.close());
})();
