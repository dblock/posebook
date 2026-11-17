(() => {
  const types = ["image/jpeg", "image/png", "image/webp"];
  const regions = () => Array.from(document.querySelectorAll("[data-photo-region]"));

  function hideUploadButtons() {
    document.querySelectorAll("[data-photo-upload-submit]").forEach(button => { button.hidden = true; });
  }

  document.addEventListener("posebook:replaced", hideUploadButtons);
  hideUploadButtons();

  async function submit(form) {
    const region = form.closest("[data-photo-region]");
    const index = regions().indexOf(region);
    const photo = form.closest("[data-photo]")?.dataset.photo;
    const body = new FormData(form);
    const buttons = Array.from(form.querySelectorAll("button, input[type='submit']"));
    buttons.forEach(button => {
      button.disabled = true;
      button.setAttribute("aria-busy", "true");
    });

    try {
      const response = await fetch(form.action, { method: "POST", body, headers: { Accept: "text/html" } });
      const destination = new URL(response.url);
      if (!response.ok || destination.pathname !== location.pathname) {
        location.assign(response.url);
        return null;
      }
      const html = new DOMParser().parseFromString(await response.text(), "text/html");
      const replacement = html.querySelectorAll("[data-photo-region]")[index];
      if (!replacement) throw new Error("Photo region not found");

      region.replaceWith(replacement);
      hideUploadButtons();
      const flashes = html.querySelector("[data-flash-messages]");
      if (flashes) document.querySelector("[data-flash-messages]")?.replaceChildren(...flashes.children);
      const figure = photo && Array.from(replacement.querySelectorAll("[data-photo]"))
        .find(element => element.dataset.photo === photo);
      (figure || replacement).querySelector("button, input:not([type='hidden'])")?.focus({ preventScroll: true });
      return replacement;
    } catch {
      location.assign(location.href);
      return null;
    }
  }

  document.addEventListener("submit", event => {
    const form = event.target.closest?.("form[data-photo-action]");
    if (!form?.closest("[data-photo-region]") || event.defaultPrevented) return;

    event.preventDefault();
    submit(form);
  });

  document.addEventListener("change", event => {
    const input = event.target.closest?.("input[data-photo-upload]");
    if (!input?.files.length) return;

    const button = input.form.querySelector("[data-photo-upload-submit]");
    if (button && !button.disabled) input.form.requestSubmit(button);
  });

  function uploadForm(target) {
    const form = target.closest?.("form[data-photo-action]");
    return form?.closest("[data-photo-region]") && form.querySelector("input[type='file']") ? form : null;
  }

  function showAlert(message) {
    const alert = document.createElement("p");
    alert.className = "flash flash-alert";
    alert.setAttribute("role", "alert");
    alert.textContent = message;
    document.querySelector("[data-flash-messages]")?.replaceChildren(alert);
  }

  document.addEventListener("dragover", event => {
    const form = uploadForm(event.target);
    if (!form || !event.dataTransfer.types.includes("Files")) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = "copy";
    form.classList.add("photo-drop-target");
  });

  document.addEventListener("dragleave", event => {
    const form = uploadForm(event.target);
    if (form && !form.contains(event.relatedTarget)) form.classList.remove("photo-drop-target");
  });

  document.addEventListener("drop", async event => {
    let form = uploadForm(event.target);
    if (!form || !event.dataTransfer.types.includes("Files")) return;
    event.preventDefault();
    form.classList.remove("photo-drop-target");
    const files = Array.from(event.dataTransfer.files).filter(file => types.includes(file.type));
    if (files.length === 0) {
      showAlert("Choose a JPEG, PNG, or WebP photo.");
      return;
    }

    for (const file of files) {
      const transfer = new DataTransfer();
      transfer.items.add(file);
      form.querySelector("input[type='file']").files = transfer.files;
      const region = await submit(form);
      form = region && uploadForm(region.querySelector("input[type='file']") || region);
      if (!form) return;
    }
  });
})();
