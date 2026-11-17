(() => {
  const form = document.querySelector("[data-notification-editor]");
  if (!form) return;
  const preview = form.querySelector("[data-notification-preview]");
  let timer;
  let request;
  let target = form.querySelector('[name="notification[body]"]');

  const timing = () => {
    const mode = form.querySelector('[name="notification[timing]"]');
    const days = form.querySelector("[data-days-timing]");
    if (mode && days) days.hidden = mode.value === "previous_session_end";
  };
  const update = async () => {
    request?.abort();
    request = new AbortController();
    const data = new FormData(form);
    data.delete("_method");
    try {
      const response = await fetch(form.dataset.previewUrl, {
        method: "POST", body: data, signal: request.signal,
        headers: { "X-Notification-Preview": "true", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }
      });
      if (response.ok || response.status === 422) preview.innerHTML = await response.text();
      else preview.textContent = "Preview unavailable. Your edits have not been saved.";
    } catch (error) {
      if (error.name !== "AbortError") preview.textContent = "Preview unavailable. Your edits have not been saved.";
    }
  };
  form.addEventListener("focusin", event => {
    if (["notification[body]", "notification[subject]"].includes(event.target.name)) target = event.target;
  });
  form.addEventListener("input", () => {
    timing();
    clearTimeout(timer);
    request?.abort();
    timer = setTimeout(update, 250);
  });
  form.querySelectorAll("[data-notification-placeholder]").forEach(button => {
    button.disabled = false;
    button.addEventListener("click", () => {
      target.setRangeText(button.dataset.notificationPlaceholder, target.selectionStart, target.selectionEnd, "end");
      target.focus();
      target.dispatchEvent(new Event("input", { bubbles: true }));
    });
  });
  timing();
})();
