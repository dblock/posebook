(() => {
  const pendingForms = new Map();
  const pendingLinks = new Set();
  const buttons = 'button, input[type="submit"], input[type="image"], input[type="button"]';

  function restoreForm(form) {
    const pending = pendingForms.get(form);
    if (!pending) return;
    clearTimeout(pending.timer);
    pending.controls.forEach(control => {
      control.disabled = false;
      control.removeAttribute("aria-busy");
    });
    pending.mirror?.remove();
    form.removeAttribute("aria-busy");
    pendingForms.delete(form);
  }

  document.addEventListener("submit", event => {
    const form = event.target;
    const target = event.submitter?.formTarget || form.target;
    if (event.defaultPrevented || (target && target !== "_self") ||
        (event.submitter?.formMethod || form.method) === "dialog") return;
    if (pendingForms.has(form)) {
      event.preventDefault();
      return;
    }

    const controls = Array.from(form.elements).filter(control => control.matches(buttons) && !control.disabled);
    const pending = { controls };
    const submitter = event.submitter;
    // Disabled controls are omitted, so preserve the selected button's name and value.
    if (submitter?.name && !submitter.disabled) {
      pending.mirror = document.createElement("input");
      pending.mirror.type = "hidden";
      pending.mirror.name = submitter.name;
      pending.mirror.value = submitter.value;
      form.append(pending.mirror);
    }
    pendingForms.set(form, pending);
    form.setAttribute("aria-busy", "true");
    controls.forEach(control => {
      control.disabled = true;
      control.setAttribute("aria-busy", "true");
    });
    pending.timer = setTimeout(() => {
      if (event.defaultPrevented) restoreForm(form);
    }, 0);
  });

  document.addEventListener("click", event => {
    const link = event.target.closest?.("a.button-link");
    if (!link) return;
    if (link.getAttribute("aria-disabled") === "true") {
      event.preventDefault();
      return;
    }
    if (event.defaultPrevented || event.button !== 0 ||
        event.metaKey || event.ctrlKey || event.shiftKey || event.altKey ||
        link.hasAttribute("download") || (link.target && link.target !== "_self") ||
        !["http:", "https:"].includes(link.protocol) ||
        (link.hash && link.href.split("#")[0] === location.href.split("#")[0])) return;

    pendingLinks.add(link);
    link.setAttribute("aria-disabled", "true");
    link.setAttribute("aria-busy", "true");
    setTimeout(() => {
      if (!event.defaultPrevented) return;
      link.removeAttribute("aria-disabled");
      link.removeAttribute("aria-busy");
      pendingLinks.delete(link);
    }, 0);
  });

  window.addEventListener("pageshow", () => {
    pendingForms.forEach((_, form) => restoreForm(form));
    pendingLinks.forEach(link => {
      link.removeAttribute("aria-disabled");
      link.removeAttribute("aria-busy");
    });
    pendingLinks.clear();
  });

  document.addEventListener("click", event => {
    const close = event.target.closest?.("[data-close-details]");
    if (!close) return;
    const details = close.closest("details");
    if (!details) return;
    details.open = false;
    details.querySelector("form")?.reset();
    requestAnimationFrame(() => details.querySelector("summary")?.focus());
  });

  document.addEventListener("change", event => {
    if (event.target.matches?.("select[data-auto-submit]")) event.target.form?.requestSubmit();
  });
})();
