(function () {
  "use strict";

  var REPO = "https://github.com/treymun/crazy-legs-mundell-rampage";
  var RELEASE_URL_RE = /^https:\/\/github\.com\/treymun\/crazy-legs-mundell-rampage\/releases\/download\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\.zip$/;
  var TAG_PAGE_RE = /^https:\/\/github\.com\/treymun\/crazy-legs-mundell-rampage\/releases\/tag\/(?!latest$)[A-Za-z0-9._-]+$/;

  function isReleaseZip(url) {
    return typeof url === "string" && RELEASE_URL_RE.test(url);
  }

  function formatBytes(n) {
    return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }

  function formatMib(n) {
    return (n / 1048576).toFixed(1) + " MiB";
  }

  function esc(value) {
    return String(value).replace(/[&<>"']/g, function (ch) {
      return {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        "\"": "&quot;",
        "'": "&#39;"
      }[ch];
    });
  }

  function render(page, cfg) {
    var download = cfg && cfg.download ? cfg.download : {};
    var url = isReleaseZip(download.url) ? download.url : null;
    var html = [];
    if (!url) {
      html.push('<p class="soon">Download coming soon</p>');
      html.push("<p>No public Windows ZIP is published in this repository.</p>");
    } else {
      var name = esc(decodeURIComponent(url.split("/").pop())).replace(/_/g, "_<wbr>");
      var line = name + ".";
      if (Number.isInteger(download.expectedBytes) && download.expectedBytes > 0) {
        line = name + ". " + formatMib(download.expectedBytes) + " (" + formatBytes(download.expectedBytes) + " bytes).";
      }
      html.push('<p class="cta"><a href="' + url + '">Download the Windows x64 ZIP</a></p>');
      html.push("<p>" + line + "</p>");
      html.push("<p>Windows x64 development build. Public v1.4.3 prerelease.</p>");
      if (typeof cfg.releasePage === "string" && TAG_PAGE_RE.test(cfg.releasePage)) {
        html.push('<p><a href="' + cfg.releasePage + '">View the v1.4.3 release</a></p>');
      }
    }
    if (page === "index") {
      html.push('<p><a href="play.html#download">Read the download notes</a></p>');
    }
    html.push('<p><a href="' + REPO + '">View project on GitHub</a></p>');
    return html.join("\n");
  }

  function apply(cfg) {
    var slots = document.querySelectorAll("[data-download-slot]");
    for (var i = 0; i < slots.length; i += 1) {
      var page = slots[i].getAttribute("data-download-slot");
      if (page !== "index" && page !== "play") continue;
      slots[i].innerHTML = render(page, cfg);
    }
  }

  window.CLMRDownload = {
    isReleaseZip: isReleaseZip,
    render: render,
    apply: apply
  };

  var slots = document.querySelectorAll("[data-download-slot]");
  if (!slots.length) return;

  fetch("site.json", { credentials: "omit", cache: "no-store" })
    .then(function (response) {
      if (!response.ok) throw new Error("config");
      return response.json();
    })
    .then(apply)
    .catch(function () {});
}());
