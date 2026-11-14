(() => {
  const selector = "[data-calendar]";
  if (!document.querySelector(selector)) return;

  let pending;
  history.replaceState({ ...history.state, calendar: true }, "", location.href);

  async function navigate(url, push = true) {
    pending?.abort();
    const request = new AbortController();
    pending = request;
    const calendar = document.querySelector(selector);
    calendar.setAttribute("aria-busy", "true");

    try {
      const response = await fetch(url, {
        signal: request.signal,
        headers: {
          Accept: "text/html",
          "X-Posebook-Calendar-Context": calendar.dataset.calendarContext
        }
      });
      if (response.redirected) {
        location.assign(response.url);
        return;
      }
      if (!response.ok) throw new Error("Calendar request failed");
      const html = new DOMParser().parseFromString(await response.text(), "text/html");
      const replacement = html.querySelector(selector);
      if (!replacement) throw new Error("Calendar not found");
      if (request.signal.aborted) return;
      if (replacement.dataset.calendarContext !== calendar.dataset.calendarContext) {
        location.assign(url);
        return;
      }

      calendar.replaceWith(replacement);
      if (push) history.pushState({ ...history.state, calendar: true }, "", url);
      replacement.querySelector("[data-calendar-month]").focus({ preventScroll: true });
    } catch (error) {
      if (error.name !== "AbortError") location.assign(url);
    } finally {
      if (pending === request) {
        pending = null;
        calendar.removeAttribute("aria-busy");
      }
    }
  }

  document.addEventListener("click", event => {
    const link = event.target.closest?.("[data-calendar-navigation]");
    if (!link || event.defaultPrevented || event.button !== 0 ||
        event.metaKey || event.ctrlKey || event.shiftKey || event.altKey ||
        link.hasAttribute("download") || (link.target && link.target !== "_self")) return;
    if (link.origin !== location.origin) return;

    event.preventDefault();
    navigate(link.href);
  });

  window.addEventListener("popstate", event => {
    if (event.state?.calendar) navigate(location.href, false);
  });
  window.addEventListener("pagehide", () => pending?.abort());
})();
