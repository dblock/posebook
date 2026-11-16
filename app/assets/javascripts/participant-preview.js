(() => {
  const synchronize = editor => {
    const displayName = editor.querySelector('[name="participant[display_name]"]');
    const preview = editor.querySelector("[data-public-preview]");
    const instagramHidden = editor.querySelector('input[type="checkbox"][name="participant[instagram_hidden]"]');
    const instagram = preview?.querySelector("[data-public-preview-instagram]");
    if (instagramHidden && instagram) instagram.hidden = instagramHidden.checked;
    const photosHidden = editor.querySelector('input[type="checkbox"][name="participant[photos_hidden]"]');
    const photos = preview?.querySelector("[data-public-preview-photos]");
    if (photosHidden && photos) photos.hidden = photosHidden.checked;
    const label = preview?.querySelector("[data-public-preview-name]");
    if (!displayName || !label || preview.dataset.publicPreviewVisible !== "true") return;

    label.textContent = displayName.value.trim() || preview.dataset.publicPreviewFallback?.trim() || "To be announced";
  };
  const synchronizeAll = () => document.querySelectorAll("[data-participant-editor]").forEach(synchronize);

  document.addEventListener("input", event => {
    const editor = event.target.closest?.("[data-participant-editor]");
    if (editor && event.target.name === "participant[display_name]") synchronize(editor);
  });
  document.addEventListener("change", event => {
    const editor = event.target.closest?.("[data-participant-editor]");
    if (editor && /^participant\[(instagram|photos)_hidden\]$/.test(event.target.name)) synchronize(editor);
  });
  document.addEventListener("posebook:replaced", synchronizeAll);
  window.addEventListener("pageshow", synchronizeAll);
  synchronizeAll();
})();
