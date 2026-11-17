(() => {
  const update = () => {
    const consent = document.querySelector("[data-application-consent]");
    const submit = document.querySelector("[data-application-submit]");
    if (consent && submit) submit.disabled = !consent.checked;
  };

  document.addEventListener("change", event => {
    if (event.target.matches?.("[data-application-consent]")) update();
  });
  document.addEventListener("posebook:replaced", update);
  window.addEventListener("pageshow", () => queueMicrotask(update));
  update();
})();
