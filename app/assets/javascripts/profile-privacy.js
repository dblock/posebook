(() => {
  const synchronize = form => {
    const tagging = form?.querySelector("[data-profile-privacy] [data-instagram-tagging]");
    const handle = form?.querySelector("[data-instagram-handle]");
    if (tagging && handle) handle.required = tagging.checked;
  };
  const synchronizeAll = () =>
    document.querySelectorAll("[data-profile-privacy]").forEach(section => synchronize(section.closest("form")));

  document.addEventListener("change", event => {
    if (event.target.matches?.("[data-instagram-tagging]")) synchronize(event.target.form);
  });
  document.addEventListener("posebook:replaced", synchronizeAll);
  window.addEventListener("pageshow", synchronizeAll);
  synchronizeAll();
})();
