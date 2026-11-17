(() => {
  const selector = "[data-application-region]";
  if (!document.querySelector(selector)) return;

  let pending;
  history.replaceState({ ...history.state, applicationFilter: true }, "", location.href);

  async function navigate(url, push = true) {
    pending?.abort();
    const request = new AbortController();
    pending = request;
    const region = document.querySelector(selector);
    const focused = region.contains(document.activeElement) && document.activeElement.matches("select");
    region.setAttribute("aria-busy", "true");

    try {
      const response = await fetch(url, { signal: request.signal, headers: { Accept: "text/html" } });
      if (response.redirected) {
        location.assign(response.url);
        return;
      }
      if (!response.ok) throw new Error("Application filter request failed");
      const html = new DOMParser().parseFromString(await response.text(), "text/html");
      const replacement = html.querySelector(selector);
      if (!replacement) throw new Error("Application list not found");
      if (request.signal.aborted) return;

      replacement.querySelectorAll("noscript").forEach(element => element.remove());
      region.replaceWith(replacement);
      if (push) history.pushState({ ...history.state, applicationFilter: true }, "", url);
      if (focused) replacement.querySelector("select")?.focus({ preventScroll: true });
      document.dispatchEvent(new CustomEvent("posebook:replaced"));
    } catch (error) {
      if (error.name !== "AbortError") location.assign(url);
    } finally {
      if (pending === request) {
        pending = null;
        region.removeAttribute("aria-busy");
      }
    }
  }

  document.addEventListener("submit", event => {
    const form = event.target.closest?.(`${selector} form.application-filter`);
    if (!form || event.defaultPrevented || form.method !== "get" ||
        (form.target && form.target !== "_self")) return;

    event.preventDefault();
    const url = new URL(form.action);
    url.search = new URLSearchParams(new FormData(form)).toString();
    navigate(url.href);
  });

  document.addEventListener("click", event => {
    const link = event.target.closest?.(`${selector} .participant-pagination a`);
    if (!link || event.defaultPrevented || event.button !== 0 ||
        event.metaKey || event.ctrlKey || event.shiftKey || event.altKey ||
        link.hasAttribute("download") || (link.target && link.target !== "_self") ||
        link.origin !== location.origin) return;

    event.preventDefault();
    navigate(link.href);
  });

  window.addEventListener("popstate", event => {
    if (event.state?.applicationFilter) navigate(location.href, false);
  });
  window.addEventListener("pagehide", () => pending?.abort());
})();
