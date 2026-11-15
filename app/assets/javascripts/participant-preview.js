document.querySelectorAll("[data-participant-editor]").forEach(editor => {
  const name = editor.querySelector('[name="participant[name]"]');
  const displayName = editor.querySelector('[name="participant[display_name]"]');
  const preview = editor.querySelector("[data-public-preview]");
  const label = preview?.querySelector("[data-public-preview-name]");
  if (!name || !displayName || !label || preview.dataset.publicPreviewVisible !== "true") return;

  const synchronize = () => {
    label.textContent = displayName.value.trim() || name.value.trim() || "To be announced";
  };
  name.addEventListener("input", synchronize);
  displayName.addEventListener("input", synchronize);
  window.addEventListener("pageshow", synchronize);
  synchronize();
});
