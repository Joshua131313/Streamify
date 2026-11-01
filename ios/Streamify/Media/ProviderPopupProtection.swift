import Foundation
import WebKit

/// These advertising hosts were present in DaddyLive and Matchora's published
/// player HTML. Do not use a broad third-party block: nested video hosts, CDNs,
/// licenses and provider controls must keep working.
enum ProviderPopupProtection {
    static let advertisingHosts = [
        "profitableratecpmnetwork.com", "thirstacock.com", "cogwayskerb.com",
        "acscdn.com", "al5sm.com", "clearonclick.com"
    ]
    static func blocks(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return advertisingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static let rules: String = {
        let values: [[String: Any]] = advertisingHosts.map { host in
            ["trigger": ["url-filter": "^https?://([a-z0-9-]+\\.)*" + host.replacingOccurrences(of: ".", with: "\\.") + "[:/]"],
             "action": ["type": "block"]]
        }
        let data = try! JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }()

    // Native navigation still rejects new windows. Suppressing them before the
    // provider runs prevents popunder scripts from stealing a play interaction.
    // Existing same-context navigation is left to WebKit's navigation policy.
    static let script = #"""
    (() => {
      if (window.__streamifyPopupProtection) return;
      window.__streamifyPopupProtection = true;
      const open = window.open;
      const guardedOpen = function(url, target, features) {
        const name = typeof target === 'string' ? target.toLowerCase() : '';
        if (name === '_self' || name === '_parent' || name === '_top')
          return open.call(this, url, target, features);
        return null;
      };
      try { Object.defineProperty(window, 'open', {value: guardedOpen, writable: false, configurable: false}); }
      catch (_) { window.open = guardedOpen; }
      if (location.hostname === 'fxtrend.st') {
        const fitPublishedPlayer = () => {
          const frame = document.querySelector('iframe#streamIframe');
          if (!frame || document.getElementById('streamify-publisher-fit')) return;
          const style = document.createElement('style');
          style.id = 'streamify-publisher-fit';
          style.textContent = 'html,body{margin:0!important;width:100%!important;height:100%!important;overflow:hidden!important;background:#000!important}body *{visibility:hidden!important}#streamIframe{visibility:visible!important;position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;border:0!important;z-index:2147483000!important}';
          (document.head || document.documentElement).appendChild(style);
          for (let parent = frame.parentElement; parent && parent !== document.body; parent = parent.parentElement) {
            for (const [key, value] of Object.entries({position:'static',transform:'none',filter:'none',contain:'none',overflow:'visible'}))
              parent.style.setProperty(key, value, 'important');
          }
        };
        if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fitPublishedPlayer, {once:true});
        else fitPublishedPlayer();
      }
    })();
    """#
}

@MainActor enum ProviderPopupRuleStore {
    private static var cached: WKContentRuleList?
    private static var compiling = false
    private static var callbacks: [(WKContentRuleList?) -> Void] = []

    static func prepare(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let cached { completion(cached); return }
        callbacks.append(completion)
        guard !compiling else { return }
        compiling = true
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "StreamifyObservedSportsAds-v2",
            encodedContentRuleList: ProviderPopupProtection.rules) { rules, _ in
            Task { @MainActor in
                cached = rules; compiling = false
                let waiting = callbacks; callbacks = []
                waiting.forEach { $0(rules) }
            }
        }
    }
}
