// ==UserScript==
// @name         YouTube to mpv
// @namespace    local.billy.youtube-mpv
// @version      1.0.0
// @description  Adds a button and a Ctrl+M shortcut on YouTube watch/shorts pages that hands the video to the local mpv via the mpv:// protocol handler.
// @author       billy
// @match        https://www.youtube.com/*
// @match        https://m.youtube.com/*
// @match        https://music.youtube.com/*
// @noframes
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(() => {
  "use strict";

  const BUTTON_ID = "yt2mpv-button";
  const SCHEME = "mpv://open/";

  const onVideoPage = () =>
    location.pathname === "/watch" || location.pathname.startsWith("/shorts/");

  const inEditable = (el) =>
    el instanceof HTMLElement &&
    (el.isContentEditable ||
      ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName));

  const openInMpv = () => {
    if (!onVideoPage()) return;
    // don't let the tab keep playing audio in the background
    document.querySelector("video")?.pause();
    window.location.href = SCHEME + encodeURIComponent(location.href);
  };

  const makeButton = () => {
    const btn = document.createElement("button");
    btn.id = BUTTON_ID;
    btn.type = "button";
    btn.textContent = "mpv";
    btn.title = "Open this video in mpv (Ctrl+M)";
    btn.addEventListener("click", openInMpv);
    return btn;
  };

  const styleButton = (btn, floating) => {
    Object.assign(btn.style, {
      backgroundColor: "#272727",
      color: "#f1f1f1",
      border: "none",
      borderRadius: "18px",
      padding: floating ? "10px 18px" : "8px 16px",
      margin: floating ? "0" : "0 8px",
      fontFamily: "inherit",
      fontSize: "14px",
      fontWeight: "500",
      cursor: "pointer",
      zIndex: "2147483647",
      ...(floating
        ? { position: "fixed", right: "24px", bottom: "24px" }
        : {}),
    });
    btn.addEventListener(
      "mouseenter",
      () => (btn.style.backgroundColor = "#3f3f3f"),
    );
    btn.addEventListener(
      "mouseleave",
      () => (btn.style.backgroundColor = "#272727"),
    );
  };

  // YouTube is a SPA: re-place the button on every navigation.
  const mountButton = () => {
    const existing = document.getElementById(BUTTON_ID);

    if (!onVideoPage()) {
      existing?.remove();
      return;
    }
    if (existing && existing.isConnected) return;
    existing?.remove();

    const btn = makeButton();
    const bar =
      document.querySelector(
        "ytd-watch-metadata ytd-menu-renderer #top-level-buttons-computed",
      ) || document.querySelector("ytd-watch-metadata #actions");

    if (bar) {
      styleButton(btn, false);
      bar.appendChild(btn);
    } else {
      styleButton(btn, true);
      document.documentElement.appendChild(btn);
    }
  };

  document.addEventListener("yt-navigate-finish", mountButton, true);

  window.addEventListener(
    "keydown",
    (e) => {
      if (e.key.toLowerCase() !== "m") return;
      if (!e.ctrlKey || e.altKey || e.shiftKey || e.metaKey) return;
      if (inEditable(e.target)) return;
      e.preventDefault();
      e.stopImmediatePropagation();
      openInMpv();
    },
    true,
  );

  mountButton();
  // safety net for DOM parts YouTube replaces without a navigation event
  setInterval(mountButton, 2000);
})();
