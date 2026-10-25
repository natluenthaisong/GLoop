chrome.action.onClicked.addListener(async (tab) => {
  const url = new URL(tab.url || "https://invalid.local");
  if (url.protocol !== "https:" || !["www.youtube.com", "youtube.com"].includes(url.hostname) || url.pathname !== "/watch") {
    await chrome.action.setBadgeText({ tabId: tab.id, text: "YT" });
    await chrome.action.setTitle({ tabId: tab.id, title: "Open a YouTube video, then click GLoop" });
    return;
  }
  try {
    await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["core.js", "content.js"] });
    await chrome.action.setBadgeText({ tabId: tab.id, text: "" });
    await chrome.action.setTitle({ tabId: tab.id, title: "Toggle GLoop" });
  } catch {
    await chrome.action.setBadgeText({ tabId: tab.id, text: "!" });
    await chrome.action.setTitle({ tabId: tab.id, title: "Reload this YouTube page and try GLoop again" });
  }
});
