document.querySelectorAll("[data-profile-privacy]").forEach(section => {
  const toggle = section.querySelector("[data-profile-privacy-toggle]");
  const fields = section.querySelector("[data-public-profile-fields]");
  const tagging = section.querySelector("[data-instagram-tagging]");
  const handle = section.querySelector("[data-instagram-handle]");
  if (!toggle || !fields || !tagging || !handle) return;

  const synchronize = () => {
    fields.disabled = toggle.checked;
    handle.required = tagging.checked;
  };
  toggle.addEventListener("change", synchronize);
  tagging.addEventListener("change", synchronize);
  window.addEventListener("pageshow", synchronize);
  synchronize();
});
