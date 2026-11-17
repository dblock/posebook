(() => {
  const selector = "main[data-edit-in-place]";
  const controls = form => Array.from(form.elements).filter(control => control.matches("button, input[type='submit']"));

  function replaceMain(html, focus) {
    const main = document.querySelector(selector);
    const replacement = html.querySelector(selector);
    if (!main || !replacement) return false;

    main.replaceWith(replacement);
    document.title = html.title || document.title;
    const forms = Array.from(replacement.querySelectorAll("form"));
    const control = forms[focus.form] && controls(forms[focus.form])[focus.control];
    control?.focus({ preventScroll: true });
    document.dispatchEvent(new CustomEvent("posebook:replaced"));
    return true;
  }

  function showFlashes(html) {
    const flashes = html.querySelector("[data-flash-messages]");
    if (flashes) document.querySelector("[data-flash-messages]")?.replaceChildren(...flashes.children);
  }

  async function load(url, init) {
    const response = await fetch(url, { ...init, headers: { Accept: "text/html" } });
    return { response, html: new DOMParser().parseFromString(await response.text(), "text/html") };
  }

  document.addEventListener("submit", async event => {
    const form = event.target.closest?.(`${selector} form:not([data-navigate])`);
    const method = (event.submitter?.formMethod || form?.method || "").toLowerCase();
    const target = event.submitter?.formTarget || form?.target;
    if (!form || event.defaultPrevented || event.submitter?.hasAttribute("data-navigate") ||
        method !== "post" || (target && target !== "_self")) return;

    event.preventDefault();
    const main = form.closest(selector);
    const forms = Array.from(main.querySelectorAll("form"));
    const buttons = controls(form);
    const focus = { form: forms.indexOf(form), control: Math.max(buttons.indexOf(event.submitter), 0) };
    const body = new FormData(form, event.submitter);
    buttons.forEach(button => {
      button.disabled = true;
      button.setAttribute("aria-busy", "true");
    });

    try {
      const submitted = await load(event.submitter?.hasAttribute("formaction") ? event.submitter.formAction : form.action, { method: "POST", body });
      if (!submitted.response.redirected) {
        if (!replaceMain(submitted.html, focus)) throw new Error("Edit page not found");
        showFlashes(submitted.html);
        return;
      }

      const current = await load(location.href);
      if (new URL(current.response.url).pathname !== location.pathname || !replaceMain(current.html, focus)) {
        location.assign(current.response.url);
        return;
      }
      showFlashes(submitted.html);
    } catch {
      location.assign(location.href);
    }
  });
})();
