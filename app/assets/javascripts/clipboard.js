(() => {
  const resetTimers = new WeakMap();

  function enableButtons() {
    document.querySelectorAll(".copy-button[hidden]").forEach(button => { button.hidden = false; });
  }

  function copyWithSelection(value) {
    const focused = document.activeElement;
    const selection = document.getSelection();
    const ranges = Array.from({ length: selection.rangeCount }, (_, index) => selection.getRangeAt(index));
    const field = document.createElement("textarea");
    field.value = value;
    field.className = "clipboard-selection";
    field.setAttribute("aria-hidden", "true");
    field.tabIndex = -1;
    document.body.append(field);
    try {
      field.focus({ preventScroll: true });
      field.select();
      if (!document.execCommand("copy")) throw new Error("Copy unavailable");
    } finally {
      field.remove();
      focused?.focus({ preventScroll: true });
      selection.removeAllRanges();
      ranges.forEach(range => selection.addRange(range));
    }
  }

  document.addEventListener("click", async event => {
    const button = event.target.closest?.(".copy-button");
    if (!button || button.getAttribute("aria-busy") === "true") return;
    const feedback = button.parentElement.querySelector(".copy-feedback");
    const field = button.dataset.copyTarget ? document.getElementById(button.dataset.copyTarget) : null;
    const value = field ? field.value : button.dataset.copyValue;
    clearTimeout(resetTimers.get(button));
    button.textContent = "Copy";
    button.setAttribute("aria-busy", "true");
    feedback.textContent = "";
    feedback.classList.remove("copy-error");
    try {
      if (!value) throw new Error("Nothing to copy");
      if (navigator.clipboard?.writeText) await navigator.clipboard.writeText(value);
      else copyWithSelection(value);
      button.textContent = "Copied";
      feedback.textContent = "Copied!";
      resetTimers.set(button, setTimeout(() => {
        button.textContent = "Copy";
        feedback.textContent = "";
        resetTimers.delete(button);
      }, 3000));
    } catch {
      feedback.classList.add("copy-error");
      feedback.textContent = "Could not copy. Select the text and copy it manually.";
      field?.focus();
      field?.select();
    } finally {
      button.removeAttribute("aria-busy");
    }
  });

  enableButtons();
  new MutationObserver(enableButtons).observe(document.body, { childList: true, subtree: true });
})();
