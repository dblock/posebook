(() => {
  document.addEventListener("submit", async event => {
    const form = event.target.closest?.("[data-user-access] form");
    if (!form || event.defaultPrevented) return;

    event.preventDefault();
    const row = form.closest("tr[id]");
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
        return;
      }
      const html = new DOMParser().parseFromString(await response.text(), "text/html");
      const replacement = html.getElementById(row.id);
      if (!replacement) throw new Error("User row not found");

      row.replaceWith(replacement);
      const flashes = html.querySelector("[data-flash-messages]");
      if (flashes) document.querySelector("[data-flash-messages]")?.replaceChildren(...flashes.children);
      replacement.querySelector("[data-user-access] button, [data-user-access] input[type='submit']")
        ?.focus({ preventScroll: true });
    } catch {
      location.assign(location.href);
    }
  });
})();
