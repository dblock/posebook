(() => {
  const container = document.querySelector("[data-flash-messages]");
  if (!container) return;

  function enhance(flash) {
    if (flash.querySelector(".flash-dismiss")) return;
    const dismiss = document.createElement("button");
    dismiss.type = "button";
    dismiss.className = "flash-dismiss";
    dismiss.setAttribute("aria-label", "Dismiss");
    dismiss.textContent = "×";
    dismiss.addEventListener("click", () => flash.remove());
    flash.append(dismiss);
    if (!flash.classList.contains("flash-alert")) setTimeout(() => flash.remove(), 3000);
  }

  container.querySelectorAll(".flash").forEach(enhance);
  new MutationObserver(records => records.forEach(record =>
    record.addedNodes.forEach(node => node.matches?.(".flash") && enhance(node))
  )).observe(container, { childList: true });
})();
