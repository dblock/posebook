document.querySelectorAll("[data-profile-privacy]").forEach(section => {
  const toggle = section.querySelector("[data-profile-privacy-toggle]");
  const fields = section.querySelector("[data-public-profile-fields]");
  if (!toggle || !fields) return;

  const synchronize = () => { fields.disabled = toggle.checked; };
  toggle.addEventListener("change", synchronize);
  window.addEventListener("pageshow", synchronize);
  synchronize();
});
