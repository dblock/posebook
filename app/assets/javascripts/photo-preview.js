(() => {
  const dialog = document.querySelector("[data-photo-dialog]");
  if (!dialog || typeof dialog.showModal !== "function") return;
  const image = dialog.querySelector("[data-photo-image]");
  const error = dialog.querySelector("[data-photo-error]");
  const previous = dialog.querySelector("[data-photo-previous]");
  const next = dialog.querySelector("[data-photo-next]");
  const position = dialog.querySelector("[data-photo-position]");
  let series = [];
  let index = 0;

  const show = target => {
    index = (target + series.length) % series.length;
    const link = series[index];
    image.hidden = false;
    error.hidden = true;
    image.alt = link.querySelector("img")?.alt || link.dataset.photoDescription || "";
    image.src = link.href;
    const multiple = series.length > 1;
    previous.hidden = !multiple;
    next.hidden = !multiple;
    position.hidden = !multiple;
    position.textContent = multiple ? `${index + 1} of ${series.length}` : "";
  };

  dialog.querySelector("[data-photo-close]").addEventListener("click", () => dialog.close());
  previous.addEventListener("click", () => show(index - 1));
  next.addEventListener("click", () => show(index + 1));

  document.addEventListener("click", event => {
    const link = event.target.closest?.("[data-photo-preview]");
    if (!link || event.defaultPrevented || event.button !== 0 ||
        event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

    event.preventDefault();
    const explicit = link.closest("[data-photo-series]");
    const gallery = link.closest(".photo-gallery");
    series = explicit ? [...explicit.querySelectorAll("[data-photo-preview]")] : gallery ? [...gallery.querySelectorAll("[data-photo-preview]")]
      .filter(candidate => candidate === link || candidate.getClientRects().length) : [link];
    show(series.indexOf(link));
    dialog.showModal();
  });

  dialog.addEventListener("keydown", event => {
    if (series.length < 2) return;
    if (event.key === "ArrowLeft") show(index - 1);
    else if (event.key === "ArrowRight") show(index + 1);
    else return;
    event.preventDefault();
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
    series = [];
  });
  window.addEventListener("pagehide", () => dialog.close());
})();
