// ==UserScript==
// @name         Twitch to mpv
// @namespace    local.billy.twitch-mpv
// @version      1.0.0
// @description  Adds a button and a Ctrl+M shortcut on Twitch channel/VOD pages that hands the stream to the local mpv via the mpv:// protocol handler.
// @author       billy
// @match        https://www.twitch.tv/*
// @match        https://m.twitch.tv/*
// @noframes
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(() => {
  "use strict";

  const BUTTON_ID = "tw2mpv-button";
  const SCHEME = "mpv://open/";

  // top-level paths that are known pages, not channel names
  const RESERVED = new Set([
    "videos", "directory", "settings", "search", "downloads", "jobs",
    "security", "privacy", "terms", "broadcast", "store", "turbo", "team",
    "moderator", "dashboard", "u", "p", "about", "activate", "affiliate",
    "partner", "creatorcamp", "friends", "squad", "cars",
  ]);

  // a channel page (/<channel>) or a VOD watch page (/videos/<id>)
  const onVideoPage = () => {
    if (/^\/videos\/\d+/.test(location.pathname)) return true;
    const seg = location.pathname.split("/").filter(Boolean);
    return seg.length === 1 && !RESERVED.has(seg[0]);
  };

  const inEditable = (el) =>
    el instanceof HTMLElement &&
    (el.isContentEditable ||
      ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName));

  const openInMpv = () => {
    if (!onVideoPage()) return;
    // nothing to hand over if the page has no player (e.g. browse pages)
    const video =
      document.querySelector('[data-a-target="video-player"] video') ||
      document.querySelector("video");
    if (!video) return;
    // don't let the tab keep playing audio in the background
    video.pause();
    window.location.href = SCHEME + encodeURIComponent(location.href);
  };

  const makeButton = () => {
    const btn = document.createElement("button");
    btn.id = BUTTON_ID;
    btn.type = "button";
    btn.textContent = "mpv";
    btn.title = "Open this stream in mpv (Ctrl+M)";
    btn.addEventListener("click", openInMpv);
    return btn;
  };

  const styleButton = (btn, floating) => {
    Object.assign(btn.style, {
      // matches Twitch's primary (Follow) button
      backgroundColor: "#9147ff",
      color: "#ffffff",
      border: "none",
      borderRadius: "9000px",
      height: "32px",
      padding: floating ? "0 24px" : "0 16px",
      margin: floating ? "0" : "0 0 0 8px",
      display: "flex",
      alignItems: "center",
      fontFamily: "inherit",
      fontSize: "14px",
      fontWeight: "600",
      cursor: "pointer",
      zIndex: "2147483647",
      ...(floating
        ? { position: "fixed", right: "24px", bottom: "24px" }
        : {}),
    });
    btn.addEventListener(
      "mouseenter",
      () => (btn.style.backgroundColor = "#772ce8"),
    );
    btn.addEventListener(
      "mouseleave",
      () => (btn.style.backgroundColor = "#9147ff"),
    );
  };

  // row holding the Follow / Subscribe / more-options buttons; walk out of
  // single-child wrappers so we don't depend on class names
  const findActionRow = () => {
    const follow =
      document.querySelector('[data-a-target="follow-button"]') ||
      [...document.querySelectorAll("button")].find((b) =>
        /^Follow\b|^Subscribe\b/.test(b.getAttribute("aria-label") || ""),
      );
    let row = follow?.parentElement;
    while (row && row.children.length === 1) row = row.parentElement;
    return row && row.children.length <= 6 ? row : null;
  };

  // Twitch is a SPA: re-place the button on every navigation.
  const mountButton = () => {
    const existing = document.getElementById(BUTTON_ID);

    if (!onVideoPage()) {
      existing?.remove();
      return;
    }
    if (existing && existing.isConnected) return;
    existing?.remove();

    const btn = makeButton();
    const row = findActionRow();

    if (row) {
      styleButton(btn, false);
      row.appendChild(btn);
    } else {
      styleButton(btn, true);
      document.documentElement.appendChild(btn);
    }
  };

  for (const method of ["pushState", "replaceState"]) {
    const original = history[method];
    history[method] = function (...args) {
      const result = original.apply(this, args);
      mountButton();
      return result;
    };
  }
  window.addEventListener("popstate", mountButton);

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
  // safety net for DOM parts Twitch replaces without a navigation event
  setInterval(mountButton, 2000);
})();
